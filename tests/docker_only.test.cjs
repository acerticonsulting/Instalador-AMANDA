const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const { SOURCE, CORE, sourceUrl, rootPath, normalizeConfig, envValues, Runner, Manager } = require('../docker/installer/manager.cjs');
const { installInput } = require('../docker/installer/cli.cjs');
const input = extra => ({ sourceUrl: SOURCE, ...extra });
function temporary() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(),'amanda-manager-test-'));
  return { root, cleanup() { const resolved = fs.realpathSync(root); assert.ok(resolved.startsWith(fs.realpathSync(os.tmpdir()) + path.sep)); assert.ok(path.basename(resolved).startsWith('amanda-manager-test-')); fs.rmSync(resolved,{recursive:true}); } };
}
const defaultEnv = 'COMPOSE_PROJECT_NAME=amanda\nDB_PASS=fixture-db-password\nJWT_SECRET=fixture-jwt-secret\nJWT_REFRESH_SECRET=fixture-refresh\nTRANSCRIBE_API_KEY=fixture-transcription\n';
class FakeRunner {
  constructor() { this.calls=[]; this.messages=''; this.secrets=[]; this.fail=null; this.existing=[]; this.dirty=false; this.users='0'; this.badService=null; this.remote=SOURCE; }
  secret(s) { if(s)this.secrets.push(s); }
  emit(s) { this.messages+=s; }
  async run(bin,args,options={}) {
    this.calls.push({bin,args:[...args],options});
    if(this.fail?.({bin,args,options}))throw Error('Simulated failure');
    let stdout='';
    if(bin==='git') {
      if(args.includes('clone')) {
        const dir=args.at(-1); fs.mkdirSync(path.join(dir,'.git/info'),{recursive:true});fs.mkdirSync(path.join(dir,'.secrets'));fs.mkdirSync(path.join(dir,'docker'));
        fs.writeFileSync(path.join(dir,'docker-compose.yml'),'# official test fixture\n');fs.writeFileSync(path.join(dir,'docker/ensure-transcription-key.cjs'),'');fs.writeFileSync(path.join(dir,'.secrets/github_token'),'');
      }
      if(args.includes('get-url'))stdout=this.remote;
      if(args.includes('status'))stdout=this.dirty?' M docker-compose.yml\n':'';
      if(args.includes('rev-parse'))stdout='a'.repeat(40);
    } else if(bin===process.execPath && args[0].endsWith('configure.cjs')) fs.writeFileSync(path.join(options.cwd,'.env'),defaultEnv);
    else if(bin==='docker') {
      if(args[0]==='info')stdout=JSON.stringify({OSType:'linux',ServerVersion:'27.5.1',Architecture:'x86_64'});
      else if(args[0]==='volume')stdout=this.existing.join('\n');
      else if(args[0]==='network')stdout='';
      else if(args[0]==='ps')stdout=this.existingContainers?'b'.repeat(64):'';
      else if(args[0]==='inspect')stdout='sha256:'+'c'.repeat(64);
      else if(args[0]==='compose') {
        if(args.includes('config')) {
          const project=args[args.indexOf('-p')+1];
          stdout=JSON.stringify({services:Object.fromEntries(CORE.map(n=>[n,{image:project+'-'+n+':local',environment:{}}])),volumes:Object.fromEntries(['postgres_data','redis_data','backend_database','backend_private','backend_public','oficial_public','wuzapi_data','rabbitmq_data','caddy_data','caddy_config'].map(n=>[n,{name:project+'_'+n}]))});
        } else if(args.includes('ps')) {
          if(args.includes('-q'))stdout='b'.repeat(64);
          else stdout=[...CORE,'edge'].map(Service=>JSON.stringify({Service,State:Service===this.badService?'exited':'running',Health:'healthy'})).join('\n');
        } else if(args.includes('psql'))stdout=this.users;
      }
      if(args[0]==='run' && args.includes('-czf')) {
        const bind=args.find(a=>a.startsWith('type=bind,source=')); const dir=bind.slice('type=bind,source='.length).split(',')[0];fs.writeFileSync(path.join(dir,'volumes.tgz'),'fixture archive');
      }
    }
    if(options.outputFile)fs.writeFileSync(options.outputFile,'fixture dump');
    return {stdout,stderr:'',code:0};
  }
}
async function fixture() { const t=temporary(),runner=new FakeRunner(),m=new Manager(t.root,runner);await m.prepare(input());return {...t,runner,m}; }
function isSeed(call) { return call.bin==='docker'&&call.args.includes('run')&&call.args.includes('seed'); }

