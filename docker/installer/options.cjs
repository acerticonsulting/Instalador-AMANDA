const fs = require('node:fs');
const crypto = require('node:crypto');

const GROUPS = {
  identity: [['appName','Título da aplicação','AMANDA'],['supportPhone','Telefone de suporte','']],
  email: [['MAIL_HOST','Servidor SMTP',''],['MAIL_PORT','Porta SMTP','587'],['MAIL_SECURE','TLS implícito (true para 465; false para STARTTLS/587)','false'],['MAIL_USER','Usuário SMTP',''],['MAIL_PASS','Senha SMTP','',true],['MAIL_FROM','E-mail do remetente SMTP','']],
  facebook: [['FACEBOOK_APP_ID','Facebook App ID',''],['FACEBOOK_APP_SECRET','Facebook App Secret','',true]],
  integrations: [['TRANSCRIBE_URL','URL interna da transcrição','http://api_transcricao:4002'],['URL_API_OFICIAL','URL interna da API Oficial','http://api_oficial:6000'],['WUZAPI_URL','URL interna WuzAPI','http://wuzapi:8080'],['HUB_CENTRAL_URL','URL do HUB externo',''],['HUB_ADMIN_API_KEY','Chave administrativa HUB','',true]],
  google: [['GOOGLE_CLIENT_ID','Google OAuth Client ID',''],['GOOGLE_CLIENT_SECRET','Google OAuth Client Secret','',true]],
  ai: [['OPENAI_API_KEY','Chave OpenAI para fallback de transcrição do IVR de voz','',true]],
};
const INITIAL_SETTINGS=['signupSmtpFromName','activePaymentGateway','stripeprivatekey','asaastoken','asaassandbox','mpaccesstoken','mpnotificationurl','mpsandbox'];
const PG_PROFILES={small:{maxConnections:100,sharedBuffers:'128MB'},medium:{maxConnections:200,sharedBuffers:'256MB'},large:{maxConnections:300,sharedBuffers:'512MB'}};
function validatePg(pg, memory){
  if(!pg||Object.keys(pg).some(k=>!['maxConnections','sharedBuffers'].includes(k))||!Number.isInteger(pg.maxConnections)||pg.maxConnections<20||pg.maxConnections>500||!/^([1-9][0-9]*)(MB|GB)$/.test(pg.sharedBuffers||''))throw Error('PostgreSQL: use 20–500 conexões e shared_buffers em MB/GB.');
  const [,amount,unit]=pg.sharedBuffers.match(/^(\d+)(MB|GB)$/),bytes=Number(amount)*1024**(unit==='GB'?3:2);
  if(bytes<32*1024**2||bytes>4*1024**3)throw Error('PostgreSQL: shared_buffers deve ficar entre 32MB e 4GB.');
  if(memory&& (bytes>memory/4||bytes+pg.maxConnections*5*1024**2>memory*0.75))throw Error('Perfil PostgreSQL excede o orçamento de memória do Docker; reduza conexões/buffers.');
  return pg;
}
function selectedServices(options={}){
  const flags={official:true,wuzapi:true,rabbit:true,...options.services};
  return ['postgres','redis','backend','frontend','api_transcricao',...(flags.official?['api_oficial']:[]),...(flags.wuzapi?['wuzapi']:[]),...(flags.rabbit?['rabbitmq']:[])];
}
function literal(value) {
  value = String(value);
  if (/[\r\n\0]/.test(value)) throw Error('Valor com quebra de linha não permitido.');
  return JSON.stringify(value.replace(/\$/g,()=> '$$'));
}
function writeEnv(file, changes) {
  let text = fs.existsSync(file) ? fs.readFileSync(file,'utf8') : '';
  for (const [key,value] of Object.entries(changes)) {
    if (!/^[A-Z_][A-Z0-9_]*$/.test(key)) throw Error('Chave de ambiente inválida.');
    const line = key + '=' + literal(value), re = new RegExp('^'+key+'=.*$','gm');
    let found=false;text=text.replace(re,()=>{if(found)return '';found=true;return line;});
    if(!found)text=text.replace(/\s*$/,'\n')+line+'\n';
  }
  fs.writeFileSync(file,text,{mode:0o600}); fs.chmodSync(file,0o600);
}
function validateOptions(options = {}) {
  const allowed = ['appName','supportPhone','databasePassword','masterPassword','officialPort','wuzapiPort','officialUrl','backendEnv','services','pg','officialToken','wuzapiToken','testSmtp','pushEmail','initialSettings'];
  for (const key of Object.keys(options)) if (!allowed.includes(key)) throw Error('Configuração adicional desconhecida: '+key);
  for (const [key,v] of Object.entries(options)) if (key !== 'backendEnv' && /[\r\n\0]/.test(String(v))) throw Error('Valor inválido: '+key);
  if (options.appName !== undefined && (typeof options.appName !== 'string' || !options.appName.trim() || options.appName.length>120)) throw Error('Título inválido.');
  if (options.supportPhone !== undefined && !/^[+0-9 ()-]{0,30}$/.test(options.supportPhone)) throw Error('Telefone inválido.');
  for (const key of ['databasePassword','masterPassword']) if (options[key] !== undefined && (typeof options[key] !== 'string' || !options[key] || options[key].length>256)) throw Error('Senha inválida: '+key);
  for(const key of ['officialToken','wuzapiToken'])if(options[key]!==undefined&&(typeof options[key]!=='string'||options[key].length<16||options[key].length>256))throw Error('Token interno deve conter 16–256 caracteres: '+key);
  if(options.pg)validatePg(options.pg);
  if(options.testSmtp!==undefined&&typeof options.testSmtp!=='boolean')throw Error('testSmtp deve ser booleano.');
  if(options.pushEmail!==undefined&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(options.pushEmail))throw Error('E-mail VAPID inválido.');
  if(options.services!==undefined){if(!options.services||typeof options.services!=='object'||Array.isArray(options.services)||Object.entries(options.services).some(([k,v])=>!['official','wuzapi','rabbit'].includes(k)||typeof v!=='boolean'))throw Error('Seleção de serviços inválida.');if(options.services.official===false&&options.services.rabbit!==false)throw Error('RabbitMQ requer API Oficial; desabilite ambos.');}
  if(options.initialSettings!==undefined){if(!options.initialSettings||typeof options.initialSettings!=='object'||Array.isArray(options.initialSettings))throw Error('Configurações iniciais inválidas.');for(const[k,v]of Object.entries(options.initialSettings)){if(!INITIAL_SETTINGS.includes(k)||typeof v!=='string'||/[\r\n\0]/.test(v)||v.length>4096)throw Error('Configuração inicial inválida: '+k);if(k==='activePaymentGateway'&&!['none','stripe','asaas','mercadopago'].includes(v))throw Error('Gateway de pagamento inválido.');if(['asaassandbox','mpsandbox'].includes(k)&&!['true','false'].includes(v))throw Error('Sandbox deve ser true ou false.');if(k==='mpnotificationurl'&&v)validateUrl(v,k);}}
  for (const key of ['officialPort','wuzapiPort']) if (options[key] !== undefined && (!Number.isInteger(options[key]) || options[key]<1 || options[key]>65535)) throw Error('Porta inválida: '+key);
  if(options.officialUrl){const u=new URL(options.officialUrl);if(u.protocol!=='https:'||u.port||u.username||u.password||u.search||u.hash||u.pathname!=='/'||!/^[a-z0-9.-]+\.[a-z]{2,}$/i.test(u.hostname)||u.hostname.length>253||u.hostname.split('.').some(label=>! /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i.test(label)))throw Error('URL HTTPS da API Oficial inválida.');}
  const env = options.backendEnv || {};
  const keys = new Set(Object.values(GROUPS).flat().map(x=>x[0]).filter(k=>/^[A-Z_]+$/.test(k)));

  for (const [k,v] of Object.entries(env)) {
    if (!keys.has(k) || typeof v !== 'string' || /[\r\n\0]/.test(v)) throw Error('Configuração backend inválida: '+k);
    if ((k.endsWith('_URL')||k==='URL_API_OFICIAL') && v) validateUrl(v,k);
    if(k==='MAIL_SECURE'&&!['true','false'].includes(v))throw Error('MAIL_SECURE deve ser true ou false.');
    if(k==='MAIL_HOST'&&v&&!/^[a-z0-9.-]+$/i.test(v))throw Error('Host SMTP inválido.');
    if(k==='MAIL_FROM'&&v&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v))throw Error('Remetente SMTP inválido.');
    if (k==='MAIL_PORT' && (!/^\d+$/.test(v)||+v<1||+v>65535))throw Error('Porta SMTP inválida.');
  }
  return options;
}
function validateUrl(value,key){let u;try{u=new URL(value);}catch{throw Error('URL inválida: '+key);}if(!['http:','https:'].includes(u.protocol)||u.username||u.password||u.hash||u.search)throw Error('URL inválida: '+key);return u;}
async function digest(file) {
  const hash=crypto.createHash('sha256');for await(const chunk of fs.createReadStream(file))hash.update(chunk);return hash.digest('hex');
}
function vapidPrivateKey(bytes){
  if(!Buffer.isBuffer(bytes)||bytes.length<1||bytes.length>32)throw Error('Escalar P-256 inválido.');
  return Buffer.concat([Buffer.alloc(32-bytes.length),bytes]).toString('base64url');
}
module.exports = { GROUPS, INITIAL_SETTINGS, PG_PROFILES, validatePg, selectedServices, validateUrl, literal, writeEnv, validateOptions, digest,vapidPrivateKey };
