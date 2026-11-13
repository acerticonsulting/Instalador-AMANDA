const { test } = require('node:test');
require('./https_check_tests.cjs');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const { SOURCE, CORE, sourceUrl, rootPath, normalizeConfig, envValues, Runner, Manager } = require('../docker/installer/manager.cjs');
const { advancedInput: rawInstallInput } = require('../docker/installer/cli.cjs');
const installInput=(file,options={})=>rawInstallInput(file,{checkDomains:async()=>({}),...options});
require('./domain_preflight_tests.cjs');
require('./edge_diagnostics_tests.cjs');
const {Operations}=require('../docker/installer/operations.cjs');
const {MAIN,TOOLS,API,Menus}=require('../docker/installer/menus.cjs');
const {validateOptions,writeEnv,vapidPrivateKey}=require('../docker/installer/options.cjs');
const {Addons}=require('../docker/installer/addons.cjs');
const {forbiddenHostCommand,activeShellFiles}=require('./host_contract.cjs');
test('production shell cannot install or execute application dependencies on the host',()=>{
  for(const command of ['apt install nodejs','sudo apt-get install git','yum install nginx','dnf install python3','apk add ffmpeg','snap install node','npm install','pip3 install lib','pm2 start server','curl https://example.test | bash','node server.js','/usr/bin/python3 script.py','true; npm install'])assert.ok(forbiddenHostCommand(command),command);
  assert.ok(!forbiddenHostCommand('docker run --rm node:22 npm install'));
  for(const file of activeShellFiles(path.resolve(__dirname,'..')))assert.ok(!forbiddenHostCommand(fs.readFileSync(file,'utf8')),file);
  assert.ok(!activeShellFiles(path.resolve(__dirname,'..')).some(f=>f.endsWith('Dockerfile')));
});
test('archived native recipes are blocked before any historical command',()=>{
  const root=path.resolve(__dirname,'../legacy'),safe=new Set(['mf_operacoes_seguras.sh','mf_admin_inicial.sh','mf_repositorio_amanda.sh']);
  function visit(dir){for(const e of fs.readdirSync(dir,{withFileTypes:true})){const p=path.join(dir,e.name);if(e.isDirectory())visit(p);else if(e.name.endsWith('.sh')&&!safe.has(e.name)){const first=fs.readFileSync(p,'utf8').split(/\r?\n/).filter(l=>l.trim()&&!l.startsWith('#')).slice(0,2);assert.ok(first[0].startsWith("printf '%s\\n'"),p);assert.equal(first[1],'return 1 2>/dev/null || exit 1');}}}
  visit(root);
});
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
    if(args.includes('-e')&&args.lastIndexOf('-e')===args.length-2&&(bin===process.execPath||bin==='docker'&&args.includes('node')))new (require('node:vm').Script)(args.at(-1));
    if(this.fail?.({bin,args,options}))throw Error('Simulated failure');
    let stdout='';
    if(bin==='git') {
      if(args.includes('clone')) {
        const dir=args.at(-1); fs.mkdirSync(path.join(dir,'.git/info'),{recursive:true});fs.mkdirSync(path.join(dir,'.secrets'));fs.mkdirSync(path.join(dir,'docker'));
        fs.writeFileSync(path.join(dir,'docker-compose.yml'),'# official test fixture\n');fs.writeFileSync(path.join(dir,'docker/ensure-transcription-key.cjs'),'');fs.writeFileSync(path.join(dir,'.secrets/github_token'),'');
        fs.writeFileSync(path.join(dir,'.env.example'),defaultEnv);
      }
      if(args.includes('get-url'))stdout=options.cwd?.includes('/addons/')?(this.addonRemote||this.remote):this.remote;
      if(args.includes('status'))stdout=this.dirty?' M docker-compose.yml\n':'';
      if(args.includes('rev-parse'))stdout='a'.repeat(40);
      if(options.cwd?.includes('/addons/')&&args[0]!=='clone'){
        if(args.includes('merge')&&this.invalidateAddonOnMerge)this.addonValid=false;
        if(args.includes('checkout')&&this.invalidateAddonOnMerge)this.addonValid=true;
      }
    } else if(bin===process.execPath && args[0].endsWith('configure.cjs')) fs.writeFileSync(path.join(options.cwd,'.env'),defaultEnv,{mode:0o600});
    else if(bin==='docker') {
      if(args.at(-1)?.includes('async function inspectHttps'))return {stdout:JSON.stringify({ok:true,results:[]})};
      if(args[0]==='info')stdout=JSON.stringify({OSType:'linux',ServerVersion:'27.5.1',Architecture:'x86_64',MemTotal:8*1024**3,NCPU:4});
      else if(args[0]==='volume'){if(args[1]==='inspect'&&this.volumeAbsent)return {stdout:'',stderr:'',code:1};stdout=this.existing.join('\n');}
      else if(args[0]==='network')stdout=(this.existingNetworks||[]).join('\n');
      else if(args[0]==='ps')stdout=args.includes('--format')?(this.containerNames||(args.includes('-a')?[]:(this.runtimeContainerNames||CORE.map(n=>(this.project||'amanda')+'_'+n)))).join('\n'):(this.existingContainers?'b'.repeat(64):'');
      else if(args[0]==='inspect'){if(args.some(a=>a.includes('.Config.Labels')))return{stdout:'',stderr:'',code:1};stdout='sha256:'+'c'.repeat(64);}
      else if(args[0]==='compose') {
        this.project=args[args.indexOf('-p')+1];
        if(args.includes('config')) {
          const project=args[args.indexOf('-p')+1];this.project=project;
          stdout=JSON.stringify(project.endsWith('_voz')&&this.addonValid?{services:{voice:{container_name:project+'_voice',image:project+'-voice:local',environment:{},healthcheck:{test:['CMD','true']}}},volumes:{voice_data:{name:project+'_voice_data'}},networks:{amanda:{name:'amanda_default',external:true}}}:{services:Object.fromEntries([...CORE,'edge','migrate','seed','official-db-init','official-migrate'].map(n=>[n,{image:project+'-'+n+':local',environment:{}}])),networks:{default:{name:project+'_default',external:!!this.externalNetwork}},volumes:Object.fromEntries(['postgres_data','redis_data','backend_database','backend_private','backend_public','oficial_public','wuzapi_data','rabbitmq_data','caddy_data','caddy_config'].map(n=>[n,{name:project+'_'+n}]))});
          if(args.includes(path.join(path.dirname(args[args.indexOf('--project-directory')+1]),'.amanda-installer','compose-names.json'))){const c=JSON.parse(stdout),overlay=JSON.parse(fs.readFileSync(args[args.lastIndexOf('-f')+1]));for(const [k,v]of Object.entries(overlay.services))c.services[k]={...c.services[k],...v};stdout=JSON.stringify(c);}
          if(this.configTransform)stdout=JSON.stringify(this.configTransform(JSON.parse(stdout)));
        } else if(args.includes('ps')) {
          if(args.includes('-q'))stdout='b'.repeat(64);
          else stdout=(args[args.indexOf('-p')+1].endsWith('_voz')&&this.addonValid?['voice']:[...CORE,'edge']).map(Service=>JSON.stringify({Service,Name:this.wrongName?'wrong':(this.project||'amanda')+'_'+(Service==='edge'?'caddy':Service),State:Service===this.badService?'exited':'running',Health:'healthy'})).join('\n');
        } else if(args.includes('psql'))stdout=this.users;
      }
      if(args[0]==='run' && args.includes('-czf')) {
        this.archiveKeys=args.filter(a=>a.startsWith('type=volume,')).map(a=>a.match(/target=\/data\/([^,]+)/)?.[1]).filter(Boolean);
        const bind=args.find(a=>a.startsWith('type=bind,source=')); const dir=bind.slice('type=bind,source='.length).split(',')[0];fs.writeFileSync(path.join(dir,'volumes.tgz'),'fixture archive');
      }
      if(args[0]==='run'&&args.includes('-tzf'))stdout='./\n'+(this.archiveKeys||[]).map(k=>'./'+k+'/').join('\n');
    }
    if(options.outputFile)fs.writeFileSync(options.outputFile,'fixture dump');
    return {stdout,stderr:'',code:0};
  }
}
async function fixture() { const t=temporary(),runner=new FakeRunner(),m=new Manager(t.root,runner);await m.prepare(input());return {...t,runner,m}; }

