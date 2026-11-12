// Explicit integration test: official source is mounted read-only. No daemon,
// containers of the platform, migrations, databases or production files are used.
const {test}=require('node:test');const assert=require('node:assert/strict');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');const {execFileSync}=require('node:child_process');
const {Manager,envValues,Runner}=require('../docker/installer/manager.cjs');const {writeEnv}=require('../docker/installer/options.cjs');
async function fixture({edge=false,minimal=false}={}){
  const source=process.env.AMANDA_PLATFORM_SOURCE;if(!source)throw Error('Monte a fonte oficial com AMANDA_PLATFORM_SOURCE para executar esta integração.');
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'amanda-compose-contract-')),platform=path.join(root,'platform');fs.mkdirSync(path.join(platform,'docker'),{recursive:true});
  for(const file of ['docker-compose.yml','.env.example','docker/configure.cjs','docker/caddy-entry.sh','docker/Caddyfile'])fs.copyFileSync(path.join(source,file),path.join(platform,file));
  execFileSync(process.execPath,['docker/configure.cjs'],{cwd:platform,stdio:'pipe'});
  const m=new Manager(root,new Runner(null,{write:()=>{}}));m.state={project:'contract_acerti',platform,profiles:[...(minimal?[]:['official','whatsmeow','rabbit']),...(edge?['edge']:[])],naming:'company-v1',selectiveServices:true};
  const password='Fictitious$#@:/database';writeEnv(path.join(platform,'.env'),{COMPOSE_PROJECT_NAME:m.state.project,COMPOSE_PROFILES:m.state.profiles.join(','),DB_PASS:password,DB_URI_PASSWORD:encodeURIComponent(password),FRONTEND_URL:edge?'https://app.example.test':'http://192.0.2.2:3300',BACKEND_URL:edge?'https://api.example.test':'http://192.0.2.2:8800',ALLOWED_ORIGINS:edge?'https://app.example.test':'http://192.0.2.2:3300',FRONTEND_HOST:'app.example.test',BACKEND_HOST:'api.example.test',OFICIAL_HOST:edge?'official.example.test':'',BIND_ADDRESS:edge?'127.0.0.1':'0.0.0.0',PORT_FRONTEND:edge?3000:3300,PORT_BACKEND:edge?8080:8800,PORT_APIOFICIAL:6100,PORT_WUZAPI:8190,REACT_APP_NUMBER_SUPPORT:'5511999999999',PG_MAX_CONNECTIONS:150,PG_SHARED_BUFFERS:'256MB',USE_WHATSAPP_OFICIAL:String(!minimal),RABBITMQ_ENABLED_GLOBAL:String(!minimal),WUZAPI_URL:minimal?'':'http://wuzapi:8080'});
  writeEnv(path.join(platform,'.env.backend'),{MAIL_HOST:'smtp.example.test',MAIL_PORT:'465',MAIL_SECURE:'true',MAIL_PASS:'fictitious$smtp',GOOGLE_CLIENT_ID:'fictitious-client',GOOGLE_CLIENT_SECRET:'fictitious-secret'});
  await m.configureNames();const config=await m.configuration();return {m,root,config,platform,password,cleanup:()=>fs.rmSync(root,{recursive:true})};
}
test('official Compose resolves public URLs, internal endpoints, optional env and passwords literally',async()=>{
  const t=await fixture();try{const c=t.config;assert.equal(c.services.backend.environment.DB_PASS.replace(/\$\$/g,'$'),t.password);assert.ok(c.services.api_oficial.environment.DATABASE_LINK.includes(encodeURIComponent(t.password)));assert.equal(c.services.frontend.environment.REACT_APP_BACKEND_URL,'http://192.0.2.2:8800');assert.equal(c.services.frontend.environment.REACT_APP_NUMBER_SUPPORT,'5511999999999');assert.equal(c.services.backend.environment.ALLOWED_ORIGINS,'http://192.0.2.2:3300');assert.equal(c.services.backend.environment.URL_API_OFICIAL,'http://api_oficial:6000');assert.equal(c.services.backend.environment.WUZAPI_WEBHOOK_BASE_URL,'http://backend:8080');assert.equal(c.services.backend.environment.MAIL_PASS.replace(/\$\$/g,'$'),'fictitious$smtp');assert.equal(c.services.backend.environment.MAIL_SECURE,'true');assert.equal(c.services.backend.environment.GOOGLE_CLIENT_ID,'fictitious-client');assert.ok(c.services.postgres.command.includes('shared_buffers=256MB'));for(const n of t.m.services())assert.equal(c.services[n].container_name,'contract_acerti_'+n);assert.equal(c.services.backend.ports[0].published,'8800');}finally{t.cleanup();}
});
test('minimal profile has no optional APIs or brokers and preserves database isolation',async()=>{
  const t=await fixture({minimal:true});try{for(const n of ['api_oficial','wuzapi','rabbitmq','official-migrate','edge'])assert.equal(t.config.services[n],undefined);assert.deepEqual(t.m.databases(),['amanda']);assert.equal(t.config.volumes.wuzapi_data,undefined);assert.equal(t.config.volumes.postgres_data.name,'contract_acerti_postgres_data');assert.equal(t.config.networks.default.name,'contract_acerti_default');}finally{t.cleanup();}
});
test('HTTPS profile applies three separate domains and the official Caddy entry generates its route',async()=>{
  const t=await fixture({edge:true});try{const c=t.config;assert.equal(c.services.edge.container_name,'contract_acerti_caddy');assert.equal(c.services.edge.environment.OFICIAL_HOST,'official.example.test');assert.equal(c.services.backend.ports[0].host_ip,'127.0.0.1');const output=path.join(t.root,'Caddyfile');execFileSync('/bin/sh',[path.join(t.platform,'docker/caddy-entry.sh')],{env:{...process.env,AMANDA_CADDY_TEMPLATE:path.join(t.platform,'docker/Caddyfile'),AMANDA_CADDY_OUTPUT:output,AMANDA_CADDY_CONFIG_ONLY:'1',OFICIAL_HOST:'official.example.test'}});assert.ok(fs.readFileSync(output,'utf8').includes('reverse_proxy api_oficial:6000'));}finally{t.cleanup();}
});
test('official generator produces distinct internal secrets with private permissions',async()=>{
  const t=await fixture();try{const env=envValues(path.join(t.platform,'.env')),keys=['JWT_SECRET','JWT_REFRESH_SECRET','MASTER_KEY','TOKEN_API_OFICIAL','TRANSCRIBE_API_KEY','WUZAPI_ADMIN_TOKEN','RABBITMQ_PASS'];for(const k of keys)assert.match(env[k],/^[a-f0-9]{64}$/);assert.equal(new Set(keys.map(k=>env[k])).size,keys.length);assert.equal(fs.statSync(path.join(t.platform,'.env')).mode&0o777,0o600);assert.throws(()=>execFileSync(process.execPath,['docker/configure.cjs'],{cwd:t.platform,stdio:'pipe'}));}finally{t.cleanup();}
});
test('historical custom HTTPS bindings are accepted by official Compose without changing container endpoints',async()=>{
 const t=await fixture({edge:true});try{
  writeEnv(path.join(t.platform,'.env'),{PORT_FRONTEND:3310,PORT_BACKEND:8810});const c=await t.m.configuration();
  assert.equal(c.services.frontend.ports[0].published,'3310');assert.equal(c.services.frontend.ports[0].target,80);assert.equal(c.services.frontend.ports[0].host_ip,'127.0.0.1');
  assert.equal(c.services.backend.ports[0].published,'8810');assert.equal(c.services.backend.ports[0].target,8080);assert.equal(c.services.backend.ports[0].host_ip,'127.0.0.1');
  assert.equal(c.services.backend.environment.URL_API_OFICIAL,'http://api_oficial:6000');assert.equal(c.services.edge.container_name,'contract_acerti_caddy');
 }finally{t.cleanup();}
});
test('built manager includes the recovered historical presentation',()=>{
 const output=execFileSync('sh',['/opt/amanda-installer/historical.sh','--main'],{encoding:'utf8'});
 assert.ok(output.includes('MULTICANAL v1.0.0'));assert.ok(output.includes('[8] Menu de Ferramentas Adicionais'));assert.ok(output.includes('[11] Instalar ou Gerenciar API Oficial'));
});
test('built manager provides kernel operation locking without host dependencies',async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'amanda-image-lock-'));try{const m=new Manager(root,new Runner(null,{write(){}}));await m.lock(()=>m.lock(async()=>{}));assert.ok(!fs.existsSync(path.join(root,'.amanda-installer/operation.lock')));}finally{fs.rmSync(root,{recursive:true});}
});
test('built manager provisions deploy in a disposable Linux account database',()=>{
 const {BASE,provision}=require('../docker/installer/deploy.cjs'),host=fs.mkdtempSync(path.join(os.tmpdir(),'deploy-account-'));
 try{fs.mkdirSync(host+'/etc');fs.mkdirSync(host+BASE,{recursive:true});for(const[file,value]of Object.entries({passwd:'root:x:0:0:root:/root:/bin/sh\n',group:'root:x:0:\n',shadow:'root:!:20000:0:99999:7:::\n',gshadow:'root:!::\n','login.defs':'SYS_UID_MIN 100\nSYS_UID_MAX 999\nSYS_GID_MIN 100\nSYS_GID_MAX 999\nUSERGROUPS_ENAB yes\n'}))fs.writeFileSync(host+'/etc/'+file,value);
 const owner=provision('amanda',{host});assert.ok(owner.uid>0);const before=fs.readFileSync(host+'/etc/passwd','utf8');provision('acerti',{host});assert.equal(fs.readFileSync(host+'/etc/passwd','utf8'),before);assert.equal(fs.statSync(host+BASE+'/amanda').uid,owner.uid);assert.equal(fs.statSync(host+BASE+'/acerti').mode&0o777,0o700);assert.ok(!fs.readFileSync(host+'/etc/group','utf8').includes('docker'));assert.ok(!fs.readFileSync(host+'/etc/group','utf8').includes('sudo'));
 }finally{fs.rmSync(host,{recursive:true});}
});

