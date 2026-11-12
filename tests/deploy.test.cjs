const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {BASE,companyDirectory,account,provision,ownership,installationManager}=require('../docker/installer/deploy.cjs');
const {inspectDirectory,setupRecord}=require('../docker/installer/directory-state.cjs');
const {startInstallation}=require('../docker/installer/deploy.cjs');
const {Manager,SOURCE,normalizeConfig}=require('../docker/installer/manager.cjs');
function fixture(passwd='root:x:0:0:root:/root:/bin/sh\n'){const root=fs.mkdtempSync(path.join(os.tmpdir(),'deploy-test-'));fs.mkdirSync(root+'/etc');fs.mkdirSync(root+BASE,{recursive:true});fs.writeFileSync(root+'/etc/passwd',passwd);return {root,cleanup:()=>fs.rmSync(root,{recursive:true,force:true})};}
test('company paths are isolated and reject traversal, metacharacters and invalid slugs',()=>{assert.equal(companyDirectory('amanda'),BASE+'/amanda');assert.equal(companyDirectory('acerti'),BASE+'/acerti');for(const value of ['../root','a/b','/root','a;id','a b','',null])assert.throws(()=>companyDirectory(value));assert.throws(()=>account('deploy:x:0:0::/home/deploy:/bin/sh'));});
test('missing deploy account is created with no sudo/docker membership and private company directory',()=>{const t=fixture();try{let args;const owner=provision('amanda',{host:t.root,run:(cmd,a)=>{assert.equal(cmd,'useradd');args=a;fs.appendFileSync(t.root+'/etc/passwd','deploy:!:12345:12345::/home/deploy:/usr/sbin/nologin\n');}});assert.equal(owner.uid,12345);assert.ok(args.includes('--system'));assert.ok(!args.includes('--groups'));assert.equal(fs.statSync(t.root+BASE+'/amanda').uid,12345);assert.equal(fs.statSync(t.root+BASE+'/amanda').mode&0o777,0o700);}finally{t.cleanup();}});
test('existing deploy credentials, groups, shell and home permissions are preserved across companies',()=>{const passwd='root:x:0:0::/root:/bin/sh\ndeploy:x:12345:12346::/existing/home:/bin/bash\n',t=fixture(passwd);try{fs.chmodSync(t.root+BASE,0o750);provision('amanda',{host:t.root,run(){throw Error('must not change account');}});provision('acerti',{host:t.root,run(){throw Error('must not change account');}});assert.equal(fs.readFileSync(t.root+'/etc/passwd','utf8'),passwd);assert.equal(fs.statSync(t.root+BASE).mode&0o777,0o750);assert.equal(fs.statSync(t.root+BASE+'/acerti').gid,12346);}finally{t.cleanup();}});
test('populated legacy directory and symlink targets are rejected without altering data',()=>{const t=fixture('deploy:x:12345:12345::/home/deploy:/bin/sh\n');try{fs.mkdirSync(t.root+BASE+'/amanda');fs.writeFileSync(t.root+BASE+'/amanda/data','keep');assert.throws(()=>provision('amanda',{host:t.root}),/já contém/);assert.equal(fs.readFileSync(t.root+BASE+'/amanda/data','utf8'),'keep');fs.symlinkSync(t.root+BASE+'/amanda',t.root+BASE+'/acerti');assert.throws(()=>provision('acerti',{host:t.root}),/simbólico/);}finally{t.cleanup();}});
test('ownership inventories only the selected company and never follows symlinks',()=>{fs.mkdirSync(BASE,{recursive:true});const root=BASE+'/test_'+require('node:crypto').randomBytes(8).toString('hex'),outside=fs.mkdtempSync(path.join(os.tmpdir(),'deploy-outside-'));try{fs.mkdirSync(root);fs.mkdirSync(root+'/.amanda-installer',{mode:0o700});fs.writeFileSync(root+'/.amanda-installer/state.json','{}',{mode:0o666});fs.writeFileSync(outside+'/keep','keep');fs.symlinkSync(outside,root+'/external');ownership({root,deploymentOwner:{uid:12345,gid:12346}});assert.equal(fs.statSync(root+'/.amanda-installer/state.json').uid,12345);assert.equal(fs.statSync(root+'/.amanda-installer/state.json').mode&0o777,0o600);const m=new(require('../docker/installer/manager.cjs').Manager)(root);m.deploymentOwner={uid:12345,gid:12346};m.runner.output={write(){}};m.runner.emit('diagnóstico');assert.equal(fs.statSync(root+'/.amanda-installer/install.log').uid,12345);assert.equal(fs.statSync(root+'/.amanda-installer/install.log').mode&0o777,0o600);assert.equal(fs.statSync(outside+'/keep').uid,0);fs.linkSync(outside+'/keep',root+'/hardlink');assert.throws(()=>ownership({root,deploymentOwner:{uid:12345,gid:12346}}),/hardlinks/);assert.equal(fs.statSync(outside+'/keep').uid,0);assert.throws(()=>ownership({root:outside,deploymentOwner:{uid:12345,gid:12346}}),/Escopo|Identificador/);}finally{fs.rmSync(root,{recursive:true,force:true});fs.rmSync(outside,{recursive:true,force:true});}});
test('explicit legacy layout does not create deploy, move files or change its Manager',async()=>{const old=process.env.AMANDA_DEPLOY_LAYOUT;try{process.env.AMANDA_DEPLOY_LAYOUT='0';const m={root:'/root/amanda',docker(){throw Error('unexpected provisioning');}};assert.equal(await installationManager(m,{project:'amanda'}),m);}finally{if(old===undefined)delete process.env.AMANDA_DEPLOY_LAYOUT;else process.env.AMANDA_DEPLOY_LAYOUT=old;}});
test('bootstrap mounts deploy base for new installs and detects the historical registered path',()=>{
 const t=fixture();try{const bin=t.root+'/bin',log=t.root+'/docker-args';fs.mkdirSync(bin);fs.writeFileSync(bin+'/docker','#!/bin/sh\ncase "$1" in info) echo linux ;; context) echo unix:///var/run/docker.sock ;; run) printf "%s\\n" "$@" >> "$TEST_LOG" ;; esac\n',{mode:0o755});const {spawnSync}=require('node:child_process'),script=path.resolve(__dirname,'../instalador_single.sh'),env={...process.env,PATH:bin+':'+process.env.PATH,HOME:t.root,TEST_LOG:log};delete env.AMANDA_INSTALL_DIR;
 let result=spawnSync('sh',[script,'status'],{env,encoding:'utf8'});assert.equal(result.status,0,result.stderr);let args=fs.readFileSync(log,'utf8');assert.ok(args.includes('AMANDA_DEPLOY_LAYOUT=1'));assert.ok(args.includes(BASE+':'+BASE));fs.unlinkSync(log);
 const old=t.root+'/amanda';fs.mkdirSync(old+'/.amanda-installer',{recursive:true});fs.writeFileSync(old+'/.amanda-installer/state.json','{}');result=spawnSync('sh',[script,'status'],{env,encoding:'utf8'});assert.equal(result.status,0,result.stderr);args=fs.readFileSync(log,'utf8');assert.ok(args.includes('AMANDA_DEPLOY_LAYOUT=1'));assert.ok(args.includes(old+':'+old));assert.equal(fs.readFileSync(old+'/.amanda-installer/state.json','utf8'),'{}');
 }finally{t.cleanup();}
});