test('preparation interrupted before configuration resumes saved choices without another clone or questionnaire',async()=>{
 const t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);try{
  r.fail=c=>c.bin===process.execPath&&c.args[0].endsWith('configure.cjs');
  const config=input({sourceToken:'synthetic-source',adminPassword:'selected-password',options:{pg:{maxConnections:100,sharedBuffers:'128MB'}}});
  await assert.rejects(m.prepare(config));assert.equal(m.state.phase,'preparing');assert.ok(fs.existsSync(path.join(m.private,'setup.json')));
  r.fail=null;await m.execute('resume');assert.equal(m.state.phase,'ready');assert.equal(r.calls.filter(c=>c.bin==='git'&&c.args.includes('clone')).length,1);assert.equal(r.calls.filter(isSeed).length,1);
  assert.equal(fs.readFileSync(path.join(m.private,'source-token'),'utf8'),'synthetic-source');
  assert.equal(JSON.parse(fs.readFileSync(path.join(m.private,'admin-access.json'))).password,'selected-password');assert.equal(envValues(path.join(m.state.platform,'.env')).PG_MAX_CONNECTIONS,'100');
 }finally{t.cleanup();}
});

test('source acquisition failure resumes saved company without creating a second deployment',async()=>{
 const t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);try{
  r.fail=c=>c.bin==='git'&&c.args.includes('clone');await assert.rejects(m.prepare(input({adminPassword:'saved-choice'})));assert.ok(!fs.existsSync(m.state.platform));
  r.fail=null;await require('../docker/installer/deploy.cjs').startInstallation(m,{automatic:false,question:async()=> '1',collect:async()=>{throw Error('must not repeat questions');},out(){}});
  assert.equal(m.state.phase,'ready');assert.equal(r.calls.filter(isSeed).length,1);assert.equal(JSON.parse(fs.readFileSync(path.join(m.private,'admin-access.json'))).password,'saved-choice');assert.ok(!r.calls.some(c=>c.args.includes('--provision')));
 }finally{t.cleanup();}
});

test('failed Docker preflight retains approved configuration before preparation starts',async()=>{
 const t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);try{
  const deploy=require('../docker/installer/deploy.cjs');r.fail=c=>c.bin==='docker'&&c.args[0]==='info';await assert.rejects(deploy.install(m,input({adminPassword:'approved-choice'})));assert.ok(!fs.existsSync(m.stateFile));
  assert.equal(JSON.parse(fs.readFileSync(path.join(m.private,'setup.json'))).config.adminPassword,'approved-choice');r.fail=null;
  await deploy.startInstallation(m,{automatic:false,config:input(),collect:async()=>{throw Error('must not repeat questionnaire');},out(){}});
  assert.equal(m.state.phase,'ready');assert.equal(JSON.parse(fs.readFileSync(path.join(m.private,'admin-access.json'))).password,'approved-choice');
 }finally{t.cleanup();}
});
test('failure after configuration publication reuses exact credentials, URLs and push keys on resume',async()=>{
 const t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);try{
  r.fail=c=>c.bin==='docker'&&c.args.includes('config');
  await assert.rejects(m.prepare(input({adminPassword:'kept-password',options:{pushEmail:'owner@example.test'}})));
  const env=fs.readFileSync(path.join(m.state.platform,'.env'),'utf8'),backend=fs.readFileSync(path.join(m.state.platform,'.env.backend'),'utf8'),account=fs.readFileSync(path.join(m.private,'admin-access.json'),'utf8');
  assert.equal(m.state.configurationReady,true);r.fail=null;await m.execute('resume');
  assert.equal(fs.readFileSync(path.join(m.state.platform,'.env'),'utf8'),env);assert.equal(fs.readFileSync(path.join(m.state.platform,'.env.backend'),'utf8'),backend);assert.equal(fs.readFileSync(path.join(m.private,'admin-access.json'),'utf8'),account);
  assert.equal(r.calls.filter(c=>c.bin===process.execPath&&c.args[0].endsWith('configure.cjs')).length,1);assert.equal(r.calls.filter(isSeed).length,1);
 }finally{t.cleanup();}
});
test('changed configuration after interrupted preparation is preserved and blocks publication and seeds',async()=>{
 const t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);try{
  r.fail=c=>c.bin==='docker'&&c.args.includes('config');await assert.rejects(m.prepare(input()));r.fail=null;
  const file=path.join(m.state.platform,'.env');fs.appendFileSync(file,'CUSTOM=keep\n');const before=fs.readFileSync(file,'utf8');
  await assert.rejects(m.execute('resume'),/nenhum arquivo foi sobrescrito/);assert.equal(fs.readFileSync(file,'utf8'),before);assert.equal(r.calls.filter(isSeed).length,0);
 }finally{t.cleanup();}
});
test('install recognizes a failed build and resumes existing configuration without reprovisioning',async()=>{
 const t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);try{
  const deploy=require('../docker/installer/deploy.cjs');r.fail=c=>c.bin==='docker'&&c.args.includes('build');await assert.rejects(deploy.install(m,input({adminPassword:'keep-me'})));
  const before=fs.readFileSync(path.join(m.state.platform,'.env'),'utf8');r.fail=null;
  await deploy.startInstallation(m,{automatic:false,config:input(),collect:async()=>{throw Error('must not collect');},out(){}});
  assert.equal(m.state.phase,'ready');assert.equal(fs.readFileSync(path.join(m.state.platform,'.env'),'utf8'),before);assert.equal(r.calls.filter(isSeed).length,1);assert.equal(r.calls.filter(c=>c.bin==='git'&&c.args.includes('clone')).length,1);assert.ok(!r.calls.some(c=>c.args.includes('--provision')||c.args.includes('down')));
 }finally{t.cleanup();}
});
test('first-install migration failure resumes claimed resources without reasserting an empty project',async()=>{
 const t=await fixture();try{
  t.runner.fail=c=>c.args.includes('run')&&c.args.includes('migrate');await assert.rejects(t.m.initialize());assert.equal(t.m.state.phase,'migrations');assert.equal(t.m.state.resourcesClaimed,true);
  const before=fs.readFileSync(path.join(t.m.state.platform,'.env'),'utf8');t.runner.fail=null;t.runner.existing=['amanda_postgres_data'];await t.m.execute('resume');assert.equal(t.m.state.phase,'ready');assert.equal(t.runner.calls.filter(isSeed).length,1);assert.equal(fs.readFileSync(path.join(t.m.state.platform,'.env'),'utf8'),before);
 }finally{t.cleanup();}
});

