const fs=require('node:fs'),path=require('node:path');
const {execFileSync}=require('node:child_process');
const BASE='/home/deploy';
const {inspectDirectory,conflict}=require('./directory-state.cjs');
function companyDirectory(project){if(typeof project!=='string'||!/^[a-z0-9][a-z0-9_]{0,39}$/.test(project))throw Error('Identificador de empresa inválido.');return BASE+'/'+project;}
function account(passwd){const row=passwd.split('\n').find(l=>l.startsWith('deploy:'));if(!row)return null;const fields=row.split(':'),uid=Number(fields[2]),gid=Number(fields[3]);if(!Number.isInteger(uid)||uid<=0||!Number.isInteger(gid)||gid<0)throw Error('Conta deploy sem identidade segura.');return {uid,gid};}
function hostOwner(){return account(fs.readFileSync(fs.existsSync('/run/amanda-host-passwd')?'/run/amanda-host-passwd':'/etc/passwd','utf8'));}
function inspectInstallation(root,project){return inspectDirectory(root,{project,owner:hostOwner()});}
function assertDirectory(dir){const st=fs.lstatSync(dir);if(!st.isDirectory()||st.isSymbolicLink()||fs.realpathSync(dir)!==dir)throw Error('Diretório deploy não pode ser link simbólico.');}
function provision(project,{host='/host',run=execFileSync}={}){
 const target=host+companyDirectory(project),base=host+BASE,passwd=host+'/etc/passwd';
 assertDirectory(base);
 let owner=account(fs.readFileSync(passwd,'utf8'));const info=inspectDirectory(target,{project,owner,logicalRoot:companyDirectory(project)});
 if(info.kind==='unknown')throw Error('Diretório da empresa já contém arquivos: '+conflict(info));
 if(!['absent','empty','temporary'].includes(info.kind))throw Error(`Instalação AMANDA ${info.kind==='complete'?'concluída':'não concluída'} em ${companyDirectory(project)}; etapa: ${info.phase}. Use o reconhecimento inicial para gerenciar ou retomar.`);
 const created=!owner;
 if(!owner){try{run('useradd',['--prefix',host,'--system','--user-group','--home-dir',BASE,'--shell','/usr/sbin/nologin','deploy'],{stdio:'pipe'});}catch(e){if(e.status!==9||!account(fs.readFileSync(passwd,'utf8')))throw Error('Não foi possível criar a conta deploy. Verifique permissões e cadastro de usuários.');}owner=account(fs.readFileSync(passwd,'utf8'));}
 fs.mkdirSync(target,{recursive:true,mode:0o700});if(created){fs.chownSync(base,owner.uid,owner.gid);fs.chmodSync(base,0o711);}fs.chownSync(target,owner.uid,owner.gid);fs.chmodSync(target,0o700);
 return owner;
}
function ownership(manager){
 const owner=manager.deploymentOwner||manager.state?.deploymentOwner;if(!owner)return;
 if(manager.root!==companyDirectory(path.basename(manager.root))||!Number.isInteger(owner.uid)||owner.uid<=0||!Number.isInteger(owner.gid)||owner.gid<0)throw Error('Escopo de propriedade deploy inválido.');
 assertDirectory(manager.root);
 // Inventariar primeiro; links são tratados com lchown, nunca percorridos.
 const entries=[];function walk(file){const st=fs.lstatSync(file);if(st.isFile()&&st.nlink>1&&(st.uid!==owner.uid||st.gid!==owner.gid))throw Error('Arquivo com hardlinks exige revisão antes de alterar propriedade.');entries.push([file,st]);if(st.isDirectory()&&!st.isSymbolicLink())for(const name of fs.readdirSync(file))walk(path.join(file,name));}walk(manager.root);
 for(const[file,st]of entries){const current=fs.lstatSync(file);if(current.ino!==st.ino||current.dev!==st.dev)throw Error('Árvore alterada durante ajuste de propriedade.');if(current.uid!==owner.uid||current.gid!==owner.gid)fs.lchownSync(file,owner.uid,owner.gid);const parts=path.relative(manager.root,file).split(path.sep),privatePath=file===manager.root||parts.includes('.amanda-installer')||parts.includes('.secrets')||/^\.env(?:$|\.(?:backend|oficial)$)/.test(path.basename(file));if(privatePath&&!current.isSymbolicLink()){const mode=current.isDirectory()?0o700:0o600;if((current.mode&0o777)!==mode)fs.chmodSync(file,mode);}}
}
async function installationManager(manager,config){
 if(process.env.AMANDA_DEPLOY_LAYOUT!=='1')return manager;
 const target=companyDirectory(config.project);
 const result=await manager.docker(['run','--rm','--name',config.project+'_provision_'+require('node:crypto').randomUUID(),'--network','none','--read-only','--tmpfs','/tmp','--mount','type=bind,source=/etc,target=/host/etc','--mount','type=bind,source='+BASE+',target=/host'+BASE,'--entrypoint','node',process.env.AMANDA_MANAGER_IMAGE||'amanda-installer:local','/opt/amanda-installer/deploy.cjs','--provision',config.project],{quiet:true,label:'Preparando conta deploy e diretório exclusivo'});
 const owner=JSON.parse(result.stdout);if(!Number.isInteger(owner.uid)||owner.uid<=0||!Number.isInteger(owner.gid)||owner.gid<0)throw Error('Identidade deploy inválida.');
 const {Manager}=require('./manager.cjs'),nested=new Manager(target);nested.deploymentOwner=owner;return nested;
}
async function install(manager,config){
 const c=require('./manager.cjs').normalizeConfig(config),root=process.env.AMANDA_DEPLOY_LAYOUT==='1'?companyDirectory(c.project):manager.root,info=inspectInstallation(root,c.project);
 if(info.kind==='unknown')throw Error(conflict(info));
 if(!['absent','empty','temporary'].includes(info.kind))throw Error(`Instalação AMANDA já registrada em ${root}; use resume ou gerenciamento, sem novo provisionamento.`);
 const target=await installationManager(manager,c),pending=info.savedConfig||c;
 await target.lock(async()=>{
   const current=inspectInstallation(target.root,c.project);if(current.kind==='unknown')throw Error(conflict(current));
   if(!['empty','temporary'].includes(current.kind))throw Error('Estado alterado durante a instalação; use o reconhecimento inicial.');
   if(current.savedConfig&&JSON.stringify(current.savedConfig)!==JSON.stringify(pending))throw Error('Configuração salva mudou; consulte novamente o diagnóstico.');
   if(!current.savedConfig)target.write(path.join(target.private,'setup.json'),require('./directory-state.cjs').setupRecord(target.root,pending));
   await target.doctor();await target.prepare(pending);await target.build();await target.initialize();
 });return target;
}
async function startInstallation(manager,{question,collect,config,directory=manager.root,automatic=process.env.AMANDA_DEPLOY_LAYOUT==='1',out=console.log,manage,inspect=inspectInstallation,installNew=install}={}){
 const {Manager,normalizeConfig,SOURCE}=require('./manager.cjs');
 let project=config?normalizeConfig(config).project:null;
 if(!project&&fs.existsSync(manager.stateFile)&&!automatic){try{project=JSON.parse(fs.readFileSync(manager.stateFile,'utf8')).project;}catch{throw Error(conflict({root:manager.root,reason:'Estado JSON inválido.'}));}}
 if(!project){const value=await question('Nome técnico da empresa','amanda');if(value==null||[':cancelar',':sair','0'].includes(value))return manager;project=normalizeConfig({sourceUrl:SOURCE,project:value||'amanda'}).project;}
 const root=automatic?companyDirectory(project):typeof directory==='function'?directory({project}):directory;
 const info=inspect(root,project);
 if(info.kind==='unknown')throw Error(conflict(info));
 out(`Empresa: ${project}\nDiretório: ${root}`);
 if(['partial','complete'].includes(info.kind)){
   const target=root===manager.root?manager:new Manager(root);
   const resume=()=>target.lock(async()=>{const current=inspect(root,project);if(current.kind==='unknown')throw Error(conflict(current));if(current.kind!=='partial')throw Error('O estado mudou durante a seleção; consulte novamente o diagnóstico.');await target.execute('resume');return target;});
   out(info.kind==='partial'?`Foi encontrada uma instalação AMANDA não concluída.\nÚltima etapa registrada: ${info.phase}`:'Foi encontrada uma instalação AMANDA concluída. Nenhuma nova instalação será executada.');
   if(info.kind==='complete'&&config){out('Use menu, status ou update com --dir '+root+'.');return target;}
   if(config)return resume();
   while(true){
     out(info.kind==='partial'?'[1] Retomar instalação\n[2] Consultar diagnóstico\n[0] Voltar':'[1] Gerenciar ou atualizar instalação\n[2] Consultar diagnóstico\n'+(automatic?'[3] Escolher outra empresa\n':'')+'[0] Voltar');
     const choice=await question('Selecione a opção','0');if(choice==null||choice==='0')return manager;
     if(choice==='2'){out(`Diretório: ${root}\nEstado: ${info.kind}\nEtapa registrada: ${info.phase}\nSeed iniciado: ${info.state.seedAttempted?'sim':'não'}\nSeed concluído: ${info.state.seedSucceeded?'sim':'não'}\nNenhum arquivo foi alterado pelo diagnóstico.`);continue;}
     if(choice==='3'&&info.kind==='complete'&&automatic)return startInstallation(manager,{question,collect,directory,automatic,out,manage,inspect,installNew});
     if(choice!=='1')throw Error('Opção inválida.');
     if(info.kind==='partial')return resume();
     if(manage)await manage(target);else out('Use menu ou update com --dir '+root+'.');return target;
   }
 }
 if(info.savedConfig)out('Configuração salva validada; as perguntas não serão repetidas.');
 const input=info.savedConfig||config||await collect({project,directory:root});
 if(input.project!==project)throw Error('Empresa difere do diretório verificado.');
 const target=root===manager.root?manager:new Manager(root);
 return installNew(target,input);
}
async function migrationPlan(manager){
 await manager.doctor();manager.load();await manager.validateSource();const config=await manager.configuration();
 const containers=(await manager.compose(['ps','--all','--format','json'],{quiet:true})).stdout;
 let backupVerified=false;if(manager.state.lastBackup){await new(require('./operations.cjs').Operations)(manager).checkBackup(manager.state.lastBackup);backupVerified=true;}
 return {source:manager.root,destination:companyDirectory(manager.state.project),backupVerified,backup:manager.state.lastBackup||null,volumes:Object.values(config.volumes||{}).map(v=>v.name),bindMounts:Object.entries(config.services).flatMap(([service,s])=>(s.volumes||[]).filter(v=>v.type==='bind').map(v=>({service,source:v.source,target:v.target}))),containers:containers.split('\n').filter(Boolean).map(line=>{const c=JSON.parse(line);return {service:c.Service,state:c.State};}),automaticMigration:false,next:'Preserve a origem. Exija backup verificado e autorização para copiar, ajustar caminhos/propriedade e validar antes de trocar os agendamentos.'};
}
if(require.main===module){try{if(process.argv[2]!=='--provision')throw Error('Operação inválida.');process.stdout.write(JSON.stringify(provision(process.argv[3])));}catch(e){console.error(e.message);process.exitCode=1;}}
module.exports={BASE,companyDirectory,account,hostOwner,inspectInstallation,provision,ownership,installationManager,install,startInstallation,migrationPlan};