test('authorized repository is mandatory, canonical and cannot carry credentials or a fork',()=>{
  for(const s of [SOURCE,SOURCE.slice(0,-4),SOURCE+'/'])assert.equal(sourceUrl(s),SOURCE);
  for(const s of ['',undefined,'http://github.com/acerticonsulting/AMANDA','https://github.com/acerticonsulting/AMANDA-extra','https://user:secret@github.com/acerticonsulting/AMANDA','https://github.com/acerticonsulting/AMANDA?x=1'])assert.throws(()=>sourceUrl(s));
});
test('default complete stack and administrator are retained; custom values remain literal',()=>{
  const c=normalizeConfig(input());assert.equal(c.adminEmail,'admin@amanda.com.br');assert.equal(c.adminPassword,'adminamanda');
  assert.equal(normalizeConfig(input({adminPassword:"custom$#'\\value"})).adminPassword,"custom$#'\\value");
  for(const extra of [{project:'../etc'},{adminEmail:'invalid'},{adminPassword:''},{sourceUrl:'https://other.invalid/repo'},{frontendUrl:'javascript:alert(1)'},{backendUrl:'http://user:password@localhost:8080'},{frontendUrl:'http://localhost:6000'},{frontendUrl:'http://server:3000'}])assert.throws(()=>normalizeConfig(input(extra)));
  assert.equal(normalizeConfig(input({frontendUrl:'http://server:3000',backendUrl:'http://server:8080',public:true})).public,true);
});
test('HTTPS remains optional and requires explicit separate DNS domains',()=>{
  assert.equal(normalizeConfig(input({edge:true,frontendUrl:'https://app.example.test',backendUrl:'https://api.example.test'})).edge,true);
  for(const extra of [{frontendUrl:'https://app.example.test'},{edge:true,frontendUrl:'https://localhost',backendUrl:'https://localhost'},{edge:true,frontendUrl:'https://app.example.test',backendUrl:'https://app.example.test'}])assert.throws(()=>normalizeConfig(input(extra)));
});
test('protected filesystem paths are refused',()=>{for(const p of ['/','/etc','/etc/amanda','/var/lib/docker/amanda','/run/user/1','/tmp/a,b'])assert.throws(()=>rootPath(p));});
test('preparation uses official Git/Compose, unique secrets and only the actual eight services',async()=>{
  const t=await fixture();try{
    assert.deepEqual(t.m.state.profiles,['official','whatsmeow','rabbit']);assert.equal(t.m.state.freshResourcesVerified,true);
    const env=envValues(path.join(t.m.state.platform,'.env'));assert.equal(env.USE_WHATSAPP_OFICIAL,'true');assert.equal(env.RABBITMQ_ENABLED_GLOBAL,'true');assert.equal(env.WUZAPI_URL,'http://wuzapi:8080');assert.equal(env.BIND_ADDRESS,'127.0.0.1');assert.equal(env.DB_PASS,'fixture-db-password');
    assert.equal(env.AMANDA_ADMIN_PASSWORD,undefined);
    assert.ok(!t.runner.calls.some(c=>['apt','sudo','npm','pm2','python','openssl','systemctl'].includes(c.bin)));
    assert.equal(fs.readFileSync(path.join(t.m.state.platform,'docker-compose.yml'),'utf8'),'# official test fixture\n');
  }finally{t.cleanup();}
});
test('new installation collision refuses preexisting volumes before any seed',async()=>{
  const t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);r.existing=['amanda_postgres_data'];try{await assert.rejects(m.prepare(input()),/já existem/);assert.equal(r.calls.filter(isSeed).length,0);}finally{t.cleanup();}
  const later=await fixture();try{later.runner.existing=['amanda_postgres_data'];later.runner.calls=[];await assert.rejects(later.m.initialize(),/já existem/);assert.equal(later.runner.calls.filter(isSeed).length,0);assert.ok(!later.runner.calls.some(c=>c.args.includes('run')&&c.args.includes('migrate')));}finally{later.cleanup();}
});
test('preexisting containers and nonempty directories are not overwritten',async()=>{
  const t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);fs.writeFileSync(path.join(t.root,'personal-data'),'keep');try{await assert.rejects(m.prepare(input()),/não vazio/);assert.equal(fs.readFileSync(path.join(t.root,'personal-data'),'utf8'),'keep');assert.equal(r.calls.length,0);}finally{t.cleanup();}
});
test('separate source/build tokens stay in protected files, never URLs or Compose context changes',async()=>{
  const t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);try{
    await m.prepare(input({sourceToken:'synthetic-source-token',buildToken:'synthetic-build-token',adminPassword:"custom$#'value"}));
    assert.equal(fs.readFileSync(path.join(m.state.platform,'.secrets/github_token'),'utf8'),'synthetic-build-token');
    const clone=r.calls.find(c=>c.args.includes('clone'));assert.ok(clone.args.includes(SOURCE));assert.ok(!JSON.stringify(clone.args).includes('synthetic-'));
    assert.equal(fs.statSync(path.join(m.private,'admin-access.json')).mode&0o777,0o600);
    assert.ok(!fs.readFileSync(path.join(m.state.platform,'.env'),'utf8').includes("custom$#'value"));
    const malformed=path.join(m.private,'invalid.json');fs.writeFileSync(malformed,'{"buildToken":"synthetic-private-value",BROKEN}');
    await assert.rejects(installInput(malformed),error=>!error.message.includes('synthetic-private-value')&&error.message.includes('arquivo privado'));
  }finally{t.cleanup();}
});
test('initial seed only runs after migrations and an empty user table; all services and login are validated',async()=>{
  const t=await fixture();try{
    await t.m.build();await t.m.initialize();
    assert.equal(t.m.state.initialized,true);assert.equal(t.m.state.phase,'ready');assert.equal(t.runner.calls.filter(isSeed).length,1);
    const seed=t.runner.calls.find(isSeed);assert.equal(seed.options.env.AMANDA_ADMIN_EMAIL,'admin@amanda.com.br');assert.equal(seed.options.env.AMANDA_ADMIN_PASSWORD,'adminamanda');
    const start=t.runner.calls.find(c=>c.args.includes('up')&&c.args.includes('backend'));for(const name of CORE)assert.ok(start.args.includes(name));
    assert.ok(t.runner.calls.some(c=>c.args.some(a=>String(a).includes('/auth/me'))));
  }finally{t.cleanup();}
});
test('existing users cause initialization to refuse seeds',async()=>{
  const t=await fixture();try{t.runner.users='1';await assert.rejects(t.m.initialize(),/já possui usuários/);assert.equal(t.runner.calls.filter(isSeed).length,0);}finally{t.cleanup();}
});
test('failed or interrupted seed is not silently repeated',async()=>{
  const t=await fixture();try{t.runner.fail=c=>isSeed(c);await assert.rejects(t.m.initialize());assert.equal(t.m.state.seedAttempted,true);t.runner.fail=null;await assert.rejects(t.m.initialize(),/Seed anterior incompleto/);assert.equal(t.runner.calls.filter(isSeed).length,1);}finally{t.cleanup();}
});
test('unhealthy required service cannot yield a success result',async()=>{
  const t=await fixture();try{t.runner.badService='api_oficial';await assert.rejects(t.m.initialize(),/api_oficial/);assert.equal(t.m.state.initialized,false);}finally{t.cleanup();}
});
test('resume after startup failure preserves accounts and does not seed again',async()=>{
  const t=await fixture();try{t.runner.badService='frontend';await assert.rejects(t.m.initialize());t.runner.badService=null;await t.m.execute('resume');assert.equal(t.runner.calls.filter(isSeed).length,1);assert.equal(t.m.state.initialized,true);}finally{t.cleanup();}
});
test('update builds, backs up both databases and volumes, migrates and never seeds',async()=>{
  const t=await fixture();try{await t.m.initialize();t.runner.calls=[];await t.m.execute('update');assert.equal(t.runner.calls.filter(isSeed).length,0);assert.ok(fs.existsSync(path.join(t.m.state.lastBackup,'amanda.dump')));assert.ok(fs.existsSync(path.join(t.m.state.lastBackup,'api_oficial.dump')));assert.ok(fs.existsSync(path.join(t.m.state.lastBackup,'volumes.tgz')));assert.equal(JSON.parse(fs.readFileSync(path.join(t.m.state.lastBackup,'backup.json'))).complete,true);assert.equal(t.m.state.phase,'ready');}finally{t.cleanup();}
});
test('update refuses tracked user changes and preserves secret configuration',async()=>{
  const t=await fixture();try{await t.m.initialize();const before=fs.readFileSync(path.join(t.m.state.platform,'.env'),'utf8');t.runner.dirty=true;await assert.rejects(t.m.execute('update'),/alterações locais/);assert.equal(fs.readFileSync(path.join(t.m.state.platform,'.env'),'utf8'),before);}finally{t.cleanup();}
});
test('failed build restores old tags/source and does not stop the running platform',async()=>{
  const t=await fixture();try{await t.m.initialize();t.runner.calls=[];t.runner.fail=c=>c.bin==='docker'&&c.args.includes('build');await assert.rejects(t.m.execute('update'));assert.equal(t.runner.calls.filter(c=>c.args.includes('stop')).length,0);assert.ok(t.runner.calls.some(c=>c.args[0]==='image'&&c.args[1]==='tag'));assert.ok(t.runner.calls.some(c=>c.bin==='git'&&c.args.includes('--detach')));}finally{t.cleanup();}
});
test('backup failure prevents migrations and restores previous running services',async()=>{
  const t=await fixture();try{await t.m.initialize();t.runner.calls=[];t.runner.fail=c=>!!c.options.outputFile;await assert.rejects(t.m.execute('update'));assert.equal(t.runner.calls.filter(c=>c.args.includes('run')&&c.args.includes('migrate')).length,0);assert.ok(t.runner.calls.some(c=>c.args.includes('up')&&c.args.includes('frontend')));assert.equal(t.m.state.phase,'ready');}finally{t.cleanup();}
});
test('migration failure keeps applications stopped and provides a resumable state',async()=>{
  const t=await fixture();try{await t.m.initialize();t.runner.calls=[];t.runner.fail=c=>c.args.includes('run')&&c.args.includes('migrate');await assert.rejects(t.m.execute('update'));assert.equal(t.m.state.phase,'migration-update');assert.ok(!t.runner.calls.some(c=>c.args.includes('up')&&c.args.includes('backend')));t.runner.fail=null;await t.m.execute('resume');assert.equal(t.m.state.phase,'ready');assert.equal(t.runner.calls.filter(isSeed).length,0);}finally{t.cleanup();}
});
test('status and logs work with edited source, stop never removes volumes',async()=>{
  const t=await fixture();try{await t.m.initialize();t.runner.dirty=true;t.runner.calls=[];await t.m.execute('status');await t.m.execute('stop');assert.ok(t.runner.calls.some(c=>c.args.includes('stop')));assert.ok(!t.runner.calls.some(c=>c.args.includes('down')||c.args.includes('-v')||c.args.includes('volume')));}finally{t.cleanup();}
});

