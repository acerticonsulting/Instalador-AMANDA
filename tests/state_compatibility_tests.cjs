const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const current=require('../docker/installer/directory-state.cjs'),old=require('./fixtures/directory-state-882f0d5.cjs');
function fixture(){const root=fs.mkdtempSync(path.join(os.tmpdir(),'amanda-state-compat-'));fs.chmodSync(root,0o700);fs.mkdirSync(path.join(root,'platform'),{mode:0o700});const privateDir=path.join(root,'.amanda-installer');fs.mkdirSync(privateDir,{mode:0o700});const file=path.join(privateDir,'state.json');
 const state={schema:1,sourceUrl:'https://github.com/acerticonsulting/AMANDA.git',project:'amanda',phase:'starting',platform:path.join(root,'platform'),profiles:['edge'],initialized:false,seedAttempted:true,seedSucceeded:true,freshResourcesVerified:true,infrastructureReady:true,internalHttpReady:true,publicHttps:'pending',adminPassword:'fixture-secret-never-print'};
 const write=()=>fs.writeFileSync(file,JSON.stringify(state),{mode:0o600});write();return{root,file,privateDir,state,write,inspect:()=>current.inspectDirectory(root,{project:'amanda'}),cleanup:()=>fs.rmSync(root,{recursive:true,force:true})};}
test('882f0d5 and b48de8c share validator: starting works; previously written https-pending was rejected',()=>{
 const t=fixture();try{assert.equal(old.inspectDirectory(t.root,{project:'amanda'}).kind,'partial');t.state.phase='https-pending';t.write();const before=fs.readFileSync(t.file);assert.equal(old.inspectDirectory(t.root,{project:'amanda'}).kind,'unknown');assert.equal(t.inspect().kind,'partial');assert.equal(t.inspect().phase,'https-pending');assert.deepEqual(fs.readFileSync(t.file),before);}finally{t.cleanup();}
});
for(const phase of ['starting','build','migrations','ready','https-pending'])test('known phase '+phase+' is compatible without rewriting state',()=>{const t=fixture();try{t.state.phase=phase;t.state.initialized=phase==='ready';t.write();const before=fs.readFileSync(t.file);assert.equal(t.inspect().kind,phase==='ready'?'complete':'partial');assert.equal(t.inspect().kind,phase==='ready'?'complete':'partial');assert.deepEqual(fs.readFileSync(t.file),before);}finally{t.cleanup();}});
for(const [field,value]of [['schema',9],['project','other'],['sourceUrl','https://other.test'],['phase','invented'],['seedSucceeded','yes'],['initialized',null],['profiles',['unknown']]])test('precise rejection '+field,()=>{const t=fixture();try{t.state[field]=value;t.write();assert.equal(t.inspect().kind,'unknown');assert.match(t.inspect().reason,new RegExp(field));const diagnosis=current.diagnoseDirectory(t.root,{project:'amanda'});assert.ok(!JSON.stringify(diagnosis).includes('fixture-secret-never-print'));}finally{t.cleanup();}});
test('HTTPS pending requires actual checkpoints; old optional fields stay optional for starting',()=>{const t=fixture();try{delete t.state.infrastructureReady;delete t.state.internalHttpReady;assert.equal((t.write(),t.inspect()).kind,'partial');t.state.phase='https-pending';t.write();assert.match(t.inspect().reason,/checkpoints HTTPS/);}finally{t.cleanup();}});
test('symlinks insecure permissions unknown private files partial JSON and owner remain blocked',()=>{const t=fixture();try{
 fs.chmodSync(t.file,0o644);assert.equal(t.inspect().kind,'unknown');fs.chmodSync(t.file,0o600);
 const extra=path.join(t.privateDir,'unrecognized');fs.writeFileSync(extra,'secret',{mode:0o600});assert.equal(t.inspect().kind,'unknown');fs.unlinkSync(extra);
 fs.writeFileSync(t.file,'{"schema":');assert.equal(t.inspect().kind,'unknown');t.write();
 fs.symlinkSync(t.file,path.join(t.privateDir,'state.json.tmp'));assert.equal(t.inspect().kind,'unknown');fs.unlinkSync(path.join(t.privateDir,'state.json.tmp'));
 if(process.getuid()===0){fs.chownSync(t.file,123456,123456);assert.equal(t.inspect().kind,'unknown');fs.chownSync(t.file,0,0);}
 assert.equal(t.inspect().kind,'partial');
 }finally{t.cleanup();}});
test('state-diagnose CLI reads an incompatible state without load failure, secrets or writes',()=>{
 const t=fixture();try{t.state.schema=9;t.write();const before=fs.readFileSync(t.file),names=fs.readdirSync(t.privateDir);
 const r=require('node:child_process').spawnSync(process.execPath,[path.join(__dirname,'../docker/installer/cli.cjs'),'state-diagnose'],{encoding:'utf8',env:{...process.env,AMANDA_INSTALL_DIR:t.root}});
 assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/schema não suportado/);assert.match(r.stdout,/"readOnly": true/);assert.ok(!r.stdout.includes('fixture-secret-never-print'));assert.deepEqual(fs.readFileSync(t.file),before);assert.deepEqual(fs.readdirSync(t.privateDir),names);
 }finally{t.cleanup();}
});
