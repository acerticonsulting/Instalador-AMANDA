const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const { SOURCE, CORE, sourceUrl, rootPath, normalizeConfig, envValues, Runner, Manager } = require('../docker/installer/manager.cjs');
const { installInput } = require('../docker/installer/cli.cjs');
const {Operations}=require('../docker/installer/operations.cjs');
const {MAIN,TOOLS,API,Menus}=require('../docker/installer/menus.cjs');
const {validateOptions,writeEnv}=require('../docker/installer/options.cjs');
const {Addons}=require('../docker/installer/addons.cjs');
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
  mask(s) { return s; }
  async run(bin,args,options={}) {
    this.calls.push({bin,args:[...args],options});
    if(this.fail?.({bin,args,options}))throw Error('Simulated failure');
    let stdout='';
    if(bin==='git') {
      if(args.includes('clone')) {
        const dir=args.at(-1); fs.mkdirSync(path.join(dir,'.git/info'),{recursive:true});fs.mkdirSync(path.join(dir,'.secrets'));fs.mkdirSync(path.join(dir,'docker'));
        fs.writeFileSync(path.join(dir,'docker-compose.yml'),'# official test fixture\n');fs.writeFileSync(path.join(dir,'docker/ensure-transcription-key.cjs'),'');fs.writeFileSync(path.join(dir,'.secrets/github_token'),'');
      }
      if(args.includes('get-url'))stdout=options.cwd?.includes('/addons/')?(this.addonRemote||this.remote):this.remote;
      if(args.includes('status'))stdout=this.dirty?' M docker-compose.yml\n':'';
      if(args.includes('rev-parse'))stdout='a'.repeat(40);
    } else if(bin===process.execPath && args[0].endsWith('configure.cjs')) fs.writeFileSync(path.join(options.cwd,'.env'),defaultEnv);
    else if(bin==='docker') {
      if(args[0]==='info')stdout=JSON.stringify({OSType:'linux',ServerVersion:'27.5.1',Architecture:'x86_64'});
      else if(args[0]==='volume')stdout=this.existing.join('\n');
      else if(args[0]==='network')stdout='';
      else if(args[0]==='ps')stdout=this.existingContainers?'b'.repeat(64):'';
      else if(args[0]==='inspect'){if(args.some(a=>a.includes('.Config.Labels')))return{stdout:'',stderr:'',code:1};stdout='sha256:'+'c'.repeat(64);}
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
      if(args[0]==='run'&&args.includes('-tzf'))stdout='./\n'+['redis_data','backend_database','backend_private','backend_public','oficial_public','wuzapi_data','rabbitmq_data','caddy_data','caddy_config'].map(k=>'./'+k+'/').join('\n');
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

test('all original main/tools/API numbers are preserved and menus repeat after an operation',async()=>{
  assert.deepEqual(MAIN.slice(0,11).map(x=>x[0]),Array.from({length:11},(_,i)=>String(i+1)));
  assert.deepEqual(TOOLS.map(x=>x[0]),['2','3','4','5','6','7','8','9','10','11','12','13','14','15','16','17','18','19','20','21','22','23','24','25','26','27','30','31','32']);
  assert.deepEqual(API.map(x=>x[0]),Array.from({length:9},(_,i)=>String(i+1)));
  const t=temporary();try{const m=new Manager(t.root,new FakeRunner()),answers=['14','0'],calls=[],menus=new Menus(m,async()=>answers.shift(),null,{out:()=>{}});menus.dispatch=async action=>calls.push(action);await menus.run();assert.deepEqual(calls,['doctor']);assert.equal(answers.length,0);}finally{t.cleanup();}
});

test('nested operation locks are reentrant but a second independent manager is blocked',async()=>{
  const t=temporary();try{const m=new Manager(t.root,new FakeRunner());await m.lock(async()=>{await m.lock(async()=>{});await assert.rejects(new Manager(t.root,new FakeRunner()).lock(async()=>{}),/Outra operação/);});assert.ok(!fs.existsSync(path.join(m.private,'operation.lock')));}finally{t.cleanup();}
});

test('advanced installation config applies SMTP, Facebook, DB URI, master and support without touching source',async()=>{
  const t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);try{await m.prepare(input({options:{appName:'Minha AMANDA',supportPhone:'+55 (11) 99999-9999',databasePassword:'db$#@value',masterPassword:'master$#value',officialPort:6100,wuzapiPort:8190,backendEnv:{MAIL_HOST:'smtp.example.test',MAIL_PASS:'mail$#secret',FACEBOOK_APP_ID:'123',FACEBOOK_APP_SECRET:'facebook-secret'}}}));
    const env=envValues(path.join(m.state.platform,'.env')),backend=envValues(path.join(m.state.platform,'.env.backend'));assert.equal(env.DB_URI_PASSWORD,encodeURIComponent('db$#@value'));assert.equal(env.PORT_APIOFICIAL,'6100');assert.equal(env.REACT_APP_NUMBER_SUPPORT,'+55 (11) 99999-9999');assert.equal(backend.MAIL_HOST,'smtp.example.test');assert.ok(r.secrets.includes('db$#@value'));assert.equal(JSON.parse(fs.readFileSync(path.join(m.private,'admin-access.json'))).appName,'Minha AMANDA');
    assert.equal(fs.statSync(path.join(m.state.platform,'.env.backend')).mode&0o777,0o600);
  }finally{t.cleanup();}
  for(const o of[{unknown:'x'},{officialPort:0},{supportPhone:'";alert(1)'},{backendEnv:{DB_HOST:'other'}},{backendEnv:{MAIL_PORT:'bad'}},{backendEnv:{TRANSCRIBE_URL:'javascript:alert(1)'}}])assert.throws(()=>validateOptions(o));
});

test('runtime options preserve passwords and unknown fields; invalid changes do not stop services',async()=>{
  const t=await fixture();try{await t.m.initialize();const ops=new Operations(t.m),file=path.join(t.m.state.platform,'.env');fs.appendFileSync(file,'CUSTOM_VALUE=preserve\n');const old=envValues(file).DB_PASS;
    await ops.configure({network:{frontendUrl:'http://localhost:3100',backendUrl:'http://localhost:8180'},backendEnv:{MAIL_HOST:'smtp.example.test',MAIL_PASS:'hidden$value'},supportPhone:'5511999999999'});
    assert.equal(envValues(file).DB_PASS,old);assert.equal(envValues(file).CUSTOM_VALUE,'preserve');assert.equal(envValues(file).PORT_FRONTEND,'3100');assert.equal(envValues(file).PORT_BACKEND,'8180');assert.equal(envValues(path.join(t.m.state.platform,'.env.backend')).MAIL_HOST,'smtp.example.test');
    t.runner.calls=[];await assert.rejects(ops.configure({backendEnv:{DB_HOST:'unsafe'}}));assert.ok(!t.runner.calls.some(c=>c.args.includes('stop')));
  }finally{t.cleanup();}
});

test('configuration failure restores old env and state rather than leaving a half applied URL',async()=>{
  const t=await fixture();try{await t.m.initialize();const before=fs.readFileSync(path.join(t.m.state.platform,'.env'),'utf8');let fail=true;t.runner.fail=c=>c.args.includes('up')&&c.args.includes('frontend')&&fail?(fail=false,true):false;await assert.rejects(new Operations(t.m).configure({network:{frontendUrl:'http://localhost:3100'}}));assert.equal(fs.readFileSync(path.join(t.m.state.platform,'.env'),'utf8'),before);assert.equal(t.m.state.frontendUrl,'http://localhost:3000');}finally{t.cleanup();}
});

test('push setup generates a matching P-256 key pair once and preserves subscriptions on reconfiguration',async()=>{
  const t=await fixture();try{await t.m.initialize();const ops=new Operations(t.m);await ops.configure({pushEmail:'owner@example.test'});const file=path.join(t.m.state.platform,'.env.backend'),first=envValues(file);assert.equal(Buffer.from(first.VAPID_PUBLIC_KEY,'base64url').length,65);assert.equal(Buffer.from(first.VAPID_PRIVATE_KEY,'base64url').length,32);await ops.configure({pushEmail:'new@example.test'});assert.equal(envValues(file).VAPID_PRIVATE_KEY,first.VAPID_PRIVATE_KEY);}finally{t.cleanup();}
});

test('service submenu targets only the selected Compose service and rejects arbitrary names',async()=>{
  const t=await fixture();try{await t.m.initialize();t.runner.calls=[];const ops=new Operations(t.m);await ops.services('restart','api_oficial');const call=t.runner.calls.find(c=>c.args.includes('restart'));assert.equal(call.args.at(-1),'api_oficial');await assert.rejects(ops.services('restart','some-other-project'));assert.ok(!t.runner.calls.some(c=>c.bin==='sudo'));}finally{t.cleanup();}
});

test('restore verifies hashes and typed project confirmation before any destructive call',async()=>{
  const t=await fixture();try{await t.m.initialize();const dir=await t.m.backup();t.runner.calls=[];const ops=new Operations(t.m);await assert.rejects(ops.restore(dir,'amanda','wrong'),/Confirmação/);assert.ok(!t.runner.calls.some(c=>c.args.includes('dropdb')));fs.appendFileSync(path.join(dir,'amanda.dump'),'corrupt');await assert.rejects(ops.restore(dir,'amanda','RESTAURAR amanda'),/Integridade/);assert.ok(!t.runner.calls.some(c=>c.args.includes('dropdb')));}finally{t.cleanup();}
});

test('database restore is targeted, backed up first, and a failure leaves services stopped for recovery',async()=>{
  const t=await fixture();try{await t.m.initialize();const dir=await t.m.backup();t.runner.calls=[];await new Operations(t.m).restore(dir,'api_oficial','RESTAURAR amanda');const drops=t.runner.calls.filter(c=>c.args.includes('dropdb'));assert.equal(drops.length,1);assert.equal(drops[0].args.at(-1),'api_oficial');assert.ok(t.runner.calls.findIndex(c=>c.args.includes('pg_dump'))<t.runner.calls.findIndex(c=>c.args.includes('dropdb')));assert.equal(t.m.state.phase,'ready');
    t.runner.calls=[];t.runner.fail=c=>c.args.includes('pg_restore')&&c.args.includes('--single-transaction');await assert.rejects(new Operations(t.m).restore(dir,'amanda','RESTAURAR amanda'));assert.equal(t.m.state.phase,'restoring');assert.ok(!t.runner.calls.some(c=>c.args.includes('up')&&c.args.includes('backend')));
    t.runner.fail=null;await new Operations(t.m).restore(dir,'amanda','RESTAURAR amanda');assert.equal(t.m.state.phase,'ready');
  }finally{t.cleanup();}
});

test('SQL import validates path and cluster commands, then upgrades only the selected database without seeds',async()=>{
  const t=await fixture();try{await t.m.initialize();const imports=path.join(t.m.root,'imports');fs.mkdirSync(imports);const file=path.join(imports,'amanda.sql');fs.writeFileSync(file,'CREATE TABLE example(id integer);\n');const ops=new Operations(t.m);t.runner.calls=[];
    await ops.importDatabase(file,'amanda','IMPORTAR amanda');assert.equal(t.runner.calls.filter(isSeed).length,0);assert.ok(t.runner.calls.some(c=>c.args.includes('psql')&&c.options.inputFile===file&&c.args.includes('ON_ERROR_STOP=1')));assert.ok(t.runner.calls.some(c=>c.args.includes('migrate')));
    t.runner.calls=[];fs.writeFileSync(file,'\\connect other_database\n');await assert.rejects(ops.importDatabase(file,'amanda','IMPORTAR amanda'),/psql/);assert.ok(!t.runner.calls.some(c=>c.args.includes('dropdb')));
    fs.writeFileSync(file,'DROP DATABASE other_database;\n');await assert.rejects(ops.importDatabase(file,'amanda','IMPORTAR amanda'),/cluster/);
    const outside=path.join(t.m.root,'outside.sql');fs.writeFileSync(outside,'SELECT 1;');await assert.rejects(ops.importDatabase(outside,'amanda','IMPORTAR amanda'),/imports/);
  }finally{t.cleanup();}
});

test('uninstall keeps data by default; destructive selection requires exact confirmation and volume ownership',async()=>{
  const t=await fixture();try{await t.m.initialize();const ops=new Operations(t.m);t.runner.calls=[];await ops.uninstall(false,'REMOVER amanda');assert.ok(t.runner.calls.some(c=>c.args.includes('down')&&!c.args.includes('--volumes')));t.runner.calls=[];await assert.rejects(ops.uninstall(true,'wrong'));assert.ok(!t.runner.calls.some(c=>c.args.includes('down')));await assert.rejects(ops.uninstall(true,'DELETAR TUDO amanda'));assert.ok(!t.runner.calls.some(c=>c.args.includes('--volumes')));}finally{t.cleanup();}
});

test('scheduled jobs run in containers and refuse invalid times without creating host cron tasks',async()=>{
  const t=await fixture();try{await t.m.initialize();t.runner.calls=[];const ops=new Operations(t.m);await ops.schedule('backup',3);assert.equal(JSON.parse(fs.readFileSync(path.join(t.m.private,'schedule-backup.json'))).hour,3);const call=t.runner.calls.find(c=>c.args.includes('--restart'));assert.ok(call.args.includes('/opt/amanda-installer/scheduler.cjs'));assert.ok(call.args.includes('type=bind,source='+t.m.root+',target='+t.m.root));assert.ok(!t.runner.calls.some(c=>['crontab','systemctl'].includes(c.bin)));await assert.rejects(ops.schedule('update',25));}finally{t.cleanup();}
});

test('rollback restores data and recorded revision before starting the application',async()=>{
  const t=await fixture();try{await t.m.initialize();const dir=await t.m.backup();t.runner.calls=[];await new Operations(t.m).rollback(dir,'RESTAURAR amanda');const checkout=t.runner.calls.findIndex(c=>c.bin==='git'&&c.args.includes('--detach')),start=t.runner.calls.findIndex(c=>c.args.includes('up')&&c.args.includes('backend'));assert.ok(checkout>=0&&start>checkout);assert.equal(t.m.state.phase,'ready');assert.equal(t.runner.calls.filter(isSeed).length,0);}finally{t.cleanup();}
});

test('GHCR credential uses stdin, private storage and no token in CLI arguments',async()=>{
  const t=await fixture();try{await t.m.initialize();t.runner.calls=[];await new Operations(t.m).ghcr('operator','synthetic-registry-secret');const login=t.runner.calls.find(c=>c.args.includes('login'));assert.ok(login.args.includes('--password-stdin'));assert.ok(login.options.inputFile);assert.ok(!JSON.stringify(login.args).includes('synthetic-registry-secret'));assert.ok(!fs.existsSync(login.options.inputFile));}finally{t.cleanup();}
});

test('external components reject missing Docker contracts and never borrow the connector token',async()=>{
  const t=await fixture();try{await t.m.initialize();t.runner.calls=[];const addon=new Addons(t.m);await assert.rejects(addon.deploy('voz',{sourceUrl:'https://token@github.com/owner/voice'}));assert.ok(!t.runner.calls.some(c=>c.args.includes('clone')));
    t.runner.addonRemote='https://github.com/owner/voice';await assert.rejects(addon.deploy('voz',{sourceUrl:t.runner.addonRemote,token:'synthetic-addon-token'}),/healthcheck/);assert.ok(!fs.existsSync(path.join(t.m.private,'addon-voz.json')));assert.equal(fs.readFileSync(path.join(t.m.state.platform,'.secrets/github_token'),'utf8'),'');assert.ok(!t.runner.calls.some(c=>c.args.includes('up')));
  }finally{t.cleanup();}
});

test('restored main menu is shown before any Docker download and exit creates no resources',()=>{
  const t=temporary();try{const bin=path.join(t.root,'bin');fs.mkdirSync(bin);const log=path.join(t.root,'docker-calls');fs.writeFileSync(path.join(bin,'docker'),'#!/bin/sh\nprintf called >> "$TEST_LOG"\nexit 99\n',{mode:0o755});const script=path.resolve(__dirname,'../instalador_single.sh');const quote=s=>"'"+s.replace(/'/g,"'\\''")+"'";
    const run=spawnSync('script',['-q','-c','sh '+quote(script),'/dev/null'],{input:'0\n',encoding:'utf8',timeout:5000,env:{...process.env,PATH:bin+':/usr/bin:/bin',TEST_LOG:log}});assert.equal(run.status,0,run.stderr);assert.ok(run.stdout.includes('[11]'));assert.ok(run.stdout.includes('[8]'));assert.ok(!fs.existsSync(log));
    const nonInteractive=spawnSync(process.execPath,[path.resolve(__dirname,'../docker/installer/cli.cjs'),'menu'],{env:{...process.env,AMANDA_INSTALL_DIR:t.root},encoding:'utf8',timeout:5000});assert.equal(nonInteractive.status,1);assert.ok(nonInteractive.stderr.includes('terminal interativo'));
  }finally{t.cleanup();}
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
  const t=await fixture();try{t.runner.badService='frontend';await assert.rejects(t.m.initialize());t.runner.badService=null;await new Operations(t.m).configure({network:{frontendUrl:'http://localhost:3100'}});assert.equal(t.m.state.initialized,false);await t.m.execute('resume');assert.equal(t.runner.calls.filter(isSeed).length,1);assert.equal(t.m.state.initialized,true);}finally{t.cleanup();}
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
