const fs=require('node:fs'),path=require('node:path');
const {execFileSync}=require('node:child_process');
const BASE='/home/deploy';
function companyDirectory(project){if(typeof project!=='string'||!/^[a-z0-9][a-z0-9_]{0,39}$/.test(project))throw Error('Identificador de empresa inválido.');return BASE+'/'+project;}
function account(passwd){const row=passwd.split('\n').find(l=>l.startsWith('deploy:'));if(!row)return null;const fields=row.split(':'),uid=Number(fields[2]),gid=Number(fields[3]);if(!Number.isInteger(uid)||uid<=0||!Number.isInteger(gid)||gid<0)throw Error('Conta deploy sem identidade segura.');return {uid,gid};}
function assertDirectory(dir){const st=fs.lstatSync(dir);if(!st.isDirectory()||st.isSymbolicLink()||fs.realpathSync(dir)!==dir)throw Error('Diretório deploy não pode ser link simbólico.');}
function provision(project,{host='/host',run=execFileSync}={}){
 const target=host+companyDirectory(project),base=host+BASE,passwd=host+'/etc/passwd';
 assertDirectory(base);
 if(fs.existsSync(target)){assertDirectory(target);const entries=fs.readdirSync(target);if(entries.some(n=>n!=='.amanda-installer')||fs.existsSync(path.join(target,'.amanda-installer/state.json')))throw Error('Diretório da empresa já contém arquivos. Use --dir e resume/adopt; migração exige autorização.');if(entries.length)assertDirectory(path.join(target,'.amanda-installer'));}
 let owner=account(fs.readFileSync(passwd,'utf8'));const created=!owner;
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
async function install(manager,config){const target=await installationManager(manager,config);await target.lock(async()=>{await target.doctor();await target.prepare(config);await target.build();await target.initialize();});return target;}
async function migrationPlan(manager){
 await manager.doctor();manager.load();await manager.validateSource();const config=await manager.configuration();
 const containers=(await manager.compose(['ps','--all','--format','json'],{quiet:true})).stdout;
 let backupVerified=false;if(manager.state.lastBackup){await new(require('./operations.cjs').Operations)(manager).checkBackup(manager.state.lastBackup);backupVerified=true;}
 return {source:manager.root,destination:companyDirectory(manager.state.project),backupVerified,backup:manager.state.lastBackup||null,volumes:Object.values(config.volumes||{}).map(v=>v.name),bindMounts:Object.entries(config.services).flatMap(([service,s])=>(s.volumes||[]).filter(v=>v.type==='bind').map(v=>({service,source:v.source,target:v.target}))),containers:containers.split('\n').filter(Boolean).map(line=>{const c=JSON.parse(line);return {service:c.Service,state:c.State};}),automaticMigration:false,next:'Preserve a origem. Exija backup verificado e autorização para copiar, ajustar caminhos/propriedade e validar antes de trocar os agendamentos.'};
}
if(require.main===module){try{if(process.argv[2]!=='--provision')throw Error('Operação inválida.');process.stdout.write(JSON.stringify(provision(process.argv[3])));}catch(e){console.error(e.message);process.exitCode=1;}}
module.exports={BASE,companyDirectory,account,provision,ownership,installationManager,install,migrationPlan};