test('HTTPS pending and legacy starting resume validation without build migration up or seed',async()=>{
 for(const phase of ['starting','https-pending']){const t=await fixture();try{
  await t.m.initialize();t.m.save({...t.m.state,initialized:false,phase,seedSucceeded:true});
  const before=fs.readFileSync(path.join(t.m.state.platform,'.env'),'utf8');t.runner.calls=[];
  await t.m.execute('resume');assert.equal(t.m.state.phase,'ready');
  assert.ok(!t.runner.calls.some(c=>c.args.includes('build')||c.args.includes('up')||c.args.includes('migrate')||isSeed(c)||c.args.includes('clone')||c.args.includes('down')));
  assert.equal(fs.readFileSync(path.join(t.m.state.platform,'.env'),'utf8'),before);
 }finally{t.cleanup();}}
});

test('older prepared state without draft resumes only with consistent private config and proven empty resources',async()=>{
 for(const occupied of [false,true]){const t=await fixture();try{
  fs.unlinkSync(path.join(t.m.private,'setup.json'));fs.rmSync(path.join(t.m.private,'setup-files'),{recursive:true});
  const state={...t.m.state,phase:'preparing'};for(const key of ['freshResourcesVerified','configurationFiles','configurationReady','adminFingerprint','naming'])delete state[key];t.m.save(state);
  writeEnv(path.join(t.m.state.platform,'.env'),{MASTER_KEY:'fixture-master',TOKEN_API_OFICIAL:'fixture-official'});
  const before=fs.readFileSync(path.join(t.m.state.platform,'.env'),'utf8');if(occupied)t.runner.existing=['amanda_postgres_data'];
  if(occupied){await assert.rejects(t.m.execute('resume'),/volumes já existem/);assert.equal(t.runner.calls.filter(isSeed).length,0);assert.equal(t.m.state.phase,'preparing');}
  else{await t.m.execute('resume');assert.equal(t.m.state.phase,'ready');assert.equal(t.runner.calls.filter(isSeed).length,1);}
  assert.equal(fs.readFileSync(path.join(t.m.state.platform,'.env'),'utf8'),before);
 }finally{t.cleanup();}}
});

test('legacy recovery asks only missing admin fields after resource proof and preserves saved settings',async()=>{
 for(const missing of ['email','password']){const t=await fixture();try{
  fs.unlinkSync(path.join(t.m.private,'setup.json'));fs.rmSync(path.join(t.m.private,'setup-files'),{recursive:true});
  const state={...t.m.state,phase:'preparing'};for(const key of ['freshResourcesVerified','configurationFiles','configurationReady','adminFingerprint'])delete state[key];t.m.save(state);
  writeEnv(path.join(t.m.state.platform,'.env'),{MASTER_KEY:'fixture-master',TOKEN_API_OFICIAL:'fixture-official'});
  const file=path.join(t.m.private,'admin-access.json'),admin=JSON.parse(fs.readFileSync(file));admin.email='kept@example.test';admin.password='kept-secret';admin.initialSettings={preserved:'yes'};delete admin[missing];fs.writeFileSync(file,JSON.stringify(admin));
  const env=fs.readFileSync(path.join(t.m.state.platform,'.env'),'utf8'),prompts=[];
  t.m.recoveryQuestion=async label=>{prompts.push(label);return label.includes('E-mail')?'new@example.test':'new-secret';};await t.m.execute('resume');
  const saved=JSON.parse(fs.readFileSync(file));assert.equal(saved.email,missing==='email'?'new@example.test':'kept@example.test');assert.equal(saved.password,missing==='password'?'new-secret':'kept-secret');assert.deepEqual(saved.initialSettings,{preserved:'yes'});assert.equal(prompts.length,missing==='email'?1:2);assert.equal(fs.readFileSync(path.join(t.m.state.platform,'.env'),'utf8'),env);assert.equal(t.runner.calls.filter(isSeed).length,1);
 }finally{t.cleanup();}}
});

test('legacy recovery refuses noninteractive missing credentials and redacts corrupt admin JSON errors',async()=>{
 for(const corrupt of [false,true]){const t=await fixture();try{
  fs.unlinkSync(path.join(t.m.private,'setup.json'));fs.rmSync(path.join(t.m.private,'setup-files'),{recursive:true});
  const state={...t.m.state,phase:'preparing'};for(const key of ['freshResourcesVerified','configurationFiles','configurationReady','adminFingerprint'])delete state[key];t.m.save(state);
  writeEnv(path.join(t.m.state.platform,'.env'),{MASTER_KEY:'fixture-master',TOKEN_API_OFICIAL:'fixture-official'});
  const file=path.join(t.m.private,'admin-access.json'),before=corrupt?'{"password":"private-do-not-print",BROKEN}':JSON.stringify({email:'kept@example.test'});fs.writeFileSync(file,before);
  await assert.rejects(t.m.execute('resume'),error=>{assert.ok(!error.message.includes('private-do-not-print'));return /terminal interativo|Arquivo privado de acesso inválido/.test(error.message);});
  assert.equal(fs.readFileSync(file,'utf8'),before);assert.equal(t.runner.calls.filter(isSeed).length,0);
 }finally{t.cleanup();}}
});

