const {createUI}=require('./ui.cjs');
const fs=require('node:fs');const path=require('node:path');
const {Operations}=require('./operations.cjs');const {GROUPS,validateOptions,PG_PROFILES,validatePg}=require('./options.cjs');
const MAIN=require('./historical.cjs').labels("main").map(([id,label])=>[id,label,({"1":"install","2":"update","3":"urls","4":"services","5":"logs","6":"backup","7":"restore","8":"tools","9":"uninstall","10":"automation","11":"official","12":"wuzapi"})[id]]);
const TOOLS=require('./historical.cjs').labels("tools").map(([id,label])=>[id,label,({"2":"push","3":"wuzapi-start","4":"rollback","5":"new-instance","6":"schedule-backup","7":"native-unavailable","8":"backup","9":"restore-redis","10":"import-amanda","11":"backup","12":"import-api_oficial","13":"databases","14":"restore-amanda","15":"urls","16":"update","17":"wuzapi-update","18":"postgres","19":"portainer-unavailable","20":"urls","21":"ssl","22":"backup","23":"restore-wuzapi","30":"token-update","31":"official","32":"update","33":"baileys","34":"audit"})[id]]);
const API=require('./historical.cjs').labels("api").map(([id,label])=>[id,label,({"1":"start","2":"update","3":"ps","4":"restart","5":"stop","6":"logs","7":"sync","8":"ssl","9":"rm"})[id]]);
TOOLS.find(item=>item[0]==='3')[2]='wuzapi';
class Menus{
  async selectInstance(strict=false){
    const {Manager}=require('./manager.cjs'),base=this.baseRoot,children=process.env.AMANDA_DEPLOY_LAYOUT==='1'?require('./deploy.cjs').BASE:path.join(base,'instances');
    const {inspectInstallation}=require('./deploy.cjs'),safe=value=>this.ui.text(String(value)).replace(/[\x00-\x1f\x7f]/g,' ').slice(0,300);
    const accepted=new Map(),rejected=[],childrenExist=fs.existsSync(children),childrenSafe=childrenExist&&fs.lstatSync(children).isDirectory()&&!fs.lstatSync(children).isSymbolicLink()&&fs.realpathSync(children)===children;
    if(childrenExist&&!childrenSafe)rejected.push(safe(children)+': Diretório de empresas inválido ou simbólico.');
    const candidates=[...new Set([...(fs.existsSync(path.join(base,'.amanda-installer/state.json'))?[base]:[]),...(childrenSafe?fs.readdirSync(children).filter(n=>/^[a-z0-9][a-z0-9_-]{0,39}$/.test(n)&&(fs.lstatSync(path.join(children,n)).isSymbolicLink()||fs.existsSync(path.join(children,n,'.amanda-installer/state.json')))).sort().map(n=>path.join(children,n)):[])])];
    for(const root of candidates){const expected=root===this.m.root?this.m.state?.project:undefined,info=inspectInstallation(root,expected);if(['complete','partial'].includes(info.kind))accepted.set(root,info.project);else rejected.push(safe(root)+': '+safe(info.reason||info.kind));}
    const roots=[...accepted.keys()];
    const select=root=>{const info=inspectInstallation(root,accepted.get(root));if(!['complete','partial'].includes(info.kind))throw Error('Instalação não reconhecida: '+safe(info.reason||info.kind));const selected=root===this.m.root?this.m:new Manager(root);selected.load();if(selected.state.project!==info.project)throw Error('Identidade da empresa mudou durante a seleção.');this.m=selected;};
    if(!roots.length){if(strict||rejected.length)throw Error('Nenhuma instalação reconhecida.'+(rejected.length?'\n'+rejected.join('\n'):''));return;}
    if(rejected.length)this.out('Instalações descartadas:\n'+rejected.join('\n'));
    if(roots.length===1){select(roots[0]);return;}
    this.out(this.ui.banner('SELECIONAR INSTÂNCIA'));roots.forEach((root,i)=>this.out(this.ui.item(String(i+1),path.basename(root))));
    const value=await this.ask('Selecione a instância (0 cancela)',String(roots.indexOf(this.m.root)+1));
    if(value==='0')throw Error('Operação cancelada.');
    if(!/^[1-9][0-9]*$/.test(value)||!roots[+value-1])throw Error('Instância inválida.');
    select(roots[+value-1]);
  }
  async update(){
    this.m.load();this.out(require('./historical.cjs').render('update','',{empresa:this.m.state.project}));
    this.out('Revisão: '+(this.m.state.revision||'consulte status')+'. A atualização inclui backup e preservação dos dados.');
    if(!/^s$/i.test(await this.ask('Deseja iniciar a atualização de todos os contêineres da AMANDA? (S/N)','n')))throw Error('Atualização cancelada.');
    this.out(require('./historical.cjs').render('channel','',{motivo:'a atualização'}));
    const selected=await this.ask('Digite a opção desejada [1-4] (Padrão: 1)','1');
    if(!['1','2','3','4'].includes(selected))throw Error('Opção inválida.');
    const branch=selected==='4'?await this.ask('Digite o nome exato da branch remota','main'):({'1':'main','2':'davi-alteracoes','3':'alan-alteracoes'})[selected];
    if(branch!=='main')throw Error('Canal indisponível neste instalador: somente main possui contrato oficial validado. Nenhuma atualização executada.');
    return this.m.execute('update');
  }
  constructor(manager,ask,installInput,{out=console.log,initial,install,startInstall}={}){this.m=manager;this.baseRoot=manager.root;this.ask=ask;this.input=installInput;this.out=out;this.initial=initial;this.install=install;this.startInstall=startInstall;this.ui=createUI();}
  async choose(title,items,before){const historical=items===MAIN?'main':items===TOOLS?'tools':items===API?'api':title==='STATUS E REINÍCIO'?'status':null;if(historical)this.out(require('./historical.cjs').render(historical,'',{emp:this.m.state?.project||'Instância atual'}));else this.out(this.ui.banner(title));if(before)await before();this.out(' Instância: '+this.m.root+'\n');if(historical==='status')for(const[id,label]of items.filter(x=>+x[0]>6))this.out(this.ui.item(id,label));if(!historical){this.out(' Selecione abaixo a opção desejada:\n');for(const[id,label]of items)this.out(this.ui.item(id,label));this.out(this.ui.item('0','Voltar / sair'));}const id=await this.ask('Selecione a opção desejada');if(id==='0')return null;const item=items.find(x=>x[0]===id);if(!item)throw Error('Opção inválida.');return item[2];}
  async form(group){const values={};const {envValues}=require('./manager.cjs');const file=this.m.state?path.join(this.m.state.platform,'.env.backend'):null,current=file&&fs.existsSync(file)?envValues(file):{};for(const[key,label,fallback,secret]of GROUPS[group]){const value=await this.ask(label+(secret&&current[key]?' (ENTER preserva o valor existente)':''),secret?undefined:(current[key]??fallback),secret);values[key]=secret&&!value&&current[key]?current[key]:value;}validateOptions(group==='identity'?values:{backendEnv:values});return values;}
  async changeUrls(ops,network){return ops.configure({network,confirmNetwork:async({urls,dnsValid,expected})=>{
    this.out('Frontend: '+urls.frontendUrl+'\nBackend: '+urls.backendUrl+'\n'+(dnsValid?'DNS compatível; TLS será validado na retomada.':'DNS pendente: somente a proposta será salva; serviços não serão alterados.'));
    return this.ask('Digite '+expected+' para confirmar (ou ENTER para cancelar)','');
  }});}
  async network(ssl=false){const ops=new Operations(this.m);await ops.ready(false,'network');const current=ops.current();
    if(this.m.state.phase==='https-pending')return this.changeUrls(ops,{frontendUrl:await this.ask('URL HTTPS frontend',this.m.state.pendingNetwork?.urls?.frontendUrl||current.frontendUrl),backendUrl:await this.ask('URL HTTPS backend',this.m.state.pendingNetwork?.urls?.backendUrl||current.backendUrl)});
    const edge=ssl||/^s(im)?$/i.test(await this.ask('Habilitar HTTPS com Caddy em Docker',current.edge?'s':'n'));
    const frontendUrl=await this.ask('URL pública frontend',ssl?undefined:current.frontendUrl),backendUrl=await this.ask('URL pública backend',ssl?undefined:current.backendUrl);
    const publish=edge?false:/^s(im)?$/i.test(await this.ask('Publicar HTTP na rede além do próprio servidor',current.public?'s':'n'));
    const officialPort=Number(await this.ask('Porta da API Oficial',String(current.options.officialPort))),wuzapiPort=Number(await this.ask('Porta da WuzAPI',String(current.options.wuzapiPort)));
    const officialUrl=edge?await this.ask('URL HTTPS pública da API Oficial (opcional)',current.options.officialUrl||''):'';
    await ops.configure({network:{frontendUrl,backendUrl,edge,public:publish,options:{officialPort,wuzapiPort,officialUrl}}});
  }
  async enable(service){const ops=new Operations(this.m);await ops.ready();this.out('O serviço será preparado em Docker. Haverá backup e possível interrupção; falhas de migration exigem Retomar operação.');const plan=['api_oficial','wuzapi'].includes(service)?await this.apiPlan(service):undefined;return ops.enableService(service,await this.ask('Digite HABILITAR '+this.m.state.project+' '+service),plan);}
  async urls(){while(true){const a=await this.choose('GERENCIAR URLs DO SISTEMA',[['1','Frontend (painel web)','front'],['2','Backend (REST / Socket)','back'],['3','API Oficial — URL interna Docker','URL_API_OFICIAL'],['4','Transcrição de áudio','TRANSCRIBE_URL'],['5','WuzAPI / WhatsMeow — URL interna Docker','WUZAPI_URL'],['7','Alterar URLs principais, portas e publicação','network'],['8','Domínios e HTTPS / SSL em Docker','ssl'],['9','VOZ / HUB: sincronizar configuração pela API','external-settings']]);if(!a)return;const ops=new Operations(this.m);
    if(a==='network')await this.network();else if(a==='ssl')await this.network(true);
    else if(a==='external-settings')await this.dispatch(a);else if(a==='front'||a==='back'){await ops.ready(false,'network');const current=ops.current(),key=a==='front'?'frontendUrl':'backendUrl';this.out('Frontend atual: '+current.frontendUrl+'\nBackend atual: '+current.backendUrl);await this.changeUrls(ops,{[key]:await this.ask('Nova URL',this.m.state.pendingNetwork?.urls?.[key]||current[key])});}
    else await ops.configure({backendEnv:{[a]:await this.ask('Nova URL acessível pelo backend')}});
    await this.ask('Pressione ENTER para continuar');
  }}
  async services(){
    const{Dashboard,render,ports,status}=require('./dashboard.cjs');await this.selectInstance(true);
    const entries=[['1','Atualizar painel','refresh'],['2','Detalhes','details'],['3','Logs recentes','logs'],['4','Reiniciar serviço','restart'],['5','Reiniciar todos','restart-all'],['6','Iniciar serviço','start'],['7','Parar serviço','stop'],['8','Iniciar plataforma','start-all'],['9','Parar plataforma','stop-all'],['10','Consumo de recursos','stats'],['11','Portas e redes','network'],['12','Trocar empresa','company']];
    while(true){const d=new Dashboard(this.m);let model;try{model=await d.collect();this.out(render(model));}catch(error){this.out(this.ui.banner('STATUS — INCOMPLETO'));this.out(this.ui.text(error.message));if(await this.ask('ENTER tenta novamente; 0 volta')==='0')return;continue;}
      for(const[id,label]of entries)this.out(this.ui.item(id,label));this.out(this.ui.item('0','Voltar'));const choice=await this.ask('Selecione a opção'),action=entries.find(x=>x[0]===choice)?.[2];if(choice==='0')return;if(!action){this.out('Opção inválida.');continue;}if(action==='refresh')continue;if(action==='company'){await this.selectInstance(true);continue;}
      try{if(action==='stats')this.out(JSON.stringify(await d.stats(),null,2));else if(action==='network')this.out(JSON.stringify(model.items.map(x=>({service:x.key,ports:ports(x.container),networks:Object.keys(x.container?.Networks||{}),access:x.service==='edge'?'Proxy Caddy; verificar binds efetivos':'Ver publicação; EXPOSE não indica acesso público'})),null,2));else{
        let selected=model.items;if(!action.endsWith('-all')){model.items.forEach((x,i)=>this.out(this.ui.item(String(i+1),x.key+' — '+(x.container?.Name||'AUSENTE')+' — '+status(x.container))));const value=await this.ask('Serviço (0 cancela)');if(value==='0')continue;if(!/^[1-9][0-9]*$/.test(value)||!model.items[+value-1])throw Error('Seleção inválida.');selected=[model.items[+value-1]];}
        if(action==='details')this.out(JSON.stringify(d.details(selected[0]),(_k,v)=>v===undefined?'Não verificado':v,2));else if(action==='logs')this.out(await d.logs(selected[0].key));else{const op=action.replace('-all',''),verb={restart:'REINICIAR',start:'INICIAR',stop:'PARAR'}[op],scope=selected.length===model.items.length?'TODOS':selected[0].key;this.out('Empresa: '+model.project+'\nServiços: '+selected.map(x=>x.key).join(', ')+'\nPoderá ocorrer indisponibilidade. Dados e volumes serão preservados.');const confirmation=await this.ask('Digite '+verb+' '+model.project+' '+scope);this.out(this.ui.banner('RESULTADO DO GERENCIAMENTO'));this.out(JSON.stringify(await d.act(op,selected.map(x=>x.key),confirmation),null,2));}
      }}catch(error){this.out(this.ui.text('OPERAÇÃO NÃO VALIDADA: '+error.message));}await this.ask('ENTER para voltar ao painel');
    }
  }
  async apiPlan(service){
    const{ApiServices,DEFINITIONS,publicUrl}=require('./api-services.cjs'),api=new ApiServices(this.m),d=DEFINITIONS[service];this.m.load();
    this.out(this.ui.banner(d.label+' — DOMÍNIO PRÓPRIO'));
    this.out('Empresa: '+(this.m.state.companyName||this.m.state.project)+'\nProjeto: '+this.m.state.project+'\nDiretório: '+this.m.root+'\nURL interna do backend: '+d.internal);
    const env=require('./manager.cjs').envValues(path.join(this.m.state.platform,'.env'));
    this.out('Docker: gerenciamento em container\nPerfil: '+d.profile+'\nPorta interna: '+(service==='api_oficial'?'6000':'8080')+'\nPorta no host em loopback: '+(service==='api_oficial'?(env.PORT_APIOFICIAL||6000):(env.PORT_WUZAPI||8090))+'\nVolume: '+this.m.state.project+'_'+(service==='api_oficial'?'oficial_public':'wuzapi_data')+'\nToken administrativo: '+(env[service==='api_oficial'?'TOKEN_API_OFICIAL':'WUZAPI_ADMIN_TOKEN']?'Configurado; será preservado':'Ausente; instalação bloqueada até configurar com segurança')+'\nCaddy: '+(this.m.state.profiles.includes('edge')?'Existente; somente domínio desta API será alterado':'Não habilitado'));
    if(service==='wuzapi')this.out('Publicação WuzAPI bloqueada até homologar autenticação e bloqueio de rotas administrativas. O modo interno mantém sessões em volume.');
    if(!this.m.state.profiles.includes('edge'))this.out('Esta instalação não possui Caddy. Disponível somente modo interno.');
    const value=await this.ask('URL HTTPS própria da '+d.label+' (ou digite INTERNO)',this.m.state.pendingApi?.service===service?this.m.state.pendingApi.url:undefined);
    if(value==='INTERNO'){if(await this.ask('Digite CONFIRMAR INTERNO','')!=='CONFIRMAR INTERNO')throw Error('Modo interno não confirmado.');return api.plan(service,'');}
    const plan=await api.plan(service,publicUrl(value));
    if(!plan.dnsValid)this.out(plan.dnsError+' A proposta poderá ser salva sem instalar nem emitir certificado.');
    this.out('URL pública proposta: '+plan.url+'\nURL interna preservada: '+d.internal);return plan;
  }
  async official(service='api_oficial'){
    await this.selectInstance(true);const{ApiServices,DEFINITIONS}=require('./api-services.cjs'),d=DEFINITIONS[service];
    const entries=[['1','Instalar '+d.label,'install'],['2',service==='api_oficial'?'Atualizar plataforma AMANDA (inclui API Oficial)':'Atualizar somente imagem WuzAPI','update'],['3','Status e diagnóstico','ps'],['4','Iniciar / reiniciar','restart'],['5','Parar','stop'],['6','Logs recentes','logs'],['7','Sincronizar integração interna do backend','sync'],['8','Domínio próprio e HTTPS','ssl'],['9','Remover somente container (preservar volumes)','rm']];
    while(true){try{
      const api=new ApiServices(this.m),info=await api.inspect(service);this.out(this.ui.banner(d.label));this.out(this.ui.text(require('./api-services.cjs').renderApi(info)));
      const a=await this.choose(d.label,entries);if(!a)return;const ops=new Operations(this.m);
      if(a==='install')await this.enable(service);
      else if(a==='update'){if(service==='api_oficial')await this.m.lock(()=>this.update());else{const confirmation=await this.ask('Digite ATUALIZAR '+this.m.state.project+' wuzapi');await this.m.lock(()=>api.updateWuzapi(confirmation));}}
      else if(a==='ssl'){const plan=await this.apiPlan(service),confirmation=await this.ask('Digite DOMINIO '+this.m.state.project+' '+service);await this.m.lock(()=>api.domain(service,plan,confirmation));}
      else if(a==='sync'){await ops.ready();ops.service(service);await ops.configure({backendEnv:{[d.integration]:d.internal}});}
      else if(a==='ps'){this.out(this.ui.text(require('./api-services.cjs').renderApi(await api.inspect(service))));}
      else if(a==='rm'){this.out('Serão preservados banco, credenciais e volumes: '+JSON.stringify(info.volumes||[])+'\nA integração ficará indisponível até iniciar novamente.');if(await this.ask('Digite REMOVER '+this.m.state.project+' '+service)!=='REMOVER '+this.m.state.project+' '+service)throw Error('Remoção cancelada.');await ops.services('rm',service);}
      else if(a==='logs')this.out(await new(require('./dashboard.cjs').Dashboard)(this.m).logs(service));
      else if(a==='restart'){if(await this.ask('Digite INICIAR '+this.m.state.project+' '+service)!=='INICIAR '+this.m.state.project+' '+service)throw Error('Operação cancelada.');await ops.services(info.installed?'restart':'start',service);}
      else if(a==='stop'){if(await this.ask('Digite PARAR '+this.m.state.project+' '+service)!=='PARAR '+this.m.state.project+' '+service)throw Error('Operação cancelada.');await ops.services('stop',service);}
    }catch(error){this.out(this.ui.text('OPERAÇÃO NÃO CONCLUÍDA: '+this.m.runner.mask(error.message)));}await this.ask('Pressione ENTER para continuar');}
  }
  async restore(kind='amanda',rollback=false){this.m.load();const base=path.join(this.m.private,'backups');if(!fs.existsSync(base))throw Error('Nenhum backup gerenciado encontrado.');
    const backups=fs.readdirSync(base).filter(n=>fs.existsSync(path.join(base,n,'backup.json'))).sort().reverse();if(!backups.length)throw Error('Nenhum backup completo encontrado.');
    backups.forEach((n,i)=>this.out('['+(i+1)+'] '+n));const index=Number(await this.ask('Escolha o backup (0 cancela)'));if(!index)return;if(!backups[index-1])throw Error('Backup inválido.');
    this.out('A operação substitui os dados selecionados. Um backup do estado atual será criado antes.');const confirmation=await this.ask('Digite RESTAURAR '+this.m.state.project);const ops=new Operations(this.m),dir=path.join(base,backups[index-1]);
    if(rollback)await ops.rollback(dir,confirmation);else await ops.restore(dir,kind,confirmation);
  }
  async configure(){const ops=new Operations(this.m);while(true){const a=await this.choose('CONFIGURAÇÕES DA PLATAFORMA',[['1','Nome da aplicação e telefone de suporte','identity'],['2','E-mail SMTP','email'],['3','Facebook App ID / App Secret','facebook'],['4','URLs / domínios / portas / SSL','urls'],['5','Integrações internas e HUB externo','integrations'],['6','Push Notifications','push'],['7','Segredo privado de build GitHub','token'],['8','Otimizar PostgreSQL','postgres'],['9','Sincronizar VOZ / HUB local pela API administrativa','external-settings'],['10','Consultar configuração atual sem segredos','view-config'],['11','Alterar URL do frontend','front-url'],['12','Alterar URL do backend','back-url'],['13','Alterar portas externas / HTTPS','network'],['14','Configurar API Oficial','official'],['15','Configurar WuzAPI','wuzapi-config'],['16','Google OAuth','google'],['17','IA — fallback de transcrição IVR','ai'],['18','Testar conexão SMTP (sem enviar e-mail)','smtp-test'],['19','Gateways de pagamento pela API administrativa','payments'],['20','Habilitar serviço opcional com backup','optional-service']]);if(!a)return;
    if(a==='identity'){const v=await this.form('identity');const email=await this.ask('E-mail administrativo atual','admin@amanda.com.br'),password=await this.ask('Senha administrativa atual',undefined,true);await ops.identity(v.appName,email,password);await ops.configure({supportPhone:v.supportPhone});}
    else if(['email','facebook','integrations','google','ai'].includes(a)){await ops.ready(false,true);await ops.configure({backendEnv:await this.form(a)});}else await this.dispatch(a);
    await this.ask('Pressione ENTER para continuar');
  }}
  async token(){this.m.load();await this.m.identifyManager();
    this.out('O backend usa dependências públicas; somente o acesso à própria AMANDA pode exigir credencial.');
    const token=await this.ask('Novo token de leitura da plataforma',undefined,true);
    if(!token||/[\r\n\0]/.test(token))throw Error('Token inválido.');
    this.m.runner.secret(token);this.m.write(path.join(this.m.private,'source-token'),token);
    this.out('Credencial da plataforma atualizada fora do Git.');
  }
  async instances(){const choices=[['1','Nova instância isolada','new'],['2','Selecionar instância neste diretório','select'],['3','Adotar Compose oficial neste diretório','adopt']];const a=await this.choose('INSTÂNCIAS',choices);if(!a)return;
    if(a==='new'){if(this.startInstall){this.m=await this.startInstall(this.m,{parent:this.m.root});return;}const c=await this.input({parent:this.m.root});this.m=await new Operations(this.m).instance(c);}
    else if(a==='adopt'){const source=await this.ask('Link da plataforma (obrigatório)');await this.m.lock(async()=>{await this.m.doctor();await this.m.adopt(source);});}
    else{const base=process.env.AMANDA_DEPLOY_LAYOUT==='1'?require('./deploy.cjs').BASE:path.join(this.baseRoot,'instances');if(!fs.existsSync(base))throw Error('Sem instâncias filhas. Para outro diretório, execute novamente com --dir.');const dirs=fs.readdirSync(base).filter(n=>/^[a-z0-9][a-z0-9_-]{0,39}$/.test(n)&&fs.existsSync(path.join(base,n,'.amanda-installer/state.json')));dirs.forEach((n,i)=>this.out('['+(i+1)+'] '+n));this.out('[P] Instância principal: '+this.baseRoot);const selection=await this.ask('Selecione a instância');if(selection.toUpperCase()==='P'){const{Manager}=require('./manager.cjs');this.m=new Manager(this.baseRoot);this.m.load();return;}const n=Number(selection);if(!dirs[n-1])throw Error('Instância inválida.');const{Manager}=require('./manager.cjs');this.m=new Manager(path.join(base,dirs[n-1]));this.m.load();}
  }
  async automation(){while(true){const a=await this.choose('GHCR / AGENDAMENTO DOCKER',[['1','Autenticar no GHCR','ghcr'],['2','Agendar atualização com backup/migrations (substitui Watchtower)','schedule-update'],['3','Agendar backup diário','schedule-backup'],['4','Atualizar agora com backup','update']]);if(!a)return;await this.dispatch(a);await this.ask('Pressione ENTER para continuar');}}
  async auditCenter(){
    const{Audit,compare}=require('./audit.cjs'),audit=new Audit(this.m);
    const entries=[['1','Diagnóstico operacional somente leitura','quick'],['2','Backend','backend'],['3','Flow Builder (cobertura parcial)','flowbuilder'],['4','Campanhas (cobertura parcial)','campaigns'],['5','Webhooks (cobertura parcial)','webhooks'],['6','Tickets e retomada de fluxo','tickets'],['7','Frontend','frontend'],['8','API Oficial','official'],['9','Infraestrutura','infrastructure'],['10','Jest/cobertura','unit'],['11','Todas as suítes disponíveis','all'],['12','Selecionar várias categorias','multi'],['14','Relatórios anteriores','history'],['15','Comparar últimas execuções','compare'],['16','Reexecutar falhas da última auditoria','retry'],['17','Lacunas de cobertura','gaps']];
    while(true){const action=await this.choose('CENTRAL DE TESTES — COBERTURA PARCIAL',entries);if(!action)return;
      const ids=audit.list();
      if(action==='history')this.out(ids.join('\n')||'Nenhuma execução');
      else if(action==='compare'&&ids.length>1)this.out(JSON.stringify(compare(audit.read(ids.at(-2)).report?.results||[],audit.read(ids.at(-1)).report?.results||[]),null,2));
      else if(action==='gaps'&&ids.length)this.out(JSON.stringify(audit.read(ids.at(-1)).report?.coverage||{status:'Inventário não executado'},null,2));
      else if(action==='retry'){if(ids.length){this.out('Nova execução das categorias de origem, incluindo pré-requisitos; nenhum resultado anterior é reaproveitado.');if(await this.ask('Digite AUDITAR '+path.basename(this.m.root))==='AUDITAR '+path.basename(this.m.root))await this.m.lock(()=>audit.retry(ids.at(-1)));}}
      else if(!['compare','gaps'].includes(action)){const mode=action==='multi'?await this.ask('Categorias separadas por vírgula (ex.: flowbuilder,campaigns,webhooks,tickets)'):action;this.out('Instalação: '+this.m.root+'\nTestes mutáveis somente no projeto isolado; cobertura parcial e homologações externas pendentes.');if(await this.ask('Digite AUDITAR '+path.basename(this.m.root))==='AUDITAR '+path.basename(this.m.root))await this.m.lock(()=>audit.run(mode));}
      await this.ask('ENTER para continuar');
    }
  }
  async baileys(){
    const {Baileys,PACKAGE}=require('./baileys.cjs'),b=new Baileys(this.m);
    while(true){
      const info=await this.m.lock(()=>b.inspect());
      this.out(this.ui.banner('ATUALIZAÇÃO DO BAILEYS'));
      this.out(this.ui.text(`Empresa: ${this.m.state.project}\nBackend: ${info.container}\nBiblioteca: ${PACKAGE}\nVersão configurada: ${info.configured}\nVersão instalada/carregada: ${info.runtime?.version||'Não verificado'}\nVersão disponível: ${info.versions?.at(-1)||'Não verificado'}\nVersões candidatas da mesma linha: ${info.compatible.join(', ')||'Nenhuma consultável'}\nOrigem: ${info.supported?'NPM público fixado':'Local/fork/resolução não suportada; revisão técnica necessária'}`));
      const action=await this.choose('BAILEYS', [['1','Verificar versão instalada','inspect'],['2','Atualizar Baileys','update'],['3','Consultar logs','logs'],['4','Rollback da última atualização Baileys','rollback']]);
      if(!action)return;
      if(action==='update'){
        if(!info.supported||!info.compatible.length){this.out('Nenhuma atualização candidata compatível disponível.');continue;}
        const target=await this.ask('Versão exata da mesma linha',info.compatible.at(-1));
        this.out(this.ui.text(`ATENÇÃO — ATUALIZAÇÃO DO BAILEYS\nEmpresa: ${this.m.state.project}\nVersão atual: ${info.runtime?.version||'Não verificado'}\nNova versão: ${target}\nServiços afetados: backend (${info.container})\nA operação poderá interromper temporariamente conexões WhatsApp.\nBackup e rollback serão preparados. Homologação WhatsApp continuará pendente.`));
        const confirmation=await this.ask('Digite ATUALIZAR BAILEYS '+this.m.state.project);
        await this.m.lock(()=>b.update(target,confirmation));
      }else if(action==='logs')await this.m.lock(()=>b.logs());
      else if(action==='rollback'){const confirmation=await this.ask('Digite REVERTER BAILEYS '+this.m.state.project);await this.m.lock(()=>b.rollback(confirmation));}
    }
  }
  async dispatch(action,locked=false){
    if(action==='audit')return this.auditCenter();
    if(!locked&&!['install','new-instance','tools','official','wuzapi','services','instances','doctor','native-unavailable','portainer-unavailable'].includes(action))await this.selectInstance();
    if(!locked&&!['install','new-instance','tools','official','wuzapi','configure','services','urls','instances','automation','baileys'].includes(action))return this.m.lock(async()=>{this.m.runner.emit('Operação: '+action+'\n');try{const value=await this.dispatch(action,true);this.m.runner.emit('OK: '+action+'\n');return value;}catch(error){this.m.runner.emit('FALHA: '+action+' — '+error.message+'\n');throw error;}});
    const m=this.m,ops=new Operations(m);
    if(action?.startsWith('restore-'))return this.restore(action.slice(8));
    if(action?.startsWith('import-')){m.load();this.out('Copie um backup confiável de um único banco para '+path.join(m.root,'imports')+'. O banco selecionado será substituído.');const file=await this.ask('Caminho absoluto do arquivo dentro de imports');return ops.importDatabase(file,action.slice(7),await this.ask('Digite IMPORTAR '+m.state.project));}
    switch(action){
      case'install':if(this.startInstall){const installed=await this.startInstall(m);if(installed?.root)this.m=installed;return installed;}if(fs.existsSync(m.stateFile))throw Error('Instalação já registrada. Use resume para retomar sem responder novamente nem repetir seeds.');if(this.install){const installed=await this.install(m,await this.input());if(installed?.root)this.m=installed;return installed;}return null;
      case'urls':return this.urls();case'services':return this.services();case'official':return this.official();case'wuzapi':return this.official('wuzapi');case'configure':return this.configure();case'instances':return this.instances();case'automation':return this.automation();
      case'audit':return this.auditCenter();
      case'baileys':return this.baileys();
      case'tools':while(true){const a=await this.choose('FERRAMENTAS ADICIONAIS',TOOLS);if(!a)return;await this.dispatch(a);await this.ask('Pressione ENTER para continuar');}
      case'restore':return this.restore();case'rollback':return this.restore('all',true);
      case'uninstall':{m.load();const a=await this.choose('DESINSTALAR',[['1','Remover containers preservando dados','keep'],['2','Remover containers e apagar volumes — backup obrigatório','erase']]);if(!a)return;this.out('Código, configuração e backups serão preservados.');return ops.uninstall(a==='erase',await this.ask('Digite '+(a==='erase'?'DELETAR TUDO ':'REMOVER ')+m.state.project));}
      case'external-settings':{const kind=await this.choose('INTEGRAÇÕES EXTERNAS',[['1','VOZ','voz'],['2','HUB local','hub']]);if(!kind)return;const values=kind==='voz'?{amandaVozUrl:await this.ask('URL pública AMANDA VOZ')}:{hubLocalUrl:await this.ask('URL do HUB acessível pelo backend'),hubLocalAdminKey:await this.ask('Chave administrativa HUB',undefined,true)};return ops.settings(values,await this.ask('E-mail administrativo atual','admin@amanda.com.br'),await this.ask('Senha administrativa atual',undefined,true));}
      case'channels-unavailable':throw Error('Catálogo de versões MultiFlow indisponível. A plataforma oficial utiliza main; escolha o canal pelo menu de atualização.');
      case'external-unavailable':throw Error('Instalação externa HUB/VOZ indisponível: nenhum serviço no Compose oficial. Configure a integração existente pelo comando configure.');
      case'helper-unavailable':throw Error('Receita auxiliar nativa indisponível. Use atualização, diagnóstico ou configurações do Compose oficial; nenhum reparo foi executado.');
      case'native-unavailable':throw Error('Operação nativa indisponível: a VPS utiliza somente Docker. Para backup diário use a opção 6.');case'portainer-unavailable':throw Error('Portainer indisponível: não há contrato de instalação autenticada no Compose oficial. Nenhum container foi instalado.');
      case'ssl':return this.network(true);case'token':return this.token();case'token-update':await this.token();return this.update();
      case'optional-service':{const service=await this.choose('HABILITAR SERVIÇO OPCIONAL',[['1','API Oficial','api_oficial'],['2','WuzAPI','wuzapi'],['3','RabbitMQ (requer API Oficial)','rabbitmq']]);return service?this.enable(service):undefined;}
      case'network':return this.network();
      case'front-url':case'back-url':{await ops.ready(false,'network');const key=action==='front-url'?'frontendUrl':'backendUrl';return this.changeUrls(ops,{[key]:await this.ask('Nova URL pública',this.m.state.pendingNetwork?.urls?.[key]||ops.current()[key])});}
      case'view-config':{await ops.ready(false,'view');const {envValues}=require('./manager.cjs'),e=envValues(path.join(m.state.platform,'.env')),be=fs.existsSync(path.join(m.state.platform,'.env.backend'))?envValues(path.join(m.state.platform,'.env.backend')):{};const {publicSummary}=require('./wizard.cjs');const summary=publicSummary({...ops.current(),companyName:m.state.companyName,adminEmail:'Preservado; consulte a conta na plataforma',options:{...ops.current().options,appName:'Gerenciado na interface da plataforma',supportPhone:e.REACT_APP_NUMBER_SUPPORT||'',backendEnv:{MAIL_HOST:be.MAIL_HOST},pg:{maxConnections:+e.PG_MAX_CONNECTIONS||100,sharedBuffers:e.PG_SHARED_BUFFERS||'128MB'}}},m.root);for(const[k,v]of Object.entries(summary))this.out(this.ui.text(k+': '+v));return;}
      case'smtp-test':await ops.ready();return m.testSmtp();
      case'wuzapi-config':return this.official('wuzapi');
      case'payments':{await ops.ready();const gateway=await this.choose('PAGAMENTOS',[['1','Desabilitado','none'],['2','Stripe','stripe'],['3','Asaas','asaas'],['4','Mercado Pago','mercadopago']]);if(!gateway)return;const values={};if(gateway!=='none'){const key={stripe:'stripeprivatekey',asaas:'asaastoken',mercadopago:'mpaccesstoken'}[gateway];values[key]=await this.ask('Credencial privada do gateway',undefined,true);if(!values[key])throw Error('Credencial vazia.');if(gateway==='asaas'||gateway==='mercadopago')values[gateway==='asaas'?'asaassandbox':'mpsandbox']=/^s(im)?$/i.test(await this.ask('Usar sandbox (s/n)','s'))?'true':'false';}values.activePaymentGateway=gateway;this.out('Teste cobranças e webhooks com a conta do provedor antes de ativar produção.');return ops.settings(values,await this.ask('E-mail administrativo atual','admin@amanda.com.br'),await this.ask('Senha administrativa atual',undefined,true));}
      case'push':return ops.configure({pushEmail:await this.ask('E-mail de contato VAPID')});
      case'postgres':{const a=await this.choose('POSTGRESQL EM CONTAINER',[['1','Econômico: 100 conexões / 128MB','small'],['2','Intermediário: 200 conexões / 256MB','medium'],['3','Alto desempenho: 300 conexões / 512MB','large'],['4','Personalizado (validado contra memória Docker)','custom']]);if(!a)return;const pg=a==='custom'?{maxConnections:Number(await this.ask('Máximo de conexões','100')),sharedBuffers:await this.ask('shared_buffers','128MB')}:PG_PROFILES[a];validatePg(pg);return ops.configure({pg});}
      case'wuzapi-start':m.load();return m.services().includes('wuzapi')?ops.services('start','wuzapi'):this.enable('wuzapi');
      case'wuzapi-update':return new(require('./api-services.cjs').ApiServices)(m).updateWuzapi(await this.ask('Digite ATUALIZAR '+m.state.project+' wuzapi'));
      case'databases':return ops.databases();
      case'schedule-backup':case'schedule-update':return ops.schedule(action==='schedule-backup'?'backup':'update',Number(await this.ask('Hora diária em UTC (0–23)','3')));
      case'ghcr':return ops.ghcr(await this.ask('Usuário GitHub / GHCR'),await this.ask('Token de leitura GHCR',undefined,true));
      case'new-instance':if(this.startInstall){this.m=await this.startInstall(m,{parent:m.root});return;}this.m=await ops.instance(await this.input({parent:m.root}));return;
      case'update':return this.update();
      default:if(['logs','backup','doctor','resume','start','stop','restart'].includes(action))return m.execute(action);throw Error('Ação sem implementação: '+action);
    }
  }
  async run(){let first=this.initial;while(true){try{const action=first?MAIN.find(i=>i[0]===first)?.[2]:await this.choose('INSTALADOR AMANDA — MENU PRINCIPAL',MAIN);first=undefined;if(!action)return;
      await this.dispatch(action);
      await this.ask('Pressione ENTER para voltar ao menu principal');
    }catch(error){this.out('ERRO: '+this.m.runner.mask(error.message));this.out('Operação não concluída. Dados preservados; revise o log antes de tentar novamente.');await this.ask('Pressione ENTER para voltar ao menu principal');}}
  }
}
module.exports={MAIN,TOOLS,API,Menus};
