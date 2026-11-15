const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const assert=require('node:assert/strict');
const PACKAGE='@whiskeysockets/baileys',REGISTRY='https://registry.npmjs.org';
const fixed=v=>typeof v==='string'&&/^\d+\.\d+\.\d+$/.test(v);
const sameLine=(a,b)=>fixed(a)&&fixed(b)&&a.split('.').slice(0,2).join('.')===b.split('.').slice(0,2).join('.');
const newer=(a,b)=>sameLine(a,b)&&Number(b.split('.')[2])>Number(a.split('.')[2]);
function dependency(manifest,lock){
 const configured=manifest.dependencies?.[PACKAGE],entry=lock.packages?.['node_modules/'+PACKAGE];
 const supported=fixed(configured)&&entry?.version===configured&&!entry.link&&entry.resolved===REGISTRY+'/'+PACKAGE+'/-/baileys-'+configured+'.tgz'&&Boolean(entry.integrity)&&lock.packages?.['']?.dependencies?.[PACKAGE]===configured;
 return {configured:configured||'Ausente',locked:entry?.version||'Não verificado',supported};
}
function lockDelta(before,after,oldManifest,newManifest,target){
 const expected=structuredClone(oldManifest);expected.dependencies[PACKAGE]=target;assert.deepEqual(newManifest,expected,'Manifesto alterou outros campos');
 const oldRoot=structuredClone(before.packages['']),newRoot=structuredClone(after.packages['']);oldRoot.dependencies[PACKAGE]=target;assert.deepEqual(newRoot,oldRoot,'Raiz do lockfile alterou outros campos');
 const entries={...before.packages,...after.packages},name=k=>k.slice(k.lastIndexOf('node_modules/')+13),allowed=new Set([PACKAGE]);
 let size;do{size=allowed.size;for(const source of [before.packages,after.packages])for(const[k,v]of Object.entries(source))if(k&&allowed.has(name(k)))for(const dep of Object.keys({...v.dependencies,...v.optionalDependencies}))allowed.add(dep);}while(allowed.size!==size);
 for(const k of Object.keys(entries))if(k&&!allowed.has(name(k)))assert.deepEqual(after.packages[k],before.packages[k],'Dependência não relacionada alterada: '+k);
 const metaOld={...before},metaNew={...after};delete metaOld.packages;delete metaNew.packages;assert.deepEqual(metaNew,metaOld,'Formato/metadados do lockfile alterados');
 if(!dependency(newManifest,after).supported)throw Error('Resolução Baileys inesperada.');
}
// Carrega o mesmo pacote/caminho interno usado pelos imports CommonJS do backend.
const PROBE=`const fs=require('fs'),path=require('path');const b=require('${PACKAGE}');require('${PACKAGE}/lib/Utils/logger.js');for(const k of ['initAuthCreds','makeCacheableSignalKeyStore','fetchLatestBaileysVersion'])if(typeof b[k]!=='function')throw Error('Contrato Baileys ausente');if(typeof b.default!=='function'||!b.proto||!b.BufferJSON||!b.DisconnectReason)throw Error('Exports incompatíveis');let p=path.dirname(require.resolve('${PACKAGE}'));while(!fs.existsSync(path.join(p,'package.json')))p=path.dirname(p);const pkg=JSON.parse(fs.readFileSync(path.join(p,'package.json')));console.log(JSON.stringify({version:pkg.version,node:process.versions.node}));`;
const AUTH_PROBE=`(async()=>{const fs=require('fs/promises'),os=require('os'),path=require('path');const p=await fs.mkdtemp(path.join(os.tmpdir(),'amanda-baileys-'));const{useSQLiteAuthState}=require('./dist/helpers/baileysSQLiteAuthState');let a=await useSQLiteAuthState(p);const id=a.state.creds.registrationId;await a.state.keys.set({'session':{'test':Buffer.from('fixture')}});await a.saveCreds();await a.close();a=await useSQLiteAuthState(p);if(a.state.creds.registrationId!==id||!(await a.state.keys.get('session',['test'])).test.equals(Buffer.from('fixture')))throw Error('Persistência incompatível');await a.close();await fs.rm(p,{recursive:true});})().catch(()=>process.exit(1));`;
class Baileys{
 constructor(manager){this.m=manager;this.journal=path.join(manager.private,'baileys-update.json');}
 record(){return fs.existsSync(this.journal)?JSON.parse(fs.readFileSync(this.journal,'utf8')):null;}
 saveRecord(record){const temp=this.journal+'.tmp';this.m.write(temp,record);fs.renameSync(temp,this.journal);}
 async ready(){await new(require('./operations.cjs').Operations)(this.m).ready();}
 async inspect({available=true}={}){
  const m=this.m;await this.ready();const dir=path.join(m.state.platform,'backend'),manifest=JSON.parse(fs.readFileSync(path.join(dir,'package.json'))),lock=JSON.parse(fs.readFileSync(path.join(dir,'package-lock.json'))),dep=dependency(manifest,lock),config=await m.configuration();
  let runtime=null;try{runtime=JSON.parse((await m.compose(['exec','-T','backend','node','-e',PROBE],{quiet:true,label:'Identificando Baileys carregado no backend'})).stdout);}catch{}
  let versions=null;if(available&&dep.supported)try{const value=JSON.parse((await m.docker(['run','--rm','node:22-bookworm','npm','view',PACKAGE,'versions','--json','--registry='+REGISTRY],{quiet:true,label:'Consultando versões públicas do Baileys'})).stdout);versions=(Array.isArray(value)?value:[value]).filter(fixed).sort((a,b)=>a.localeCompare(b,undefined,{numeric:true}));}catch{}
  return {...dep,configured:fixed(dep.configured)?dep.configured:'Origem local/fork (especificação omitida)',runtime,versions,compatible:versions?.filter(v=>newer(dep.configured,v))||[],container:config.services.backend.container_name||'Não verificado',image:config.services.backend.image};
 }
 async logs(){await this.ready();return this.m.compose(['logs','--no-color','--tail','150','backend'],{label:'Logs protegidos do backend'});}
 async update(target,confirmation){
  const m=this.m;await this.ready();if(confirmation!=='ATUALIZAR BAILEYS '+m.state.project)throw Error('Confirmação incorreta; nenhuma alteração.');
  const pending=this.record();if(pending&&!['complete','rolled-back'].includes(pending.phase))throw Error('Atualização interrompida; use rollback Baileys antes de continuar.');
  const info=await this.inspect();
  if(!info.supported)throw Error('Fork, dependência local, patch ou resolução não suportada; exige revisão técnica.');
  if(!info.runtime||info.runtime.version!==info.configured||!/^22\./.test(info.runtime.node))throw Error('Versão carregada/Node difere do contrato ou contrato não validado.');
  if(!newer(info.configured,target)||!info.compatible.includes(target))throw Error('Selecione uma versão publicada mais recente da mesma linha major.minor. Mudanças de linha, prereleases e downgrades exigem migração.');
  try{await m.validateSource(true);}catch(error){
   // Somente os dois manifestos previamente gerenciados podem permanecer alterados.
   if(!error.message.startsWith('Há alterações locais')||pending?.phase!=='complete'||await m.revision()!==pending.revision)throw error;
   const names=(await m.git(['diff','--name-only','HEAD'],{quiet:true})).stdout.trim().split('\n');
   if(names.some(n=>!['backend/package.json','backend/package-lock.json'].includes(n)))throw error;
   for(const[f,v]of Object.entries(pending.updated))if(fs.readFileSync(path.join(pending.platform,'backend',f)).toString('base64')!==v)throw error;
  }
  await m.verifyHealth();
  const config=await m.configuration(),service=config.services.backend,build=service.build,platform=m.state.platform;
  if(!build||path.resolve(build.context)!==path.resolve(platform)||build.dockerfile!=='docker/backend.Dockerfile'||!service.healthcheck||!service.image||service.image.includes('@')||service.image.startsWith('sha256:'))throw Error('Contrato de build/saúde do backend não suportado.');
  const dockerfile=fs.readFileSync(path.join(platform,build.dockerfile),'utf8');
  if(!/FROM node:22-bookworm AS build/.test(dockerfile)||!dockerfile.includes('npm ci'))throw Error('Imagem Node/build requer revisão de compatibilidade.');
  const dir=path.join(platform,'backend'),manifest=JSON.parse(fs.readFileSync(path.join(dir,'package.json'))),lock=JSON.parse(fs.readFileSync(path.join(dir,'package-lock.json')));
  if(manifest.overrides||manifest.scripts?.postinstall||manifest.scripts?.preinstall||manifest.dependencies?.['patch-package']||manifest.devDependencies?.['patch-package']||fs.existsSync(path.join(dir,'patches')))throw Error('Patches/scripts locais exigem revisão de compatibilidade.');
  const history=path.join(m.private,'baileys',crypto.randomUUID());fs.mkdirSync(history,{recursive:true,mode:0o700});
  for(const file of ['package.json','package-lock.json']){const bytes=fs.readFileSync(path.join(dir,file),'utf8');m.write(path.join(history,'original',file),bytes);m.write(path.join(history,file),bytes);}
  // NPM vê apenas manifestos e a política pública de peers; nenhum segredo de runtime.
  m.write(path.join(history,'.npmrc'),'legacy-peer-deps=true\n');
  await m.docker(['run','--rm','--mount',`type=bind,source=${history},target=/work`,'-w','/work','-e','GIT_CONFIG_COUNT=2','-e','GIT_CONFIG_KEY_0=url.https://github.com/.insteadOf','-e','GIT_CONFIG_VALUE_0=ssh://git@github.com/','-e','GIT_CONFIG_KEY_1=url.https://github.com/.insteadOf','-e','GIT_CONFIG_VALUE_1=git@github.com:','-e','GIT_TERMINAL_PROMPT=0','node:22-bookworm','npm','install',PACKAGE+'@'+target,'--save-exact','--package-lock-only','--ignore-scripts','--engine-strict','--no-audit','--no-fund','--registry='+REGISTRY],{label:'Preparando lockfile Baileys em container isolado'});
  const nextManifest=JSON.parse(fs.readFileSync(path.join(history,'package.json'))),nextLock=JSON.parse(fs.readFileSync(path.join(history,'package-lock.json')));lockDelta(lock,nextLock,manifest,nextManifest,target);
  const id=(await m.compose(['ps','-a','-q','backend'],{quiet:true})).stdout.trim();if(!/^[a-f0-9]{12,64}$/.test(id))throw Error('Container backend não identificado.');
  const oldImage=(await m.docker(['inspect','--format','{{.Image}}',id],{quiet:true})).stdout.trim();if(!/^sha256:[a-f0-9]{64}$/.test(oldImage))throw Error('Imagem anterior não identificada.');
  const rollbackTag=m.state.project+'-backend:baileys-'+path.basename(history);await m.docker(['image','tag',oldImage,rollbackTag],{label:'Preservando imagem anterior do backend'});
  const original={};for(const file of ['package.json','package-lock.json']){const src=path.join(dir,file),stat=fs.statSync(src);original[file]={bytes:fs.readFileSync(src).toString('base64'),uid:stat.uid,gid:stat.gid,mode:stat.mode&0o777};}
  const updated=Object.fromEntries(['package.json','package-lock.json'].map(f=>[f,fs.readFileSync(path.join(history,f)).toString('base64')]));
  const record={phase:'preparing',project:m.state.project,platform,revision:await m.revision(),previous:info.runtime.version,target,history,oldImage,rollbackTag,image:service.image,container:info.container,original,updated};this.saveRecord(record);
  try{
   this.writeManifests(record,Object.fromEntries(['package.json','package-lock.json'].map(f=>[f,fs.readFileSync(path.join(history,f))])));
   await m.compose(['build','--pull','backend'],{label:'Compilando apenas backend com npm ci e TypeScript'});
   const probe=JSON.parse((await m.docker(['run','--rm','--network','none','--entrypoint','node',service.image,'-e',PROBE],{quiet:true,label:'Validando imports Baileys na nova imagem'})).stdout);if(probe.version!==target)throw Error('Imagem não contém a versão selecionada.');
   await m.docker(['run','--rm','--network','none','--entrypoint','node',service.image,'-e',AUTH_PROBE],{label:'Validando persistência SQLite com sessão sintética isolada'});
   record.phase='backup';this.saveRecord(record);record.backup=await m.backup({scope:'backend',restart:false});record.phase='applying';this.saveRecord(record);
   await this.startBackend();
   const final=JSON.parse((await m.compose(['exec','-T','backend','node','-e',PROBE],{quiet:true})).stdout);if(final.version!==target)throw Error('Versão efetivamente carregada inesperada.');
   const logs=await m.compose(['logs','--no-color','--since','2m','--tail','100','backend'],{quiet:true,label:'Verificando erros de inicialização do backend'});
   if(/ERR_REQUIRE_ESM|Cannot find module|SyntaxError|UnhandledPromiseRejection|uncaughtException|FATAL/.test(logs.stdout+'\n'+logs.stderr))throw Error('Logs indicam falha de inicialização/compatibilidade do backend.');
   const image=(await m.docker(['image','inspect','--format','{{.Id}}',service.image],{quiet:true})).stdout.trim();
   if(!/^sha256:[a-f0-9]{64}$/.test(image))throw Error('Identificador da nova imagem não verificado.');
   const finalId=(await m.compose(['ps','-a','-q','backend'],{quiet:true})).stdout.trim();if(!/^[a-f0-9]{12,64}$/.test(finalId)||(await m.docker(['inspect','--format','{{.Image}}',finalId],{quiet:true})).stdout.trim()!==image)throw Error('Container não utiliza a imagem validada.');
   record.phase='complete';record.newImage=image;this.saveRecord(record);
   m.runner.emit(`BAILEYS — ATUALIZAÇÃO TÉCNICA CONCLUÍDA\nEmpresa: ${m.state.project}\nBiblioteca: ${PACKAGE}\nVersão anterior: ${info.runtime.version}\nVersão atual carregada: ${final.version}\nImagem backend: ${image}\nContainer: ${info.container}\nSaúde do backend: aprovada pelo healthcheck\nTeste de conexões WhatsApp: PENDENTE (conexão, reconexão, eventos e mensagens reais)\nBackup: ${record.backup}\nRollback: disponível no menu Baileys\nResultado: homologação WhatsApp pendente; revisar logs.\n`);
   return record;
  }catch(error){try{await this.rollbackRecord(record);}catch{throw Error('Falha na atualização e no rollback; preserve '+this.journal+' e use rollback Baileys.');}throw Error('Atualização falhou; manifestos e imagem anteriores restaurados. '+error.message);}
 }
 writeManifests(record,values){for(const[file,bytes]of Object.entries(values)){const dest=path.join(record.platform,'backend',file),temp=dest+'.baileys-'+crypto.randomUUID();try{fs.writeFileSync(temp,bytes,{mode:0o600,flag:'wx'});const meta=record.original[file];fs.chownSync(temp,meta.uid,meta.gid);fs.chmodSync(temp,meta.mode);fs.renameSync(temp,dest);}finally{if(fs.existsSync(temp))fs.unlinkSync(temp);}}}
 async startBackend(){await this.m.compose(['up','-d','--no-deps','--no-build','--pull','never','--force-recreate','--wait','--wait-timeout','300','backend'],{label:'Aplicando somente backend e aguardando healthcheck'});}
 async rollbackRecord(record){
  const m=this.m,restart=record.phase!=='preparing';
  for(const[f,v]of Object.entries(record.original)){const current=fs.readFileSync(path.join(record.platform,'backend',f)).toString('base64');if(current!==v.bytes&&current!==record.updated[f])throw Error('Manifestos alterados após a operação; preserve e revise antes do rollback.');}
  record.phase='rollback-required';this.saveRecord(record);
  this.writeManifests(record,Object.fromEntries(Object.entries(record.original).map(([f,v])=>[f,Buffer.from(v.bytes,'base64')])));
  await m.docker(['image','tag',record.oldImage,record.image],{label:'Restaurando imagem anterior do backend'});if(restart)await this.startBackend();
  const previous=JSON.parse((await m.compose(['exec','-T','backend','node','-e',PROBE],{quiet:true})).stdout);if(previous.version!==record.previous)throw Error('Rollback não confirmou a versão anterior.');record.phase='rolled-back';this.saveRecord(record);m.runner.emit('Rollback Baileys aprovado; dados e sessões preservados.\n');
 }
 async rollback(confirmation){await this.ready();const r=this.record();if(!r||r.project!==this.m.state.project||r.platform!==this.m.state.platform||confirmation!=='REVERTER BAILEYS '+r.project)throw Error('Rollback ausente ou confirmação incorreta.');if(await this.m.revision()!==r.revision)throw Error('Revisão mudou; rollback exige revisão técnica.');return this.rollbackRecord(r);}
}
module.exports={Baileys,PACKAGE,dependency,lockDelta,sameLine,newer,PROBE,AUTH_PROBE};