test('integration: old main fails after PostgreSQL choice; corrected principal menu resumes /home/deploy/amanda',async()=>{
 const root='/home/deploy/amanda';assert.ok(!fs.existsSync(root),'isolated test directory must not preexist');
 const r=new FakeRunner(),m=new Manager(root,r),answers=['1','localhost','owner@example.test','amanda','db-choice','master-choice','AMANDA','5511999999999','','','source-choice',SOURCE,'s','admin-choice','admin-choice','s','1'],output=[];
 try{
  const config=await require('../docker/installer/historical.cjs').collectHistorical({question:async()=>answers.shift(),out:s=>output.push(s),directory:root});
  assert.equal(answers.length,0);assert.equal(config.options.pg.maxConnections,100);await m.prepare(config);
  const before=fs.readFileSync(path.join(m.state.platform,'.env'),'utf8');
  assert.throws(()=>require('./fixtures/deploy-main-8d748f1.cjs').provision('amanda',{host:'',run(){throw Error('must not provision');}}),/Diretório da empresa já contém arquivos\. Use --dir e resume\/adopt/);
  const prompts=[],question=async label=>{prompts.push(label);return label==='Nome técnico da empresa'?'amanda':'1';};
  const deploy=require('../docker/installer/deploy.cjs'),menu=new Menus(m,question,null,{out(){},startInstall:target=>deploy.startInstallation(target,{automatic:true,question,out(){},collect:async()=>{throw Error('full questionnaire repeated');}})});
  await menu.dispatch('install');assert.equal(m.state.phase,'ready');assert.deepEqual(prompts,['Nome técnico da empresa','Selecione a opção']);assert.equal(fs.readFileSync(path.join(m.state.platform,'.env'),'utf8'),before);assert.equal(r.calls.filter(isSeed).length,1);assert.ok(!r.calls.some(c=>c.args.includes('--provision')));assert.equal(envValues(path.join(m.state.platform,'.env')).PG_MAX_CONNECTIONS,'100');
 }finally{assert.equal(root,'/home/deploy/amanda');fs.rmSync(root,{recursive:true,force:true});}
});
test('company names are normalized separately from commercial titles',()=>{
  assert.equal(normalizeConfig(input({project:' ÁCERTI Filial-2 '})).project,'acerti_filial_2');
  for(const project of ['../x','a;id','a/b','_x','💜','a.b'])assert.throws(()=>normalizeConfig(input({project})));
});
test('new stacks use explicit names and check effective Docker names',async()=>{
  const t=await fixture();try{
    assert.equal(t.m.state.naming,'company-v1');
    const overlay=JSON.parse(fs.readFileSync(path.join(t.m.private,'compose-names.json')));
    for(const name of CORE)assert.equal(overlay.services[name].container_name,'amanda_'+name);
    assert.equal(overlay.services.edge.container_name,'amanda_caddy');
    assert.equal(overlay.services['official-migrate'].container_name,'amanda_official_migrate');
    await t.m.initialize();t.runner.wrongName=true;await assert.rejects(t.m.verifyHealth(),/Nome efetivo/);
    t.runner.wrongName=false;t.runner.containerNames=['intruder'];await assert.rejects(t.m.verifyHealth(),/docker ps/);
  }finally{t.cleanup();}
});
test('one-off operations receive unique company names and automatic removal',async()=>{
  const t=await fixture();try{
    await t.m.initialize();await t.m.backup();
    const jobs=t.runner.calls.filter(c=>c.bin==='docker'&&c.args.includes('run'));
    const names=jobs.map(c=>c.args[c.args.indexOf('--name')+1]);
    assert.equal(new Set(names).size,names.length);
    for(const c of jobs){assert.match(c.args[c.args.indexOf('--name')+1],/^amanda_[a-z_]+_[a-f0-9]{32}$/);assert.ok(c.args.includes('--rm'));}
  }finally{t.cleanup();}
});
test('legacy managed state preserves its original Compose naming policy',async()=>{
  const t=await fixture();try{delete t.m.state.naming;t.m.save(t.m.state);t.m.load();t.runner.calls=[];await t.m.configuration();assert.ok(!t.runner.calls.some(c=>c.args.includes(path.join(t.m.private,'compose-names.json'))));}finally{t.cleanup();}
});
test('legacy update refuses supplier renaming before stopping services',async()=>{
  const t=await fixture();try{
    await t.m.initialize();delete t.m.state.naming;t.m.save(t.m.state);t.runner.calls=[];
    let changed=false;t.runner.fail=({bin,args})=>{if(bin==='git'&&args.includes('merge'))changed=true;if(bin==='git'&&args.includes('checkout'))changed=false;return false;};
    t.runner.configTransform=c=>{if(changed)c.services.backend.container_name='other_backend';return c;};
    await assert.rejects(t.m.update(),/nome existente/);
    assert.equal(t.m.state.phase,'ready');assert.ok(!t.runner.calls.some(c=>c.args.includes('stop')||c.args.includes('build')));
  }finally{t.cleanup();}
});
test('enabling HTTPS checks Caddy effective name from the all-profile override',async()=>{
  const t=await fixture();try{t.m.state.profiles.push('edge');t.runner.containerNames=[...CORE.map(n=>'amanda_'+n),'amanda_caddy'];await t.m.verifyHealth();t.runner.containerNames.pop();await assert.rejects(t.m.verifyHealth(),/docker ps.*edge/);}finally{t.cleanup();}
});
test('two companies use distinct names, volumes, networks and published ports',async()=>{
  const a=await fixture(),b=temporary(),r=new FakeRunner(),m=new Manager(b.root,r);try{
    await m.prepare(input({project:'acerti',frontendUrl:'http://localhost:3001',backendUrl:'http://localhost:8081',options:{officialPort:6001,wuzapiPort:8091}}));
    const x=await a.m.configuration(),y=await m.configuration();
    for(const k of CORE)assert.notEqual(x.services[k].container_name,y.services[k].container_name);
    for(const k of Object.keys(x.volumes))assert.notEqual(x.volumes[k].name,y.volumes[k].name);
    assert.notEqual(x.networks.default.name,y.networks.default.name);
    const env=envValues(path.join(m.state.platform,'.env'));assert.equal(env.PORT_FRONTEND,'3001');assert.equal(env.PORT_BACKEND,'8081');assert.equal(env.PORT_APIOFICIAL,'6001');assert.equal(env.PORT_WUZAPI,'8091');
  }finally{a.cleanup();b.cleanup();}
});
test('foreign container-name collisions and existing networks reject initialization without seed',async()=>{
  for(const type of ['containerNames','existingNetworks']){
    const t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);r[type]=[type==='containerNames'?'amanda_backend':'amanda_default'];
    try{await assert.rejects(m.prepare(input()),/já existem/);assert.ok(!r.calls.some(c=>c.args.includes('seed')));}finally{t.cleanup();}
  }
});
test('external networks are rejected and company installer gets a stable name',async()=>{
  const t=await fixture(),old=process.env.AMANDA_MANAGER_CONTAINER,root=process.env.AMANDA_INSTALL_DIR;
  try{t.runner.externalNetwork=true;await assert.rejects(t.m.configuration(),/Rede externa/);process.env.AMANDA_MANAGER_CONTAINER='amanda_bootstrap_test';process.env.AMANDA_INSTALL_DIR=t.m.root;await t.m.identifyManager();assert.ok(t.runner.calls.some(c=>c.args[0]==='rename'&&c.args[2]==='amanda_installer'));}
  finally{if(old===undefined)delete process.env.AMANDA_MANAGER_CONTAINER;else process.env.AMANDA_MANAGER_CONTAINER=old;if(root===undefined)delete process.env.AMANDA_INSTALL_DIR;else process.env.AMANDA_INSTALL_DIR=root;t.cleanup();}
});
function isSeed(call) { return call.bin==='docker'&&call.args.includes('run')&&call.args.includes('seed'); }
test('literal environment preserves dollar variable names and removes duplicate assignments',()=>{
  const t=temporary();try{const file=path.join(t.root,'config.env'),value="pass$UNSET_VAR#'\\\"value";fs.writeFileSync(file,'MAIL_PASS=old\nMAIL_PASS=stale\nKEEP=value\n');writeEnv(file,{MAIL_PASS:value});const first=fs.readFileSync(file,'utf8');assert.ok(first.includes('$$UNSET_VAR'));assert.equal(first.match(/^MAIL_PASS=/gm).length,1);assert.equal(envValues(file).MAIL_PASS,value);writeEnv(file,{MAIL_PASS:value});assert.equal(fs.readFileSync(file,'utf8'),first);}finally{t.cleanup();}
});
test('minimal installation builds, migrates, backs up, restores and updates only selected services',async()=>{
  const t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);try{await m.prepare(input({companyName:'Empresa Teste',options:{services:{official:false,wuzapi:false,rabbit:false}}}));await m.build();await m.initialize();assert.equal(m.services().length,5);assert.deepEqual(m.databases(),['amanda']);assert.ok(!r.calls.some(c=>c.args.includes('official-migrate')));const dir=await m.backup(),data=JSON.parse(fs.readFileSync(path.join(dir,'backup.json')));assert.deepEqual(data.databases,['amanda']);assert.equal(data.hashes['api_oficial.dump'],undefined);await new Operations(m).restore(dir,'all','RESTAURAR amanda');await m.update();const env=envValues(path.join(m.state.platform,'.env'));assert.equal(env.USE_WHATSAPP_OFICIAL,'false');assert.equal(env.WUZAPI_URL,'');assert.deepEqual(m.state.profiles,[]);assert.equal(r.calls.filter(isSeed).length,1);}finally{t.cleanup();}
});
test('optional service can be enabled later with backup and migrations but no new seed',async()=>{
  const t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);r.volumeAbsent=true;try{await m.prepare(input({options:{services:{official:false,wuzapi:false,rabbit:false}}}));await m.initialize();r.calls=[];await new Operations(m).enableService('api_oficial','HABILITAR amanda api_oficial');assert.ok(m.services().includes('api_oficial'));assert.equal(envValues(path.join(m.state.platform,'.env')).USE_WHATSAPP_OFICIAL,'true');assert.equal(r.calls.filter(isSeed).length,0);assert.ok(r.calls.findIndex(c=>c.args.includes('pg_dump'))<r.calls.findIndex(c=>c.args.includes('official-migrate')));assert.equal(m.state.phase,'ready');}finally{t.cleanup();}
});
test('failed optional-service migration remains resumable without automatic schema rollback',async()=>{
  const t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);r.volumeAbsent=true;try{await m.prepare(input({options:{services:{official:false,wuzapi:false,rabbit:false}}}));await m.initialize();r.fail=c=>c.args.includes('official-migrate');await assert.rejects(new Operations(m).enableService('api_oficial','HABILITAR amanda api_oficial'));assert.equal(m.state.phase,'migration-update');r.fail=null;await m.execute('resume');assert.equal(m.state.phase,'ready');assert.equal(r.calls.filter(isSeed).length,1);}finally{t.cleanup();}
});
test('resource limits reject oversized PostgreSQL profiles before cloning or modifying runtime config',async()=>{
  const {validatePg}=require('../docker/installer/options.cjs');assert.throws(()=>validatePg({maxConnections:500,sharedBuffers:'1GB'},1024**3),/memória/);for(const pg of [{maxConnections:0,sharedBuffers:'128MB'},{maxConnections:100,sharedBuffers:'8GB'},{maxConnections:100,sharedBuffers:'128MB;id'}])assert.throws(()=>validatePg(pg));
  const t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);try{await assert.rejects(m.prepare(input({options:{pg:{maxConnections:500,sharedBuffers:'4GB'}}})),/memória/);assert.ok(!r.calls.some(c=>c.args.includes('clone')));}finally{t.cleanup();}
});
test('disabled-component volumes still block fresh resource claims and remain subject to ownership checks',async()=>{
  const t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);r.existing=['amanda_wuzapi_data'];try{await assert.rejects(m.prepare(input({options:{services:{official:false,wuzapi:false,rabbit:false}}})),/já existem/);}finally{t.cleanup();}
});
test('configuration view is a public allowlist and initial identity form accepts display fields',async()=>{
  const t=await fixture();try{await t.m.initialize();writeEnv(path.join(t.m.state.platform,'.env.backend'),{MAIL_PASS:'never-print-this',MAIL_HOST:'smtp.example.test'});const output=[],menus=new Menus(t.m,async(label,fallback)=>fallback||'',null,{out:s=>output.push(s)});const values=await menus.form('identity');assert.equal(values.appName,'AMANDA');await menus.dispatch('view-config');assert.ok(!output.join('').includes('never-print-this'));assert.ok(output.join('').includes('amanda'));}finally{t.cleanup();}
});
test('SMTP failure warns after installation without corrupting core readiness',async()=>{
  const t=await fixture();try{t.m.state.testSmtp=true;t.runner.fail=c=>c.options.label==='Testando conexão SMTP sem envio';await t.m.initialize();assert.equal(t.m.state.phase,'ready');assert.ok(t.runner.messages.includes('SMTP não validado'));assert.ok(t.runner.calls.some(c=>c.args.some(a=>typeof a==='string'&&a.includes('t.verify()'))));}finally{t.cleanup();}
});
test('runtime SMTP changes recreate only backend and preserve literal passwords and historical service selection',async()=>{
  const t=await fixture();try{await t.m.initialize();t.runner.calls=[];await new Operations(t.m).configure({backendEnv:{MAIL_HOST:'smtp.example.test',MAIL_PASS:'password$VAR',MAIL_SECURE:'true'}});const up=t.runner.calls.filter(c=>c.args.includes('up'));assert.equal(up.length,1);assert.equal(up[0].args.at(-1),'backend');assert.ok(!up[0].args.includes('postgres'));assert.equal(envValues(path.join(t.m.state.platform,'.env.backend')).MAIL_PASS,'password$VAR');}finally{t.cleanup();}
});
test('port conflicts are rejected before migrations and initial data; unchanged bindings are skipped',async()=>{
  const {assertPorts}=require('../docker/installer/preflight.cjs'),t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);r.configTransform=c=>{c.services.backend.ports=[{published:'8080',host_ip:'127.0.0.1',protocol:'tcp'}];return c;};r.fail=c=>c.options.label?.startsWith('Verificando portas TCP');try{await assert.rejects(m.prepare(input()),/falhou|failure/);assert.ok(!r.calls.some(c=>c.args.includes('migrate')||isSeed(c)));r.fail=null;const c=await m.configuration();r.calls=[];await assertPorts(m,c,c);assert.ok(!r.calls.some(c=>c.args.includes('run')));}finally{t.cleanup();}
  const {probeBindings}=require('../docker/installer/preflight.cjs'),server=require('node:net').createServer();await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const port=server.address().port;
  try{await assert.rejects(probeBindings([{port,host:'127.0.0.1',protocol:'tcp'}]),/indisponível/);}finally{await new Promise(resolve=>server.close(resolve));}
  await probeBindings([{port,host:'127.0.0.1',protocol:'tcp'}]);
});
test('HTTPS diagnoses DNS, TLS, network and HTTP separately without credentials',async()=>{
  const {probeHttp}=require('../docker/installer/diagnostics.cjs'),original=global.fetch;try{for(const[code,message]of [['ENOTFOUND','DNS'],['CERT_HAS_EXPIRED','TLS'],['ECONNREFUSED','REDE']]){global.fetch=async()=>{const error=Error('fetch failed');error.cause={code};throw error;};await assert.rejects(probeHttp([{url:'https://example.test',exact:true}],1),new RegExp(message));}global.fetch=async()=>({status:502});await assert.rejects(probeHttp([{url:'https://example.test',exact:true}],1),/HTTP 502/);}finally{global.fetch=original;}
});
test('commercial company identity and initial settings are gated to a new seeded installation',async()=>{
  const t=temporary(),r=new FakeRunner(),m=new Manager(t.root,r);try{await m.prepare(input({companyName:'ACERTI Ltda',options:{initialSettings:{signupSmtpFromName:'ACERTI'}}}));await m.initialize();const call=r.calls.find(c=>c.options.label?.startsWith('Aplicando nome comercial'));assert.equal(call.options.env.A_COMPANY,'ACERTI Ltda');assert.ok(call.args.at(-1).includes('WHERE id=1 RETURNING'));assert.ok(!call.args.at(-1).includes('ACERTI Ltda'));await assert.rejects(m.verifyLogin(),/só é permitida/);}finally{t.cleanup();}
});

