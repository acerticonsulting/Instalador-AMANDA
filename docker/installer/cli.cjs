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
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  // Segredos têm digitação visível, mas nunca são apresentados como padrão.
  try { const value = await rl.question(label===''?'\n> ':ui.question(label,secret?undefined:fallback)); return value || fallback || ''; } finally { rl.close(); }
}

async function advancedInput(configFile,options={}) {
  if(configFile)return normalizeConfig(configInput(configFile));
  return require('./wizard.cjs').collectInstallation({question:ask,checkDomains:require('./domain-preflight.cjs').checker(new Manager(process.env.AMANDA_INSTALL_DIR||require('./deploy.cjs').BASE)),...options});
}
async function installInput(configFile,options={}) {
  if(configFile)return normalizeConfig(configInput(configFile));
  return require('./historical.cjs').collectHistorical({question:ask,checkDomains:require('./domain-preflight.cjs').checker(new Manager(process.env.AMANDA_INSTALL_DIR||require('./deploy.cjs').BASE)),...options});
}
async function main() {
  const args = process.argv.slice(2); let action = args.shift() || 'menu', configFile,initial;
  while (args.length) { const flag=args.shift();if(!args.length)throw Error('Argumentos inválidos.');if(flag==='--config')configFile=args.shift();else if(flag==='--initial')initial=args.shift();else throw Error('Argumentos inválidos.'); }
  console.log(require('./revision.cjs').revisionLine());
  if (action === 'help') {
    console.log(`AMANDA — gerenciador inteiramente em containers
Uso: sh instalador_single.sh [comando] --dir /pasta/da/instalacao [--config /arquivo.json]
Comandos: install, update, resume, adopt, start, stop, restart, status, logs, backup, doctor, https-diagnose, state-diagnose, build-token, unlock
Administração: configure, instances, official, urls, services, ssl, postgres
Compatibilidade: scripts históricos encaminham para operações em Docker; receitas nativas ficam indisponíveis.
O assistente histórico é o padrão. wizard mantém o assistente adicional de 11 etapas.
Sem comando: menu interativo. Source obrigatório: ${SOURCE}
A base e os serviços opcionais usam o Compose oficial. Caddy é opcional para HTTPS.
stop preserva volumes. update gera backup e não executa seeds.
adopt verifica uma instalação oficial existente antes de registrá-la.
Node, Git, Compose, Buildx, ferramentas de banco e compiladores rodam em containers.`); return;
  }
  const deploy=require('./deploy.cjs'),automatic=process.env.AMANDA_DEPLOY_LAYOUT==='1';
  let manager = new Manager(process.env.AMANDA_INSTALL_DIR || deploy.BASE);
  if(action==='state-diagnose')return console.log(JSON.stringify(require('./directory-state.cjs').diagnoseDirectory(manager.root,{project:path.basename(manager.root),owner:deploy.hostOwner()}),null,2));
  if(action==='https-diagnose'){manager.load();return require('./edge-diagnostics.cjs').diagnoseEdge(manager);}
  const directory=(context,m=manager)=>automatic?c=>deploy.companyDirectory(c.project):context?.parent?c=>path.join(context.parent,'instances',c.project):m.root;
  const startInstall=(m,context)=>deploy.startInstallation(m,{question:ask,config:configFile?configInput(configFile):undefined,directory:directory(context,m),automatic,collect:options=>(action==='wizard'?advancedInput:installInput)(undefined,{question:ask,...options,getResources:()=>m.resources()}),manage:target=>new Menus(target,ask,null,{startInstall}).run()});
  if (action === 'menu') {
    if(!process.stdin.isTTY)throw Error('O menu requer terminal interativo. Para instalar sem interação use install --config /arquivo.json.');
    return new Menus(manager,ask,context=>installInput(configFile,{directory:directory(context),getResources:()=>manager.resources()}),{initial,startInstall}).run();
  }
  if(automatic&&!['menu','install','wizard','doctor','instances'].includes(action)){
    const selection=new Menus(manager,ask,null);await selection.selectInstance();manager=selection.m;
    if(!fs.existsSync(manager.stateFile))throw Error('Selecione a instalação existente com --dir /home/deploy/empresa (ou seu caminho histórico).');
  }
  if (action === 'doctor') return manager.doctor();
  if(action==='migration-plan')return manager.lock(async()=>console.log(JSON.stringify(await deploy.migrationPlan(manager),null,2)));
  if (action === 'unlock') { await manager.doctor(); return manager.unlock(); }
  if(['configure','instances','urls','services','official','ssl','push','postgres','optional-service','rollback','schedule-backup','wuzapi-start','native-unavailable','channels-unavailable','external-unavailable','helper-unavailable'].includes(action))return new Menus(manager,ask,context=>installInput(configFile,{directory:directory(context)}),{startInstall}).dispatch(action);
  if (action === 'install'||action==='wizard') return startInstall(manager);
  if (action === 'adopt') {
    const url = configFile ? configInput(configFile).sourceUrl : await ask('Link da plataforma existente (obrigatório)');
    return manager.lock(async () => { await manager.doctor(); await manager.adopt(url); });
  }
  if(action==='resume'){
    manager.recoveryQuestion=process.stdin.isTTY?ask:undefined;
    let project;try{project=JSON.parse(fs.readFileSync(manager.stateFile,'utf8')).project;}catch{throw Error('Estado ausente ou inválido em '+manager.root+'. Nenhum arquivo foi alterado.');}
    const info=deploy.inspectInstallation(manager.root,project);if(info.kind==='unknown')throw Error(require('./directory-state.cjs').conflict(info));
  }
  if (action === 'build-token') {
    console.log('O backend usa dependências públicas. Nenhum token de conector é necessário.'); return;
  }
  if (['status','logs'].includes(action)) return manager.execute(action);
  return manager.lock(() => manager.execute(action));
}
if (require.main === module) main().catch(error => { console.error('ERRO: ' + error.message); process.exitCode = 1; });
module.exports = { main, installInput, advancedInput, ask };
