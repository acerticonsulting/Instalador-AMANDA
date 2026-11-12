// Os printf vêm do instalador original, sem carregar seu provisionamento nativo.
const path=require('node:path');
const {spawnSync}=require('node:child_process');
const {isIP}=require('node:net');
const {SOURCE,normalizeConfig}=require('./manager.cjs');
const {validateOptions,PG_PROFILES}=require('./options.cjs');
function render(screen,key='',values={}){
  const result=spawnSync('sh',[path.join(__dirname,'historical.sh'),'--'+screen,key],{encoding:'utf8',env:{...process.env,AMANDA_UI_TTY:process.stdout.isTTY?'1':'0',emp_padrao:'amanda',ip_sugerido:'localhost',emp:'Instância atual',status_texto:'Consulte a opção 3',modo_execucao:'Docker Compose',porta_oficial:'Consulte a opção 3',url_oficial:'Consulte a opção 3',st_be:'Verificação antes da instalação',st_fe:'Verificação antes da instalação',...values},maxBuffer:128*1024});
  if(result.error||result.status!==0)throw Error('Não foi possível apresentar a interface histórica.');
  return result.stdout;
}
function labels(screen){return [...render(screen,'',{AMANDA_UI_TTY:'0'}).replace(/\x1b\[[0-9;]*[A-Za-z]/g,'').matchAll(/\[([0-9]+)\] ([^\n]+)/g)].filter(m=>m[1]!=='0').map(m=>[m[1],m[2]]);}
async function collectHistorical({question,out=console.log,directory=process.env.AMANDA_DEPLOY_LAYOUT==='1'?c=>require('./deploy.cjs').companyDirectory(c.project):process.env.AMANDA_INSTALL_DIR||require('./deploy.cjs').BASE}={}){
  let c={sourceUrl:SOURCE,project:'amanda',companyName:'AMANDA',options:{backendEnv:{}}};
  const text=s=>out(String(s).replace(/[\x00-\x08\x0b-\x1f\x7f]/g,''));
  const extra=async(...args)=>{const value=await question(...args);if(value==null||[':cancelar',':sair'].includes(value))throw Error('Instalação cancelada antes de criar recursos.');return value;};
  async function read(key,fallback,validate,secret=false){
    while(true){out(render('question',key));const value=await question('',fallback,secret);
      if(value==null||[':cancelar',':sair'].includes(value))throw Error('Instalação cancelada antes de criar recursos.');
      const v=value===''?(fallback??''):value;
      try{if(/[\x00-\x1f\x7f]/.test(v))throw Error('Caracteres de controle não permitidos.');return validate?validate(v):v;}
      catch(error){text('VALOR INVÁLIDO: '+(secret?'Revise o segredo informado.':error.message));}
    }
  }
  const email=v=>{if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v))throw Error('Informe um e-mail válido.');return v;};
  const port=v=>{if(!/^\d+$/.test(v)||+v<1||+v>65535)throw Error('Use uma porta entre 1 e 65535.');return String(+v);};
  const domain=v=>{const u=new URL(/^https?:\/\//i.test(v)?v:'https://'+v);if(u.protocol!=='https:'||u.username||u.password||u.port||u.pathname!=='/'||u.search||u.hash||isIP(u.hostname)||!u.hostname.includes('.')||u.hostname.split('.').some(p=>!/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/i.test(p)))throw Error('Use um domínio HTTPS sem porta ou caminho.');return u.origin;};
  const yn=v=>{if(!/^[sn]$/i.test(v))throw Error('Responda S ou N.');return v.toLowerCase();};
  const mode=await read('modo_rede','1',v=>{if(!['1','2'].includes(v))throw Error('Escolha 1 ou 2.');return v;});
  let host;
  if(mode==='1')host=await read('host_escolhido','localhost',v=>{if(v!=='localhost'&&!isIP(v))throw Error('Use localhost, IPv4 ou IPv6, sem protocolo/porta.');return v;});
  else{
    c.backendUrl=await read('subdominio_backend','',v=>v===''?'':domain(v));
    if(!c.backendUrl)host=await read('host_escolhido','localhost',v=>{if(v!=='localhost'&&!isIP(v))throw Error('IP inválido.');return v;});
    else c.frontendUrl=await read('subdominio_frontend',undefined,domain);
  }
  // Ordem original de questoes_variaveis_base, inclusive token antes do repositório.
  c.adminEmail=await read('email_deploy','admin@amanda.com.br',email);
  c.project=await read('input_empresa','amanda',v=>normalizeConfig({sourceUrl:SOURCE,project:v}).project);
  c.companyName=c.project;
  const db=await read('senha_deploy','',v=>{if(v)validateOptions({databasePassword:v});return v;},true);if(db)c.options.databasePassword=db;
  const master=await read('senha_master','',v=>{if(v)validateOptions({masterPassword:v});return v;},true);if(master)c.options.masterPassword=master;
  c.options.appName=await read('nome_titulo','AMANDA',v=>{validateOptions({appName:v});return v;});
  c.options.supportPhone=await read('numero_suporte','',v=>{validateOptions({supportPhone:v});return v;});
  c.options.backendEnv.FACEBOOK_APP_ID=await read('facebook_app_id','',v=>{validateOptions({backendEnv:{FACEBOOK_APP_ID:v}});return v;});
  c.options.backendEnv.FACEBOOK_APP_SECRET=await read('facebook_app_secret','',v=>{validateOptions({backendEnv:{FACEBOOK_APP_SECRET:v}});return v;},true);
  c.sourceToken=await read('github_token','',null,true);
  c.sourceUrl=await read('repo_url',SOURCE,v=>normalizeConfig({sourceUrl:v}).sourceUrl);
  c.edge=!host;c.public=Boolean(host&&host!=='localhost'&&host!=='127.0.0.1'&&host!=='::1');
  if(c.edge)out(render('question','proxy'));
  const defaults=await read('use_default_ports','s',yn);
  let back='8080',front='3000';
  if(defaults==='n'){back=await read('backend_port','8080',port);front=await read('frontend_port','3000',v=>{port(v);if(+v===+back)throw Error('Frontend e backend precisam de portas diferentes.');return v;});}
  if(host){const address=isIP(host)===6?'['+host+']':host;c.backendUrl='http://'+address+':'+back;c.frontendUrl='http://'+address+':'+front;}
  else{c.options.backendPort=+back;c.options.frontendPort=+front;}
  // Novas perguntas estritamente necessárias vêm após o bloco histórico intacto.
  text('A conta administrativa usa o e-mail informado. A senha é distinta da senha do banco.');
  c.adminPassword=await extra('Senha do administrador',undefined,true);
  if(!c.adminPassword||/[\x00-\x1f\x7f]/.test(c.adminPassword)||c.adminPassword.length>256)throw Error('Senha administrativa vazia/inválida.');
  if(await extra('Confirmação da senha',undefined,true)!==c.adminPassword)throw Error('Confirmação diferente.');
  c.buildToken=await extra('Token de leitura do conector privado (ENTER se já disponível)',undefined,true)||'';
  c=normalizeConfig(c);
  out(render('question','confirmacao').split(' >> Os dados estão corretos?')[0]);
  out(render('summary','',{subdominio_backend:c.backendUrl,subdominio_frontend:c.frontendUrl,email_deploy:c.adminEmail,empresa:c.project,nome_titulo:c.options.appName,numero_suporte:c.options.supportPhone,facebook_app_id:c.options.backendEnv.FACEBOOK_APP_ID,repo_url:c.sourceUrl,proxy:c.edge?'Caddy (Docker)':'none',backend_port:back,frontend_port:front,PORT_WUZAPI:'8090',versao_instalacao:'main',commit_instalacao:'Revisão oficial obtida após confirmação'}));
  text('Diretório da instalação: '+(typeof directory==='function'?directory(c):directory));
  text('PostgreSQL, Redis e transcrição: portas internas da rede Docker. API Oficial: 6000; WuzAPI: 8090.');
  if(!/^s$/i.test(await extra('Os dados estão corretos? S/N','n')))throw Error('Instalação cancelada antes de criar recursos.');
  text(' >> Continuando a Instalação...');
  out(render('optimize'));
  const profile=await extra('','0');
  if(!['0','1','2','3'].includes(profile))throw Error('Perfil PostgreSQL inválido. Nenhum recurso criado.');
  if(profile!=='0')c.options.pg=structuredClone(PG_PROFILES[{'1':'small','2':'medium','3':'large'}[profile]]);
  return normalizeConfig(c);
}
module.exports={render,labels,collectHistorical};
