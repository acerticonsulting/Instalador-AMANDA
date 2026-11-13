const path=require('node:path');
const {isIP}=require('node:net');
const {normalizeConfig,SOURCE}=require('./manager.cjs');
const {GROUPS,PG_PROFILES,validatePg,validateOptions,selectedServices}=require('./options.cjs');
const {createUI}=require('./ui.cjs');
const TITLES=['TIPO DE INSTALAÇÃO','CONFIGURAÇÃO DE DOMÍNIOS E URLS','PERSONALIZAÇÃO DA PLATAFORMA','CONFIGURAÇÃO DO ACESSO ADMINISTRATIVO','CONFIGURAÇÃO DO POSTGRESQL','SEGURANÇA E CREDENCIAIS INTERNAS','INTEGRAÇÕES WHATSAPP','CONFIGURAÇÃO SMTP','OUTRAS INTEGRAÇÕES','HTTPS E SSL','RESUMO DA INSTALAÇÃO AMANDA'];
const BACK=Symbol('back');
const email=value=>{if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value))throw Error('Informe um e-mail válido.');return value;};
const port=value=>{if(!/^\d+$/.test(value)||+value<1||+value>65535)throw Error('Use uma porta entre 1 e 65535.');return String(+value);};
const domain=value=>{const v=/^https?:\/\//i.test(value)?value:'https://'+value;const u=new URL(v);if(u.protocol!=='https:'||u.port||u.username||u.password||u.search||u.hash||u.pathname!=='/'||!u.hostname.includes('.')||u.hostname.split('.').some(p=>! /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/i.test(p))||isIP(u.hostname))throw Error('Use um domínio DNS válido, com HTTPS, sem porta ou caminho.');return u.origin;};
function publicSummary(c,directory){
  const o=c.options,pg=o.pg||PG_PROFILES.small,flags={official:true,wuzapi:true,rabbit:true,...o.services};
  return {
    tipo:c.edge?'Domínios e HTTPS':c.public?'IP / acesso pela rede':'Local',empresa:c.companyName||c.project,projeto:c.project,plataforma:o.appName||'AMANDA',suporte:o.supportPhone||'Não informado',frontend:c.frontendUrl,backend:c.backendUrl,
    portas:c.edge?'80 TCP, 443 TCP/UDP (HTTP direto em loopback)':(new URL(c.frontendUrl).port||'80')+' / '+(new URL(c.backendUrl).port||'80'),
    apiOficial:flags.official?(o.officialUrl||(c.public?'HTTP publicado na rede, porta ':'HTTP em loopback, porta ')+(o.officialPort||6000)):'Desabilitada',wuzapi:flags.wuzapi?(c.public?'HTTP publicado na rede, porta ':'HTTP em loopback, porta ')+(o.wuzapiPort||8090):'Desabilitada',administrador:c.adminEmail,
    postgres:pg.maxConnections+' conexões / shared_buffers '+pg.sharedBuffers,integracoes:['Baileys','Transcrição',...(flags.official?['API Oficial']:[]),...(flags.wuzapi?['WuzAPI']:[]),...(flags.rabbit?['RabbitMQ']:[]),...(['facebook','google','ai'].filter(group=>GROUPS[group].some(([key])=>o.backendEnv?.[key])).map(g=>({facebook:'Facebook',google:'Google OAuth',ai:'OpenAI IVR'})[g])),...(o.pushEmail?['Push']:[]),...(o.initialSettings?.activePaymentGateway?['Pagamentos: '+o.initialSettings.activePaymentGateway]:[])].join(', '),smtp:o.backendEnv?.MAIL_HOST?'Habilitado (conexão '+(o.testSmtp?'será testada':'não testada')+')':'Configurar posteriormente',https:c.edge?'Caddy; certificado ainda não confirmado':'Desabilitado',servicos:selectedServices(o).concat(c.edge?['edge (Caddy)']:[]).join(', '),diretorio:typeof directory==='function'?directory(c):directory,
  };
}
async function collectInstallation({question,checkDomains,out=console.log,getResources,project,directory=process.env.AMANDA_DEPLOY_LAYOUT==='1'?c=>require('./deploy.cjs').companyDirectory(c.project):process.env.AMANDA_INSTALL_DIR||require('./deploy.cjs').BASE}={}){
  const ui=createUI(),draft={sourceUrl:SOURCE,project:'amanda',companyName:'AMANDA',frontendUrl:'http://localhost:3000',backendUrl:'http://localhost:8080',edge:false,public:false,options:{appName:'AMANDA',supportPhone:'',backendEnv:{}}};
  let step=0,mode='3',resources;
  const show=s=>out(ui.text(s));
  async function read(label,fallback,validate,secret=false,previous){
    while(true){const value=await question(label+(secret&&previous?' (ENTER mantém o valor; :limpar remove)':''),secret?undefined:fallback,secret);
      if(value===undefined||value===null||[':cancelar',':sair'].includes(value))throw Error('Instalação cancelada antes de criar recursos.');
      if(value===':voltar')throw BACK;
      const v=secret&&value===':limpar'?'':value===''?(secret?(previous||''):(fallback??'')):value;
      try{if(/[\x00-\x1f\x7f]/.test(v))throw Error('Caracteres de controle não são permitidos.');return validate?validate(v):v;}catch(error){show('VALOR INVÁLIDO: '+(secret?'Revise o segredo informado.':error.message));}
    }
  }
  const choice=(label,fallback,choices)=>read(label,fallback,v=>{if(!choices.includes(v))throw Error('Escolha '+choices.join(', ')+'.');return v;});
  const yes=async(label,fallback='n')=>/^(s|sim|1)$/i.test(await read(label+' (s/n)',fallback,v=>{if(!/^(s|sim|n|nao|não|1|2)$/i.test(v))throw Error('Responda s ou n.');return v;}));
  async function group(name){for(const[key,label,fallback,secret]of GROUPS[name])draft.options.backendEnv[key]=await read(label,draft.options.backendEnv[key]??fallback,v=>{validateOptions({backendEnv:{[key]:v}});return v;},secret,draft.options.backendEnv[key]);}
  const sections=[
    async()=>{show('COMO DESEJA INSTALAR A AMANDA?\n1. Domínios e HTTPS\n2. IP do servidor\n3. Local para desenvolvimento ou testes');mode=await choice('Tipo de instalação',mode,['1','2','3']);draft.edge=mode==='1';draft.public=mode==='2';},
    async()=>{
      if(draft.edge){draft.backendUrl=await read('URL do backend HTTPS',draft.backendUrl.startsWith('https:')?draft.backendUrl:undefined,domain);draft.frontendUrl=await read('URL do frontend HTTPS',draft.frontendUrl.startsWith('https:')?draft.frontendUrl:undefined,domain);draft.public=false;
        if(checkDomains){const result=await checkDomains(draft,{question,out});if(result.back)throw BACK;Object.assign(draft,result);}
        show('Caddy publica 80/443; portas diretas dos serviços permanecem em loopback.');}
      else{
        const previousHost=new URL(draft.frontendUrl).hostname.replace(/^\[|\]$/g,'');
        let host='localhost';if(mode==='2')host=await read('IP do servidor (sem protocolo, porta ou caminho)',isIP(previousHost)?previousHost:undefined,v=>{if(!isIP(v))throw Error('IP do servidor inválido. Informe IPv4 ou IPv6.');return v;});
        const custom=await yes('Deseja utilizar portas personalizadas',(new URL(draft.frontendUrl).port||'3000')!=='3000'||(new URL(draft.backendUrl).port||'8080')!=='8080'?'s':'n');
        const front=custom?await read('Porta externa do frontend',new URL(draft.frontendUrl).port||'3000',port):'3000',back=custom?await read('Porta externa do backend',new URL(draft.backendUrl).port||'8080',port):'8080';
        if(front===back)throw Error('Frontend e backend precisam de portas diferentes.');
        draft.public=mode==='2'?await yes('Permitir acesso pela rede externa','s'):false;
        if(mode==='2'&&!draft.public)throw Error('O modo IP exige acesso pela rede; escolha Local para loopback.');
        const address=isIP(host)===6?'['+host+']':host;draft.frontendUrl='http://'+address+':'+front;draft.backendUrl='http://'+address+':'+back;
      }
      if(draft.frontendUrl===draft.backendUrl)throw Error('Frontend e backend precisam de endereços diferentes.');
    },
    async()=>{draft.companyName=await read('Nome comercial da empresa',draft.companyName,v=>{if(!v.trim()||v.length>120)throw Error('Informe até 120 caracteres.');return v.trim();});draft.options.appName=await read('Nome de exibição da plataforma',draft.options.appName,v=>{validateOptions({appName:v});return v;});draft.project=project||await read('Nome técnico do projeto Docker',draft.project,v=>normalizeConfig({sourceUrl:SOURCE,project:v}).project);draft.options.supportPhone=await read('Número de telefone do suporte',draft.options.supportPhone,v=>{validateOptions({supportPhone:v});return v;});},
    async()=>{
      show('O padrão local é admin@amanda.com.br / adminamanda. Informe a senha que deseja utilizar.');
      const customized=draft.adminPassword&&draft.adminPassword!=='adminamanda'||draft.adminEmail&&draft.adminEmail!=='admin@amanda.com.br';
      const custom=await yes('Personalizar o acesso administrativo',customized||draft.public||draft.edge?'s':'n');
      if(custom){draft.adminEmail=await read('E-mail do administrador',draft.adminEmail||'admin@amanda.com.br',email);const previous=draft.adminPassword;draft.adminPassword=await read('Senha do administrador',undefined,v=>{if(!v||v.length>256)throw Error('Senha inválida.');return v;},true,previous);await read('Confirmação da senha',undefined,v=>{if(v!==draft.adminPassword)throw Error('Confirmação diferente.');return v;},true,draft.adminPassword===previous?previous:undefined);}
      else{draft.adminEmail='admin@amanda.com.br';draft.adminPassword='adminamanda';if(draft.edge||draft.public)show('AVISO: acesso padrão público. Altere a senha na plataforma antes de liberar acesso aos usuários.');}
    },
    async()=>{
      if(await yes('Gerar senha PostgreSQL segura automaticamente',draft.options.databasePassword?'n':'s'))delete draft.options.databasePassword;else draft.options.databasePassword=await read('Senha PostgreSQL personalizada',undefined,v=>{validateOptions({databasePassword:v});return v;},true,draft.options.databasePassword);
      resources=getResources?await getResources():undefined;
      if(resources?.memory)show('Docker: '+(resources.memory/1024**3).toFixed(1)+' GiB / '+resources.cpus+' CPUs. O orçamento inclui outros serviços e instalações.');
      show('1. Econômico: 100 conexões / 128MB\n2. Intermediário: 200 / 256MB\n3. Alto desempenho: 300 / 512MB\n4. Personalizado');
      const previousPg=draft.options.pg||PG_PROFILES.small,profileDefault=Object.values(PG_PROFILES).findIndex(p=>p.maxConnections===previousPg.maxConnections&&p.sharedBuffers===previousPg.sharedBuffers);
      const profile=await choice('Perfil PostgreSQL',profileDefault<0?'4':String(profileDefault+1),['1','2','3','4']);draft.options.pg=profile==='4'?{maxConnections:Number(await read('Máximo de conexões',String(previousPg.maxConnections),v=>{if(!/^\d+$/.test(v))throw Error('Use um inteiro.');return v;})),sharedBuffers:await read('shared_buffers (ex.: 128MB, 1GB)',previousPg.sharedBuffers)}:structuredClone(PG_PROFILES[{1:'small',2:'medium',3:'large'}[profile]]);validatePg(draft.options.pg,resources?.memory);
    },
    async()=>{
      show('JWT, refresh, banco, transcrição, API Oficial, WuzAPI e RabbitMQ recebem chaves distintas pelo gerador oficial. Atualizações preservam as chaves.');
      const master=await read('MASTER_KEY personalizada (ENTER gera automaticamente)',undefined,v=>{if(v)validateOptions({masterPassword:v});return v;},true,draft.options.masterPassword);if(master)draft.options.masterPassword=master;else delete draft.options.masterPassword;
      draft.sourceToken=await read('Token GitHub de leitura da plataforma (vazio se público)',undefined,null,true,draft.sourceToken);
      draft.sourceUrl=await read('Link da plataforma (obrigatório: https://github.com/acerticonsulting/AMANDA)',undefined,v=>normalizeConfig({sourceUrl:v}).sourceUrl);
    },
    async()=>{
      show('Baileys e transcrição fazem parte do backend oficial. Pareamento e contas Meta são configurados na interface após a instalação.');
      const previousServices={official:true,wuzapi:true,rabbit:true,...draft.options.services};
      const services={official:await yes('Habilitar API Oficial WhatsApp/Meta',previousServices.official?'s':'n'),wuzapi:await yes('Habilitar WuzAPI/WhatsMeow',previousServices.wuzapi?'s':'n')};services.rabbit=services.official?await yes('Habilitar RabbitMQ para filas da API Oficial',previousServices.rabbit?'s':'n'):false;draft.options.services=services;
      for(const [flag,key,label,defaultPort,tokenKey]of [['official','officialPort','API Oficial','6000','officialToken'],['wuzapi','wuzapiPort','WuzAPI','8090','wuzapiToken']]){
        if(services[flag]){draft.options[key]=Number(await read('Porta externa '+label,String(draft.options[key]||defaultPort),port));const token=await read('Token interno '+label+' (ENTER gera automaticamente)',undefined,v=>{if(v)validateOptions({[tokenKey]:v});return v;},true,draft.options[tokenKey]);if(token)draft.options[tokenKey]=token;else delete draft.options[tokenKey];}else{delete draft.options[key];delete draft.options[tokenKey];}
      }
      if(draft.edge&&services.official)draft.options.officialUrl=await read('URL pública HTTPS da API Oficial (opcional)',draft.options.officialUrl||'',v=>v?domain(v):'');else delete draft.options.officialUrl;
      if(await yes('Configurar Facebook/Meta App ID e App Secret agora',GROUPS.facebook.some(([k])=>draft.options.backendEnv[k])?'s':'n'))await group('facebook');else for(const[k]of GROUPS.facebook)delete draft.options.backendEnv[k];
    },
    async()=>{
      if(await yes('Deseja configurar o envio de e-mails',draft.options.backendEnv.MAIL_HOST?'s':'n')){show('Use TLS implícito na porta 465; STARTTLS na 587. O teste verifica conexão/autenticação sem enviar e-mail. Configurações SMTP salvas na interface podem prevalecer sobre o ambiente.');await group('email');if(!draft.options.backendEnv.MAIL_HOST||!draft.options.backendEnv.MAIL_FROM)throw Error('SMTP exige servidor e e-mail remetente.');draft.options.initialSettings={...draft.options.initialSettings,signupSmtpFromName:await read('Nome do remetente SMTP (opcional)',draft.options.initialSettings?.signupSmtpFromName||'')};draft.options.testSmtp=await yes('Testar conexão SMTP após iniciar a plataforma','s');}
      else{for(const[key]of GROUPS.email)delete draft.options.backendEnv[key];if(draft.options.initialSettings)delete draft.options.initialSettings.signupSmtpFromName;draft.options.testSmtp=false;}
    },
    async()=>{
      show('Integrações podem ser configuradas depois no menu 12. Google OAuth usa callback BACKEND_URL/auth/google/callback. IA aqui atende somente o fallback de transcrição do IVR.');
      for(const[name,label]of [['google','Configurar Google OAuth agora'],['ai','Configurar chave de IA para IVR agora']])if(await yes(label,GROUPS[name].some(([k])=>draft.options.backendEnv[k])?'s':'n'))await group(name);else for(const[k]of GROUPS[name])delete draft.options.backendEnv[k];
      if(await yes('Configurar notificações push agora',draft.options.pushEmail?'s':'n'))draft.options.pushEmail=await read('E-mail de contato VAPID',draft.options.pushEmail||draft.adminEmail,email);else delete draft.options.pushEmail;
      show('Pagamentos são configurados na área administrativa da plataforma (gateways e credenciais por conta). VOZ/HUB exigem serviços externos próprios; GoFlow não tem fonte neste Compose.');
    },
    async()=>{
      if(draft.edge)show('Aponte os registros DNS dos domínios para o servidor e libere 80/TCP e 443/TCP/UDP. Caddy em Docker solicita e renova certificados. DNS, portas e TLS serão verificados; nenhum certificado foi emitido ainda.');else show('HTTPS desabilitado. No modo IP/HTTP não envie credenciais em redes não confiáveis; configure domínios/HTTPS no menu 12 antes do uso público.');
      if(!await yes('Confirmar a configuração de acesso e HTTPS','s'))throw BACK;
    },
  ];
  while(true){
    out(ui.banner('[ETAPA '+String(step+1).padStart(2,'0')+'/11] '+TITLES[step]));
    show('Digite :voltar para a etapa anterior ou :cancelar para sair. Nenhum dado da plataforma será criado antes da confirmação.');
    try{
      if(step<10){await sections[step]();step++;continue;}
      let config;try{config=normalizeConfig(draft);}catch(error){show('Revise as configurações: '+error.message);step=await read('Etapa para corrigir (1–10)','2',v=>{if(!/^(10|[1-9])$/.test(v))throw Error('Escolha de 1 a 10.');return +v-1;});continue;}
      for(const[key,value]of Object.entries(publicSummary(config,directory)))show(' '+key+': '+value);
      show('1. Confirmar e instalar\n2. Revisar configurações\n3. Cancelar instalação');
      const action=await choice('Como deseja continuar','3',['1','2','3']);if(action==='1')return config;if(action==='3')throw Error('Instalação cancelada antes de criar recursos.');
      step=await read('Qual etapa deseja revisar (1–10)','2',v=>{if(!/^(10|[1-9])$/.test(v))throw Error('Escolha de 1 a 10.');return +v-1;});
    }catch(error){if(error===BACK){step=Math.max(0,step-1);continue;}if(/cancelada/.test(error.message))throw error;show('ETAPA NÃO CONCLUÍDA: '+error.message);}
  }
}
module.exports={TITLES,collectInstallation,publicSummary,domain,email,port};
