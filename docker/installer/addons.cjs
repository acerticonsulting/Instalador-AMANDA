const fs=require('node:fs');const path=require('node:path');
const {writeEnv}=require('./options.cjs');
// External components must supply their own Docker contract, never a host installer.
class Addons{
  constructor(manager){this.m=manager;}
  async deploy(kind,{sourceUrl,token='',composeFile='docker-compose.yml',environment={}}={},update=false){
    if(!['voz','hub','goflow'].includes(kind))throw Error('Componente inválido.');
    const m=this.m,dir=path.join(m.root,'addons',kind),record=path.join(m.private,'addon-'+kind+'.json'),tokenFile=path.join(m.private,'addon-'+kind+'-source-token');
    const previous=fs.existsSync(record)?JSON.parse(fs.readFileSync(record,'utf8')):null;
    if(update){if(!previous)throw Error('Componente ainda não instalado. Use Instalar e forneça a fonte Docker.');({sourceUrl,composeFile}=previous);}
    if(!/^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(?:\.git)?$/.test(sourceUrl||''))throw Error('Informe o repositório GitHub HTTPS autorizado do componente, sem credenciais no link.');
    if(!/^[A-Za-z0-9_./-]+\.ya?ml$/.test(composeFile)||path.isAbsolute(composeFile)||composeFile.split('/').includes('..'))throw Error('Arquivo Compose inválido.');
    if(typeof token!=='string'||/[\r\n\0]/.test(token))throw Error('Token inválido.');
    if(token){m.runner.secret(token);m.write(tokenFile,token);}else if(fs.existsSync(tokenFile))m.runner.secret(fs.readFileSync(tokenFile,'utf8'));
    const env={GIT_TERMINAL_PROMPT:'0',GIT_ASKPASS:path.join(__dirname,'source-askpass.cjs'),AMANDA_SOURCE_TOKEN_FILE:tokenFile};
    if(!fs.existsSync(dir)){if(update)throw Error('Código do componente ausente.');await m.runner.run('git',['-c','credential.helper=','clone','--branch','main','--single-branch',sourceUrl,dir],{env,label:'Obtendo fonte Docker de '+kind});}
    const git=(args,opts={})=>m.runner.run('git',['-c','safe.directory='+dir,...args],{cwd:dir,quiet:true,...opts});
    if((await git(['remote','get-url','origin'])).stdout.trim()!==sourceUrl)throw Error('Origem do componente difere do registro.');
    if((await git(['status','--porcelain','--untracked-files=no'])).stdout.trim())throw Error('Código do componente possui mudanças locais.');
    const old=(await git(['rev-parse','HEAD'])).stdout.trim();
    const pending=previous?.phase==='starting',images={};
    if(pending&&old!==previous.revision)throw Error('Retome a revisão registrada do componente antes de atualizar.');
    if(previous&&!pending){await m.backup();Object.assign(images,await m.imageIds());}
    if(!pending&&(update||!previous)){await git(['-c','credential.helper=','fetch','origin','main'],{env});await git(['merge-base','--is-ancestor','HEAD','origin/main']);await git(['merge','--ff-only','origin/main']);}
    const file=path.join(dir,composeFile);if(!fs.existsSync(file))throw Error('Fonte obtida sem '+composeFile+'. É necessário o Compose mantido pelo fornecedor; nenhuma instalação foi declarada concluída.');
    const project=m.state.project+'_'+kind,envFile=path.join(m.private,'addon-'+kind+'.env');
    if(!update){for(const v of Object.values(environment))m.runner.secret(v);writeEnv(envFile,{...environment,AMANDA_NETWORK:m.state.project+'_default'});}
    const base=['compose','--project-directory',dir,'--env-file',envFile,'-p',project,'-f',file];
    const config=JSON.parse((await m.docker([...base,'config','--format','json'],{quiet:true})).stdout);
    for(const service of Object.values(config.services||{})){
      for(const[k,v]of Object.entries(service.environment||{}))if(/KEY|TOKEN|SECRET|PASS/.test(k))m.runner.secret(v);
      if(service.privileged||service.cap_add?.length||service.network_mode||service.pid||service.devices?.length)throw Error('Contrato Docker do componente exige privilégios não suportados.');
      if(service.build){const context=path.resolve(service.build.context||dir);if(context!==dir&&!context.startsWith(dir+path.sep))throw Error('Contexto de build fora da pasta do componente recusado.');}
      for(const v of service.volumes||[])if(v.type==='bind'&&!path.resolve(v.source).startsWith(dir+path.sep))throw Error('Bind mount externo à pasta do componente recusado.');
      if(!service.healthcheck||service.healthcheck.disable)throw Error('Componente deve declarar healthcheck para cada serviço.');
    }
    if(!Object.keys(config.services||{}).length)throw Error('Compose sem serviços.');
    for(const v of Object.values(config.volumes||{}))if(v.external||!v.name?.startsWith(project+'_'))throw Error('Volume do componente não está isolado.');
    if(!Object.values(config.networks||{}).some(n=>n.external&&n.name===m.state.project+'_default'))throw Error('Compose do componente deve usar rede externa ${AMANDA_NETWORK} da AMANDA.');
    for(const n of Object.values(config.networks||{}))if(n.external?n.name!==m.state.project+'_default':!n.name?.startsWith(project+'_'))throw Error('Rede de componente fora da instância.');
    if(!previous)await m.backup();
    try{await m.docker([...base,'build'],{cwd:dir,label:'Build em Docker: '+kind});}
    catch(error){await m.restoreTags(images);await git(['checkout','--detach',old]);throw error;}
    // A failed startup may have applied the supplier's migrations: keep its revision,
    // rather than pretending a source checkout alone rolls the database back.
    const candidate={sourceUrl,composeFile,project,dir,revision:(await git(['rev-parse','HEAD'])).stdout.trim(),phase:'starting',preDeploymentBackup:m.state.lastBackup};m.write(record,candidate);
    await m.docker([...base,'up','-d','--wait','--wait-timeout','300'],{cwd:dir,label:'Validando serviços Docker: '+kind});
    m.write(record,{...candidate,phase:'ready'});m.runner.emit('Componente '+kind+' saudável. Configure sua URL/chave de integração com a plataforma.\n');
  }
}
module.exports={Addons};
