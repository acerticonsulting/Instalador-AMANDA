const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');
const { AsyncLocalStorage } = require('node:async_hooks');
const { validateOptions, validatePg, writeEnv, digest } = require('./options.cjs');

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
  const allowed = ['sourceUrl', 'project', 'companyName', 'frontendUrl', 'backendUrl', 'public', 'edge', 'adminEmail', 'adminPassword', 'sourceToken', 'buildToken','options','domainPreflight'];
  if(input.domainPreflight&&(!['compatible','exception'].includes(input.domainPreflight.status)||JSON.stringify(input.domainPreflight).length>65536))throw Error('Registro de pré-validação inválido.');
  for (const key of Object.keys(input)) if (!allowed.includes(key)) throw Error('Campo de configuração desconhecido: ' + key);
  const c = { project: 'amanda', frontendUrl: 'http://localhost:3000', backendUrl: 'http://localhost:8080', public: false, edge: false, adminEmail: 'admin@amanda.com.br', adminPassword: 'adminamanda', ...input };
  c.sourceUrl = sourceUrl(c.sourceUrl);
  if(typeof c.project!=='string')throw Error('Nome do projeto inválido.');
  c.project=c.project.trim().normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[ -]+/g,'_');
  if (!/^[a-z0-9][a-z0-9_]{0,39}$/.test(c.project)) throw Error('Nome do projeto inválido.');
  if(c.companyName!==undefined&&(typeof c.companyName!=='string'||!c.companyName.trim()||c.companyName.length>120||/[\x00-\x1f\x7f]/.test(c.companyName)))throw Error('Nome comercial da empresa inválido.');
  if (typeof c.public !== 'boolean' || typeof c.edge !== 'boolean') throw Error('public e edge devem ser booleanos.');
  for (const key of ['frontendUrl', 'backendUrl']) {
    if(typeof c[key]!=='string'||/[\x00-\x20\x7f]/.test(c[key]))throw Error('URL inválida: '+key);
    const u = new URL(c[key]);
    if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password || u.search || u.hash || u.pathname !== '/') throw Error('URL inválida: ' + key);
    c[key] = u.origin;
  }
  const front = new URL(c.frontendUrl), back = new URL(c.backendUrl);
  c.options=validateOptions(c.options);
  const flags={official:true,wuzapi:true,rabbit:true,...c.options.services};
  if(c.options.officialUrl&&!flags.official)throw Error('Domínio da API Oficial exige o serviço habilitado.');
  if(c.options.officialUrl&&(!c.edge||[front.hostname,back.hostname].includes(new URL(c.options.officialUrl).hostname)))throw Error('A API Oficial pública requer Caddy/HTTPS e domínio próprio diferente do frontend/backend.');
  if (c.edge) {
    const ports=[80,443,c.options.frontendPort||3000,c.options.backendPort||8080,...(flags.official?[c.options.officialPort||6000]:[]),...(flags.wuzapi?[c.options.wuzapiPort||8090]:[])];
    if(new Set(ports).size!==ports.length)throw Error('Portas da API Oficial/WuzAPI conflitam com o proxy, frontend ou backend.');
    for (const u of [front, back]) if (u.protocol !== 'https:' || u.port || !/^[a-z0-9.-]+\.[a-z]{2,}$/i.test(u.hostname)||u.hostname.length>253||u.hostname.split('.').some(label=>! /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i.test(label))) throw Error('HTTPS/Caddy exige dois domínios DNS válidos e porta 443.');
    if (front.hostname === back.hostname) throw Error('Use domínios diferentes para frontend e backend.');
  } else {
    if (front.protocol !== 'http:' || back.protocol !== 'http:') throw Error('Para HTTPS, habilite edge/Caddy.');
    const ports = [front.port || '80', back.port || '80', ...(flags.official?[String(c.options.officialPort || 6000)]:[]), ...(flags.wuzapi?[String(c.options.wuzapiPort || 8090)]:[])];
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
    if(!m[2].startsWith("'"))v=v.replace(/\$\$/g,'$');
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
    if (this.logFile) { fs.mkdirSync(path.dirname(this.logFile), { recursive: true, mode: 0o700 });const fd=fs.openSync(this.logFile,fs.constants.O_APPEND|fs.constants.O_CREAT|fs.constants.O_WRONLY|fs.constants.O_NOFOLLOW,0o600);try{fs.appendFileSync(fd,safe);const owner=this.deploymentOwner?.();if(owner){if(!Number.isInteger(owner.uid)||owner.uid<=0||!Number.isInteger(owner.gid)||owner.gid<0)throw Error('Proprietário do log inválido.');fs.fchownSync(fd,owner.uid,owner.gid);fs.fchmodSync(fd,0o600);}}finally{fs.closeSync(fd);} }
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
    this.runner.deploymentOwner=()=>this.deploymentOwner||this.state?.deploymentOwner;
    this.operationScope=new AsyncLocalStorage();
  }
  write(file, value) { fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 }); fs.writeFileSync(file, typeof value === 'string' ? value : JSON.stringify(value, null, 2) + '\n', { mode: 0o600 }); }
  save(state) { if(this.deploymentOwner)state={...state,deploymentOwner:this.deploymentOwner};this.write(this.stateFile + '.tmp', state); fs.renameSync(this.stateFile + '.tmp', this.stateFile); this.state = state; }
  services(){return ['postgres','redis','backend','frontend','api_transcricao',...(this.state.profiles.includes('official')?['api_oficial']:[]),...(this.state.profiles.includes('whatsmeow')?['wuzapi']:[]),...(this.state.profiles.includes('rabbit')?['rabbitmq']:[])];}
  databases(){return ['amanda',...(this.state.profiles.includes('official')?['api_oficial']:[])];}
  async resources(){const info=JSON.parse((await this.docker(['info','--format','{{json .}}'],{quiet:true})).stdout);return {memory:info.MemTotal,cpus:info.NCPU};}
  load({preparing=false}={}) {
    const s = JSON.parse(fs.readFileSync(this.stateFile, 'utf8'));
    if (s.schema !== 1 || sourceUrl(s.sourceUrl) !== SOURCE || !/^[a-z0-9][a-z0-9_-]{0,39}$/.test(s.project)||!Array.isArray(s.profiles)||s.profiles.some(p=>!['official','whatsmeow','rabbit','edge'].includes(p))) throw Error('Estado do instalador inválido.');
    const relative = path.relative(this.root, s.platform);
    if (relative.startsWith('..') || path.isAbsolute(relative)) throw Error('Plataforma fora do diretório selecionado.');
    const physicalRoot = fs.realpathSync(this.root), physical = preparing&&s.phase==='preparing'&&!fs.existsSync(s.platform)?path.join(physicalRoot,'platform'):fs.realpathSync(s.platform);
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
    const account = path.join(this.private,'admin-access.json'); if (fs.existsSync(account)){let a;try{a=JSON.parse(fs.readFileSync(account,'utf8'));if(!a||typeof a!=='object'||Array.isArray(a))throw Error();}catch{throw Error('Arquivo privado de acesso inválido; conteúdo preservado para diagnóstico.');}this.runner.secret(a.password);for(const[k,v]of Object.entries(a.initialSettings||{}))if(/key|token|pass|secret/i.test(k))this.runner.secret(v);}
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
    for (const name of this.services()) if (!config.services[name]) throw Error('Compose não contém o serviço ' + name);
    config.declaredVolumes={...config.volumes};
    if(this.state.selectiveServices){for(const[key,service]of Object.entries({oficial_public:'api_oficial',wuzapi_data:'wuzapi',rabbitmq_data:'rabbitmq'}))if(!this.services().includes(service))delete config.volumes[key];}
    if(this.state.selectiveServices&&!this.state.retainedEdgeVolumes&&!this.state.profiles.includes('edge'))for(const key of ['caddy_data','caddy_config'])delete config.volumes[key];
    if(this.state.naming==='company-v1')for(const [key,v]of Object.entries(config.services))if(v.container_name!==this.state.project+'_'+(key==='edge'?'caddy':key.replace(/-/g,'_')))throw Error('Nome de container inesperado: '+key);
    for(const [key,n]of Object.entries(config.networks||{}))if(n.external||n.name!==this.state.project+'_'+key)throw Error('Rede externa ou nome inesperado: '+key);
    for (const [key,v] of Object.entries(config.declaredVolumes || {})) if (v.external || v.name !== this.state.project + '_' + key) throw Error('Volume externo ou nome inesperado: ' + key);
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
    if (ids || Object.values(config.services).some(s=>s.container_name&&names.has(s.container_name)) || Object.values(config.declaredVolumes).some(v => volumes.has(v.name)) || Object.values(config.networks||{}).some(n=>networks.has(n.name)) || networks.has(this.state.project + '_default')) throw Error('Projeto ou volumes já existem. Use adopt para a instalação oficial existente; nenhum seed foi executado.');
  }
  async prepare(input, { resume = false } = {}) {
    const c = normalizeConfig(input);
    const {inspectInstallation}=require('./deploy.cjs'),{conflict,setupRecord}=require('./directory-state.cjs');
    const info=inspectInstallation(this.root,c.project);
    if(info.kind==='unknown')throw Error(conflict(info));
    if(resume){
      if(info.kind!=='partial'||info.phase!=='preparing'||!info.savedConfig)throw Error('Preparação interrompida sem configuração salva comprovada. Preserve o diretório e consulte o diagnóstico.');
      this.state=info.state;
    }else if(!['absent','empty','temporary'].includes(info.kind))throw Error('Instalação já registrada; use update ou resume.');
    if(info.savedConfig&&JSON.stringify(info.savedConfig)!==JSON.stringify(c))throw Error('Configuração difere da preparação salva; use a retomada.');
    this.runner.secret(c.adminPassword); this.runner.secret(c.sourceToken); this.runner.secret(c.buildToken);
    const o=c.options;
    for(const v of [o.databasePassword,o.masterPassword,o.officialToken,o.wuzapiToken,...Object.values(o.backendEnv||{})])this.runner.secret(v);
    for(const[k,v]of Object.entries(o.initialSettings||{}))if(/key|token|pass|secret/i.test(k))this.runner.secret(v);
    if(o.pg){const resources=await this.resources();if(!resources.memory)throw Error('Docker não informou memória para validar PostgreSQL.');validatePg(o.pg,resources.memory);}
    fs.mkdirSync(this.root,{recursive:true,mode:0o700});
    if(!info.savedConfig)this.write(path.join(this.private,'setup.json'),setupRecord(this.root,c));
    const flags={official:true,wuzapi:true,rabbit:true,...o.services};
    const profiles=[...(flags.official?['official']:[]),...(flags.wuzapi?['whatsmeow']:[]),...(flags.rabbit?['rabbit']:[]),...(c.edge?['edge']:[])];
    if(!resume)this.save({schema:1,sourceUrl:SOURCE,project:c.project,companyName:c.companyName,frontendUrl:c.frontendUrl,backendUrl:c.backendUrl,domainPreflight:c.domainPreflight,platform:path.join(this.root,'platform'),profiles,selectiveServices:true,retainedEdgeVolumes:c.edge,phase:'preparing',initialized:false,seedAttempted:false,seedSucceeded:false});
    const tokenFile=path.join(this.private,'source-token');
    if(c.sourceToken&&!fs.existsSync(tokenFile))this.write(tokenFile,c.sourceToken);
    const gitEnv={GIT_TERMINAL_PROMPT:'0',GIT_ASKPASS:path.join(__dirname,'source-askpass.cjs'),AMANDA_SOURCE_TOKEN_FILE:tokenFile};
    if(!fs.existsSync(this.state.platform))await this.runner.run('git',['-c','credential.helper=','clone','--branch','main','--single-branch',SOURCE,this.state.platform],{env:gitEnv,label:'Obtendo a plataforma autorizada'});
    else await this.validateSource(true);
    // Prepare private staging files first. Publish only absent files or identical bytes.
    // A crash never requires overwriting an existing environment or regenerating its keys.
    const configRoot=path.join(this.private,'setup-files');
    fs.mkdirSync(configRoot,{recursive:true,mode:0o700});
    const admin={email:c.adminEmail,password:c.adminPassword,appName:o.appName,companyName:c.companyName,initialSettings:o.initialSettings};
    const adminBytes=JSON.stringify(admin,null,2)+'\n';
    const fingerprint=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
    if(!this.state.configurationFiles){
      const example=path.join(configRoot,'.env.example');
      if(!fs.existsSync(example)){fs.copyFileSync(path.join(this.state.platform,'.env.example'),example,fs.constants.COPYFILE_EXCL);fs.chownSync(example,process.getuid(),process.getgid());fs.chmodSync(example,0o600);}
      const stagedEnv=path.join(configRoot,'.env');
      if(!fs.existsSync(stagedEnv))await this.runner.run(process.execPath,[path.join(this.state.platform,'docker/configure.cjs')],{cwd:configRoot,label:'Preparando configuração privada recuperável no container'});
      const existing=envValues(stagedEnv);
      if(!existing.DB_PASS||!existing.JWT_SECRET||!existing.JWT_REFRESH_SECRET)throw Error('Configuração em preparação incompleta; nenhuma chave existente foi substituída.');
      const f=new URL(c.frontendUrl),b=new URL(c.backendUrl);
      editEnv(stagedEnv,{COMPOSE_PROJECT_NAME:c.project,COMPOSE_PROFILES:profiles.join(','),USE_WHATSAPP_OFICIAL:String(flags.official),RABBITMQ_ENABLED_GLOBAL:String(flags.rabbit),WUZAPI_URL:flags.wuzapi?'http://wuzapi:8080':'',FRONTEND_URL:c.frontendUrl,BACKEND_URL:c.backendUrl,ALLOWED_ORIGINS:c.frontendUrl,BIND_ADDRESS:c.edge||!c.public?'127.0.0.1':'0.0.0.0',PORT_FRONTEND:c.edge?(o.frontendPort||3000):(f.port||80),PORT_BACKEND:c.edge?(o.backendPort||8080):(b.port||80),FRONTEND_HOST:f.hostname,BACKEND_HOST:b.hostname});
      const rootOptions={PORT_APIOFICIAL:o.officialPort||6000,PORT_WUZAPI:o.wuzapiPort||8090,REACT_APP_NUMBER_SUPPORT:o.supportPhone||'',OFICIAL_HOST:o.officialUrl?new URL(o.officialUrl).hostname:''};
      if(o.databasePassword){rootOptions.DB_PASS=o.databasePassword;rootOptions.DB_URI_PASSWORD=encodeURIComponent(o.databasePassword);}
      if(o.masterPassword)rootOptions.MASTER_KEY=o.masterPassword;
      if(o.officialToken)rootOptions.TOKEN_API_OFICIAL=o.officialToken;
      if(o.wuzapiToken)rootOptions.WUZAPI_ADMIN_TOKEN=o.wuzapiToken;
      if(o.pg){rootOptions.PG_MAX_CONNECTIONS=o.pg.maxConnections;rootOptions.PG_SHARED_BUFFERS=o.pg.sharedBuffers;}
      const backendOptions={...o.backendEnv};
      for(const key of ['TRANSCRIBE_URL','URL_API_OFICIAL','WUZAPI_URL','GO_CAMPAIGN_DISPATCHER_URL','USE_GO_CAMPAIGN_DISPATCHER'])if(backendOptions[key]!==undefined){rootOptions[key]=backendOptions[key];delete backendOptions[key];}
      writeEnv(stagedEnv,rootOptions);
      if(o.pushEmail){
        const saved=fs.existsSync(path.join(configRoot,'.env.backend'))?envValues(path.join(configRoot,'.env.backend')):{};
        if(saved.VAPID_PUBLIC_KEY&&saved.VAPID_PRIVATE_KEY){backendOptions.VAPID_PUBLIC_KEY=saved.VAPID_PUBLIC_KEY;backendOptions.VAPID_PRIVATE_KEY=saved.VAPID_PRIVATE_KEY;}
        else{const ecdh=crypto.createECDH('prime256v1');ecdh.generateKeys();backendOptions.VAPID_PUBLIC_KEY=ecdh.getPublicKey().toString('base64url');backendOptions.VAPID_PRIVATE_KEY=require('./options.cjs').vapidPrivateKey(ecdh.getPrivateKey());}
        backendOptions.VAPID_SUBJECT='mailto:'+o.pushEmail;
      }
      if(Object.keys(backendOptions).length)writeEnv(path.join(configRoot,'.env.backend'),backendOptions);
      const files={};for(const name of ['.env','.env.backend'])if(fs.existsSync(path.join(configRoot,name)))files[name]=fingerprint(fs.readFileSync(path.join(configRoot,name)));
      this.save({...this.state,configurationFiles:files,adminFingerprint:fingerprint(adminBytes),testSmtp:Boolean(o.testSmtp)});
    }
    const publish=(file,bytes,expected)=>{
      if(fingerprint(bytes)!==expected)throw Error('Integridade da configuração em preparação inválida.');
      if(fs.existsSync(file)){
        const st=fs.lstatSync(file);if(!st.isFile()||st.isSymbolicLink()||st.nlink!==1||fingerprint(fs.readFileSync(file))!==expected)throw Error('Configuração existente difere da preparação salva; nenhum arquivo foi sobrescrito.');
      }else fs.writeFileSync(file,bytes,{flag:'wx',mode:0o600});
    };
    for(const[name,expected]of Object.entries(this.state.configurationFiles)){
      if(!['.env','.env.backend'].includes(name))throw Error('Arquivo de configuração não autorizado.');
      publish(path.join(this.state.platform,name),fs.readFileSync(path.join(configRoot,name)),expected);
    }
    publish(path.join(this.private,'admin-access.json'),adminBytes,this.state.adminFingerprint);
    this.state.naming='company-v1';this.save({...this.state,configurationReady:true});
    await this.configureNames();await this.identifyManager();
    this.loadSecrets();await this.validateSource(true);await this.assertFreshResources();
    await require('./preflight.cjs').assertPorts(this,await this.configuration());
    if(c.edge){const hosts=[new URL(c.frontendUrl).hostname,new URL(c.backendUrl).hostname,...(o.officialUrl?[new URL(o.officialUrl).hostname]:[])];await this.runner.run(process.execPath,['-e',`const d=require('node:dns').promises;Promise.all(${JSON.stringify(hosts)}.map(h=>d.lookup(h))).catch(()=>{console.error('DNS: domínio sem resolução; revise os registros antes de instalar.');process.exit(1)})`],{label:'Verificando resolução DNS antes de criar bancos'});}
    this.save({...this.state,phase:'build',freshResourcesVerified:true});
  }
  async build() { await this.compose(['build',...this.services().filter(s=>['backend','frontend','api_transcricao','api_oficial'].includes(s))], { label: 'Compilando os componentes selecionados dentro do Docker' }); }
  async recoverLegacyPreparation() {
    const info=require('./deploy.cjs').inspectInstallation(this.root,this.state.project);
    if(info.kind!=='partial'||info.phase!=='preparing'||this.state.seedAttempted||this.state.initialized)throw Error('Preparação interrompida sem checkpoint seguro para recuperação.');
    const envFile=path.join(this.state.platform,'.env'),adminFile=path.join(this.private,'admin-access.json');
    if(!fs.existsSync(envFile))throw Error('Preparação interrompida sem configuração salva suficiente. Código, credenciais e estado foram preservados; consulte o diagnóstico.');
    const originalAdmin=fs.existsSync(adminFile)?fs.readFileSync(adminFile,'utf8'):null;
    const env=envValues(envFile);let admin;try{admin=originalAdmin===null?{}:JSON.parse(originalAdmin);if(!admin||typeof admin!=='object'||Array.isArray(admin))throw Error();}catch{throw Error('Arquivo privado de acesso inválido; conteúdo preservado para diagnóstico.');}
    if(env.COMPOSE_PROJECT_NAME!==this.state.project||env.FRONTEND_URL!==this.state.frontendUrl||env.BACKEND_URL!==this.state.backendUrl||['DB_PASS','JWT_SECRET','JWT_REFRESH_SECRET','MASTER_KEY','TRANSCRIBE_API_KEY','TOKEN_API_OFICIAL'].some(k=>!env[k]))throw Error('Preparação interrompida com configuração incompleta ou de outra empresa; nenhum arquivo foi substituído.');
    await this.validateSource(true);
    if(fs.existsSync(path.join(this.private,'compose-names.json')))this.state.naming='company-v1';
    const config=await this.configuration();
    if(env.PG_MAX_CONNECTIONS||env.PG_SHARED_BUFFERS)validatePg({maxConnections:Number(env.PG_MAX_CONNECTIONS),sharedBuffers:env.PG_SHARED_BUFFERS},(await this.resources()).memory);
    // Existing resources cannot be assumed fresh just because preparation stopped.
    await this.assertFreshResources();await require('./preflight.cjs').assertPorts(this,config);
    const missing=['email','password'].filter(key=>admin[key]===undefined||admin[key]==='');
    if(missing.length&&!this.recoveryQuestion)throw Error('Configuração administrativa incompleta: '+missing.join(', ')+'. Retome em terminal interativo para informar somente os campos faltantes.');
    for(const key of missing){
      const value=await this.recoveryQuestion(key==='email'?'E-mail administrativo ausente':'Senha administrativa ausente',undefined,key==='password');
      if(value==null||[':cancelar',':sair'].includes(value))throw Error('Retomada cancelada; configuração existente preservada.');
      if(key==='password'&&await this.recoveryQuestion('Confirmação da senha administrativa ausente',undefined,true)!==value)throw Error('Confirmação diferente; configuração existente preservada.');
      admin[key]=value;
    }
    normalizeConfig({sourceUrl:SOURCE,project:this.state.project,frontendUrl:env.FRONTEND_URL,backendUrl:env.BACKEND_URL,edge:this.state.profiles.includes('edge'),public:env.BIND_ADDRESS==='0.0.0.0',adminEmail:admin.email,adminPassword:admin.password});
    if(missing.length){
      if((fs.existsSync(adminFile)?fs.readFileSync(adminFile,'utf8'):null)!==originalAdmin)throw Error('A configuração administrativa mudou durante a retomada; nenhum valor foi substituído.');
      this.runner.secret(admin.password);this.write(adminFile,admin);
    }
    this.save({...this.state,phase:'build',freshResourcesVerified:true,configurationReady:true});
  }
  async refreshInterruptedBuild() {
    if (this.state.phase !== 'build' || this.state.initialized || this.state.seedAttempted) return;
    await this.validateSource(true);
    const env = { GIT_TERMINAL_PROMPT: '0', GIT_ASKPASS: path.join(__dirname,'source-askpass.cjs'), AMANDA_SOURCE_TOKEN_FILE: path.join(this.private,'source-token') };
    await this.git(['-c','credential.helper=','fetch','origin','main'], { env, label: 'Obtendo correções oficiais para o build interrompido' });
    await this.git(['merge-base','--is-ancestor','HEAD','origin/main'], { quiet: true });
    await this.git(['merge','--ff-only','origin/main'], { label: 'Aplicando correções sem substituir configuração ou dados' });
    if (this.state.naming === 'company-v1') await this.configureNames();
    this.save({ ...this.state, revision: await this.revision() });
  }
  async migrations() {
    await this.compose(['up','-d','--wait','--wait-timeout','180','postgres','redis'], { label: 'Aguardando PostgreSQL e Redis' });
    await this.compose(['run','--rm','--no-deps','migrate'], { label: 'Migrations Sequelize no container' });
    if(this.state.profiles.includes('official')){
      await this.compose(['run','--rm','official-db-init'], { label: 'Inicialização não destrutiva do banco da API Oficial' });
      await this.compose(['run','--rm','--no-deps','official-migrate'], { label: 'Migrations Prisma no container' });
    }
  }
  async initialize() {
    if (this.state.initialized || !this.state.freshResourcesVerified) throw Error('Inicialização sem prova de projeto novo recusada.');
    await require('./preflight.cjs').assertPorts(this,await this.configuration());
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
    if(this.state.testSmtp)await this.testSmtp();
    this.runner.emit('Instalação completa: '+this.services().length+' serviços, login e sessão validados. Integrações externas aguardam suas contas.\n');
    this.runner.emit(`Frontend: ${this.state.frontendUrl}\nBackend: ${this.state.backendUrl}\nAcesso inicial escolhido: ${path.join(this.private,'admin-access.json')} (arquivo privado).\n`);
  }
  async startServices() {
    await this.compose(['up','-d','--no-deps','--wait','--wait-timeout','300',...this.services(),...(this.state.profiles.includes('edge') ? ['edge'] : [])], { label: 'Iniciando a plataforma completa e verificando prontidão' });
    for(const a of(await this.configuration()).installerAddons)await this.docker([...a.base,'up','-d','--wait','--wait-timeout','300'],{label:'Iniciando componente '+a.project});
    await this.verifyHealth();
  }
  async verifyHealth() {
    const rows = (await this.compose(['ps','--all','--format','json'], { quiet: true })).stdout.trim().split(/\r?\n/).filter(Boolean).flatMap(l => { const r = JSON.parse(l); return Array.isArray(r) ? r : [r]; });
    for (const name of [...this.services(),...(this.state.profiles.includes('edge') ? ['edge'] : [])]) {
      const r = rows.find(x => x.Service === name && x.State === 'running' && (name === 'edge' || x.Health === 'healthy'));
      if (!r || r.State !== 'running' || (name !== 'edge' && r.Health !== 'healthy')) throw Error('Serviço não está pronto: ' + name);
      if(this.state.naming==='company-v1'&&r.Name!==this.state.project+'_'+(name==='edge'?'caddy':name))throw Error('Nome efetivo de container divergente: '+name);
    }
    if(this.state.naming==='company-v1'){
      const names=new Set((await this.docker(['ps','--filter','label=com.docker.compose.project='+this.state.project,'--format','{{.Names}}'],{quiet:true})).stdout.trim().split(/\s+/));
      for(const name of [...this.services(),...(this.state.profiles.includes('edge')?['edge']:[])])if(!names.has(this.state.project+'_'+(name==='edge'?'caddy':name)))throw Error('docker ps não confirmou o nome: '+name);
    }
    for(const a of(await this.configuration()).installerAddons){const raw=(await this.docker([...a.base,'ps','--all','--format','json'],{quiet:true})).stdout;const rows=raw.trim().split(/\r?\n/).filter(Boolean).flatMap(l=>{const v=JSON.parse(l);return Array.isArray(v)?v:[v];});for(const name of a.services)if(!rows.some(r=>r.Service===name&&r.State==='running'&&r.Health==='healthy'&&(this.state.naming!=='company-v1'||r.Name===a.project+'_'+name.replace(/-/g,'_'))))throw Error('Componente não saudável ou nome divergente: '+a.project+'/'+name);}
    await this.compose(['exec','-T','backend','node','-e',`Promise.all(['http://127.0.0.1:8080/healthz','http://frontend/'].map(async u=>{const r=await fetch(u);if(r.status!==200)throw Error('HTTP '+r.status)})).catch(()=>process.exit(1))`], { label: 'Verificando HTTP interno do backend e frontend' });
    if(this.state.profiles.includes('edge')){
      const env=envValues(path.join(this.state.platform,'.env'));
      const urls=[{url:env.FRONTEND_URL,exact:true},{url:env.BACKEND_URL+'/healthz',exact:true},...(env.OFICIAL_HOST?[{url:'https://'+env.OFICIAL_HOST,exact:false}]:[])];
      const pending = !this.state.initialized;
      if(pending)this.save({...this.state,phase:'https-pending',infrastructureReady:true,internalHttpReady:true,publicHttps:'pending'});
      const {inspectHttps,awaitHttps}=require('./https-check.cjs');
      const timeout=Number(process.env.AMANDA_HTTPS_TIMEOUT_MS||120000);
      if(!Number.isFinite(timeout)||timeout<1000||timeout>600000)throw Error('AMANDA_HTTPS_TIMEOUT_MS deve estar entre 1000 e 600000.');
      await awaitHttps({timeoutMs:timeout,emit:s=>this.runner.emit(s),probe:async()=>{
        const expectedAddresses=(process.env.AMANDA_HTTPS_EXPECTED_ADDRESSES||'').split(',').filter(Boolean);
        const result=await this.compose(['exec','-T','backend','node','-e',`(${inspectHttps.toString()})(${JSON.stringify(urls)},${JSON.stringify({connectivity:true,expectedAddresses})}).then(r=>console.log(JSON.stringify(r))).catch(e=>{console.error(e.code||e.message);process.exit(1)})`],{quiet:true,label:'Verificando DNS A/AAAA e HTTPS por endereço, com confiança TLS'});
        return JSON.parse(result.stdout.trim());
      },caddy:async()=> (await this.compose(['logs','--no-color','--since','2m','--tail','100','edge'],{quiet:true,label:'Consultando emissão ACME sem reiniciar Caddy'})).stdout});
      if(pending)this.save({...this.state,publicHttps:'validated'});
    }
  }
  async verifyLogin() {
    if(this.state.initialized||!this.state.seedSucceeded)throw Error('Personalização inicial só é permitida após seed novo confirmado.');
    const account = JSON.parse(fs.readFileSync(path.join(this.private,'admin-access.json'),'utf8'));
    const script = ` (async()=>{const r=await fetch('http://127.0.0.1:8080/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:process.env.AMANDA_ADMIN_EMAIL,password:process.env.AMANDA_ADMIN_PASSWORD})});if(r.status!==200)throw Error();const a=await r.json();if(a.user?.id!==1||a.user?.profile!=='admin')throw Error();const headers={Authorization:'Bearer '+a.token,'Content-Type':'application/json'};const me=await fetch('http://127.0.0.1:8080/auth/me',{headers});if(me.status!==200)throw Error();if(process.env.AMANDA_APP_NAME){const s=await fetch('http://127.0.0.1:8080/settings/appName',{method:'PUT',headers,body:JSON.stringify({value:process.env.AMANDA_APP_NAME})});if(s.status!==200)throw Error();}console.log('Login inicial, sessão e identidade aprovados.')})().catch(()=>process.exit(1))`;
    await this.compose(['exec','-T','-e','AMANDA_ADMIN_EMAIL','-e','AMANDA_ADMIN_PASSWORD','-e','AMANDA_APP_NAME','backend','node','-e',script], { env: { AMANDA_ADMIN_EMAIL: account.email, AMANDA_ADMIN_PASSWORD: account.password, AMANDA_APP_NAME:account.appName || '' }, label: 'Validando o acesso escolhido, sem enviar mensagens' });
    if(account.companyName){
      const company=`const{Client}=require('pg');(async()=>{const c=new Client({host:process.env.DB_HOST,port:Number(process.env.DB_PORT),user:process.env.DB_USER,password:process.env.DB_PASS,database:process.env.DB_NAME});await c.connect();try{await c.query('BEGIN');const r=await c.query('UPDATE "Companies" SET name=$1 WHERE id=1 RETURNING id',[process.env.A_COMPANY]);if(r.rowCount!==1)throw Error();await c.query('COMMIT');}catch(e){await c.query('ROLLBACK');throw e;}finally{await c.end();}})().catch(()=>process.exit(1))`;
      await this.compose(['exec','-T','-e','A_COMPANY','backend','node','-e',company],{env:{A_COMPANY:account.companyName},label:'Aplicando nome comercial somente à empresa inicial recém-criada'});
    }
    if(Object.keys(account.initialSettings||{}).length){
      const settings=`(async()=>{const r=await fetch('http://127.0.0.1:8080/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:process.env.A_EMAIL,password:process.env.A_PASSWORD})});if(r.status!==200)throw Error();const a=await r.json();for(const[key,value]of Object.entries(JSON.parse(process.env.A_SETTINGS)).sort((a,b)=>Number(a[0]==='activePaymentGateway')-Number(b[0]==='activePaymentGateway'))){const s=await fetch('http://127.0.0.1:8080/settings/'+key,{method:'PUT',headers:{Authorization:'Bearer '+a.token,'Content-Type':'application/json'},body:JSON.stringify({value})});if(s.status!==200)throw Error();}})().catch(()=>process.exit(1))`;
      await this.compose(['exec','-T','-e','A_EMAIL','-e','A_PASSWORD','-e','A_SETTINGS','backend','node','-e',settings],{env:{A_EMAIL:account.email,A_PASSWORD:account.password,A_SETTINGS:JSON.stringify(account.initialSettings)},label:'Aplicando configurações iniciais pela API autenticada'});
    }
  }
  async testSmtp(){
    const script=`const n=require('nodemailer');const e=process.env;if(!e.MAIL_HOST){console.error('SMTP não configurado.');process.exit(1);}const t=n.createTransport({host:e.MAIL_HOST,port:Number(e.MAIL_PORT||587),secure:e.MAIL_SECURE==='true'||Number(e.MAIL_PORT)===465,...(e.MAIL_USER?{auth:{user:e.MAIL_USER,pass:e.MAIL_PASS}}:{}),connectionTimeout:10000,greetingTimeout:10000,socketTimeout:15000});t.verify().then(()=>{t.close();console.log('Conexão SMTP do ambiente validada; nenhum e-mail enviado.');}).catch(()=>{t.close();console.error('SMTP: falha de conexão, TLS ou autenticação. Revise o provedor.');process.exitCode=1;});`;
    try{await this.compose(['exec','-T','backend','node','-e',script],{label:'Testando conexão SMTP sem envio'});this.runner.emit('SMTP: conexão aprovada; entrega de e-mail ainda não homologada.\n');return true;}
    catch{this.runner.emit('AVISO: SMTP não validado. Plataforma preservada; revise SMTP no menu 12.\n');return false;}
  }
  async revision() { return (await this.git(['rev-parse','HEAD'], { quiet: true })).stdout.trim(); }
  async adopt(url) {
    sourceUrl(url); if (fs.existsSync(this.stateFile)) throw Error('Diretório já gerenciado.');
    const platform = fs.existsSync(path.join(this.root,'docker-compose.yml')) ? this.root : path.join(this.root,'platform');
    const env = envValues(path.join(platform,'.env'));
    const project = env.COMPOSE_PROJECT_NAME || 'amanda';
    if (!/^[a-z0-9][a-z0-9_-]{0,39}$/.test(project)) throw Error('Projeto existente inválido.');
    const profiles=env.COMPOSE_PROFILES===undefined?PROFILES:env.COMPOSE_PROFILES.split(',').filter(Boolean);
    if(profiles.some(p=>!['official','whatsmeow','rabbit','edge'].includes(p)))throw Error('Perfis Compose existentes não suportados.');
    this.state = { schema: 1, sourceUrl: SOURCE, project, platform, profiles, initialized: true, phase: 'ready', seedAttempted: false, seedSucceeded: false };
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
    const stopped = [...this.services().filter(x => x !== 'postgres'),...(this.state.profiles.includes('edge') ? ['edge'] : [])];
    try {
      for(const a of config.installerAddons)await this.docker([...a.base,'stop'],{label:'Pausando componente '+a.project+' para backup'});
      await this.compose(['stop',...stopped], { label: 'Pausando gravadores para backup consistente' });
      for (const name of this.databases()) await this.compose(['exec','-T','postgres','pg_dump','-U','amanda','-d',name,'-Fc'], { outputFile: path.join(dir,name+'.dump'), label: 'Backup do banco ' + name });
      const mounts = Object.entries(config.volumes).filter(([key]) => key !== 'postgres_data').flatMap(([key,v]) => ['--mount',`type=volume,source=${v.name},target=/data/${key},readonly`]);
      await this.docker(['run','--rm','--network','none',...mounts,'--mount',`type=bind,source=${dir},target=/backup`,'alpine:3.21','tar','-czf','/backup/volumes.tgz','-C','/data','.'], { label: 'Arquivando volumes de mídia, sessões, filas e certificados' });
      await this.docker(['run','--rm','--network','none','--mount',`type=bind,source=${dir},target=/backup,readonly`,'alpine:3.21','sh','-c','tar -tzf /backup/volumes.tgz >/dev/null'], { label: 'Verificando integridade do arquivo de volumes' });
      for (const file of ['.env','.env.backend','.env.oficial']) { const p = path.join(this.state.platform,file); if (fs.existsSync(p)) { fs.copyFileSync(p,path.join(dir,file)); fs.chmodSync(path.join(dir,file),0o600); } }
      for (const f of [...this.databases().map(n=>n+'.dump'),'volumes.tgz']) if (!fs.statSync(path.join(dir,f)).size) throw Error('Backup vazio: '+f);
      const accountFile = path.join(this.private,'admin-access.json');
      if (fs.existsSync(accountFile)) { fs.copyFileSync(accountFile,path.join(dir,'admin-access.json')); fs.chmodSync(path.join(dir,'admin-access.json'),0o600); }
      const addons=[];for(const a of config.installerAddons){const kind=a.project.slice(this.state.project.length+1),record=JSON.parse(fs.readFileSync(path.join(this.private,'addon-'+kind+'.json'),'utf8'));addons.push(record);const file='addon-'+kind+'.env';this.write(path.join(dir,file),fs.readFileSync(path.join(this.private,file),'utf8'));}
      const hashes={};for(const file of [...this.databases().map(n=>n+'.dump'),'volumes.tgz'])hashes[file]=await digest(path.join(dir,file));
      this.write(path.join(dir,'backup.json'), { complete: true, project: this.state.project, revision: this.state.revision, images, hashes,addons,databases:this.databases(),volumes:config.volumes });
      this.save({ ...this.state, lastBackup: dir }); return dir;
    } finally { if (restart) await this.startServices(); }
  }
  async imageIds() {
    const config = await this.configuration(), result = {};
    for (const name of this.services().filter(s=>['backend','frontend','api_transcricao','api_oficial'].includes(s))) {
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
      for(const type of ['declaredVolumes','networks'])for(const[key,value]of Object.entries(previousConfig[type]||{}))if(nextConfig[type]?.[key]?.name!==value.name)throw Error('Atualização alteraria recurso persistente: '+key);
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
    if(action==='resume'&&!fs.existsSync(this.stateFile))throw Error('Instalação ainda não registrada. Inicie pelo comando install.');
    if(action==='resume'){try{this.load({preparing:true});if(this.state.phase==='preparing'){const info=require('./deploy.cjs').inspectInstallation(this.root,this.state.project);if(info.savedConfig)await this.prepare(info.savedConfig,{resume:true});else await this.recoverLegacyPreparation();}}catch(e){if(e.code==='ENOENT')throw Error('Preparação interrompida: fonte ou configuração ausente. Preserve o diretório e revise a preparação antes de retomar; não repita seed.');throw e;}if(!this.state.initialized&&!this.state.freshResourcesVerified)throw Error('Preparação interrompida na fase '+this.state.phase+'. Preserve código, configuração e volumes; não é seguro assumir banco novo. Revise a preparação antes de retomar, sem repetir seed.');}
    this.load();await this.identifyManager(); await this.validateSource(); await this.configuration();
    if (action === 'update') return this.update();
    if (action === 'resume') {
      await this.validateSource(true);
      if(!this.state.initialized&&this.state.seedSucceeded&&['starting','https-pending'].includes(this.state.phase)){
        await this.verifyHealth(); await this.verifyLogin();
        this.save({...this.state,initialized:true,phase:'ready',revision:await this.revision()});
        this.runner.emit('Instalação concluída após validar serviços, HTTPS e login; sem build, migrations ou seed adicionais.\n');return;
      }
      await this.refreshInterruptedBuild();
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
    return require('./operation-lock.cjs').withLock(this,async()=>{try{return await this.operationScope.run(this,fn);}finally{require('./deploy.cjs').ownership(this);}});
  }
  async unlock() {
    return require('./operation-lock.cjs').withLock(this,null,true);
  }
}
module.exports = { SOURCE, CORE, PROFILES, sourceUrl, rootPath, normalizeConfig, envValues, editEnv, Runner, Manager };
