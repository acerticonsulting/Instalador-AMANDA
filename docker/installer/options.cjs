const fs = require('node:fs');
const crypto = require('node:crypto');

const GROUPS = {
  identity: [['appName','Título da aplicação','AMANDA'],['supportPhone','Telefone de suporte','']],
  email: [['MAIL_HOST','Servidor SMTP',''],['MAIL_PORT','Porta SMTP','587'],['MAIL_USER','Usuário SMTP',''],['MAIL_PASS','Senha SMTP','',true],['MAIL_FROM','Remetente SMTP','']],
  facebook: [['FACEBOOK_APP_ID','Facebook App ID',''],['FACEBOOK_APP_SECRET','Facebook App Secret','',true]],
  integrations: [['TRANSCRIBE_URL','URL interna da transcrição','http://api_transcricao:4002'],['URL_API_OFICIAL','URL interna da API Oficial','http://api_oficial:6000'],['WUZAPI_URL','URL interna WuzAPI','http://wuzapi:8080'],['HUB_CENTRAL_URL','URL do HUB externo',''],['HUB_ADMIN_API_KEY','Chave administrativa HUB','',true]],
};
function literal(value) {
  value = String(value);
  if (/[\r\n\0]/.test(value)) throw Error('Valor com quebra de linha não permitido.');
  return JSON.stringify(value.replace(/\$/g,'$$'));
}
function writeEnv(file, changes) {
  let text = fs.existsSync(file) ? fs.readFileSync(file,'utf8') : '';
  for (const [key,value] of Object.entries(changes)) {
    if (!/^[A-Z_][A-Z0-9_]*$/.test(key)) throw Error('Chave de ambiente inválida.');
    const line = key + '=' + literal(value), re = new RegExp('^'+key+'=.*$','m');
    text = re.test(text) ? text.replace(re,()=>line) : text.replace(/\s*$/,'\n') + line + '\n';
  }
  fs.writeFileSync(file,text,{mode:0o600}); fs.chmodSync(file,0o600);
}
function validateOptions(options = {}) {
  const allowed = ['appName','supportPhone','databasePassword','masterPassword','officialPort','wuzapiPort','officialUrl','backendEnv'];
  for (const key of Object.keys(options)) if (!allowed.includes(key)) throw Error('Configuração adicional desconhecida: '+key);
  for (const [key,v] of Object.entries(options)) if (key !== 'backendEnv' && /[\r\n\0]/.test(String(v))) throw Error('Valor inválido: '+key);
  if (options.appName !== undefined && (typeof options.appName !== 'string' || !options.appName.trim() || options.appName.length>120)) throw Error('Título inválido.');
  if (options.supportPhone !== undefined && !/^[+0-9 ()-]{0,30}$/.test(options.supportPhone)) throw Error('Telefone inválido.');
  for (const key of ['databasePassword','masterPassword']) if (options[key] !== undefined && (typeof options[key] !== 'string' || !options[key] || options[key].length>256)) throw Error('Senha inválida: '+key);
  for (const key of ['officialPort','wuzapiPort']) if (options[key] !== undefined && (!Number.isInteger(options[key]) || options[key]<1 || options[key]>65535)) throw Error('Porta inválida: '+key);
  if(options.officialUrl){const u=new URL(options.officialUrl);if(u.protocol!=='https:'||u.port||u.username||u.password||u.search||u.hash||u.pathname!=='/'||!/^[a-z0-9.-]+\.[a-z]{2,}$/i.test(u.hostname))throw Error('URL HTTPS da API Oficial inválida.');}
  const env = options.backendEnv || {};
  const keys = new Set(Object.values(GROUPS).flat().map(x=>x[0]).filter(k=>/^[A-Z_]+$/.test(k)));

  for (const [k,v] of Object.entries(env)) {
    if (!keys.has(k) || typeof v !== 'string' || /[\r\n\0]/.test(v)) throw Error('Configuração backend inválida: '+k);
    if (k.endsWith('_URL') && v) { const u=new URL(v); if(!['http:','https:'].includes(u.protocol)||u.username||u.password||u.hash)throw Error('URL inválida: '+k); }
    if (k==='MAIL_PORT' && (!/^\d+$/.test(v)||+v<1||+v>65535))throw Error('Porta SMTP inválida.');
  }
  return options;
}
async function digest(file) {
  const hash=crypto.createHash('sha256');for await(const chunk of fs.createReadStream(file))hash.update(chunk);return hash.digest('hex');
}
module.exports = { GROUPS, literal, writeEnv, validateOptions, digest };
