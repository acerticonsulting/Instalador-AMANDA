const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {spawn}=require('node:child_process');
const {Manager}=require('../docker/installer/manager.cjs');
function fixture(){const root=fs.mkdtempSync(path.join(os.tmpdir(),'amanda-lock-')),m=new Manager(root,{emit(){}});fs.mkdirSync(m.private);return {m,file:path.join(m.private,'operation.lock'),cleanup:()=>fs.rmSync(root,{recursive:true,force:true})};}
test('resume distinguishes an unstarted installation from interrupted preparation',async()=>{const t=fixture();try{t.m.doctor=async()=>{};await assert.rejects(t.m.execute('resume'),/ainda não registrada/);t.m.save({schema:1,sourceUrl:'https://github.com/acerticonsulting/AMANDA.git',project:'amanda',profiles:[],platform:path.join(t.m.root,'platform'),phase:'preparing',initialized:false});await assert.rejects(t.m.execute('resume'),/Preparação interrompida/);assert.ok(fs.existsSync(t.m.stateFile));}finally{t.cleanup();}});
test('fresh, nested, failed and subsequent operations release only their own lock',async()=>{const t=fixture();try{await t.m.lock(async()=>{assert.ok(fs.existsSync(t.file));await t.m.lock(async()=>{});});assert.ok(!fs.existsSync(t.file));await assert.rejects(t.m.lock(async()=>{throw Error('build failed');}),/build failed/);await t.m.lock(async()=>{});assert.ok(!fs.existsSync(t.file));}finally{t.cleanup();}});
test('atomic guard excludes concurrent managers and allows a later operation',async()=>{const t=fixture();try{let release,ready;const started=new Promise(r=>ready=r);const operation=t.m.lock(async()=>{ready();await new Promise(r=>release=r);});await started;await assert.rejects(new Manager(t.m.root,{emit(){}}).lock(async()=>{}),/Outra operação/);release();await operation;await t.m.lock(async()=>{});}finally{t.cleanup();}});
test('legacy stopped or absent Docker owners recover, but active or unverified owners remain protected',async()=>{
 for(const state of ['true','false','absent','daemon-error','unknown']){const t=fixture();try{
 fs.writeFileSync(t.file,JSON.stringify({container:'a'.repeat(12),at:'2026-11-12T00:00:00Z'}));
 t.m.docker=async args=>{if(args[0]==='inspect')return {code:state==='absent'||state==='daemon-error'?1:0,stdout:state};if(state==='daemon-error')throw Error('daemon unavailable');return {code:0,stdout:''};};
 if(['false','absent'].includes(state)){await t.m.lock(async()=>{});assert.ok(!fs.existsSync(t.file));}else{await assert.rejects(t.m.lock(async()=>{}));assert.ok(fs.existsSync(t.file));await assert.rejects(t.m.unlock());assert.ok(fs.existsSync(t.file));}
 }finally{t.cleanup();}}
});
test('malformed and unidentified owners are never recovered automatically',async()=>{for(const value of ['bad','{}',JSON.stringify({container:'not-a-docker-id'})]){const t=fixture();try{fs.writeFileSync(t.file,value);await assert.rejects(t.m.lock(async()=>{}));assert.equal(fs.readFileSync(t.file,'utf8'),value);}finally{t.cleanup();}}});
test('replaced ownership is preserved on completion',async()=>{const t=fixture();try{await t.m.lock(async()=>{fs.writeFileSync(t.file,JSON.stringify({container:'b'.repeat(12)}));});assert.equal(JSON.parse(fs.readFileSync(t.file)).container,'b'.repeat(12));}finally{t.cleanup();}});
for(const signal of ['SIGINT','SIGTERM'])test('interrupted owner '+signal+' is recoverable without touching platform data',async()=>{
 const t=fixture();try{
 fs.writeFileSync(path.join(t.m.root,'preserved-data'),'keep');
 const code=`const {Manager}=require(${JSON.stringify(path.resolve(__dirname,'../docker/installer/manager.cjs'))});new Manager(${JSON.stringify(t.m.root)},{emit(){}}).lock(async()=>{console.log('LOCKED');await new Promise(()=>{setInterval(()=>{},1000);});});`;
 const child=spawn(process.execPath,['-e',code],{env:{...process.env,AMANDA_MANAGER_CONTAINER:''},stdio:['ignore','pipe','pipe']});
 await new Promise((resolve,reject)=>{const timer=setTimeout(()=>{child.kill('SIGKILL');reject(Error('Child timeout'));},5000);child.stdout.once('data',()=>{clearTimeout(timer);resolve();});child.once('error',reject);});
 await new Promise(resolve=>{child.once('close',resolve);child.kill(signal);});
 // The owner's flock/cat children release their kernel lock asynchronously.
 // Await that observable release instead of racing it after the owner exits.
 await new Promise((resolve,reject)=>{const guard=spawn('flock',['-w','2',t.file+'.guard','true']);guard.once('error',reject);guard.once('close',code=>code===0?resolve():reject(Error('Guard did not release after interrupted owner')));});
 await t.m.lock(async()=>{});assert.ok(!fs.existsSync(t.file));assert.equal(fs.readFileSync(path.join(t.m.root,'preserved-data'),'utf8'),'keep');
 }finally{t.cleanup();}
});
