const fs = require('node:fs');
const path = require('node:path');
const readline = require('node:readline/promises');
const { Manager, normalizeConfig, SOURCE } = require('./manager.cjs');

function configInput(file) {
  try { return JSON.parse(fs.readFileSync(file,'utf8')); }
  catch { throw Error('Não foi possível ler o JSON de configuração. Revise o arquivo privado.'); }
}

async function ask(label, fallback, secret = false) {
  if (!process.stdin.isTTY) throw Error('Use --config com JSON para execução não interativa.');
  if (!secret) {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    try { const value = await rl.question(label + (fallback !== undefined ? ` [${fallback}]` : '') + ': '); return value || fallback || ''; } finally { rl.close(); }
  }
  process.stdout.write(label + ': ');
  return new Promise((resolve, reject) => {
    let value = '';
    const previous = process.stdin.isRaw;
    process.stdin.setRawMode(true); process.stdin.resume();
    const cleanup = () => { process.stdin.removeListener('data', receive); process.stdin.setRawMode(previous); process.stdin.pause(); process.stdout.write('\n'); };
    const receive = buffer => {
      for (const ch of buffer.toString()) {
        if (ch === '\u0003' || ch === '\u0004') { cleanup(); reject(Error('Entrada cancelada.')); return; }
        if (ch === '\r' || ch === '\n') { cleanup(); resolve(value); return; }
        if (ch === '\u007f' || ch === '\b') value = value.slice(0,-1);
        else if (ch >= ' ' && value.length < 4096) value += ch;
      }
    };
    process.stdin.on('data', receive);
  });
}
async function installInput(configFile) {
  if (configFile) return normalizeConfig(configInput(configFile));
  const sourceUrl = await ask('Link da plataforma (obrigatório)');
  const project = await ask('Nome único do projeto Docker', 'amanda');
  const edge = /^s(im)?$/i.test(await ask('Usar HTTPS com Caddy em container (DNS já configurado)', 'n'));
  const frontendUrl = await ask('URL de acesso ao frontend', edge ? undefined : 'http://localhost:3000');
  const backendUrl = await ask('URL de acesso ao backend', edge ? undefined : 'http://localhost:8080');
  const publish = edge ? false : /^s(im)?$/i.test(await ask('Publicar as portas na rede, além do próprio servidor', 'n'));
  let adminEmail = 'admin@amanda.com.br', adminPassword = 'adminamanda';
  if (/^s(im)?$/i.test(await ask('Personalizar o acesso padrão admin@amanda.com.br / adminamanda', 'n'))) {
    adminEmail = await ask('E-mail do administrador');
    adminPassword = await ask('Senha do administrador', undefined, true);
    if (adminPassword !== await ask('Confirme a senha', undefined, true)) throw Error('Confirmação de senha diferente.');
  }
  const sourceToken = await ask('Token de leitura da plataforma, apenas se o repositório for privado (vazio para público)', undefined, true);
  const buildToken = await ask('Token de leitura do conector privado, usado somente como segredo BuildKit', undefined, true);
  return normalizeConfig({ sourceUrl, project, frontendUrl, backendUrl, public: publish, edge, adminEmail, adminPassword, sourceToken, buildToken });
}
async function main() {
  const args = process.argv.slice(2); let action = args.shift() || 'menu', configFile;
  while (args.length) { if (args.shift() !== '--config' || !args.length) throw Error('Argumentos inválidos.'); configFile = args.shift(); }
  if (action === 'help') {
    console.log(`AMANDA — gerenciador inteiramente em containers
Uso: sh instalador_single.sh [comando] --dir /pasta/da/instalacao [--config /arquivo.json]
Comandos: install, update, resume, adopt, start, stop, restart, status, logs, backup, doctor, build-token, unlock
Sem comando: menu interativo. Source obrigatório: ${SOURCE}
Todos os oito serviços usam o Compose oficial. Caddy é opcional para HTTPS.
stop preserva volumes. update gera backup e não executa seeds.
adopt verifica uma instalação oficial existente antes de registrá-la.
Node, Git, Compose, Buildx, ferramentas de banco e compiladores rodam em containers.`); return;
  }
  const manager = new Manager(process.env.AMANDA_INSTALL_DIR || '/opt/amanda');
  if (action === 'menu') {
    const actions = ['install','update','status','start','stop','restart','logs','backup','resume','adopt','doctor','build-token'];
    actions.forEach((v,i) => console.log(`${i+1} - ${v}`));
    const selected = await ask('Escolha uma operação'); action = actions[Number(selected)-1];
    if (!action) throw Error('Opção inválida.');
  }
  if (action === 'doctor') return manager.doctor();
  if (action === 'unlock') { await manager.doctor(); return manager.unlock(); }
  if (action === 'install') {
    const input = await installInput(configFile);
    return manager.lock(async () => { await manager.doctor(); await manager.prepare(input); await manager.build(); await manager.initialize(); });
  }
  if (action === 'adopt') {
    const url = configFile ? configInput(configFile).sourceUrl : await ask('Link da plataforma existente (obrigatório)');
    return manager.lock(async () => { await manager.doctor(); await manager.adopt(url); });
  }
  if (action === 'build-token') {
    return manager.lock(async () => { manager.load(); const token = await ask('Novo token de leitura do conector (não exibido)', undefined, true); if (!token || /[\r\n]/.test(token)) throw Error('Token vazio/inválido.'); manager.write(path.join(manager.state.platform,'.secrets/github_token'),token); console.log('Segredo de build atualizado fora do Git.'); });
  }
  if (['status','logs'].includes(action)) return manager.execute(action);
  return manager.lock(() => manager.execute(action));
}
if (require.main === module) main().catch(error => { console.error('ERRO: ' + error.message); process.exitCode = 1; });
module.exports = { main, installInput };