test('built image includes read-only classification and preserves logical paths inside provisioning mount',()=>{
 const {inspectDirectory,setupRecord}=require('/opt/amanda-installer/directory-state.cjs'),root=fs.mkdtempSync(path.join(os.tmpdir(),'amanda-classification-'));
 try{
  const logical='/home/deploy/acerti',config=require('../docker/installer/manager.cjs').normalizeConfig({sourceUrl:'https://github.com/acerticonsulting/AMANDA.git',project:'acerti'});
  fs.mkdirSync(root+'/.amanda-installer',{mode:0o700});fs.writeFileSync(root+'/.amanda-installer/setup.json',JSON.stringify(setupRecord(logical,config)),{mode:0o600});
  assert.equal(inspectDirectory(root,{project:'acerti',logicalRoot:logical}).kind,'temporary');
  assert.equal(inspectDirectory(root,{project:'acerti'}).kind,'unknown');
 }finally{fs.rmSync(root,{recursive:true});}
});

test('real generator and Compose resume staged preparation without regenerating published credentials',async()=>{
 const source=process.env.AMANDA_PLATFORM_SOURCE,root=fs.mkdtempSync(path.join(os.tmpdir(),'amanda-staged-contract-')),platform=path.join(root,'platform');
 const {SOURCE,normalizeConfig}=require('../docker/installer/manager.cjs'),{setupRecord}=require('../docker/installer/directory-state.cjs');
 try{
  fs.mkdirSync(platform+'/docker',{recursive:true});for(const file of ['docker-compose.yml','.env.example','docker/configure.cjs'])fs.copyFileSync(path.join(source,file),path.join(platform,file));
  fs.writeFileSync(platform+'/.gitignore','.env\n.env.backend\n.secrets/\n');
  const git=args=>execFileSync('git',args,{cwd:platform,stdio:'pipe'});git(['init']);git(['add','.']);git(['-c','user.name=fixture','-c','user.email=fixture@example.test','commit','-m','fixture']);git(['remote','add','origin',SOURCE]);
  class StagingRunner extends Runner{
   constructor(){super(null,{write(){}});this.block=true;this.generations=0;}
   async run(bin,args,options){
    if(bin===process.execPath){this.generations++;return super.run(bin,args,options);}
    if(bin==='git')return super.run(bin,args,options);
    if(bin!=='docker')throw Error('Unexpected test command');
    if(args[0]==='compose'&&args.includes('config')){if(this.block)throw Error('synthetic config interruption');return super.run(bin,args,options);}
    if(args[0]==='info')return {stdout:JSON.stringify({MemTotal:8*1024**3,NCPU:4}),code:0};
    return {stdout:'',code:0}; // No daemon or containers are accessed by this contract test.
   }
  }
  const runner=new StagingRunner(),m=new Manager(root,runner),c=normalizeConfig({sourceUrl:SOURCE,project:'acerti',adminPassword:'kept-choice',options:{pg:{maxConnections:100,sharedBuffers:'128MB'},services:{official:false,wuzapi:false,rabbit:false}}});
  m.write(path.join(m.private,'setup.json'),setupRecord(root,c));m.save({schema:1,sourceUrl:SOURCE,project:'acerti',platform,profiles:[],selectiveServices:true,phase:'preparing',initialized:false,seedAttempted:false,seedSucceeded:false});
  await assert.rejects(m.prepare(c,{resume:true}),/synthetic config interruption/);
  const before=fs.readFileSync(platform+'/.env','utf8');assert.match(envValues(platform+'/.env').JWT_SECRET,/^[a-f0-9]{64}$/);
  runner.block=false;await m.prepare(c,{resume:true});assert.equal(m.state.phase,'build');assert.equal(fs.readFileSync(platform+'/.env','utf8'),before);assert.equal(runner.generations,1);
  const config=await m.configuration();assert.equal(config.services.backend.environment.DB_HOST,'postgres');assert.equal(config.services.postgres.command.includes('max_connections=100'),true);assert.equal(JSON.parse(fs.readFileSync(m.private+'/admin-access.json')).password,'kept-choice');
 }finally{fs.rmSync(root,{recursive:true});}
});
