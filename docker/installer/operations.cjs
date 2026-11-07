const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const { CORE,normalizeConfig,envValues,Manager }=require('./manager.cjs');
const { writeEnv,validateOptions,digest }=require('./options.cjs');

class Operations {
  constructor(manager){this.m=manager;}
  async ready(restoring=false,configuring=false){const m=this.m;await m.doctor();m.load();await m.validateSource();await m.configuration();if(configuring&&!m.state.initialized&&m.state.seedSucceeded&&m.state.phase==='starting')return;if(!m.state.initialized||(m.state.phase!=='ready'&&!(restoring&&m.state.phase==='restoring')))throw Error('Instalação incompleta. Use Retomar operação ou repita a restauração registrada.');}
  service(name){if(![...CORE,'edge'].includes(name))throw Error('Serviço inválido.');return name;}
  async services(action,name){await this.ready();if(name)this.service(name);if(!['ps','restart','stop','start','logs','rm'].includes(action))throw Error('Operação inválida.');
    const args=action==='ps'?['ps','--all']:action==='logs'?['logs','--no-color','--tail','200']:action==='start'?['up','-d','--no-deps','--wait']:action==='rm'?['rm','-s','-f']:[action];
    if(name)args.push(name);else if(['restart','stop','start','rm'].includes(action))args.push(...CORE,...(this.m.state.profiles.includes('edge')?['edge']:[]));
    await this.m.compose(args,{label:'Gerenciamento de serviços Docker'});
  }
  current(){const m=this.m;const e=envValues(path.join(m.state.platform,'.env'));return {sourceUrl:m.state.sourceUrl,project:m.state.project,frontendUrl:e.FRONTEND_URL,backendUrl:e.BACKEND_URL,edge:m.state.profiles.includes('edge'),public:e.BIND_ADDRESS==='0.0.0.0',options:{officialPort:+e.PORT_APIOFICIAL||6000,wuzapiPort:+e.PORT_WUZAPI||8090,officialUrl:e.OFICIAL_HOST?`https://${e.OFICIAL_HOST}`:undefined}};}
  async configure({ network, backendEnv={}, supportPhone, pg, pushEmail }={}){
    await this.ready(false,true);const m=this.m,root={},backend={...backendEnv};validateOptions({backendEnv,...(supportPhone!==undefined?{supportPhone}:{})});
    const beforeState={...m.state};
    if(network){const c=normalizeConfig({...this.current(),...network});const f=new URL(c.frontendUrl),b=new URL(c.backendUrl);
      Object.assign(root,{FRONTEND_URL:c.frontendUrl,BACKEND_URL:c.backendUrl,ALLOWED_ORIGINS:c.frontendUrl,FRONTEND_HOST:f.hostname,BACKEND_HOST:b.hostname,BIND_ADDRESS:c.public&&!c.edge?'0.0.0.0':'127.0.0.1',PORT_FRONTEND:c.edge?3000:+(f.port||80),PORT_BACKEND:c.edge?8080:+(b.port||80),PORT_APIOFICIAL:c.options.officialPort||6000,PORT_WUZAPI:c.options.wuzapiPort||8090,OFICIAL_HOST:c.options.officialUrl?new URL(c.options.officialUrl).hostname:``});
      m.state={...m.state,profiles:['official','whatsmeow','rabbit',...(c.edge?['edge']:[])],frontendUrl:c.frontendUrl,backendUrl:c.backendUrl};root.COMPOSE_PROFILES=m.state.profiles.join(',');
    }
    for(const key of ['TRANSCRIBE_URL','URL_API_OFICIAL','WUZAPI_URL','GO_CAMPAIGN_DISPATCHER_URL','USE_GO_CAMPAIGN_DISPATCHER'])if(backend[key]!==undefined){root[key]=backend[key];delete backend[key];}
    if(supportPhone!==undefined)root.REACT_APP_NUMBER_SUPPORT=supportPhone;
    if(pg){if(![100,200,300].includes(pg.maxConnections)||!['128MB','256MB','512MB','1GB'].includes(pg.sharedBuffers))throw Error('Perfil PostgreSQL inválido.');Object.assign(root,{PG_MAX_CONNECTIONS:pg.maxConnections,PG_SHARED_BUFFERS:pg.sharedBuffers});}
    if(pushEmail){if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(pushEmail))throw Error('E-mail VAPID inválido.');const old=fs.existsSync(path.join(m.state.platform,'.env.backend'))?envValues(path.join(m.state.platform,'.env.backend')):{};
      if(old.VAPID_PUBLIC_KEY&&old.VAPID_PRIVATE_KEY){m.runner.emit('Chaves push existentes preservadas.\n');}
      else{const ecdh=crypto.createECDH('prime256v1');ecdh.generateKeys();backend.VAPID_PUBLIC_KEY=ecdh.getPublicKey().toString('base64url');backend.VAPID_PRIVATE_KEY=ecdh.getPrivateKey().toString('base64url');}
      backend.VAPID_SUBJECT='mailto:'+pushEmail;
    }
    for(const [k,v]of Object.entries({...root,...backend}))if(/PASS|SECRET|KEY|TOKEN/.test(k))m.runner.secret(v);
    const files=['.env','.env.backend'],saved=new Map(files.map(f=>{const p=path.join(m.state.platform,f);return[p,fs.existsSync(p)?fs.readFileSync(p):null];}));
    const safe=path.join(m.private,'config-history',new Date().toISOString().replace(/[:.]/g,'-'));for(const[p,v]of saved)if(v)m.write(path.join(safe,path.basename(p)),v.toString());
    try{
      writeEnv(path.join(m.state.platform,'.env'),root);if(Object.keys(backend).length)writeEnv(path.join(m.state.platform,'.env.backend'),backend);await m.configuration();
      if(pg){await m.backup({restart:false});await m.compose(['up','-d','--no-deps','--wait','postgres'],{label:'Aplicando configuração PostgreSQL no container'});}
      if(beforeState.profiles.includes('edge')&&!m.state.profiles.includes('edge'))await m.compose(['--profile','edge','stop','edge']);
      await m.startServices();m.save(m.state);m.runner.emit('Configurações aplicadas e serviços verificados. Histórico privado: '+safe+'\n');
    }catch(error){for(const[p,v]of saved){if(v)fs.writeFileSync(p,v,{mode:0o600});else if(fs.existsSync(p))fs.unlinkSync(p);}m.state=beforeState;m.save(beforeState);await m.startServices();throw error;}
  }
  async identity(appName,email,password){
    validateOptions({appName});return this.settings({appName},email,password);
  }
  async settings(values,email,password){
    await this.ready();const m=this.m;
    for(const[k,v]of Object.entries(values)){if(!['appName','amandaVozUrl','hubLocalUrl','hubLocalAdminKey'].includes(k)||typeof v!=='string'||/[\r\n\0]/.test(v))throw Error('Configuração de plataforma inválida.');if(k==='appName')validateOptions({appName:v});if(k.endsWith('Url')&&v){const u=new URL(v);if(!['http:','https:'].includes(u.protocol)||u.username||u.password||u.hash)throw Error('URL inválida.');}if(k.endsWith('Key'))m.runner.secret(v);}
    m.runner.secret(password);
    const script=`(async()=>{const r=await fetch('http://127.0.0.1:8080/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:process.env.A_EMAIL,password:process.env.A_PASSWORD})});if(r.status!==200)throw Error();const a=await r.json();for(const[key,value]of Object.entries(JSON.parse(process.env.A_SETTINGS))){const s=await fetch('http://127.0.0.1:8080/settings/'+key,{method:'PUT',headers:{Authorization:'Bearer '+a.token,'Content-Type':'application/json'},body:JSON.stringify({value})});if(s.status!==200)throw Error();}console.log('Configuração sincronizada pela API autenticada.')})().catch(()=>process.exit(1))`;
    await m.compose(['exec','-T','-e','A_EMAIL','-e','A_PASSWORD','-e','A_SETTINGS','backend','node','-e',script],{env:{A_EMAIL:email,A_PASSWORD:password,A_SETTINGS:JSON.stringify(values)},label:'Atualizando configurações pela API autenticada'});
  }
  async databases(){await this.ready();return this.m.compose(['exec','-T','postgres','psql','-U','amanda','-d','postgres','-c','SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname'],{label:'Bancos do PostgreSQL da instância'});}
  async checkBackup(dir){
    const m=this.m,base=fs.realpathSync(path.join(m.private,'backups')),real=fs.realpathSync(dir);if(!real.startsWith(base+path.sep))throw Error('Selecione backup desta instância dentro da pasta privada.');
    const data=JSON.parse(fs.readFileSync(path.join(real,'backup.json'),'utf8'));if(!data.complete||data.project!==m.state.project||!data.hashes)throw Error('Backup incompleto, antigo sem hashes ou de outra instância.');
    for(const name of['amanda.dump','api_oficial.dump','volumes.tgz'])if(await digest(path.join(real,name))!==data.hashes[name])throw Error('Integridade do backup inválida: '+name);
    for(const name of['amanda','api_oficial'])await m.compose(['exec','-T','postgres','pg_restore','--list'],{inputFile:path.join(real,name+'.dump'),quiet:true,label:'Validando arquivo PostgreSQL '+name});
    return{dir:real,data};
  }
  async restore(dir,kind,confirmation,{start=true,allowRevision=false}={}){
    await this.ready(true);const m=this.m;if(!['all','amanda','api_oficial','redis','wuzapi'].includes(kind))throw Error('Destino inválido.');if(confirmation!=='RESTAURAR '+m.state.project)throw Error('Confirmação de restauração não confere.');
    await m.validateSource(true);
    const backup=await this.checkBackup(dir);
    if(!allowRevision&&['all','amanda','api_oficial'].includes(kind)&&backup.data.revision!==m.state.revision)throw Error('Backup de outra revisão. Use rollback completo para recuperar código e esquema juntos.');
    const config=await m.configuration();
    if(backup.data.volumes&&JSON.stringify(Object.entries(backup.data.volumes).map(([k,v])=>[k,v.name]).sort())!==JSON.stringify(Object.entries(config.volumes).map(([k,v])=>[k,v.name]).sort()))throw Error('Volumes do backup diferem do contrato atual. Recuperação exige ambiente isolado com o contrato original.');
    if(!allowRevision&&kind==='all'&&JSON.stringify((backup.data.addons||[]).map(a=>a.project+':'+a.revision).sort())!==JSON.stringify(config.installerAddons.map(a=>a.project+':'+a.revision).sort()))throw Error('Componentes externos de outra revisão. Use rollback completo.');
    if(m.state.phase==='restoring'){if(m.state.restoreBackup!==backup.dir||m.state.restoreKind!==kind)throw Error('Retome a mesma restauração interrompida antes de escolher outra.');}
    else{await m.backup({restart:false,allowUnhealthy:true});m.save({...m.state,phase:'restoring',restoreBackup:backup.dir,restoreKind:kind});}
    try{
      for(const db of(kind==='all'?['amanda','api_oficial']:['amanda','api_oficial'].includes(kind)?[kind]:[])){
        await m.compose(['exec','-T','postgres','dropdb','-U','amanda','--force','--if-exists',db],{label:'Recriando banco selecionado '+db});
        await m.compose(['exec','-T','postgres','createdb','-U','amanda',db]);
        await m.compose(['exec','-T','postgres','pg_restore','--exit-on-error','--single-transaction','--no-owner','-U','amanda','-d',db],{inputFile:path.join(backup.dir,db+'.dump'),label:'Restaurando banco '+db});
      }
      const keys=kind==='all'?Object.keys(config.volumes).filter(k=>k!=='postgres_data'):kind==='redis'?['redis_data']:kind==='wuzapi'?['wuzapi_data']:[];
      if(keys.length){
        const listing=(await m.docker(['run','--rm','--network','none','--mount',`type=bind,source=${backup.dir},target=/backup,readonly`,'alpine:3.21','tar','-tzf','/backup/volumes.tgz'],{quiet:true})).stdout;
        for(const entry of listing.split('\n').filter(Boolean)){if(entry==='./'||entry==='.')continue;if(entry.startsWith('/')||entry.split('/').includes('..')||!Object.keys(config.volumes).includes(entry.replace(/^\.\//,'').split('/')[0]))throw Error('Caminho inválido no arquivo de volumes.');}
        for(const key of keys)if(!listing.split('\n').some(p=>p==='./'+key+'/'||p.startsWith('./'+key+'/')))throw Error('Volume ausente no arquivo: '+key);
        for(const key of keys){const volume=config.volumes[key].name;
          await m.docker(['run','--rm','--network','none','--mount',`type=volume,source=${volume},target=/target`,'alpine:3.21','sh','-c','find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +'],{label:'Limpando somente volume selecionado '+key});
          await m.docker(['run','--rm','--network','none','--mount',`type=volume,source=${volume},target=/target`,'--mount',`type=bind,source=${backup.dir},target=/backup,readonly`,'alpine:3.21','tar','-xzf','/backup/volumes.tgz','--strip-components=2','-C','/target','./'+key],{label:'Restaurando volume '+key});
        }
      }
      if(start){await m.startServices();m.save({...m.state,phase:'ready'});}
    }catch(error){for(const a of config.installerAddons)await m.docker([...a.base,'stop']);await m.compose(['stop',...CORE.filter(s=>s!=='postgres')]);m.runner.emit('Restauração falhou. Aplicação permanece parada; preservar volumes e backup anterior.\n');throw error;}
  }
  async rollback(dir,confirmation){
    await this.ready(true);const m=this.m;await m.validateSource(true);const b=await this.checkBackup(dir);if(!/^[a-f0-9]{40}$/.test(b.data.revision))throw Error('Revisão do backup inválida.');
    if(confirmation!=='RESTAURAR '+m.state.project)throw Error('Confirmação inválida.');
    // restore takes the pre-operation backup while source/configuration still match production.
    await this.restore(dir,'all',confirmation,{start:false,allowRevision:true});
    m.save({...m.state,phase:'restoring',restoreBackup:b.dir});
    await m.git(['checkout','--detach',b.data.revision],{label:'Recuperando revisão registrada no backup'});await m.restoreTags(b.data.images);
    for(const a of b.data.addons||[]){const kind=a.project.slice(m.state.project.length+1),expected=path.join(m.root,'addons',kind);if(!['voz','hub','goflow'].includes(kind)||a.dir!==expected||!/^[a-f0-9]{40}$/.test(a.revision))throw Error('Registro de componente inválido no backup.');await m.runner.run('git',['-c','safe.directory='+expected,'checkout','--detach',a.revision],{cwd:expected,label:'Recuperando componente '+kind});m.write(path.join(m.private,'addon-'+kind+'.json'),a);m.write(path.join(m.private,'addon-'+kind+'.env'),fs.readFileSync(path.join(b.dir,'addon-'+kind+'.env'),'utf8'));}
    for(const file of['.env','.env.backend','.env.oficial'])if(fs.existsSync(path.join(b.dir,file)))m.write(path.join(m.state.platform,file),fs.readFileSync(path.join(b.dir,file),'utf8'));
    const restored=envValues(path.join(m.state.platform,'.env'));m.state={...m.state,profiles:['official','whatsmeow','rabbit',...((restored.COMPOSE_PROFILES||'').split(',').includes('edge')?['edge']:[])],frontendUrl:restored.FRONTEND_URL,backendUrl:restored.BACKEND_URL};
    await m.startServices();m.save({...m.state,phase:'ready',revision:b.data.revision});
  }
  async importDatabase(file,db,confirmation){
    await this.ready(true);const m=this.m;if(!['amanda','api_oficial'].includes(db)||confirmation!=='IMPORTAR '+m.state.project)throw Error('Destino ou confirmação de importação inválidos.');
    await m.validateSource(true);
    const base=fs.realpathSync(path.join(m.root,'imports')),source=fs.realpathSync(file);if(!source.startsWith(base+path.sep))throw Error('Coloque o arquivo na pasta imports desta instância.');
    const isSql=/\.sql$/i.test(source);if(!isSql&&!/\.(dump|backup)$/i.test(source))throw Error('Use arquivo .sql ou pg_dump custom .dump/.backup.');
    if(!fs.statSync(source).size)throw Error('Arquivo de backup vazio.');
    if(isSql){const readline=require('node:readline');let copying=false;for await(const line of readline.createInterface({input:fs.createReadStream(source),crlfDelay:Infinity})){
      if(copying){if(line==='\\.')copying=false;continue;}if(/^COPY\s.+\sFROM stdin;\s*$/i.test(line)){copying=true;continue;}
      if(/^\s*\\/.test(line)&&!/^\s*\\(?:restrict|unrestrict)\b/.test(line))throw Error('SQL contém comando psql não permitido. Use backup pg_dump de um único banco.');
      if(/^\s*(?:CREATE\s+DATABASE|DROP\s+DATABASE|ALTER\s+SYSTEM)\b/i.test(line))throw Error('SQL de cluster/configuração não permitido; importe somente um banco.');
    }}else await m.compose(['exec','-T','postgres','pg_restore','--list'],{inputFile:source,quiet:true,label:'Validando backup importado'});
    const hash=await digest(source);if(m.state.phase==='restoring'){if(m.state.importFile!==source||m.state.importDatabase!==db||m.state.importHash!==hash)throw Error('Retome a mesma importação interrompida.');}
    else{await m.backup({restart:false,allowUnhealthy:true});m.save({...m.state,phase:'restoring',importFile:source,importDatabase:db,importHash:hash});}
    try{
      await m.compose(['exec','-T','postgres','dropdb','-U','amanda','--force','--if-exists',db]);await m.compose(['exec','-T','postgres','createdb','-U','amanda',db]);
      const command=isSql?['psql','-X','--single-transaction','--set','ON_ERROR_STOP=1','-U','amanda','-d',db]:['pg_restore','--single-transaction','--exit-on-error','--no-owner','-U','amanda','-d',db];
      await m.compose(['exec','-T','postgres',...command],{inputFile:source,label:'Importando backup escolhido sem seeds'});
      await m.migrations();await m.startServices();m.save({...m.state,phase:'ready'});
    }catch(error){for(const a of(await m.configuration()).installerAddons)await m.docker([...a.base,'stop']);await m.compose(['stop',...CORE.filter(s=>s!=='postgres')]);m.runner.emit('Importação falhou. Repita a mesma importação corrigindo a causa ou recupere pelo backup anterior em ambiente isolado.\n');throw error;}
  }
  async uninstall(erase,confirmation){
    await this.ready();const m=this.m,config=await m.configuration();if(confirmation!==(erase?'DELETAR TUDO ':'REMOVER ')+m.state.project)throw Error('Confirmação inválida.');
    await m.validateSource(true);
    if(erase){await m.backup();for(const v of Object.values(config.volumes)){const r=await m.docker(['volume','inspect','--format','{{json .Labels}}',v.name],{quiet:true,allowFailure:true});const owner=r.code===0?JSON.parse(r.stdout||'{}')?.['com.docker.compose.project']:null;if(r.code===0&&(![m.state.project,...config.installerAddons.map(a=>a.project)].includes(owner)||!v.name.startsWith(owner+'_')))throw Error('Volume sem propriedade comprovada: '+v.name);}}
    for(const a of config.installerAddons)await m.docker([...a.base,'down',...(erase?['--volumes']:[])]);
    for(const action of['backup','update']){const name=m.state.project+'-agendador-'+action,r=await m.docker(['inspect','--format','{{index .Config.Labels "amanda.installer.project"}}',name],{quiet:true,allowFailure:true});if(r.code===0&&r.stdout.trim()===m.state.project)await m.docker(['rm','-f',name]);}
    await m.compose(['down',...(erase?['--volumes']:[])],{label:erase?'Removendo containers e volumes da instância confirmada':'Removendo containers; volumes preservados'});
    if(erase)m.save({...m.state,phase:'removed',initialized:false});m.runner.emit('Arquivos de configuração, código e backups foram preservados.\n');
  }
  async schedule(action,hour){
    await this.ready();const m=this.m;if(!['backup','update'].includes(action)||!Number.isInteger(hour)||hour<0||hour>23)throw Error('Agendamento inválido.');
    const file=path.join(m.private,'schedule-'+action+'.json');m.write(file,{action,hour,timezone:'UTC'});const name=m.state.project+'-agendador-'+action;
    const existing=await m.docker(['inspect','--format','{{index .Config.Labels "amanda.installer.project"}}',name],{quiet:true,allowFailure:true});
    if(existing.code===0){if(existing.stdout.trim()!==m.state.project)throw Error('Container de agendamento pertence a outro proprietário.');await m.docker(['rm','-f',name]);}
    await m.docker(['run','-d','--restart','unless-stopped','--name',name,'--label','amanda.installer.project='+m.state.project,'--mount','type=bind,source='+(process.env.AMANDA_DOCKER_SOCKET||'/var/run/docker.sock')+',target=/var/run/docker.sock','--mount',`type=bind,source=${m.root},target=${m.root}`,'-e','DOCKER_HOST=unix:///var/run/docker.sock','-e','AMANDA_INSTALL_DIR='+m.root,'-e','AMANDA_DOCKER_SOCKET='+(process.env.AMANDA_DOCKER_SOCKET||'/var/run/docker.sock'),'--entrypoint','node',process.env.AMANDA_MANAGER_IMAGE || 'amanda-installer:local','/opt/amanda-installer/scheduler.cjs',action],{label:'Instalando agendador Docker, horário UTC '+hour+':00'});
  }
  async portainer(port){await this.ready();if(!Number.isInteger(port)||port<1||port>65535)throw Error('Porta inválida.');const m=this.m;
    await m.docker(['run','-d','--restart','unless-stopped','--name',m.state.project+'-portainer','--label','amanda.installer.project='+m.state.project,'-p','127.0.0.1:'+port+':9443','--mount','type=bind,source='+(process.env.AMANDA_DOCKER_SOCKET||'/var/run/docker.sock')+',target=/var/run/docker.sock','--mount',`type=volume,source=${m.state.project}_portainer_data,target=/data`,'portainer/portainer-ce:latest'],{label:'Instalando Portainer em container, acesso restrito ao servidor'});
    m.runner.emit('Portainer: https://localhost:'+port+' — concluir cadastro administrativo pelo navegador.\n');}
  async ghcr(username,token){await this.ready();if(!/^[a-zA-Z0-9-]+$/.test(username)||!token||/[\r\n]/.test(token))throw Error('Credencial GHCR inválida.');const m=this.m;m.runner.secret(token);const dir=path.join(m.private,'docker-auth'),file=path.join(m.private,'registry-input');fs.mkdirSync(dir,{recursive:true,mode:0o700});m.write(file,token);
    try{await m.docker(['--config',dir,'login','ghcr.io','--username',username,'--password-stdin'],{inputFile:file,label:'Autenticando no GHCR com credencial privada'});const config=path.join(dir,'config.json');if(fs.existsSync(config))fs.chmodSync(config,0o600);}finally{fs.unlinkSync(file);}}
  async instance(config){const m=this.m,c=normalizeConfig(config);if(c.project===m.state?.project)throw Error('Use nome diferente para a nova instância.');const nested=new Manager(path.join(m.root,'instances',c.project));await nested.lock(async()=>{await nested.doctor();await nested.prepare(c);await nested.build();await nested.initialize();});return nested;}
}
for(const name of ['services','configure','identity','settings','databases','restore','rollback','importDatabase','uninstall','schedule','portainer','ghcr','instance']){
  const action=Operations.prototype[name];Operations.prototype[name]=function(...args){return this.m.lock(()=>action.apply(this,args));};
}
module.exports={Operations};