test('authorized repository is mandatory, canonical and cannot carry credentials or a fork',()=>{
  for(const s of [SOURCE,SOURCE.slice(0,-4),SOURCE+'/'])assert.equal(sourceUrl(s),SOURCE);
  for(const s of ['',undefined,'http://github.com/acerticonsulting/AMANDA','https://github.com/acerticonsulting/AMANDA-extra','https://user:secret@github.com/acerticonsulting/AMANDA','https://github.com/acerticonsulting/AMANDA?x=1'])assert.throws(()=>sourceUrl(s));
});

test('compatible historical main/tools/API numbers are preserved and menus repeat after an operation',async()=>{
  assert.deepEqual(MAIN.slice(0,11).map(x=>x[0]),Array.from({length:11},(_,i)=>String(i+1)));
  assert.deepEqual(TOOLS.map(x=>x[0]),['2','3','5','31','32','4','30','6','7','8','9','10','11','12','13','14','22','23','15','21','20','19','16','17','18']);
  assert.deepEqual(API.map(x=>x[0]),Array.from({length:9},(_,i)=>String(i+1)));
  const t=temporary();try{const m=new Manager(t.root,new FakeRunner()),answers=['6','','0'],calls=[],menus=new Menus(m,async()=>answers.shift(),null,{out:()=>{}});menus.dispatch=async action=>calls.push(action);await menus.run();assert.deepEqual(calls,['backup']);assert.equal(answers.length,0);}finally{t.cleanup();}
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
  const short=Buffer.from(vapidPrivateKey(Buffer.from([1])),'base64url');assert.equal(short.length,32);assert.equal(short.at(-1),1);assert.ok(short.subarray(0,31).every(x=>x===0));
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
    t.runner.addonRemote='https://github.com/owner/voice';await assert.rejects(addon.deploy('voz',{sourceUrl:t.runner.addonRemote,token:'synthetic-addon-token'}),/healthcheck|container_name/);assert.ok(!fs.existsSync(path.join(t.m.private,'addon-voz.json')));assert.equal(fs.readFileSync(path.join(t.m.state.platform,'.secrets/github_token'),'utf8'),'');assert.ok(!t.runner.calls.some(c=>c.args.includes('up')));
  }finally{t.cleanup();}
});

