const fs = require('node:fs');
const path = require('node:path');
const readline = require('node:readline/promises');
const { Manager, normalizeConfig, SOURCE } = require('./manager.cjs');
const { Menus }=require('./menus.cjs');
const { createUI }=require('./ui.cjs');
const ui=createUI();

function configInput(file) {
  try { return JSON.parse(fs.readFileSync(file,'utf8')); }
  catch { throw Error('Não foi possível ler o JSON de configuração. Revise o arquivo privado.'); }
}

async function ask(label, fallback, secret = false) {
  if (!process.stdin.isTTY) throw Error('Use --config com JSON para execução não interativa.');
  if (!secret) {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    try { const value = await rl.question(ui.question(label,fallback)); return value || fallback || ''; } finally { rl.close(); }
  }
  process.stdout.write(ui.question(label));
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
async function installInput(configFile,options={}) {
  if(configFile)return normalizeConfig(configInput(configFile));
  return require('./wizard.cjs').collectInstallation({question:ask,...options});
}
async function main() {
  const args = process.argv.slice(2); let action = args.shift() || 'menu', configFile,initial;
  while (args.length) { const flag=args.shift();if(!args.length)throw Error('Argumentos inválidos.');if(flag==='--config')configFile=args.shift();else if(flag==='--initial')initial=args.shift();else throw Error('Argumentos inválidos.'); }
  if (action === 'help') {
    console.log(`AMANDA — gerenciador inteiramente em containers
Uso: sh instalador_single.sh [comando] --dir /pasta/da/instalacao [--config /arquivo.json]
Comandos: install, update, resume, adopt, start, stop, restart, status, logs, backup, doctor, build-token, unlock
Sem comando: menu interativo. Source obrigatório: ${SOURCE}
A base e os serviços opcionais usam o Compose oficial. Caddy é opcional para HTTPS.
stop preserva volumes. update gera backup e não executa seeds.
adopt verifica uma instalação oficial existente antes de registrá-la.
Node, Git, Compose, Buildx, ferramentas de banco e compiladores rodam em containers.`); return;
  }
  const manager = new Manager(process.env.AMANDA_INSTALL_DIR || '/opt/amanda');
  if (action === 'menu') {
    if(!process.stdin.isTTY)throw Error('O menu requer terminal interativo. Para instalar sem interação use install --config /arquivo.json.');
    return new Menus(manager,ask,context=>installInput(configFile,{directory:context?.parent?c=>path.join(context.parent,'instances',c.project):manager.root,getResources:()=>manager.resources()}),{initial,install:(m,input)=>m.lock(async()=>{await m.doctor();await m.prepare(input);await m.build();await m.initialize();})}).run();
  }
  if (action === 'doctor') return manager.doctor();
  if (action === 'unlock') { await manager.doctor(); return manager.unlock(); }
  if (action === 'install') {
    const input = await installInput(configFile,{directory:manager.root,getResources:()=>manager.resources()});
    return manager.lock(async () => { await manager.doctor(); await manager.prepare(input); await manager.build(); await manager.initialize(); });
  }
  if (action === 'adopt') {
    const url = configFile ? configInput(configFile).sourceUrl : await ask('Link da plataforma existente (obrigatório)');
    return manager.lock(async () => { await manager.doctor(); await manager.adopt(url); });
  }
  if (action === 'build-token') {
    return manager.lock(async () => { manager.load(); await manager.identifyManager(); const token = await ask('Novo token de leitura do conector (não exibido)', undefined, true); if (!token || /[\r\n]/.test(token)) throw Error('Token vazio/inválido.'); manager.write(path.join(manager.state.platform,'.secrets/github_token'),token); console.log('Segredo de build atualizado fora do Git.'); });
  }
  if (['status','logs'].includes(action)) return manager.execute(action);
  return manager.lock(() => manager.execute(action));
}
if (require.main === module) main().catch(error => { console.error('ERRO: ' + error.message); process.exitCode = 1; });
module.exports = { main, installInput };
