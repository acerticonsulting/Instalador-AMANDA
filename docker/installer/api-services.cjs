const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {envValues}=require('./manager.cjs');
const {writeEnv,validateOptions}=require('./options.cjs');
const DEFINITIONS=Object.freeze({
  api_oficial:{label:'API Oficial',profile:'official',host:'OFICIAL_HOST',bind:'OFICIAL_BIND_ADDRESS',internal:'http://api_oficial:6000',integration:'URL_API_OFICIAL'},
  wuzapi:{label:'WhatsMeow/WuzAPI',profile:'whatsmeow',bind:'WUZAPI_BIND_ADDRESS',internal:'http://wuzapi:8080',integration:'WUZAPI_URL'},
});
function definition(service){const d=DEFINITIONS[service];if(!d)throw Error('API não suportada.');return d;}
function imageOverride(manager){
  const file=path.join(manager.private,'compose-api-image.json');if(!fs.existsSync(file))return[];
  if(fs.lstatSync(file).isSymbolicLink())throw Error('Override de imagem não pode ser link.');
  const data=JSON.parse(fs.readFileSync(file,'utf8'));
  if(Object.keys(data).join(',')!=='services'||Object.keys(data.services).join(',')!=='wuzapi'||Object.keys(data.services.wuzapi).join(',')!=='image'||!/^sha256:[a-f0-9]{64}$/.test(data.services.wuzapi.image))throw Error('Override de imagem WuzAPI inválido.');
  return['-f',file];
}
function renderApi(info){
  const fields=[['Empresa',info.company],['Projeto',info.project],['Diretório',info.directory],['Serviço / perfil',info.service+' / '+info.profile],['Instalado',info.installed?'Sim (container encontrado)':'Não; declaração Compose não comprova instalação'],['Perfil habilitado',info.enabled?'Sim':'Não'],['Estado / saúde',info.status],['Container',info.container||'Não encontrado'],['Imagem',info.image||'Não verificada'],['ID da imagem',info.imageId||'Não verificado'],['Uptime (segundos)',info.uptimeSeconds??'Não verificado'],['URL interna',info.internalUrl],['URL pública',info.publicUrl],['HTTPS',info.https?.status||'Não verificado'],['Última verificação HTTPS',info.https?.checkedAt||'Não realizada'],['DNS / URL proposta',info.pending||'Sem proposta pendente'],['Token administrativo',info.adminToken?'Configurado; preservado':'Não configurado'],['Banco / sessões',info.database],['Revisão',info.revision||'Não verificada'],['Backup',info.backup||'Não registrado']];
  return fields.map(([k,v])=>k+': '+v).concat(['Portas: '+(info.ports?.join('; ')||'Sem publicação confirmada'),'Volumes: '+(info.volumes?.map(v=>(v.name||v.type)+' → '+v.target).join('; ')||'Não verificados')]).join('\n');
}
function publicUrl(value){
  if(typeof value!=='string'||/[\s\x00-\x1f\x7f]/.test(value)||/https?:\/\/[^/]+:/.test(value))throw Error('Use domínio HTTPS sem porta, credencial ou caminho.');
  const url=/^[a-z][a-z0-9+.-]*:\/\//i.test(value)?value:'https://'+value;
  validateOptions({officialUrl:url});return new URL(url).origin;
}
function assertPublication(service,url,edge){
  definition(service);if(!url)return;
  publicUrl(url);
  if(!edge)throw Error('Publicação HTTPS exige Caddy existente. Selecione explicitamente o modo interno.');
  if(service==='wuzapi')throw Error('Publicação WuzAPI bloqueada: a imagem configurável não possui contrato validado de autenticação por rota e bloqueio administrativo. Use modo interno; nenhuma rota pública será criada.');
}
// Only recognized installation roots are inspected; never recurse into platform data.
function assertUnique(manager,url,service){
  if(!url)return;const hostname=new URL(url).hostname;
  const parent=path.dirname(manager.root),roots=new Set([manager.root]);
  for(const base of [parent,path.join(manager.root,'instances')])if(fs.existsSync(base))for(const name of fs.readdirSync(base)){
    if(!/^[a-z0-9][a-z0-9_-]{0,39}$/.test(name))continue;const root=path.join(base,name);
    if(!fs.lstatSync(root).isSymbolicLink()&&fs.existsSync(path.join(root,'.amanda-installer/state.json')))roots.add(root);
  }
  for(const root of roots){
    const state=root===manager.root?manager.state:JSON.parse(fs.readFileSync(path.join(root,'.amanda-installer/state.json'),'utf8'));
    const platform=path.resolve(state.platform||'');const realRoot=fs.realpathSync(root),realPlatform=fs.realpathSync(platform);
    if(realPlatform!==realRoot&&!realPlatform.startsWith(realRoot+path.sep))throw Error('Instalação vizinha com configuração fora do diretório; revise a propriedade antes de publicar.');
    const env=envValues(path.join(platform,'.env'));
    const values=[env.FRONTEND_URL,env.BACKEND_URL,...(root===manager.root&&service==='api_oficial'?[]:[env.OFICIAL_HOST&&'https://'+env.OFICIAL_HOST]),env.WUZAPI_HOST&&'https://'+env.WUZAPI_HOST];
    if(root!==manager.root)values.push(state.optionalOperation?.url);
    if(values.filter(Boolean).some(v=>new URL(v).hostname===hostname))throw Error('Domínio já utilizado por frontend, backend ou outra API/empresa.');
  }
}
class ApiServices{
  constructor(manager){this.m=manager;}
  async dns(url){
    const m=this.m,{probe,evaluate}=require('./domain-preflight.cjs');
    const report=await probe(m,{apiUrl:url},{existing:true}),verdict=evaluate(report);
    m.runner.emit('DNS da API: '+JSON.stringify(verdict)+'\n');
    if(!verdict.ok)throw Error('DNS/portas da API incompatíveis ou inconclusivos. Nenhuma configuração Caddy foi aplicada.');return verdict;
  }
  async plan(service,url=''){
    const m=this.m;definition(service);assertPublication(service,url,m.state.profiles.includes('edge'));
    const normalized=url?publicUrl(url):'';assertUnique(m,normalized,service);
    let dnsError;if(normalized)try{await this.dns(normalized);}catch(e){dnsError=e.message;}
    return{service,url:normalized,dnsValid:!dnsError,dnsError,mode:normalized?'public':'internal'};
  }
  async ready(pendingService){
    const m=this.m;m.load();
    if(pendingService&&m.state.initialized&&m.state.phase==='migration-update'&&m.state.optionalOperation?.stage==='https'&&m.state.optionalOperation.service===pendingService&&!m.state.optionalOperation.rollbackRequired){await m.doctor();await m.identifyManager();await m.validateSource();await m.configuration();return;}
    await new(require('./operations.cjs').Operations)(m).ready();
  }
  async install(service,confirmation,plan){
    await this.ready();const m=this.m,d=definition(service);
    if(confirmation!=='HABILITAR '+m.state.project+' '+service)throw Error('Confirmação de habilitação inválida.');
    if(m.services().includes(service))throw Error('Serviço já habilitado; use iniciar ou retomar.');
    const existingEnv=envValues(path.join(m.state.platform,'.env'));
    if(!existingEnv[service==='api_oficial'?'TOKEN_API_OFICIAL':'WUZAPI_ADMIN_TOKEN'])throw Error('Token administrativo ausente. Configure-o com segurança antes de habilitar a API; nenhuma chave existente será rotacionada.');
    if(!plan||plan.service!==service||!['internal','public'].includes(plan.mode))throw Error('Defina a URL própria ou confirme o modo interno antes de instalar a API.');
    plan=await this.plan(service,plan.url);
    if(!plan.dnsValid){m.save({...m.state,pendingApi:{service,url:plan.url,action:'install'}});m.runner.emit('Proposta pendente de DNS; API não instalada e Caddy preservado. Corrija a URL no menu da API ou use resume após corrigir DNS.\n');return{pending:true};}
    const previous=await m.configuration(),before=structuredClone(m.state),file=path.join(m.state.platform,'.env'),bytes=fs.readFileSync(file);
    const candidate={...before,profiles:[...before.profiles,d.profile]};let config;
    try{m.state=candidate;config=await m.configuration();await require('./preflight.cjs').assertPorts(m,config,previous);
      const name=config.services[service]?.container_name;if(name){const r=await m.docker(['inspect','--format','{{index .Config.Labels "com.docker.compose.project"}}',name],{quiet:true,allowFailure:true});if(!r.code&&r.stdout.trim()!==before.project)throw Error('Container pertence a outra empresa.');}
      for(const[key,v]of Object.entries(config.volumes))if(!previous.volumes[key]){const r=await m.docker(['volume','inspect','--format','{{json .Labels}}',v.name],{quiet:true,allowFailure:true});if(!r.code&&JSON.parse(r.stdout||'{}')?.['com.docker.compose.project']!==before.project)throw Error('Volume existente sem propriedade comprovada.');}
    }finally{m.state=before;}
    await m.compose(['--profile',d.profile,service==='api_oficial'?'build':'pull',service],{label:'Preparando somente '+d.label});
    m.runner.emit('Backup consistente poderá pausar temporariamente a plataforma; dados e sessões serão preservados.\n');
    const backup=await m.backup();
    const history=path.join(m.private,'config-history','api-'+crypto.randomUUID());m.write(path.join(history,'.env'),bytes.toString());m.write(path.join(history,'state.json'),before);
    // Persist recovery before changing environment or starting irreversible migrations.
    m.save({...m.state,phase:'migration-update',pendingRevision:await m.revision(),optionalOperation:{service,action:'install',url:plan.url,stage:'configure',history,backup,previous:before}});
    try{
      writeEnv(file,{COMPOSE_PROFILES:candidate.profiles.join(','),[d.bind]:'127.0.0.1',[d.integration]:d.internal,...(service==='api_oficial'?{USE_WHATSAPP_OFICIAL:'true',OFICIAL_HOST:plan.url?new URL(plan.url).hostname:''}:{})});
      m.save({...m.state,profiles:candidate.profiles,pendingApi:null});
      await this.finish();return{installed:true};
    }catch(error){
      if(!m.state.optionalOperation?.irreversible)await this.rollback(error);else m.runner.emit('API pendente: '+error.message+'. Use resume; nenhum seed será executado.\n');throw error;
    }
  }
  async rollback(cause){
    const m=this.m,op=m.state.optionalOperation;if(!op)throw cause;
    try{
      if(op.action==='install')await m.compose(['stop',op.service],{label:'Parando somente a API cuja aplicação falhou'});
      fs.writeFileSync(path.join(m.state.platform,'.env'),fs.readFileSync(path.join(op.history,'.env')),{mode:0o600});
      m.save({...op.previous,phase:'migration-update',optionalOperation:{...op,rollbackRequired:true}});
      const affected=op.action==='install'?['backend',...(op.url?['edge']:[])]:['edge'];
      if(affected.length)await m.compose(['up','-d','--no-deps','--wait','--wait-timeout','300',...affected]);
      m.save({...op.previous,lastBackup:op.backup||op.previous.lastBackup});
      m.runner.emit('Configuração anterior restaurada; volumes da API preservados.\n');
    }catch(recovery){m.save({...m.state,phase:'migration-update',optionalOperation:{...op,rollbackRequired:true}});throw new AggregateError([cause,recovery],'Falha ao aplicar API e ao restaurar configuração; preserve os recursos e consulte config-history.');}
  }
  async finish(){
    const m=this.m,op=m.state.optionalOperation,d=definition(op?.service);
    if(op.rollbackRequired)throw Error('Rollback pendente: diagnostique config-history antes de retomar.');
    if(await m.revision()!==m.state.pendingRevision)throw Error('Revisão difere da operação da API.');
    if(op.action==='update')return this.finishUpdate();
    if(op.url)await this.dns(op.url); // Before migrations, edge recreation or any ACME trigger.
    if(op.action==='install'&&op.stage!=='https'){
      if(op.stage==='configure'){
        const profiles=[...new Set([...m.state.profiles,d.profile])];
        writeEnv(path.join(m.state.platform,'.env'),{COMPOSE_PROFILES:profiles.join(','),[d.bind]:'127.0.0.1',[d.integration]:d.internal,...(op.service==='api_oficial'?{USE_WHATSAPP_OFICIAL:'true',OFICIAL_HOST:op.url?new URL(op.url).hostname:''}:{})});
        m.save({...m.state,profiles});
      }
      const effective=await m.configuration();
      if((effective.services[op.service].ports||[]).some(p=>!['127.0.0.1','::1'].includes(p.host_ip)))throw Error('Compose da plataforma não oferece bind interno seguro. Atualize a plataforma antes de instalar esta API.');
      if(op.service==='api_oficial'&&op.stage!=='https'){
        m.save({...m.state,optionalOperation:{...op,irreversible:true,stage:'migrations'}});
        await m.compose(['run','--rm','official-db-init'],{label:'Inicialização do banco da API Oficial'});
        await m.compose(['run','--rm','--no-deps','official-migrate'],{label:'Somente migrations Prisma da API Oficial'});
      }
      await m.compose(['up','-d','--no-deps','--wait','--wait-timeout','300',op.service,'backend'],{label:'Aplicando somente API e integração backend'});
    }
    if(op.url){
      // A domain transaction has no effect on frontend/backend configuration.
      writeEnv(path.join(m.state.platform,'.env'),{[d.host]:new URL(op.url).hostname});
      if(m.state.optionalOperation.stage!=='https')await m.compose(['up','-d','--no-deps','--wait','--wait-timeout','60','edge'],{label:'Aplicando domínio próprio no Caddy'});
      m.save({...m.state,optionalOperation:{...m.state.optionalOperation,stage:'https',irreversible:true}});
      await this.https(op.url);
    }
    if(op.action==='domain'&&!op.url&&d.host){writeEnv(path.join(m.state.platform,'.env'),{[d.host]:''});if(m.state.profiles.includes('edge'))await m.compose(['up','-d','--no-deps','--wait','edge']);}
    const checked=op.url?{url:op.url,status:'validated',checkedAt:new Date().toISOString()}:{status:'internal'};
    m.save({...m.state,phase:'ready',optionalOperation:null,pendingApi:null,apiHttps:{...m.state.apiHttps,[op.service]:checked}});
    m.runner.emit(d.label+': '+(op.action==='install'?'instalação concluída':'domínio aplicado')+'. '+(op.url?'HTTPS público validado.':'Modo interno; HTTPS público não configurado.')+' Nenhum seed executado.\n');
    if(op.service==='api_oficial'&&op.action==='install')await require('./completion.cjs').showOfficialApiCompletion(m,{action:'install',backup:op.backup,health:true,rebuilt:true,migrations:true});
    if(op.service==='wuzapi'&&op.action==='install')try{m.runner.emit(require('./ui.cjs').createUI().banner('WHATSMEOW / WUZAPI — INSTALAÇÃO CONCLUÍDA')+'\n'+renderApi(await this.inspect('wuzapi'))+'\nPareamento WhatsApp e webhooks externos: não homologados.\n');}catch{m.runner.emit('AVISO: resumo complementar WuzAPI indisponível. Consulte status; dados preservados.\n');}
  }
  async https(url){
    const m=this.m,{inspectHttps,awaitHttps}=require('./https-check.cjs');
    const timeout=Number(process.env.AMANDA_HTTPS_TIMEOUT_MS||120000);
    if(!Number.isFinite(timeout)||timeout<1000||timeout>600000)throw Error('AMANDA_HTTPS_TIMEOUT_MS deve estar entre 1000 e 600000.');
    await awaitHttps({timeoutMs:timeout,emit:s=>m.runner.emit(s),probe:async()=>JSON.parse((await m.compose(['exec','-T','backend','node','-e',`(${inspectHttps.toString()})(${JSON.stringify([{url,exact:false}])},{connectivity:true}).then(r=>console.log(JSON.stringify(r))).catch(()=>process.exit(1))`],{quiet:true})).stdout),caddy:async()=>(await m.compose(['logs','--no-color','--since','2m','--tail','100','edge'],{quiet:true,label:'Diagnosticando TLS da API sem reiniciar Caddy'})).stdout});
  }
  async domain(service,plan,confirmation){
    await this.ready(service);const m=this.m,d=definition(service);if(!m.services().includes(service))throw Error('Instale a API primeiro.');
    if(confirmation!=='DOMINIO '+m.state.project+' '+service)throw Error('Alteração cancelada.');
    plan=await this.plan(service,plan.url);
    if(!plan.dnsValid){m.save({...m.state,pendingApi:{service,url:plan.url,action:'domain'}});return{pending:true};}
    const previous={...structuredClone(m.state),phase:'ready',optionalOperation:null},history=path.join(m.private,'config-history','api-domain-'+crypto.randomUUID());
    m.write(path.join(history,'.env'),fs.readFileSync(path.join(m.state.platform,'.env'),'utf8'));m.write(path.join(history,'state.json'),previous);
    m.save({...m.state,phase:'migration-update',pendingRevision:await m.revision(),optionalOperation:{service,action:'domain',url:plan.url,history,previous}});
    try{return await this.finish();}catch(error){if(!m.state.optionalOperation.irreversible)await this.rollback(error);throw error;}
  }
  async inspect(service){
    const m=this.m,d=definition(service),{Dashboard}=require('./dashboard.cjs'),dashboard=new Dashboard(m),model=await dashboard.collect(),row=model.items.find(x=>x.key===service),env=envValues(path.join(m.state.platform,'.env'));
    return{company:m.state.companyName||m.state.project,project:m.state.project,directory:m.root,service,profile:d.profile,enabled:m.state.profiles.includes(d.profile),installed:Boolean(row?.container),...(row?dashboard.details(row):{status:'NÃO INSTALADO'}),internalUrl:d.internal,publicUrl:d.host&&env[d.host]?'https://'+env[d.host]:'Não configurada',https:m.state.apiHttps?.[service]||{status:'Não verificado nesta operação'},pending:m.state.pendingApi?.service===service?m.state.pendingApi.url:undefined,adminToken:Boolean(env[service==='api_oficial'?'TOKEN_API_OFICIAL':'WUZAPI_ADMIN_TOKEN']),revision:m.state.revision,backup:m.state.lastBackup||'Não registrado',database:service==='api_oficial'?'api_oficial (PostgreSQL)':'SQLite no volume wuzapi_data; sessões preservadas'};
  }
  async updateWuzapi(confirmation){
    await this.ready();const m=this.m; if(!m.services().includes('wuzapi'))throw Error('WuzAPI não habilitada.');
    if(confirmation!=='ATUALIZAR '+m.state.project+' wuzapi')throw Error('Atualização cancelada.');
    const before=await this.inspect('wuzapi');if(!before.installed)throw Error('Container ausente. Use instalar/iniciar; atualização não será simulada.');
    if(!/^sha256:[a-f0-9]{64}$/.test(before.imageId))throw Error('Imagem anterior não confirmada; atualização recusada.');
    const supplier=JSON.parse((await m.compose(['config','--format','json'],{quiet:true,supplierImages:true})).stdout).services.wuzapi.image;
    if(typeof supplier!=='string'||!supplier||supplier.startsWith('-'))throw Error('Imagem WuzAPI inválida.');
    // Backup restarts the previous services. Pin the running image before pulling
    // a mutable supplier tag, so that restart cannot apply the update prematurely.
    m.write(path.join(m.private,'compose-api-image.json'),{services:{wuzapi:{image:before.imageId}}});
    await m.docker(['pull',supplier],{label:'Obtendo somente imagem WuzAPI indicada pelo Compose'});
    const target=(await m.docker(['image','inspect','--format','{{.Id}}',supplier],{quiet:true})).stdout.trim();
    if(!/^sha256:[a-f0-9]{64}$/.test(target)||!/^sha256:[a-f0-9]{64}$/.test(before.imageId))throw Error('IDs das imagens não confirmados; nenhum container foi alterado.');
    const backup=await m.backup(),history=path.join(m.private,'config-history','wuzapi-update-'+crypto.randomUUID()),previous=structuredClone(m.state);
    m.write(path.join(history,'update.json'),{image:before.imageId,target,backup});
    m.save({...m.state,phase:'migration-update',pendingRevision:await m.revision(),optionalOperation:{service:'wuzapi',action:'update',stage:'image',previous,history,backup,from:before.imageId,target}});
    return this.finishUpdate();
  }
  async finishUpdate(){
    const m=this.m,op=m.state.optionalOperation,file=path.join(m.private,'compose-api-image.json');
    if(op?.action!=='update'||op.service!=='wuzapi'||![op.from,op.target].every(id=>/^sha256:[a-f0-9]{64}$/.test(id)))throw Error('Checkpoint WuzAPI inválido.');
    if(op.rollbackRequired)throw Error('Rollback WuzAPI pendente; diagnostique antes de retomar.');
    const apply=async id=>{m.write(file,{services:{wuzapi:{image:id}}});await m.compose(['up','-d','--no-deps','--pull','never','--wait','--wait-timeout','300','wuzapi']);const status=await this.inspect('wuzapi');if(status.status!=='HEALTHY'||status.imageId!==id)throw Error('Saúde ou imagem WuzAPI não confirmada.');};
    try{await apply(op.target);}catch(error){
      try{m.save({...m.state,optionalOperation:{...op,rollbackRequired:true}});await apply(op.from);m.save({...op.previous,phase:'ready',optionalOperation:null});}
      catch(recovery){throw new AggregateError([error,recovery],'Rollback WuzAPI não validado; preserve volumes e consulte config-history.');}throw error;
    }
    m.save({...m.state,phase:'ready',optionalOperation:null,lastWuzapiUpdate:{from:op.from,to:op.target,backup:op.backup,checkedAt:new Date().toISOString()}});
    m.runner.emit('WuzAPI saudável. '+(op.from===op.target?'Imagem já estava atualizada.':'Imagem alterada e validada.')+' Backup: '+op.backup+'\n');return{before:op.from,after:op.target,backup:op.backup};
  }
}
module.exports={ApiServices,DEFINITIONS,publicUrl,assertPublication,assertUnique,imageOverride,renderApi};