test('valid external component participates in consistent backups; invalid update restores the old source',async()=>{
  const t=await fixture();try{await t.m.initialize();t.runner.addonValid=true;t.runner.addonRemote='https://github.com/owner/voice';const addon=new Addons(t.m);await addon.deploy('voz',{sourceUrl:t.runner.addonRemote,environment:{VOICE_TOKEN:'synthetic-voice-token'}});assert.equal(JSON.parse(fs.readFileSync(path.join(t.m.private,'addon-voz.json'))).phase,'ready');assert.ok((await t.m.configuration()).volumes.voz_voice_data);
    t.runner.calls=[];await t.m.backup();const pause=t.runner.calls.findIndex(c=>c.args.includes('amanda_voz')&&c.args.includes('stop')),dump=t.runner.calls.findIndex(c=>c.args.includes('pg_dump'));assert.ok(pause>=0&&pause<dump);assert.ok(t.runner.calls.some(c=>c.args.some(v=>v.includes('source=amanda_voz_voice_data,target=/data/voz_voice_data,readonly'))));
    t.runner.calls=[];t.runner.invalidateAddonOnMerge=true;await assert.rejects(addon.deploy('voz',{},true),/healthcheck|container_name/);assert.ok(t.runner.calls.some(c=>c.bin==='git'&&c.options.cwd?.includes('/addons/')&&c.args.includes('--detach')));assert.equal(t.runner.addonValid,true);const changed=t.runner.calls.findIndex(c=>c.bin==='git'&&c.args.includes('merge'));assert.ok(changed>=0);assert.ok(!t.runner.calls.slice(changed+1).some(c=>c.args.includes('amanda_voz')&&c.args.includes('up')));
  }finally{t.cleanup();}
});

