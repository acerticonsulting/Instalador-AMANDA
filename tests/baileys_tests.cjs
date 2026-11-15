const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {Baileys,PACKAGE,dependency,lockDelta,newer}=require('../docker/installer/baileys.cjs');
const manifest=v=>({name:'backend',dependencies:{[PACKAGE]:v,other:'1.0.0'}});
const lock=v=>({lockfileVersion:3,packages:{'':{name:'backend',dependencies:{[PACKAGE]:v,other:'1.0.0'}},['node_modules/'+PACKAGE]:{version:v,resolved:'https://registry.npmjs.org/'+PACKAGE+'/-/baileys-'+v+'.tgz',integrity:'sha512-fixture',dependencies:{signal:'1.0.0'}},'node_modules/signal':{version:'1.0.0'},'node_modules/other':{version:'1.0.0'}}});
function fixture(){
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'amanda-baileys-test-')),platform=path.join(root,'platform'),backend=path.join(platform,'backend');fs.mkdirSync(backend,{recursive:true});fs.mkdirSync(path.join(platform,'docker'));
 fs.writeFileSync(path.join(platform,'docker/backend.Dockerfile'),'FROM node:22-bookworm AS build\nRUN npm ci\n');
 fs.writeFileSync(path.join(backend,'package.json'),JSON.stringify(manifest('6.7.24')));fs.writeFileSync(path.join(backend,'package-lock.json'),JSON.stringify(lock('6.7.24')));
 fs.writeFileSync(path.join(root,'sessions-fixture'),'untouched');fs.writeFileSync(path.join(root,'database-fixture'),'untouched');
 const m={root,private:path.join(root,'.amanda-installer'),state:{project:'example',platform,profiles:[],initialized:true,phase:'ready'},calls:[],messages:'',runtime:'6.7.24',imageVersion:'6.7.24',versions:['6.7.24','6.7.25','6.8.0','7.0.0'],
 runner:{emit(s){m.messages+=s;}},async doctor(){},load(){},async identifyManager(){},async validateSource(){},async verifyHealth(){},async revision(){return 'a'.repeat(40);},async lock(f){return f();},
 async configuration(){return {services:{backend:{container_name:'example_backend',image:'example-backend:local',build:{context:platform,dockerfile:'docker/backend.Dockerfile'},healthcheck:{test:['CMD','true']}}}};},
 write(file,value){fs.mkdirSync(path.dirname(file),{recursive:true,mode:0o700});fs.writeFileSync(file,typeof value==='string'?value:JSON.stringify(value),{mode:0o600});},
 async backup(options){m.calls.push({kind:'backup',options});if(m.fail==='backup')throw Error('backup failed');return '/private/backup';},
 async compose(args){m.calls.push({kind:'compose',args});
   if(args[0]==='build'){if(m.fail==='build')throw Error('build failed');m.imageVersion=JSON.parse(fs.readFileSync(path.join(backend,'package.json'))).dependencies[PACKAGE];}
   if(args[0]==='up'){if(m.fail==='health'&&m.imageVersion==='6.7.25')throw Error('health failed');if(m.fail==='rollback'&&m.imageVersion==='6.7.24')throw Error('rollback failed');m.runtime=m.imageVersion;}
   if(args.includes('ps'))return {stdout:'b'.repeat(64)};
   if(args[0]==='logs')return{stdout:m.fail==='logs'?'ERR_REQUIRE_ESM':'normal startup',stderr:''};
   return {stdout:JSON.stringify({version:m.fail==='version'&&m.runtime==='6.7.25'?'6.7.24':m.runtime,node:'22.15.0'})};
 },
 async docker(args){m.calls.push({kind:'docker',args});
   if(args.includes('view')){if(m.fail==='download')throw Error('registry offline');return {stdout:JSON.stringify(m.versions)};}
   if(args.includes('npm')&&args.includes('install')){
     if(m.fail==='npm')throw Error('npm failed');const dir=args.find(a=>a.startsWith('type=bind')).split('source=')[1].split(',target=')[0];
     const target=args.find(a=>a.startsWith(PACKAGE+'@')).slice(PACKAGE.length+1),p=manifest(target),l=lock(target);if(m.fail==='unrelated')l.packages['node_modules/other'].version='2.0.0';
     fs.writeFileSync(path.join(dir,'package.json'),JSON.stringify(p));fs.writeFileSync(path.join(dir,'package-lock.json'),JSON.stringify(l));return {stdout:''};
   }
   if(args[0]==='inspect'||args[0]==='image'&&args[1]==='inspect')return{stdout:'sha256:'+'c'.repeat(64)};
   if(args[0]==='image'&&args[1]==='tag'&&args.at(-1)==='example-backend:local')m.imageVersion='6.7.24';
   if(args.includes('--entrypoint')){if(m.fail==='imports')throw Error('import failure');return{stdout:JSON.stringify({version:m.imageVersion,node:'22.15.0'})};}
   return {stdout:''};
 }};
 return{m,b:new Baileys(m),backend,cleanup(){assert.ok(root.startsWith(os.tmpdir()+path.sep));fs.rmSync(root,{recursive:true});}};
}
test('fixed public dependency is identified; local, fork, alias and mismatched locks are not silently replaced',()=>{
 assert.equal(dependency(manifest('6.7.24'),lock('6.7.24')).supported,true);
 for(const spec of ['file:./baileys-local','github:someone/fork','npm:other@6.7.24','^6.7.24',undefined])assert.equal(dependency(manifest(spec),lock('6.7.24')).supported,false);
 const l=lock('6.7.24');l.packages['node_modules/'+PACKAGE].resolved='git+https://github.com/fork';assert.equal(dependency(manifest('6.7.24'),l).supported,false);
});
test('compatibility permits only newer stable patch in same line',()=>{for(const v of ['6.7.24','6.7.23','6.8.0','7.0.0','6.7.25-rc.1','latest','; echo secret'])assert.equal(newer('6.7.24',v),false);assert.equal(newer('6.7.24','6.7.25'),true);});
test('lockfile delta permits Baileys transitives but rejects unrelated changes',()=>{
 const next=lock('6.7.25');next.packages['node_modules/signal'].version='1.0.1';assert.doesNotThrow(()=>lockDelta(lock('6.7.24'),next,manifest('6.7.24'),manifest('6.7.25'),'6.7.25'));
 next.packages['node_modules/other'].version='2';assert.throws(()=>lockDelta(lock('6.7.24'),next,manifest('6.7.24'),manifest('6.7.25'),'6.7.25'),/não relacionada/);
});
test('inspection reports configured loaded and available versions dynamically without host NPM',async()=>{const t=fixture();try{const i=await t.b.inspect();assert.equal(i.runtime.version,'6.7.24');assert.equal(i.container,'example_backend');assert.deepEqual(i.compatible,['6.7.25']);assert.ok(t.m.calls.every(c=>['compose','docker'].includes(c.kind)));}finally{t.cleanup();}});
for(const failure of ['confirmation','download','no-new','major','local','npm','unrelated','build','imports','backup','health','version','logs'])test('Baileys failure preserves manifests and resources: '+failure,async()=>{
 const t=fixture();try{
  const original=fs.readFileSync(path.join(t.backend,'package.json')),originalLock=fs.readFileSync(path.join(t.backend,'package-lock.json'));
  if(failure==='local'){const p=manifest('file:./baileys-local');fs.writeFileSync(path.join(t.backend,'package.json'),JSON.stringify(p));}
  else if(failure==='no-new')t.m.versions=['6.7.24'];else t.m.fail=failure;
  const before=fs.readFileSync(path.join(t.backend,'package.json'));
  await assert.rejects(t.b.update(failure==='major'?'7.0.0':'6.7.25',failure==='confirmation'?'wrong':'ATUALIZAR BAILEYS example'));
  assert.deepEqual(fs.readFileSync(path.join(t.backend,'package.json')),failure==='local'?before:original);assert.deepEqual(fs.readFileSync(path.join(t.backend,'package-lock.json')),originalLock);assert.equal(t.m.runtime,'6.7.24');
  for(const f of ['sessions-fixture','database-fixture'])assert.equal(fs.readFileSync(path.join(t.m.root,f),'utf8'),'untouched');
  assert.ok(!t.m.calls.some(c=>c.args?.some(a=>['down','prune','migrate','seed'].includes(a))));
  if(['confirmation','download','no-new','major','local','npm','unrelated'].includes(failure))assert.ok(!t.m.calls.some(c=>c.kind==='compose'&&['up','build'].includes(c.args[0])));
 }finally{t.cleanup();}
});
test('compatible update rebuilds/recreates only backend; confirms loaded version; manual rollback restores originals',async()=>{
 const t=fixture();try{
  const original=fs.readFileSync(path.join(t.backend,'package.json'));const r=await t.b.update('6.7.25','ATUALIZAR BAILEYS example');assert.equal(r.phase,'complete');assert.equal(t.m.runtime,'6.7.25');assert.match(t.m.messages,/Versão atual carregada: 6.7.25/);assert.match(t.m.messages,/WhatsApp: PENDENTE/);
  assert.deepEqual(t.m.calls.find(c=>c.kind==='backup').options,{scope:'backend',restart:false});
  for(const c of t.m.calls.filter(c=>c.kind==='compose'&&['up','build'].includes(c.args[0])))assert.equal(c.args.at(-1),'backend');
  const npm=t.m.calls.find(c=>c.args?.includes('install'));assert.equal(npm.kind,'docker');assert.ok(npm.args.includes('--package-lock-only'));assert.ok(npm.args.includes('--engine-strict'));
  await t.b.rollback('REVERTER BAILEYS example');assert.equal(t.m.runtime,'6.7.24');assert.deepEqual(fs.readFileSync(path.join(t.backend,'package.json')),original);assert.equal(t.b.record().phase,'rolled-back');
 }finally{t.cleanup();}
});
test('partial states and interrupted journal do not allow a new update',async()=>{const t=fixture();try{t.m.state.initialized=false;t.m.state.phase='https-pending';await assert.rejects(t.b.inspect(),/incompleta/);t.m.state.initialized=true;t.m.state.phase='ready';t.m.write(t.b.journal,{phase:'applying'});await assert.rejects(t.b.update('6.7.25','ATUALIZAR BAILEYS example'),/interrompida/);}finally{t.cleanup();}});
test('rollback preserves subsequent manual manifest edits',async()=>{const t=fixture();try{await t.b.update('6.7.25','ATUALIZAR BAILEYS example');fs.appendFileSync(path.join(t.backend,'package.json'),' ');await assert.rejects(t.b.rollback('REVERTER BAILEYS example'),/alterados após/);assert.ok(fs.readFileSync(path.join(t.backend,'package.json'),'utf8').endsWith(' '));}finally{t.cleanup();}});
test('failed rollback leaves recoverable journal and blocks another update',async()=>{const t=fixture();try{const original=t.m.compose;t.m.compose=async args=>{if(args[0]==='up')throw Error('health failure');return original(args);};await assert.rejects(t.b.update('6.7.25','ATUALIZAR BAILEYS example'),/no rollback/);assert.equal(t.b.record().phase,'rollback-required');t.m.compose=original;await t.b.rollback('REVERTER BAILEYS example');assert.equal(t.b.record().phase,'rolled-back');}finally{t.cleanup();}});
test('Baileys submenu reports versions and returns without mutation',async()=>{const t=fixture();try{const {Menus}=require('../docker/installer/menus.cjs'),out=[];const menu=new Menus(t.m,async()=> '0',null,{out:s=>out.push(s)});await menu.dispatch('baileys');assert.match(out.join('\n'),/6.7.24/);assert.match(out.join('\n'),/example_backend/);assert.ok(!t.m.calls.some(c=>c.kind==='backup'||c.args?.includes('build')));}finally{t.cleanup();}});
test('image probe scripts parse without contacting WhatsApp',()=>{const vm=require('node:vm'),{PROBE,AUTH_PROBE}=require('../docker/installer/baileys.cjs');assert.doesNotThrow(()=>new vm.Script(PROBE));assert.doesNotThrow(()=>new vm.Script(AUTH_PROBE));});
test('another patch accepts only previously managed changes, never unrelated source edits',async()=>{const t=fixture();try{
 await t.b.update('6.7.25','ATUALIZAR BAILEYS example');t.m.versions.push('6.7.26','6.7.27');
 t.m.validateSource=async clean=>{if(clean)throw Error('Há alterações locais no código.');};t.m.git=async()=>({stdout:'backend/package.json\nbackend/package-lock.json\n'});
 await t.b.update('6.7.26','ATUALIZAR BAILEYS example');assert.equal(t.m.runtime,'6.7.26');
 t.m.git=async()=>({stdout:'backend/package.json\nbackend/src/server.ts\n'});await assert.rejects(t.b.update('6.7.27','ATUALIZAR BAILEYS example'),/Há alterações locais/);assert.equal(t.m.runtime,'6.7.26');
 }finally{t.cleanup();}});
