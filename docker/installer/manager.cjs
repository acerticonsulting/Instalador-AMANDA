const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');
const { AsyncLocalStorage } = require('node:async_hooks');
const { validateOptions, writeEnv, digest } = require('./options.cjs');

const SOURCE = 'https://github.com/acerticonsulting/AMANDA.git';
const CORE = ['postgres', 'redis', 'backend', 'frontend', 'api_transcricao', 'api_oficial', 'wuzapi', 'rabbitmq'];
const PROFILES = ['official', 'whatsmeow', 'rabbit'];
function sourceUrl(value) {
  if (typeof value !== 'string' || !/^https:\/\/github\.com\/acerticonsulting\/AMANDA(?:\.git)?\/?$/.test(value.trim())) throw Error('Informe o link autorizado: https://github.com/acerticonsulting/AMANDA');
  return SOURCE;
}
function rootPath(value) {
  const root = path.resolve(value);
  const protectedPaths = ['/etc', '/usr', '/bin', '/sbin', '/dev', '/proc', '/sys', '/run', '/var/lib/docker'];
  if (root === path.parse(root).root || /[\r\n,:]/.test(root) || protectedPaths.some(p => root === p || root.startsWith(p + path.sep))) throw Error('Use um diretório exclusivo para a AMANDA.');
  return root;
}
function normalizeConfig(input) {
  const allowed = ['sourceUrl', 'project', 'frontendUrl', 'backendUrl', 'public', 'edge', 'adminEmail', 'adminPassword', 'sourceToken', 'buildToken','options'];
  for (const key of Object.keys(input)) if (!allowed.includes(key)) throw Error('Campo de configuração desconhecido: ' + key);
  const c = { project: 'amanda', frontendUrl: 'http://localhost:3000', backendUrl: 'http://localhost:8080', public: false, edge: false, adminEmail: 'admin@amanda.com.br', adminPassword: 'adminamanda', ...input };
  c.sourceUrl = sourceUrl(c.sourceUrl);
  if(typeof c.project!=='string')throw Error('Nome do projeto inválido.');
  c.project=c.project.trim().normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[ -]+/g,'_');
  if (!/^[a-z0-9][a-z0-9_]{0,39}$/.test(c.project)) throw Error('Nome do projeto inválido.');
  if (typeof c.public !== 'boolean' || typeof c.edge !== 'boolean') throw Error('public e edge devem ser booleanos.');
  for (const key of ['frontendUrl', 'backendUrl']) {
    const u = new URL(c[key]);
    if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password || u.search || u.hash || u.pathname !== '/') throw Error('URL inválida: ' + key);
    c[key] = u.origin;
  }
  const front = new URL(c.frontendUrl), back = new URL(c.backendUrl);
  c.options=validateOptions(c.options);
  if(c.options.officialUrl&&(!c.edge||[front.hostname,back.hostname].includes(new URL(c.options.officialUrl).hostname)))throw Error('A API Oficial pública requer Caddy/HTTPS e domínio próprio diferente do frontend/backend.');
  if (c.edge) {
    if(new Set([80,443,3000,8080,c.options.officialPort||6000,c.options.wuzapiPort||8090]).size!==6)throw Error('Portas da API Oficial/WuzAPI conflitam com o proxy, frontend ou backend.');
    for (const u of [front, back]) if (u.protocol !== 'https:' || u.port || !/^[a-z0-9.-]+\.[a-z]{2,}$/i.test(u.hostname)) throw Error('HTTPS/Caddy exige dois domínios DNS e porta 443.');
    if (front.hostname === back.hostname) throw Error('Use domínios diferentes para frontend e backend.');
  } else {
    if (front.protocol !== 'http:' || back.protocol !== 'http:') throw Error('Para HTTPS, habilite edge/Caddy.');
    const ports = [front.port || '80', back.port || '80', String(c.options.officialPort || 6000), String(c.options.wuzapiPort || 8090)];
    if (new Set(ports).size !== ports.length) throw Error('As portas de frontend, backend, API Oficial (6000) e WuzAPI (8090) devem ser diferentes.');
    if (!c.public && [front, back].some(u => !['localhost', '127.0.0.1', '[::1]'].includes(u.hostname))) throw Error('URLs de rede exigem public=true ou HTTPS/Caddy.');
  }
  c.adminEmail = String(c.adminEmail).trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(c.adminEmail)) throw Error('E-mail administrativo inválido.');
  if (typeof c.adminPassword !== 'string' || !c.adminPassword || c.adminPassword.length > 256 || /[\r\n\0]/.test(c.adminPassword)) throw Error('Senha administrativa inválida.');
  for (const key of ['sourceToken', 'buildToken']) if (c[key] !== undefined && (typeof c[key] !== 'string' || c[key].length > 4096 || /[\r\n\0]/.test(c[key]))) throw Error('Credencial Git inválida.');
  return c;
}
function envValues(file) {
  const env = {};
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^([A-Z_][A-Z0-9_]*)=(.*)$/);
    if (!m) continue;
    let v = m[2];
    if (v.startsWith('"') && v.endsWith('"')) { try { v = JSON.parse(v); } catch {} }
    else if (v.startsWith("'") && v.endsWith("'")) v = v.slice(1, -1).replace(/\\'/g, "'");
    env[m[1]] = v;
  }
  return env;
}
function editEnv(file, changes) {
  let text = fs.readFileSync(file, 'utf8');
  for (const [key, value] of Object.entries(changes)) {
    const val = String(value);
    if (/[\r\n\0$'"#]/.test(val)) throw Error('Valor inválido para ' + key);
    const re = new RegExp('^' + key + '=.*$', 'm');
    text = re.test(text) ? text.replace(re, () => key + '=' + val) : text.replace(/\s*$/, '\n') + key + '=' + val + '\n';
  }
  fs.writeFileSync(file, text, { mode: 0o600 });
}
class Runner {
  constructor(logFile, output = process.stdout) { this.logFile = logFile; this.output = output; this.secrets = new Set(); }
  secret(value) { if (value && value !== 'adminamanda') this.secrets.add(String(value)); }
  mask(value) {
    let s = String(value);
    for (const secret of [...this.secrets].sort((a,b) => b.length-a.length)) s = s.split(secret).join('[oculto]');
    return s.replace(/\b(?:ghp_|github_pat_)[A-Za-z0-9_]+/g, '[token-oculto]').replace(/Bearer\s+\S+/gi, 'Bearer [oculto]').replace(/eyJ[\w-]+\.[\w-]+\.[\w-]+/g, '[jwt-oculto]');
  }
  emit(text) {
    const safe = this.mask(text); this.output.write(safe);
    if (this.logFile) { fs.mkdirSync(path.dirname(this.logFile), { recursive: true, mode: 0o700 }); fs.appendFileSync(this.logFile, safe, { mode: 0o600 }); }
  }
  async run(bin, args, options = {}) {
    const { quiet = false, label = bin, env = {}, cwd, allowFailure = false, outputFile, inputFile } = options;
    if (!quiet) this.emit('\n' + label + '\n');
    return new Promise((resolve, reject) => {
      const child = spawn(bin, args, { cwd, env: { ...process.env, ...env }, stdio: [inputFile ? 'pipe' : 'ignore','pipe','pipe'], shell: false });
      let stdout = '', stderr = '', line = '', ended = false, ioError = false;
      const destination = outputFile ? fs.createWriteStream(outputFile, { flags: 'wx', mode: 0o600 }) : null;
      destination?.on('error', () => { ioError = true; child.kill('SIGTERM'); });
      if (destination) child.stdout.pipe(destination);
      if (inputFile) {
        const source=fs.createReadStream(inputFile);
        source.on('error',()=>{ioError=true;child.kill('SIGTERM');});
        child.stdin.on('error',()=>{ioError=true;child.kill('SIGTERM');});
        child.on('close',()=>source.destroy());source.pipe(child.stdin);
      }
      const timer = setTimeout(() => { child.kill('SIGTERM'); setTimeout(() => { if (!ended) child.kill('SIGKILL'); }, 5000).unref(); }, 45 * 60 * 1000);
      child.stdout.on('data', chunk => {
        if (destination) return;
        else if (quiet) { stdout += chunk; if (stdout.length > 20e6) child.kill('SIGTERM'); }
        else { line += chunk; const lines = line.split('\n'); line = lines.pop(); for (const s of lines) this.emit(s + '\n'); }
      });
      child.stderr.on('data', chunk => { stderr += chunk; if (stderr.length > 2e6) stderr = stderr.slice(-2e6); });
      child.on('error', () => { clearTimeout(timer); destination?.end(); reject(Error(label + ': não foi possível executar o processo no container gerenciador.')); });
      child.on('close', async code => {
        ended = true; clearTimeout(timer);
        if (destination && !ioError && !destination.writableFinished) await new Promise(r => { destination.once('finish',r); destination.once('error',r); });
        if (line) this.emit(line + '\n');
        if (!quiet || code !== 0) { if (stderr) this.emit(stderr + '\n'); }
        if (ioError) reject(Error(label + ': falha gravando arquivo de backup.'));
        else if (code !== 0 && !allowFailure) reject(Error(label + ': falhou (código ' + code + '). Consulte o log protegido.'));
        else resolve({ code, stdout, stderr });
      });
    });
  }
}

class Manager {
  constructor(root, runner) {
    this.root = rootPath(root); this.private = path.join(this.root, '.amanda-installer');
    this.stateFile = path.join(this.private, 'state.json');
    this.runner = runner || new Runner(path.join(this.private, 'install.log'));
    this.operationScope=new AsyncLocalStorage();
  }
  write(file, value) { fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 }); fs.writeFileSync(file, typeof value === 'string' ? value : JSON.stringify(value, null, 2) + '\n', { mode: 0o600 }); }
  save(state) { this.write(this.stateFile + '.tmp', state); fs.renameSync(this.stateFile + '.tmp', this.stateFile); this.state = state; }
  load() {
    const s = JSON.parse(fs.readFileSync(this.stateFile, 'utf8'));
    if (s.schema !== 1 || sourceUrl(s.sourceUrl) !== SOURCE || !/^[a-z0-9][a-z0-9_-]{0,39}$/.test(s.project)) throw Error('Estado do instalador inválido.');
    const relative = path.relative(this.root, s.platform);
    if (relative.startsWith('..') || path.isAbsolute(relative)) throw Error('Plataforma fora do diretório selecionado.');
    const physicalRoot = fs.realpathSync(this.root), physical = fs.realpathSync(s.platform);
    if (physical !== physicalRoot && !physical.startsWith(physicalRoot + path.sep)) throw Error('Link de diretório fora da instalação.');
    this.state = s; this.loadSecrets(); return s;
  }
  loadSecrets() {
    if (!this.state) return;
    for (const file of ['.env','.env.backend','.env.oficial']) {
      const p = path.join(this.state.platform, file);
      if (fs.existsSync(p)) for (const [k,v] of Object.entries(envValues(p))) if (/SECRET|TOKEN|KEY|PASS/.test(k)) this.runner.secret(v);
    }
    for (const p of [path.join(this.state.platform,'.secrets/github_token'),path.join(this.private,'source-token')]) if (fs.existsSync(p)) this.runner.secret(fs.readFileSync(p,'utf8').trim());
    const account = path.join(this.private,'admin-access.json'); if (fs.existsSync(account)) this.runner.secret(JSON.parse(fs.readFileSync(account,'utf8')).password);
  }
  temporaryName(task) { return (this.state?.project || 'amanda')+'_'+task.replace(/[^a-z0-9_]/g,'_')+'_'+crypto.randomUUID().replace(/-/g,''); }
  docker(args, options={}) {
    if(args[0]==='run'&&!args.includes('--name'))args=['run','--name',this.temporaryName('maintenance'),...args.slice(1)];
    const auth=path.join(this.private,'docker-auth');return this.runner.run('docker', args, {...options,env:{...(fs.existsSync(path.join(auth,'config.json'))?{DOCKER_CONFIG:auth}:{}),...options.env}});
  }
  git(args, options = {}) { return this.runner.run('git', ['-c','safe.directory=' + this.state.platform,...args], { cwd: this.state.platform, ...options }); }
  compose(args, options = {}) {
    const s = this.state;
    const run=args.indexOf('run');
    if(run>=0&&!args.includes('--name'))args=[...args.slice(0,run+1),'--name',this.temporaryName('job'),...args.slice(run+1)];
    return this.docker(['compose', '--project-directory', s.platform, '--env-file', path.join(s.platform,'.env'), '-p', s.project, '-f', path.join(s.platform,'docker-compose.yml'), ...(s.naming==='company-v1'?['-f',path.join(this.private,'compose-names.json')]:[]), ...s.profiles.flatMap(p => ['--profile',p]), ...args], { cwd: s.platform, ...options });
  }
  async configureNames() {
    // Read the supplier contract without an override; never edit tracked source.
    const naming=this.state.naming;this.state.naming=undefined;
    let config;try{config=JSON.parse((await this.compose(['--profile','*','config','--format','json'],{quiet:true})).stdout);}finally{this.state.naming=naming;}
    const services={};
    for(const service of Object.keys(config.services))services[service]={container_name:this.state.project+'_'+(service==='edge'?'caddy':service.replace(/-/g,'_'))};
    if(new Set(Object.values(services).map(s=>s.container_name)).size!==Object.keys(services).length)throw Error('Nomes de containers ambíguos no Compose.');
    this.write(path.join(this.private,'compose-names.json'),{services});
  }
  async identifyManager() {
    if(process.env.AMANDA_MANAGER_CONTAINER){
      const id=process.env.HOSTNAME||process.env.AMANDA_MANAGER_CONTAINER,name=this.state.project+'_installer';
      const current=(await this.docker(['inspect','--format','{{.Name}}',id],{quiet:true})).stdout.trim();
      if(current!=='/'+name)await this.docker(['rename',id,name],{quiet:true});
    }
  }
  async doctor() {
    const info = JSON.parse((await this.docker(['info','--format','{{json .}}'], { quiet: true })).stdout);
    if (info.OSType !== 'linux') throw Error('O daemon deve executar containers Linux.');
    await this.docker(['compose','version'], { label: 'Compose do gerenciador' });
    await this.docker(['buildx','version'], { label: 'BuildKit/Buildx do gerenciador' });
    this.runner.emit(`Docker ${info.ServerVersion}; ${info.Architecture}; daemon Linux acessível.\n`);
  }
  async validateSource(requireClean = false) {
    const remote = (await this.git(['remote','get-url','origin'], { quiet: true })).stdout.trim();
    sourceUrl(remote);
    if (requireClean) {
      const dirty = (await this.git(['status','--porcelain','--untracked-files=no'], { quiet: true })).stdout;
      if (dirty.trim()) throw Error('Há alterações locais no código. Preserve/revise o diff antes de atualizar.');
    }
  }
  async configuration() {
    const env = envValues(path.join(this.state.platform,'.env'));
    if ((env.COMPOSE_PROJECT_NAME || 'amanda') !== this.state.project) throw Error('Nome do projeto difere do estado salvo; não trocar volumes automaticamente.');
    const config = JSON.parse((await this.compose(['config','--format','json'], { quiet: true, label: 'Validando Compose oficial' })).stdout);
    for (const name of CORE) if (!config.services[name]) throw Error('Compose não contém o serviço ' + name);
    if(this.state.naming==='company-v1')for(const [key,v]of Object.entries(config.services))if(v.container_name!==this.state.project+'_'+(key==='edge'?'caddy':key.replace(/-/g,'_')))throw Error('Nome de container inesperado: '+key);
    for(const [key,n]of Object.entries(config.networks||{}))if(n.external||n.name!==this.state.project+'_'+key)throw Error('Rede externa ou nome inesperado: '+key);
    for (const [key,v] of Object.entries(config.volumes || {})) if (v.external || v.name !== this.state.project + '_' + key) throw Error('Volume externo ou nome inesperado: ' + key);
    for (const service of Object.values(config.services)) for (const [k,v] of Object.entries(service.environment || {})) if (/SECRET|TOKEN|KEY|PASS/.test(k)) { this.runner.secret(v); if (typeof v === 'string') this.runner.secret(v.replace(/\$\$/g,'$')); }
    config.installerAddons=[];
    if(fs.existsSync(this.private))for(const name of fs.readdirSync(this.private).filter(n=>/^addon-(voz|hub|goflow)\.json$/.test(n))){
      const a=JSON.parse(fs.readFileSync(path.join(this.private,name),'utf8')),kind=name.slice(6,-5),dir=path.join(this.root,'addons',kind);
      if(a.dir!==dir||a.project!==this.state.project+'_'+kind||!/^[A-Za-z0-9_./-]+\.ya?ml$/.test(a.composeFile)||a.composeFile.split('/').includes('..')||path.isAbsolute(a.composeFile))throw Error('Registro de componente inválido.');
      const base=['compose','--project-directory',dir,'--env-file',path.join(this.private,'addon-'+kind+'.env'),'-p',a.project,'-f',path.join(dir,a.composeFile)];
      const extra=JSON.parse((await this.docker([...base,'config','--format','json'],{quiet:true})).stdout);
      if(this.state.naming==='company-v1')for(const[key,v]of Object.entries(extra.services||{}))if(v.container_name!==a.project+'_'+key.replace(/-/g,'_'))throw Error('Nome de container do componente divergente: '+key);
      for(const [key,v]of Object.entries(extra.volumes||{})){if(v.external||v.name!==a.project+'_'+key)throw Error('Volume externo de componente recusado.');config.volumes[kind+'_'+key]=v;}
      for(const service of Object.values(extra.services||{}))for(const[k,v]of Object.entries(service.environment||{}))if(/KEY|TOKEN|SECRET|PASS/.test(k))this.runner.secret(v);
      config.installerAddons.push({...a,base,services:Object.keys(extra.services||{})});
    }
    return config;
  }
  async assertFreshResources() {
    const config = await this.configuration();
    const ids = (await this.docker(['ps','-a','-q','--filter','label=com.docker.compose.project=' + this.state.project], { quiet: true })).stdout.trim();
    const volumes = new Set((await this.docker(['volume','ls','--format','{{.Name}}'], { quiet: true })).stdout.trim().split(/\s+/));
    const networks = new Set((await this.docker(['network','ls','--format','{{.Name}}'], { quiet: true })).stdout.trim().split(/\s+/));
    const names=new Set((await this.docker(['ps','-a','--format','{{.Names}}'],{quiet:true})).stdout.trim().split(/\s+/));
    if (ids || Object.values(config.services).some(s=>s.container_name&&names.has(s.container_name)) || Object.values(config.volumes).some(v => volumes.has(v.name)) || Object.values(config.networks||{}).some(n=>networks.has(n.name)) || networks.has(this.state.project + '_default')) throw Error('Projeto ou volumes já existem. Use adopt para a instalação oficial existente; nenhum seed foi executado.');
  }
  async prepare(input) {
    const c = normalizeConfig(input);
    if (fs.existsSync(this.stateFile)) throw Error('Instalação já registrada; use update ou resume.');
    fs.mkdirSync(this.root, { recursive: true });
    if (fs.readdirSync(this.root).some(p => p !== '.amanda-installer')) throw Error('Diretório não vazio. Escolha uma pasta nova ou use adopt.');
    this.runner.secret(c.adminPassword); this.runner.secret(c.sourceToken); this.runner.secret(c.buildToken);
    this.save({ schema: 1, sourceUrl: SOURCE, project: c.project, frontendUrl: c.frontendUrl, backendUrl: c.backendUrl, platform: path.join(this.root,'platform'), profiles: [...PROFILES, ...(c.edge ? ['edge'] : [])], phase: 'preparing', initialized: false, seedAttempted: false, seedSucceeded: false });
    if (c.sourceToken) this.write(path.join(this.private,'source-token'), c.sourceToken);
    const gitEnv = { GIT_TERMINAL_PROMPT: '0', GIT_ASKPASS: path.join(__dirname,'source-askpass.cjs'), AMANDA_SOURCE_TOKEN_FILE: path.join(this.private,'source-token') };
    await this.runner.run('git',['-c','credential.helper=','clone','--branch','main','--single-branch',SOURCE,this.state.platform], { env: gitEnv, label: 'Obtendo a plataforma autorizada' });
    await this.runner.run(process.execPath,[path.join(this.state.platform,'docker/configure.cjs')], { cwd: this.state.platform, label: 'Gerando configuração privada no container' });
    const f = new URL(c.frontendUrl), b = new URL(c.backendUrl);
    editEnv(path.join(this.state.platform,'.env'), { COMPOSE_PROJECT_NAME: c.project, COMPOSE_PROFILES: this.state.profiles.join(','), USE_WHATSAPP_OFICIAL: 'true', RABBITMQ_ENABLED_GLOBAL: 'true', WUZAPI_URL: 'http://wuzapi:8080', FRONTEND_URL: c.frontendUrl, BACKEND_URL: c.backendUrl, ALLOWED_ORIGINS: c.frontendUrl, BIND_ADDRESS: c.edge || !c.public ? '127.0.0.1' : '0.0.0.0', PORT_FRONTEND: c.edge ? 3000 : (f.port || 80), PORT_BACKEND: c.edge ? 8080 : (b.port || 80), FRONTEND_HOST: f.hostname, BACKEND_HOST: b.hostname });
    if (c.buildToken) this.write(path.join(this.state.platform,'.secrets/github_token'), c.buildToken);
    const o=c.options;
    for(const v of [o.databasePassword,o.masterPassword,...Object.values(o.backendEnv || {})])this.runner.secret(v);
    const rootOptions={PORT_APIOFICIAL:o.officialPort || 6000,PORT_WUZAPI:o.wuzapiPort || 8090,REACT_APP_NUMBER_SUPPORT:o.supportPhone || ''};
    rootOptions.OFICIAL_HOST=o.officialUrl?new URL(o.officialUrl).hostname:'';
    if(o.databasePassword){rootOptions.DB_PASS=o.databasePassword;rootOptions.DB_URI_PASSWORD=encodeURIComponent(o.databasePassword);}
    if(o.masterPassword)rootOptions.MASTER_KEY=o.masterPassword;
    const backendOptions={...o.backendEnv};
    for(const key of ['TRANSCRIBE_URL','URL_API_OFICIAL','WUZAPI_URL','GO_CAMPAIGN_DISPATCHER_URL','USE_GO_CAMPAIGN_DISPATCHER'])if(backendOptions[key]!==undefined){rootOptions[key]=backendOptions[key];delete backendOptions[key];}
    writeEnv(path.join(this.state.platform,'.env'),rootOptions);
    if(Object.keys(backendOptions).length)writeEnv(path.join(this.state.platform,'.env.backend'),backendOptions);
    this.write(path.join(this.private,'admin-access.json'), { email: c.adminEmail, password: c.adminPassword, appName:o.appName });
    this.state.naming='company-v1';await this.configureNames();await this.identifyManager();
    this.loadSecrets(); await this.validateSource(true); await this.assertFreshResources();
    this.save({ ...this.state, phase: 'build', freshResourcesVerified: true });
  }
  async build() { await this.compose(['build'], { label: 'Compilando todos os componentes dentro do Docker' }); }
  async migrations() {
    await this.compose(['up','-d','--wait','--wait-timeout','180','postgres','redis'], { label: 'Aguardando PostgreSQL e Redis' });
    await this.compose(['run','--rm','--no-deps','migrate'], { label: 'Migrations Sequelize no container' });
    await this.compose(['run','--rm','official-db-init'], { label: 'Inicialização não destrutiva do banco da API Oficial' });
    await this.compose(['run','--rm','--no-deps','official-migrate'], { label: 'Migrations Prisma no container' });
  }
  async initialize() {
    if (this.state.initialized || !this.state.freshResourcesVerified) throw Error('Inicialização sem prova de projeto novo recusada.');
    if (this.state.seedAttempted && !this.state.seedSucceeded) throw Error('Seed anterior incompleto. Preserve os volumes e recupere a inicialização; não repetir seeds automaticamente.');
    if (!this.state.seedSucceeded) {
      if (!this.state.resourcesClaimed) await this.assertFreshResources();
      this.save({ ...this.state, phase: 'migrations', resourcesClaimed: true }); await this.migrations();
      const count = (await this.compose(['exec','-T','postgres','psql','-U','amanda','-d','amanda','-tAc','SELECT count(*) FROM "Users"'], { quiet: true })).stdout.trim();
      if (count !== '0') throw Error('Banco já possui usuários; seed recusado.');
      this.save({ ...this.state, phase: 'seed', seedAttempted: true });
      const account = JSON.parse(fs.readFileSync(path.join(this.private,'admin-access.json'),'utf8'));
      await this.compose(['--profile','setup','run','--rm','--no-deps','seed'], { env: { AMANDA_ADMIN_EMAIL: account.email, AMANDA_ADMIN_PASSWORD: account.password }, label: 'Criando dados iniciais somente no banco novo' });
      this.save({ ...this.state, seedSucceeded: true, phase: 'starting' });
    }
    await this.startServices(); await this.verifyLogin();
    this.save({ ...this.state, initialized: true, phase: 'ready', revision: await this.revision() });
    this.runner.emit('Instalação completa: oito serviços, login e sessão validados. Integrações externas aguardam suas contas.\n');
    this.runner.emit(`Frontend: ${this.state.frontendUrl}\nBackend: ${this.state.backendUrl}\nAcesso inicial escolhido: ${path.join(this.private,'admin-access.json')} (arquivo privado).\n`);
  }
  async startServices() {
    await this.compose(['up','-d','--no-deps','--wait','--wait-timeout','300',...CORE,...(this.state.profiles.includes('edge') ? ['edge'] : [])], { label: 'Iniciando a plataforma completa e verificando prontidão' });
    for(const a of(await this.configuration()).installerAddons)await this.docker([...a.base,'up','-d','--wait','--wait-timeout','300'],{label:'Iniciando componente '+a.project});
    await this.verifyHealth();
  }
  async verifyHealth() {
    const rows = (await this.compose(['ps','--all','--format','json'], { quiet: true })).stdout.trim().split(/\r?\n/).filter(Boolean).flatMap(l => { const r = JSON.parse(l); return Array.isArray(r) ? r : [r]; });
    for (const name of [...CORE,...(this.state.profiles.includes('edge') ? ['edge'] : [])]) {
      const r = rows.find(x => x.Service === name && x.State === 'running' && (name === 'edge' || x.Health === 'healthy'));
      if (!r || r.State !== 'running' || (name !== 'edge' && r.Health !== 'healthy')) throw Error('Serviço não está pronto: ' + name);
      if(this.state.naming==='company-v1'&&r.Name!==this.state.project+'_'+(name==='edge'?'caddy':name))throw Error('Nome efetivo de container divergente: '+name);
    }
    if(this.state.naming==='company-v1'){
      const names=new Set((await this.docker(['ps','--filter','label=com.docker.compose.project='+this.state.project,'--format','{{.Names}}'],{quiet:true})).stdout.trim().split(/\s+/));
      for(const name of [...CORE,...(this.state.profiles.includes('edge')?['edge']:[])])if(!names.has(this.state.project+'_'+(name==='edge'?'caddy':name)))throw Error('docker ps não confirmou o nome: '+name);
    }
    for(const a of(await this.configuration()).installerAddons){const raw=(await this.docker([...a.base,'ps','--all','--format','json'],{quiet:true})).stdout;const rows=raw.trim().split(/\r?\n/).filter(Boolean).flatMap(l=>{const v=JSON.parse(l);return Array.isArray(v)?v:[v];});for(const name of a.services)if(!rows.some(r=>r.Service===name&&r.State==='running'&&r.Health==='healthy'&&(this.state.naming!=='company-v1'||r.Name===a.project+'_'+name.replace(/-/g,'_'))))throw Error('Componente não saudável ou nome divergente: '+a.project+'/'+name);}
    await this.compose(['exec','-T','backend','node','-e',`Promise.all(['http://127.0.0.1:8080/healthz','http://frontend/'].map(async u=>{const r=await fetch(u);if(r.status!==200)throw Error('HTTP '+r.status)})).catch(()=>process.exit(1))`], { label: 'Verificando HTTP interno do backend e frontend' });
    if(this.state.profiles.includes('edge')){
      const env=envValues(path.join(this.state.platform,'.env'));
      const urls=[{url:env.FRONTEND_URL,exact:true},{url:env.BACKEND_URL+'/healthz',exact:true},...(env.OFICIAL_HOST?[{url:'https://'+env.OFICIAL_HOST,exact:false}]:[])];
      await this.compose(['exec','-T','backend','node','-e',`(async()=>{const urls=${JSON.stringify(urls)};for(let i=0;i<6;i++){try{for(const p of urls){const r=await fetch(p.url,{signal:AbortSignal.timeout(10000),redirect:'error'});if(p.exact?r.status!==200:r.status<200||r.status>=500)throw Error();}console.log('HTTPS público e certificados validados.');return;}catch{if(i===5)throw Error();await new Promise(r=>setTimeout(r,5000));}}})().catch(()=>process.exit(1))`],{label:'Validando HTTPS público, DNS e certificados (sem enviar mensagens)'});
    }
  }
  async verifyLogin() {
    const account = JSON.parse(fs.readFileSync(path.join(this.private,'admin-access.json'),'utf8'));
    const script = ` (async()=>{const r=await fetch('http://127.0.0.1:8080/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:process.env.AMANDA_ADMIN_EMAIL,password:process.env.AMANDA_ADMIN_PASSWORD})});if(r.status!==200)throw Error();const a=await r.json();if(a.user?.id!==1||a.user?.profile!=='admin')throw Error();const headers={Authorization:'Bearer '+a.token,'Content-Type':'application/json'};const me=await fetch('http://127.0.0.1:8080/auth/me',{headers});if(me.status!==200)throw Error();if(process.env.AMANDA_APP_NAME){const s=await fetch('http://127.0.0.1:8080/settings/appName',{method:'PUT',headers,body:JSON.stringify({value:process.env.AMANDA_APP_NAME})});if(s.status!==200)throw Error();}console.log('Login inicial, sessão e identidade aprovados.')})().catch(()=>process.exit(1))`;
    await this.compose(['exec','-T','-e','AMANDA_ADMIN_EMAIL','-e','AMANDA_ADMIN_PASSWORD','-e','AMANDA_APP_NAME','backend','node','-e',script], { env: { AMANDA_ADMIN_EMAIL: account.email, AMANDA_ADMIN_PASSWORD: account.password, AMANDA_APP_NAME:account.appName || '' }, label: 'Validando o acesso escolhido, sem enviar mensagens' });
  }
  async revision() { return (await this.git(['rev-parse','HEAD'], { quiet: true })).stdout.trim(); }
  async adopt(url) {
    sourceUrl(url); if (fs.existsSync(this.stateFile)) throw Error('Diretório já gerenciado.');
    const platform = fs.existsSync(path.join(this.root,'docker-compose.yml')) ? this.root : path.join(this.root,'platform');
    const env = envValues(path.join(platform,'.env'));
    const project = env.COMPOSE_PROJECT_NAME || 'amanda';
    if (!/^[a-z0-9][a-z0-9_-]{0,39}$/.test(project)) throw Error('Projeto existente inválido.');
    this.state = { schema: 1, sourceUrl: SOURCE, project, platform, profiles: [...PROFILES,...((env.COMPOSE_PROFILES || '').split(',').includes('edge') ? ['edge'] : [])], initialized: true, phase: 'ready', seedAttempted: false, seedSucceeded: false };
    await this.validateSource(true); this.loadSecrets(); await this.configuration(); await this.verifyHealth();
    await this.identifyManager();
    this.save({ ...this.state, revision: await this.revision() });
    if (platform === this.root) { const file = path.join(platform,'.git/info/exclude'); fs.appendFileSync(file,'\n/.amanda-installer/\n/addons/\n/instances/\n/imports/\n'); }
    this.runner.emit('Instalação oficial existente adotada; configurações e volumes preservados. Nenhum seed executado.\n');
  }
  async backup({ restart = true, allowUnhealthy = false } = {}) {
    if(allowUnhealthy)await this.compose(['exec','-T','postgres','pg_isready','-U','amanda','-d','amanda'],{quiet:true,label:'Validando PostgreSQL para backup de recuperação'});
    else await this.verifyHealth();
    const config = await this.configuration();
    const images = await this.imageIds();
    const dir = path.join(this.private,'backups',new Date().toISOString().replace(/[:.]/g,'-'));
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    const stopped = [...CORE.filter(x => x !== 'postgres'),...(this.state.profiles.includes('edge') ? ['edge'] : [])];
    try {
      for(const a of config.installerAddons)await this.docker([...a.base,'stop'],{label:'Pausando componente '+a.project+' para backup'});
      await this.compose(['stop',...stopped], { label: 'Pausando gravadores para backup consistente' });
      for (const name of ['amanda','api_oficial']) await this.compose(['exec','-T','postgres','pg_dump','-U','amanda','-d',name,'-Fc'], { outputFile: path.join(dir,name+'.dump'), label: 'Backup do banco ' + name });
      const mounts = Object.entries(config.volumes).filter(([key]) => key !== 'postgres_data').flatMap(([key,v]) => ['--mount',`type=volume,source=${v.name},target=/data/${key},readonly`]);
      await this.docker(['run','--rm','--network','none',...mounts,'--mount',`type=bind,source=${dir},target=/backup`,'alpine:3.21','tar','-czf','/backup/volumes.tgz','-C','/data','.'], { label: 'Arquivando volumes de mídia, sessões, filas e certificados' });
      await this.docker(['run','--rm','--network','none','--mount',`type=bind,source=${dir},target=/backup,readonly`,'alpine:3.21','sh','-c','tar -tzf /backup/volumes.tgz >/dev/null'], { label: 'Verificando integridade do arquivo de volumes' });
      for (const file of ['.env','.env.backend','.env.oficial']) { const p = path.join(this.state.platform,file); if (fs.existsSync(p)) { fs.copyFileSync(p,path.join(dir,file)); fs.chmodSync(path.join(dir,file),0o600); } }
      for (const f of ['amanda.dump','api_oficial.dump','volumes.tgz']) if (!fs.statSync(path.join(dir,f)).size) throw Error('Backup vazio: '+f);
      const accountFile = path.join(this.private,'admin-access.json');
      if (fs.existsSync(accountFile)) { fs.copyFileSync(accountFile,path.join(dir,'admin-access.json')); fs.chmodSync(path.join(dir,'admin-access.json'),0o600); }
      const addons=[];for(const a of config.installerAddons){const kind=a.project.slice(this.state.project.length+1),record=JSON.parse(fs.readFileSync(path.join(this.private,'addon-'+kind+'.json'),'utf8'));addons.push(record);const file='addon-'+kind+'.env';this.write(path.join(dir,file),fs.readFileSync(path.join(this.private,file),'utf8'));}
      const hashes={};for(const file of ['amanda.dump','api_oficial.dump','volumes.tgz'])hashes[file]=await digest(path.join(dir,file));
      this.write(path.join(dir,'backup.json'), { complete: true, project: this.state.project, revision: this.state.revision, images, hashes,addons,volumes:config.volumes });
      this.save({ ...this.state, lastBackup: dir }); return dir;
    } finally { if (restart) await this.startServices(); }
  }
  async imageIds() {
    const config = await this.configuration(), result = {};
    for (const name of ['backend','frontend','api_transcricao','api_oficial']) {
      const id = (await this.compose(['ps','-a','-q',name], { quiet: true })).stdout.trim();
      if (!/^[a-f0-9]{12,64}$/.test(id)) throw Error('Não foi possível preservar a imagem anterior de '+name);
      result[config.services[name].image] = (await this.docker(['inspect','--format','{{.Image}}',id], { quiet: true })).stdout.trim();
    }
    for(const a of config.installerAddons)for(const name of a.services){const id=(await this.docker([...a.base,'ps','-a','-q',name],{quiet:true})).stdout.trim();if(!/^[a-f0-9]{12,64}$/.test(id))throw Error('Componente sem container preservável: '+name);const tag=(await this.docker(['inspect','--format','{{.Config.Image}}',id],{quiet:true})).stdout.trim();result[tag]=(await this.docker(['inspect','--format','{{.Image}}',id],{quiet:true})).stdout.trim();}
    return result;
  }
  async restoreTags(images) { for (const [tag,id] of Object.entries(images)) if(!tag.startsWith('sha256:')&&!tag.includes('@sha256:'))await this.docker(['image','tag',id,tag], { quiet: true }); }
  async update() {
    if (!this.state.initialized || this.state.phase !== 'ready') throw Error('Instalação incompleta; use resume.');
    await this.validateSource(true); const previousConfig=await this.configuration(); await this.verifyHealth();
    const images = await this.imageIds();
    const oldRevision = await this.revision();
    const gitEnv = { GIT_TERMINAL_PROMPT: '0', GIT_ASKPASS: path.join(__dirname,'source-askpass.cjs'), AMANDA_SOURCE_TOKEN_FILE: path.join(this.private,'source-token') };
    this.save({ ...this.state, phase: 'preparing-update', rollbackImages: images, rollbackRevision: oldRevision });
    let mayBeStopped = false;
    try {
      await this.git(['-c','credential.helper=','fetch','origin','main'], { env: gitEnv, label: 'Obtendo atualização oficial' });
      await this.git(['merge-base','--is-ancestor','HEAD','origin/main'], { quiet: true, label: 'Validando histórico oficial sem commits locais divergentes' });
      await this.git(['merge','--ff-only','origin/main'], { label: 'Aplicando somente avanço de histórico' });
      const ensure = path.join(this.state.platform,'docker/ensure-transcription-key.cjs');
      if (fs.existsSync(ensure)) await this.runner.run(process.execPath,[ensure], { cwd: this.state.platform, label: 'Preservando configuração da transcrição' });
      if(this.state.naming==='company-v1')await this.configureNames();
      const nextConfig=await this.configuration();
      for(const type of ['volumes','networks'])for(const[key,value]of Object.entries(previousConfig[type]||{}))if(nextConfig[type]?.[key]?.name!==value.name)throw Error('Atualização alteraria recurso persistente: '+key);
      for(const[key,value]of Object.entries(previousConfig.services))if(nextConfig.services[key]?.container_name!==value.container_name)throw Error('Atualização alteraria nome existente: '+key);
      this.loadSecrets(); await this.build();
      mayBeStopped = true; await this.backup({ restart: false });
    } catch (error) {
      await this.restoreTags(images); await this.git(['checkout','--detach',oldRevision], { quiet: true });
      if(this.state.naming==='company-v1')await this.configureNames();
      if (mayBeStopped) await this.startServices();
      this.save({ ...this.state, phase: 'ready', revision: oldRevision }); throw error;
    }
    this.save({ ...this.state, phase: 'migration-update', pendingRevision: await this.revision() });
    await this.migrations(); await this.startServices();
    this.save({ ...this.state, phase: 'ready', revision: await this.revision() });
    this.runner.emit('Atualização aprovada; contas, segredos e volumes preservados. Nenhum seed executado.\n');
  }
  async execute(action) {
    await this.doctor();
    if (action === 'doctor') return;
    this.load();await this.identifyManager(); await this.validateSource(); await this.configuration();
    if (action === 'update') return this.update();
    if (action === 'resume') {
      await this.validateSource(true);
      if (!this.state.initialized) { if (!this.state.freshResourcesVerified) throw Error('Preparação incompleta; não é seguro assumir banco novo.'); await this.build(); return this.initialize(); }
      if (this.state.phase === 'preparing-update') {
        await this.restoreTags(this.state.rollbackImages);
        await this.git(['checkout','--detach',this.state.rollbackRevision], { quiet: true });
        if(this.state.naming==='company-v1')await this.configureNames();
        await this.startServices(); this.save({ ...this.state, phase: 'ready', revision: this.state.rollbackRevision });
        this.runner.emit('Atualização interrompida antes das migrations revertida. Execute update novamente.\n'); return;
      }
      if (this.state.phase !== 'migration-update') throw Error('Nenhuma atualização interrompida para retomar.');
      if (await this.revision() !== this.state.pendingRevision) throw Error('Revisão difere da atualização interrompida. Preserve o código registrado antes de retomar migrations.');
      await this.build();
      await this.migrations(); await this.startServices(); this.save({ ...this.state, phase: 'ready', revision: await this.revision() }); return;
    }
    if (action === 'status') return this.verifyHealth();
    if (action === 'logs') return this.compose(['logs','--no-color','--tail','200'], { label: 'Logs (credenciais filtradas)' });
    if (action === 'stop') {for(const a of(await this.configuration()).installerAddons)await this.docker([...a.base,'stop']);return this.compose(['stop'], { label: 'Parando containers; volumes preservados' });}
    if (!this.state.initialized || this.state.phase !== 'ready') throw Error('Operação exige instalação concluída. Use resume; não executar seeds novamente.');
    if (action === 'backup') return this.backup();
    if (action === 'restart') await this.compose(['stop'], { label: 'Reiniciando a plataforma' });
    if (action === 'start' || action === 'restart') return this.startServices();
    throw Error('Comando desconhecido.');
  }
  async lock(fn) {
    if(this.operationScope.getStore()===this)return fn();
    fs.mkdirSync(this.private, { recursive: true, mode: 0o700 });
    const file = path.join(this.private,'operation.lock');
    let fd;
    try { fd = fs.openSync(file,'wx',0o600); } catch { throw Error('Outra operação está registrada. Verifique o gerenciador anterior e use unlock se já encerrou.'); }
    fs.writeFileSync(fd, JSON.stringify({ container: process.env.HOSTNAME, at: new Date().toISOString() })); fs.closeSync(fd);
    try { return await this.operationScope.run(this,fn); } finally { fs.unlinkSync(file); }
  }
  async unlock() {
    const file = path.join(this.private,'operation.lock');
    const data = JSON.parse(fs.readFileSync(file,'utf8'));
    if (!/^[a-f0-9]{12,64}$/.test(data.container || '')) throw Error('Lock sem identificação Docker; revise-o manualmente.');
    const r = await this.docker(['inspect','--format','{{.State.Running}}',data.container], { quiet: true, allowFailure: true });
    if (r.code === 0 && r.stdout.trim() === 'true') throw Error('Gerenciador anterior ainda está ativo.');
    fs.unlinkSync(file); this.runner.emit('Lock de operação encerrada removido.\n');
  }
}
module.exports = { SOURCE, CORE, PROFILES, sourceUrl, rootPath, normalizeConfig, envValues, editEnv, Runner, Manager };