test('interrupted pre-migration update restores recorded code/images without seeds or migrations',async()=>{
  const t=await fixture();try{
    await t.m.initialize();t.m.save({...t.m.state,phase:'preparing-update',rollbackImages:{'amanda-backend:local':'sha256:'+'c'.repeat(64)},rollbackRevision:'a'.repeat(40)});t.runner.calls=[];
    await assert.rejects(t.m.execute('start'),/resume/);await t.m.execute('resume');assert.equal(t.m.state.phase,'ready');
    assert.ok(t.runner.calls.some(c=>c.args.includes('--detach')));
    assert.equal(t.runner.calls.filter(isSeed).length,0);assert.ok(!t.runner.calls.some(c=>c.args.includes('run')&&c.args.includes('migrate')));
  }finally{t.cleanup();}
});
test('configuration cannot silently switch Compose projects/volumes',async()=>{
  const t=await fixture();try{fs.appendFileSync(path.join(t.m.state.platform,'.env'),'COMPOSE_PROJECT_NAME=other\n');await assert.rejects(t.m.configuration(),/difere/);}finally{t.cleanup();}
});
test('log filtering protects secrets split between stdout chunks',async()=>{
  const t=temporary();try{let output='';const r=new Runner(path.join(t.root,'test.log'),{write:s=>output+=s});r.secret('synthetic-private-value');await r.run(process.execPath,['-e',"process.stdout.write('synthetic-');setTimeout(()=>process.stdout.write('private-value\\n'),5)"]);assert.ok(!output.includes('synthetic-private-value'));assert.ok(output.includes('[oculto]'));assert.ok(!fs.readFileSync(path.join(t.root,'test.log'),'utf8').includes('synthetic-private-value'));}finally{t.cleanup();}
});

