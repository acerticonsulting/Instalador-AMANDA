const{test}=require('node:test'),assert=require('node:assert/strict');
const{workspace}=require('./fixtures/managed-instances.cjs');
const{Manager}=require('../docker/installer/manager.cjs');
const{Menus}=require('../docker/installer/menus.cjs');
const{inspectInstallation}=require('../docker/installer/deploy.cjs');
const fs=require('node:fs'),path=require('node:path');
const menu=(t,ask=async()=>{throw Error('Unexpected selection question');})=>new Menus(new Manager(t.base),ask,null,{out(){}});
test('strict selection recognizes a real ready installation with optional profiles and setup identity',async()=>{
  const t=workspace();try{const a=t.add(),before=t.snapshot(),menus=new Menus(new Manager(t.base),async()=>{throw Error('Only one company; no question expected');},null,{out(){}});await menus.selectInstance(true);assert.equal(menus.m.root,a.root);assert.equal(menus.m.state.project,'amanda');assert.deepEqual(menus.m.state.profiles,a.state.profiles);assert.deepEqual(t.snapshot(),before);}finally{t.cleanup();}
});
test('shared discovery resolves omitted project only after real directory validation',()=>{
  const t=workspace();try{const a=t.add();assert.equal(inspectInstallation(a.root).kind,'complete');assert.equal(inspectInstallation(a.root).project,'amanda');}finally{t.cleanup();}
});
test('legacy custom root can discover a validated project different from its basename',async()=>{const t=workspace();try{const a=t.add('amanda',{root:path.join(t.base,'custom-root')}),m=new Menus(a.manager,async()=>{},null,{out(){}});await m.selectInstance(true);assert.equal(m.m.state.project,'amanda');assert.equal(m.m.root,a.root);}finally{t.cleanup();}});
test('two companies remain distinct and switching changes the actual Manager and optional profiles',async()=>{const t=workspace();try{const a=t.add('acerti'),b=t.add('bravo',{profiles:[]}),before=t.snapshot();let choice='2';const m=menu(t,async() =>choice);await m.selectInstance(true);assert.equal(m.m.root,b.root);assert.deepEqual(m.m.state.profiles,[]);choice='1';await m.selectInstance(true);assert.equal(m.m.root,a.root);assert.deepEqual(m.m.state.profiles,a.state.profiles);assert.deepEqual(t.snapshot(),before);}finally{t.cleanup();}});
for(const [name,damage,reason]of [
  ['invalid JSON',a=>fs.writeFileSync(a.file,'{synthetic-private-token'),/JSON inválidos/],
  ['different project',a=>{a.state.project='other_company';a.write();},/project|empresa/],
  ['unknown phase',a=>{a.state.phase='invented';a.write();},/phase/],
  ['invalid private permissions',a=>fs.chmodSync(a.file,0o644),/permissões/],
  ['outside platform',a=>{a.state.platform='/etc';a.write();},/Plataforma|integridade/],
  ['missing platform',a=>fs.rmdirSync(a.platform,{recursive:true}),/ausente/],
  ['foreign source',a=>{a.state.sourceUrl='https://other.example.test';a.write();},/sourceUrl/],
  ['inconsistent ready',a=>{a.state.initialized=false;a.write();},/Checkpoint/],
  ['private state symlink',a=>{fs.renameSync(a.file,a.file+'.outside');fs.symlinkSync(a.file+'.outside',a.file);},/simbólico|reconhecido/],
])test('strict discovery rejects '+name+' with a sanitized reason',async()=>{const t=workspace();try{const a=t.add();damage(a);const before=t.snapshot();await assert.rejects(menu(t).selectInstance(true),e=>{assert.match(e.message,reason);assert.ok(!e.message.includes('synthetic-private-token'));return true;});assert.deepEqual(t.snapshot(),before);}finally{t.cleanup();}});
test('wrong ownership remains blocked during inferred discovery',async t=>{if(process.getuid()!==0)return t.skip('requires isolated root for chown fixture');const w=workspace();try{const a=w.add();fs.chownSync(a.file,123456,123456);await assert.rejects(menu(w).selectInstance(true),/proprietário/);}finally{w.cleanup();}});
test('symbolic company directory is rejected without accepting the target',async()=>{const t=workspace();try{const a=t.add('amanda',{root:path.join(t.base,'outside')});fs.symlinkSync(a.root,path.join(t.base,'instances','amanda'));await assert.rejects(menu(t).selectInstance(true),/simbólico/);}finally{t.cleanup();}});
test('empty discovery and unrelated folders never masquerade as an installation',async()=>{const t=workspace();try{fs.mkdirSync(path.join(t.base,'instances','unrelated'));await assert.rejects(menu(t).selectInstance(true),/Nenhuma instalação/);}finally{t.cleanup();}});
test('invalid neighbor is diagnosed while a valid company remains selectable',async()=>{const t=workspace();try{const a=t.add('acerti'),b=t.add('bravo');fs.writeFileSync(b.file,'{bad');const output=[],m=menu(t);m.out=x=>output.push(x);await m.selectInstance(true);assert.equal(m.m.root,a.root);assert.match(output.join('\n'),/bravo.*JSON inválidos/);}finally{t.cleanup();}});
test('selection can be canceled without changing the current manager or persisted files',async()=>{const t=workspace();try{t.add('acerti');t.add('bravo');const m=menu(t,async()=> '0'),before=t.snapshot(),original=m.m;await assert.rejects(m.selectInstance(true),/cancelada/);assert.equal(m.m,original);assert.deepEqual(t.snapshot(),before);}finally{t.cleanup();}});
test('state is validated again after company selection, including same-root selection',async()=>{const t=workspace();try{const a=t.add('acerti');t.add('bravo');const m=menu(t,async()=>{a.state.project='bravo';a.write();return'1';});await assert.rejects(m.selectInstance(true),/reconhecida/);}finally{t.cleanup();}});
test('partial checkpoint stays partial and does not grant API administrative access',async()=>{const t=workspace();try{const a=t.add('amanda',{phase:'starting'}),m=menu(t);await m.selectInstance(true);assert.equal(m.m.root,a.root);assert.equal(m.m.state.initialized,false);assert.equal(inspectInstallation(a.root).kind,'partial');const{Operations}=require('../docker/installer/operations.cjs');m.m.doctor=async()=>{};m.m.identifyManager=async()=>{};m.m.validateSource=async()=>{};m.m.configuration=async()=>{};await assert.rejects(new Operations(m.m).ready(),/incompleta/);}finally{t.cleanup();}});
test('all direct /home/deploy company names must match even with an explicit project',()=>{const t=workspace();try{const a=t.add('amanda');const info=require('../docker/installer/directory-state.cjs').inspectDirectory(a.root,{project:'other',logicalRoot:'/home/deploy/amanda'});assert.equal(info.kind,'unknown');assert.match(info.reason,/project/);}finally{t.cleanup();}});
test('actual /home/deploy/amanda fixture is recognized in automatic layout without modifying its persisted state',async()=>{
  // This suite runs in an isolated Docker filesystem, never on the VPS.
  const t=workspace(),root='/home/deploy/amanda',prior=process.env.AMANDA_DEPLOY_LAYOUT;let created=false;
  try{assert.equal(fs.existsSync(root),false,'Do not overwrite any existing fixture');const a=t.add('amanda',{root});created=true;const before=fs.readFileSync(a.file);process.env.AMANDA_DEPLOY_LAYOUT='1';const m=new Menus(new Manager('/home/deploy'),async()=>{throw Error('Unexpected company question');},null,{out(){}});await m.selectInstance(true);assert.equal(m.m.root,root);assert.equal(m.m.state.project,'amanda');assert.deepEqual(m.m.state.profiles,['official','whatsmeow','rabbit','edge']);assert.deepEqual(fs.readFileSync(a.file),before);}finally{if(prior===undefined)delete process.env.AMANDA_DEPLOY_LAYOUT;else process.env.AMANDA_DEPLOY_LAYOUT=prior;if(created)fs.rmSync(root,{recursive:true});t.cleanup();}
});
test('symbolic discovery parent is not traversed to find company states',async()=>{const t=workspace(),outside=workspace();try{outside.add();fs.rmdirSync(path.join(t.base,'instances'));fs.symlinkSync(path.join(outside.base,'instances'),path.join(t.base,'instances'));await assert.rejects(menu(t).selectInstance(true),/simbólico/);}finally{t.cleanup();outside.cleanup();}});