test('restored main menu is shown before any Docker download and exit creates no resources',()=>{
  const t=temporary();try{const bin=path.join(t.root,'bin');fs.mkdirSync(bin);const log=path.join(t.root,'docker-calls');fs.writeFileSync(path.join(bin,'docker'),'#!/bin/sh\nprintf called >> "$TEST_LOG"\nexit 99\n',{mode:0o755});const script=path.resolve(__dirname,'../instalador_single.sh');const quote=s=>"'"+s.replace(/'/g,"'\\''")+"'";
    const run=spawnSync('script',['-q','-c','sh '+quote(script),'/dev/null'],{input:'0\n',encoding:'utf8',timeout:5000,env:{...process.env,PATH:bin+':/usr/bin:/bin',TEST_LOG:log}});assert.equal(run.status,0,run.stderr);const plain=run.stdout.replace(/\x1b\[[0-9;]*[A-Za-z]/g,'');assert.ok(plain.includes('[11]'));assert.ok(plain.includes('[8]'));assert.ok(plain.includes('█████╗'));for(const[id,label]of MAIN)assert.ok(plain.includes('['+id+'] '+label));assert.ok(!fs.existsSync(log));
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
    assert.equal(fs.readFileSync(path.join(m.state.platform,'.secrets/github_token'),'utf8'),'');
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

test('interrupted build refreshes only official main without replacing configuration, volumes or source credentials',async()=>{
  const t=await fixture();try{
    const before=fs.readFileSync(path.join(t.m.state.platform,'.env'),'utf8');
    t.runner.calls=[];await t.m.refreshInterruptedBuild();
    assert.ok(t.runner.calls.some(c=>c.bin==='git'&&c.args.includes('fetch')&&c.args.includes('main')));
    assert.ok(t.runner.calls.some(c=>c.bin==='git'&&c.args.includes('--ff-only')));
    assert.equal(fs.readFileSync(path.join(t.m.state.platform,'.env'),'utf8'),before);
    assert.ok(!t.runner.calls.some(c=>isSeed(c)||c.args.includes('down')||c.args.includes('reset')||c.args.includes('volume')));
    t.m.state.seedAttempted=true;t.runner.calls=[];await t.m.refreshInterruptedBuild();assert.equal(t.runner.calls.length,0);
  }finally{t.cleanup();}
});

test('failed official fast-forward leaves interrupted build and private configuration resumable',async()=>{
  const t=await fixture();try{
    const before=fs.readFileSync(path.join(t.m.state.platform,'.env'),'utf8');
    t.runner.calls=[];t.runner.fail=c=>c.bin==='git'&&c.args.includes('merge-base');
    await assert.rejects(t.m.refreshInterruptedBuild());
    assert.equal(t.m.state.phase,'build');assert.equal(t.m.state.seedAttempted,false);
    assert.equal(fs.readFileSync(path.join(t.m.state.platform,'.env'),'utf8'),before);
    assert.ok(!t.runner.calls.some(c=>isSeed(c)||c.args.includes('reset')||c.args.includes('--ff-only')||c.args.includes('build')));
    t.runner.fail=null;t.runner.calls=[];t.runner.dirty=true;
    await assert.rejects(t.m.refreshInterruptedBuild(),/alterações locais/);
    assert.ok(!t.runner.calls.some(c=>c.args.includes('fetch')));
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


test('historical purple banner, menu highlights and optional plain output match bootstrap',()=>{
  const {LOGO,createUI}=require('../docker/installer/ui.cjs');
  const ui=createUI({tty:true,env:{TERM:'xterm-256color'}}),shell=fs.readFileSync(path.resolve(__dirname,'../docker/installer/historical.sh'),'utf8');
  for(const line of LOGO){assert.ok(ui.banner('MENU').includes(line));assert.ok(shell.includes(line));}
  assert.ok(ui.banner('MENU').includes('\x1b[38;2;139;92;246m'));
  assert.ok(ui.item('1','Instalar').includes('\x1b[1;38;2;167;139;250m'));
  assert.ok(shell.includes('38;2;139;92;246'));
  for(const options of [{tty:false},{tty:true,env:{NO_COLOR:'1'}},{tty:true,env:{TERM:'dumb'}}])assert.ok(!createUI(options).banner('MENU').includes('\x1b'));
  assert.ok(!ui.question('Teste\x1b[31m','valor\n').includes('Teste\x1b[31m'));
  assert.ok(!TOOLS.some(x=>/addon-/.test(x[2])));
});

function wizardQuestion(overrides={}){
  let count=0;return async(label,fallback,secret)=>{
    if(++count>200)throw Error('Instalação cancelada: perguntas em excesso no teste.');
    for(const [prefix,value]of Object.entries(overrides))if(label.startsWith(prefix))return typeof value==='function'?value(label,fallback,secret):value;
    if(label.startsWith('Link da plataforma'))return SOURCE;
    if(label==='Como deseja continuar')return '1';
    return fallback||'';
  };
}
test('additional wizard accepts short passwords in all access modes without leaking summaries',async()=>{
 for(const mode of ['1','2','3'])for(const password of ['123','teste123','MinhaSenhaPersonalizada']){
  const output=[],c=await installInput(undefined,{out:s=>output.push(s),question:wizardQuestion({'Tipo de instalação':mode,'IP do servidor':'192.0.2.10','URL do frontend HTTPS':'app.example.test','URL do backend HTTPS':'api.example.test','Personalizar o acesso administrativo':'s','Senha do administrador':password,'Confirmação da senha':password,'Gerar senha PostgreSQL segura automaticamente':'n','Senha PostgreSQL personalizada':password,'MASTER_KEY personalizada':password})});
  assert.equal(c.adminPassword,password);assert.equal(c.options.databasePassword,password);assert.equal(c.options.masterPassword,password);assert.ok(!output.join('').includes(password));
 }
});
test('eleven-stage wizard configures localhost and reviews all public choices',async()=>{
  const output=[],prompts=[];const q=wizardQuestion();const c=await installInput(undefined,{directory:'/srv/local',out:s=>output.push(s),question:(...args)=>{prompts.push(args);return q(...args);}});
  assert.equal(c.frontendUrl,'http://localhost:3000');assert.equal(c.backendUrl,'http://localhost:8080');assert.equal(c.adminEmail,'admin@amanda.com.br');assert.equal(c.companyName,'AMANDA');assert.equal(c.options.pg.sharedBuffers,'128MB');
  for(let i=1;i<=11;i++)assert.ok(output.some(s=>s.includes('[ETAPA '+String(i).padStart(2,'0')+'/11]')));
  assert.ok(output.join('').includes('/srv/local'));assert.ok(prompts.find(a=>a[0].startsWith('MASTER_KEY'))[2]);
});

test('wizard keeps the preflight company fixed while retaining PostgreSQL and administrative choices',async()=>{
 const prompts=[],q=wizardQuestion({'Nome técnico do projeto Docker':'other','Perfil PostgreSQL':'2'});
 const c=await installInput(undefined,{project:'acerti',out(){},question:(...args)=>{prompts.push(args[0]);return q(...args);}});
 assert.equal(c.project,'acerti');assert.equal(c.options.pg.maxConnections,200);assert.ok(!prompts.some(p=>p.startsWith('Nome técnico do projeto Docker')));assert.equal(c.adminEmail,'admin@amanda.com.br');
});
test('HTTPS wizard accepts distinct domains and custom administrator without leaking secrets in review',async()=>{
  const output=[],password='custom$#strongPassword',c=await installInput(undefined,{out:s=>output.push(s),question:wizardQuestion({'Tipo de instalação':'1','URL do frontend HTTPS':'app.example.com','URL do backend HTTPS':'https://api.example.com','E-mail do administrador':'owner@example.com','Senha do administrador':password,'Confirmação da senha':password,'URL pública HTTPS da API Oficial':'official.example.com'})});
  assert.equal(c.edge,true);assert.equal(c.frontendUrl,'https://app.example.com');assert.equal(c.backendUrl,'https://api.example.com');assert.equal(c.options.officialUrl,'https://official.example.com');assert.equal(c.adminPassword,password);assert.ok(!output.join('').includes(password));
});
test('IP wizard maps IPv4/IPv6 and custom ports into configuration',async()=>{
  for(const ip of ['192.0.2.20','2001:db8::1']){const c=await installInput(undefined,{out:()=>{},question:wizardQuestion({'Tipo de instalação':'2','IP do servidor':ip,'Deseja utilizar portas personalizadas':'s','Porta externa do frontend':'3300','Porta externa do backend':'8800','E-mail do administrador':'owner@example.test','Senha do administrador':'safe$Pass12345','Confirmação da senha':'safe$Pass12345'})});assert.equal(c.public,true);assert.equal(new URL(c.backendUrl).port,'8800');assert.ok(c.frontendUrl.includes(ip));}
});
test('wizard retries invalid mode, domain and password confirmation; cancel creates no resources',async()=>{
  let modes=0,domains=0,confirmation=0;const c=await installInput(undefined,{out:()=>{},question:wizardQuestion({'Tipo de instalação':()=>++modes===1?'9':'1','URL do frontend HTTPS':()=>++domains===1?'app.invalid/path':'app.example.test','URL do backend HTTPS':'api.example.test','Senha do administrador':'safe$Pass12345','Confirmação da senha':()=>++confirmation===1?'wrong':'safe$Pass12345'})});assert.equal(c.edge,true);assert.equal(modes,2);assert.equal(domains,2);assert.equal(confirmation,2);
  await assert.rejects(installInput(undefined,{out:()=>{},question:wizardQuestion({'Como deseja continuar':'3'})}),/cancelada antes de criar recursos/);
  await assert.rejects(installInput(undefined,{out:()=>{},question:wizardQuestion({'Tipo de instalação':':cancelar'})}),/cancelada/);
});
test('wizard supports back navigation and editing a section from the final review',async()=>{
  let admin=0,project=0,review=0;const c=await installInput(undefined,{out:()=>{},question:wizardQuestion({'Personalizar o acesso administrativo':()=>++admin===1?':voltar':'n','Nome técnico do projeto Docker':()=>++project>=3?'acerti':'amanda','Como deseja continuar':()=>++review===1?'2':'1','Qual etapa deseja revisar':'3'})});assert.equal(c.project,'acerti');assert.equal(review,2);assert.equal(project,3);
});
test('review preserves custom ports, admin, database password, profile and disabled services',async()=>{
  let review=0,admin=0,confirm=0;const c=await installInput(undefined,{out:()=>{},question:wizardQuestion({'Deseja utilizar portas personalizadas':'s','Porta externa do frontend':'3310','Porta externa do backend':'8810','Personalizar o acesso administrativo':'s','Senha do administrador':()=>++admin===1?'my$privatePass':'','Confirmação da senha':()=>++confirm===1?'my$privatePass':'','Gerar senha PostgreSQL segura automaticamente':'n','Senha PostgreSQL personalizada':(label,fallback)=>admin===1?'db$PRIVATE':'','Perfil PostgreSQL':'2','Habilitar API Oficial':'n','Habilitar WuzAPI':'n','Como deseja continuar':()=>++review===1?'2':'1','Qual etapa deseja revisar':'2'})});assert.equal(c.frontendUrl,'http://localhost:3310');assert.equal(c.adminPassword,'my$privatePass');assert.equal(c.options.databasePassword,'db$PRIVATE');assert.equal(c.options.pg.maxConnections,200);assert.deepEqual(c.options.services,{official:false,wuzapi:false,rabbit:false});
});
test('SMTP wizard collects real TLS settings, private password and optional connection test',async()=>{
  const c=await installInput(undefined,{out:()=>{},question:wizardQuestion({'Deseja configurar o envio de e-mails':'s','Servidor SMTP':'smtp.example.test','Porta SMTP':'465','TLS implícito':'true','Usuário SMTP':'owner@example.test','Senha SMTP':'smtp$#password','E-mail do remetente SMTP':'sender@example.test','Nome do remetente SMTP':'ACERTI'})});
  assert.equal(c.options.backendEnv.MAIL_SECURE,'true');assert.equal(c.options.backendEnv.MAIL_PASS,'smtp$#password');assert.equal(c.options.initialSettings.signupSmtpFromName,'ACERTI');assert.equal(c.options.testSmtp,true);
});
test('status is displayed after the banner and remains visible until the next selection',async()=>{
  const t=await fixture();try{await t.m.initialize();const output=[],answers=['0','0'];t.runner.emit=s=>output.push(s);const menus=new Menus(t.m,async()=>answers.shift(),null,{out:s=>output.push(s)});await menus.services();
    assert.ok(output[0].includes('STATUS E REINÍCIO'));assert.ok(t.runner.calls.some(c=>c.args.includes('ps')));assert.equal(answers.length,1);
    const order=[];await menus.choose('TESTE',[],async()=>order.push('status'));assert.deepEqual(order,['status']);
  }finally{t.cleanup();}
});

test('historical HTTPS bindings persist through later configuration and safe updates',async()=>{
 const t=temporary(),runner=new FakeRunner(),m=new Manager(t.root,runner);
 try{
  await m.prepare(input({edge:true,frontendUrl:'https://app.example.test',backendUrl:'https://api.example.test',options:{frontendPort:3310,backendPort:8810}}));
  runner.runtimeContainerNames=[...CORE.map(n=>'amanda_'+n),'amanda_caddy'];
  let e=envValues(path.join(m.state.platform,'.env'));assert.equal(e.PORT_FRONTEND,'3310');assert.equal(e.PORT_BACKEND,'8810');
  await m.initialize();await new Operations(m).configure({network:{frontendUrl:'https://panel.example.test'}});
  e=envValues(path.join(m.state.platform,'.env'));assert.equal(e.PORT_FRONTEND,'3310');assert.equal(e.PORT_BACKEND,'8810');
  runner.calls=[];await m.execute('update');e=envValues(path.join(m.state.platform,'.env'));assert.equal(e.PORT_FRONTEND,'3310');assert.equal(e.PORT_BACKEND,'8810');assert.equal(runner.calls.filter(isSeed).length,0);
 }finally{t.cleanup();}
});
test('historical administrative selection targets only the selected managed instance',async()=>{
 const t=await fixture();
 try{
  const childRoot=path.join(t.root,'instances','filial-antiga'),child=new Manager(childRoot,new FakeRunner());await child.prepare(input({project:'filial'}));
  const original=fs.readFileSync(t.m.stateFile,'utf8'),menu=new Menus(t.m,async()=> '2',null,{out:()=>{}});await menu.selectInstance();assert.equal(menu.m.root,childRoot);assert.equal(menu.m.state.project,'filial');assert.equal(fs.readFileSync(t.m.stateFile,'utf8'),original);
  const canceled=new Menus(t.m,async()=> '0',null,{out:()=>{}});await assert.rejects(canceled.selectInstance(),/cancelada/);assert.equal(canceled.m,t.m);
 }finally{t.cleanup();}
});
test('deploy ownership persists through clone, migrations, update, backup, restore and lock cleanup',async()=>{
 const base='/home/deploy',root=base+'/test_'+require('node:crypto').randomBytes(8).toString('hex');fs.mkdirSync(base,{recursive:true});fs.mkdirSync(root);const m=new Manager(root,new FakeRunner());m.deploymentOwner={uid:12345,gid:12346};
 try{await m.lock(async()=>{await m.prepare(input());await m.build();await m.initialize();});assert.equal(m.state.deploymentOwner.uid,12345);const envFile=path.join(m.state.platform,'.env'),env=fs.readFileSync(envFile,'utf8');assert.equal(fs.statSync(envFile).uid,12345);assert.equal(fs.statSync(envFile).mode&0o777,0o600);
 await m.lock(()=>m.execute('update'));const backup=m.state.lastBackup;assert.equal(fs.statSync(path.join(backup,'amanda.dump')).uid,12345);await new Operations(m).restore(backup,'all','RESTAURAR amanda');assert.equal(fs.readFileSync(envFile,'utf8'),env);assert.equal(fs.statSync(m.stateFile).uid,12345);assert.ok(!fs.existsSync(path.join(m.private,'operation.lock')));assert.equal(m.runner.calls.filter(isSeed).length,1);
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});
test('deploy migration plan validates backup and inventories mounts without changing the existing installation',async()=>{
 const t=await fixture();try{await t.m.initialize();await t.m.backup();const before=fs.readFileSync(t.m.stateFile,'utf8');t.runner.calls=[];const plan=await require('../docker/installer/deploy.cjs').migrationPlan(t.m);assert.equal(plan.source,t.root);assert.equal(plan.destination,'/home/deploy/amanda');assert.equal(plan.backupVerified,true);assert.equal(plan.automaticMigration,false);assert.equal(fs.readFileSync(t.m.stateFile,'utf8'),before);assert.ok(!t.runner.calls.some(c=>c.args.includes('stop')||c.args.includes('up')||isSeed(c)));fs.appendFileSync(path.join(t.m.state.lastBackup,'amanda.dump'),'invalid');await assert.rejects(require('../docker/installer/deploy.cjs').migrationPlan(t.m),/Integridade/);}finally{t.cleanup();}
});