function recognized(t,{phase='build',complete=false}={}){
 const root=t.root+BASE+'/amanda',privateDir=root+'/.amanda-installer';fs.mkdirSync(privateDir,{recursive:true,mode:0o700});fs.mkdirSync(root+'/platform');
 const state={schema:1,sourceUrl:SOURCE,project:'amanda',platform:root+'/platform',profiles:[],phase:complete?'ready':phase,initialized:complete,seedAttempted:complete,seedSucceeded:complete,freshResourcesVerified:true};
 fs.writeFileSync(privateDir+'/state.json',JSON.stringify(state),{mode:0o600});fs.writeFileSync(root+'/platform/.env','DB_PASS=preserved\n',{mode:0o600});
 return {root,privateDir,state};
}
test('directory classification is read-only for absent, empty and private temporary metadata',()=>{
 const t=fixture();try{
  const root=t.root+BASE+'/amanda';assert.equal(inspectDirectory(root,{project:'amanda'}).kind,'absent');assert.ok(!fs.existsSync(root));
  fs.mkdirSync(root);assert.equal(inspectDirectory(root,{project:'amanda'}).kind,'empty');
  fs.mkdirSync(root+'/.amanda-installer',{mode:0o700});fs.writeFileSync(root+'/.amanda-installer/install.log','previous attempt',{mode:0o600});fs.writeFileSync(root+'/.amanda-installer/operation.lock.guard','',{mode:0o644});
  assert.equal(inspectDirectory(root,{project:'amanda'}).kind,'temporary');
  provision('amanda',{host:t.root,run(){fs.appendFileSync(t.root+'/etc/passwd','deploy:!:12345:12345::/home/deploy:/usr/sbin/nologin\n');}});
  assert.equal(fs.readFileSync(root+'/.amanda-installer/install.log','utf8'),'previous attempt');
 }finally{t.cleanup();}
});
test('valid partial and completed states are recognized and never reprovisioned',()=>{
 for(const complete of [false,true]){const t=fixture('deploy:x:12345:12345::/home/deploy:/bin/sh\n');try{
  const f=recognized(t,{complete});assert.equal(inspectDirectory(f.root,{project:'amanda'}).kind,complete?'complete':'partial');
  fs.writeFileSync(f.privateDir+'/state.json',JSON.stringify({...f.state,platform:BASE+'/amanda/platform'}));
  const before=fs.readFileSync(f.privateDir+'/state.json','utf8');assert.throws(()=>provision('amanda',{host:t.root}),/Instalação AMANDA/);assert.equal(fs.readFileSync(f.privateDir+'/state.json','utf8'),before);
 }finally{t.cleanup();}}
});
test('invalid states, foreign ownership, symlinks, hardlinks and unknown files block without changes',()=>{
 const cases=[
  f=>fs.writeFileSync(f.privateDir+'/state.json','{broken'),
  f=>fs.writeFileSync(f.privateDir+'/state.json',JSON.stringify({...f.state,project:'other'})),
  f=>fs.writeFileSync(f.privateDir+'/state.json',JSON.stringify({...f.state,platform:'/root/amanda'})),
  f=>fs.writeFileSync(f.privateDir+'/state.json',JSON.stringify({...f.state,phase:'invented'})),
  f=>fs.writeFileSync(f.root+'/unknown.txt','keep'),
  f=>fs.writeFileSync(f.privateDir+'/unknown','keep'),
  f=>fs.writeFileSync(f.privateDir+'/backups','not-a-directory',{mode:0o600}),
  f=>fs.chmodSync(f.privateDir,0o777),
  f=>fs.chmodSync(f.privateDir+'/state.json',0o644),
  f=>fs.chownSync(f.privateDir+'/state.json',23456,23456),
  f=>{fs.renameSync(f.privateDir+'/state.json',f.root+'/original');fs.symlinkSync(f.root+'/original',f.privateDir+'/state.json');},
  f=>fs.linkSync(f.privateDir+'/state.json',f.root+'/linked')
 ];
 for(const modify of cases){const t=fixture();try{const f=recognized(t);modify(f);const before=fs.readFileSync(f.root+'/platform/.env','utf8');assert.equal(inspectDirectory(f.root,{project:'amanda'}).kind,'unknown');assert.equal(fs.readFileSync(f.root+'/platform/.env','utf8'),before);}finally{t.cleanup();}}
});
test('saved temporary configuration is integrity checked and reused without questionnaire',async()=>{
 const t=fixture();try{
  const root=t.root+BASE+'/amanda';fs.mkdirSync(root+'/.amanda-installer',{recursive:true,mode:0o700});
  const config=normalizeConfig({sourceUrl:SOURCE,project:'amanda',adminPassword:'private-choice'}),file=root+'/.amanda-installer/setup.json';
  fs.writeFileSync(file,JSON.stringify(setupRecord(root,config)),{mode:0o600});
  let installed=false;
  await startInstallation(new Manager(root),{automatic:false,question:async()=> 'amanda',collect:async()=>{throw Error('must not ask again');},out(){},installNew:async(m,c)=>{assert.deepEqual(c,config);installed=true;return m;}});
  assert.equal(installed,true);const record=JSON.parse(fs.readFileSync(file));record.config.adminPassword='altered';fs.writeFileSync(file,JSON.stringify(record));assert.equal(inspectDirectory(root,{project:'amanda'}).kind,'unknown');
 }finally{t.cleanup();}
});
test('company selection inspects before any secret or resource questions and blocks unknown directories',async()=>{
 const t=fixture();try{const root=t.root+BASE+'/amanda';fs.mkdirSync(root);fs.writeFileSync(root+'/unknown','keep');let questions=0;
  await assert.rejects(startInstallation(new Manager(root),{automatic:false,question:async label=>{questions++;assert.equal(label,'Nome técnico da empresa');return 'amanda';},collect:async()=>{throw Error('late questionnaire');},out(){}}),/Nenhum arquivo foi alterado/);
  assert.equal(questions,1);assert.deepEqual(fs.readdirSync(root),['unknown']);
 }finally{t.cleanup();}
});
test('partial detection offers diagnostics and resumes the same company without collecting config or provisioning',async()=>{
 const t=fixture();try{const f=recognized(t),m=new Manager(f.root),answers=['2','1'],output=[];let resumed=0;
  m.execute=async action=>{assert.equal(action,'resume');resumed++;};
  const result=await startInstallation(m,{automatic:false,question:async()=>answers.shift(),collect:async()=>{throw Error('must not collect');},installNew:async()=>{throw Error('must not provision');},out:s=>output.push(s)});
  assert.equal(result,m);assert.equal(resumed,1);assert.ok(output.join('\n').includes('Última etapa registrada: build'));assert.ok(!output.join('\n').includes('preserved'));assert.equal(fs.readFileSync(f.root+'/platform/.env','utf8'),'DB_PASS=preserved\n');
 }finally{t.cleanup();}
});
test('completed detection offers management and never runs a new installation or seed',async()=>{
 const t=fixture();try{const f=recognized(t,{complete:true}),m=new Manager(f.root);let managed=0;
  await startInstallation(m,{automatic:false,question:async()=> '1',collect:async()=>{throw Error('no questionnaire');},installNew:async()=>{throw Error('no install');},manage:async target=>{assert.equal(target,m);managed++;},out(){}});
  assert.equal(managed,1);assert.equal(JSON.parse(fs.readFileSync(f.privateDir+'/state.json')).seedSucceeded,true);
 }finally{t.cleanup();}
});