test('binary backup streams preserve every byte and report write errors',async()=>{
  const t=temporary();try{
    const r=new Runner(null,{write:()=>{}}),file=path.join(t.root,'binary.dump');
    await r.run(process.execPath,['-e',"process.stdout.write(Buffer.alloc(2*1024*1024,173))"],{outputFile:file});
    const bytes=fs.readFileSync(file);assert.equal(bytes.length,2*1024*1024);assert.ok(bytes.every(b=>b===173));
    await assert.rejects(r.run(process.execPath,['-e',"process.stdout.write('dump')"],{outputFile:path.join(t.root,'missing','dump')}),/backup/);
  }finally{t.cleanup();}
});

test('adoption checks the official healthy stack and never seeds or replaces configuration',async()=>{
  const t=await fixture();try{
    const before=fs.readFileSync(path.join(t.m.state.platform,'.env'));fs.unlinkSync(t.m.stateFile);t.runner.calls=[];
    await t.m.adopt(SOURCE);assert.equal(t.m.state.initialized,true);assert.equal(t.runner.calls.filter(isSeed).length,0);
    assert.deepEqual(fs.readFileSync(path.join(t.m.state.platform,'.env')),before);
    assert.ok(t.runner.calls.some(c=>c.bin==='git'&&c.args.includes('safe.directory='+t.m.state.platform)));
    fs.unlinkSync(t.m.stateFile);t.runner.remote='https://example.invalid/other';await assert.rejects(t.m.adopt(SOURCE));
    assert.ok(!fs.existsSync(t.m.stateFile));
  }finally{t.cleanup();}
});