test('recognized installations preserve configuration history, schedules and registry credentials',()=>{
 const t=fixture();try{const f=recognized(t,{complete:true});
  for(const name of ['config-history','backups','docker-auth'])fs.mkdirSync(path.join(f.privateDir,name),{mode:0o700});
  for(const name of ['schedule-backup.json','schedule-update.json','registry-input'])fs.writeFileSync(path.join(f.privateDir,name),'preserved',{mode:0o600});
  assert.equal(inspectDirectory(f.root,{project:'amanda'}).kind,'complete');assert.equal(fs.readFileSync(f.privateDir+'/registry-input','utf8'),'preserved');
 }finally{t.cleanup();}
});

test('actual noninteractive CLI diagnoses unknown or complete directories before contacting Docker',()=>{
 for(const complete of [false,true]){const t=fixture();try{
  let root;if(complete)root=recognized(t,{complete:true}).root;else{root=t.root+BASE+'/amanda';fs.mkdirSync(root);fs.writeFileSync(root+'/unknown','keep');}
  const file=t.root+'/input.json';fs.writeFileSync(file,JSON.stringify({sourceUrl:SOURCE,project:'amanda',adminPassword:'never-print-this-secret'}),{mode:0o600});
  const result=require('node:child_process').spawnSync(process.execPath,[path.resolve(__dirname,'../docker/installer/cli.cjs'),'install','--config',file],{encoding:'utf8',env:{...process.env,AMANDA_INSTALL_DIR:root,AMANDA_DEPLOY_LAYOUT:'0'}});
  assert.equal(result.status,complete?0:1);assert.ok(!result.stdout.includes('never-print-this-secret'));assert.ok(!result.stderr.includes('never-print-this-secret'));
  if(complete){assert.ok(result.stdout.includes('concluída'));assert.ok(!fs.existsSync(root+'/.amanda-installer/install.log'));}
  else{assert.ok(result.stderr.includes('Nenhum arquivo foi alterado'));assert.deepEqual(fs.readdirSync(root),['unknown']);}
 }finally{t.cleanup();}}
});