test('backup refuses an unhealthy stack before stopping any service',async()=>{
  const t=await fixture();try{await t.m.initialize();t.runner.calls=[];t.runner.badService='redis';await assert.rejects(t.m.execute('backup'),/redis/);assert.ok(!t.runner.calls.some(c=>c.args.includes('stop')));}finally{t.cleanup();}
});
test('POSIX bootstrap calls only Docker and preserves spaced paths and rootless socket',()=>{
  const t=temporary();try{
    const bin=path.join(t.root,'bin');fs.mkdirSync(bin);const log=path.join(t.root,'calls.log');
    fs.writeFileSync(path.join(bin,'docker'),`#!/bin/sh\ncase "$1" in info) printf 'linux\\n';; context) printf 'unix:///run/user/1000/docker.sock\\n';; build|run) printf '%s\\n' "$@" >> "$TEST_LOG";; *) exit 90;; esac\n`,{mode:0o755});
    for(const command of ['apt','apt-get','sudo','git','node','npm','python','openssl','systemctl'])fs.writeFileSync(path.join(bin,command),'#!/bin/sh\nexit 99\n',{mode:0o755});
    const script=path.resolve(__dirname,'../instalador_single.sh');const target=path.join(t.root,'folder with spaces');
    const env={...process.env,PATH:bin+':/usr/bin:/bin',TEST_LOG:log};delete env.DOCKER_HOST;
    const result=spawnSync('/bin/sh',[script,'status','--dir',target],{env,encoding:'utf8'});assert.equal(result.status,0,result.stderr);const text=fs.readFileSync(log,'utf8');assert.ok(text.includes(target+':'+target));assert.ok(text.includes('source=/run/user/1000/docker.sock,target=/var/run/docker.sock'));assert.ok(text.includes('status'));
    assert.notEqual(spawnSync('/bin/sh',[script,'--dir','/etc/amanda'],{env}).status,0);
    assert.notEqual(spawnSync('/bin/sh',[script,'--unknown'],{env}).status,0);
  }finally{t.cleanup();}
});
