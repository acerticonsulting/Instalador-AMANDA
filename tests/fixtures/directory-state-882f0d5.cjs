const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const SOURCE='https://github.com/acerticonsulting/AMANDA.git';
const PHASES=new Set(['preparing','build','migrations','seed','starting','ready','preparing-update','migration-update']);
const hash=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
function inspectDirectory(root,{project,owner,logicalRoot=root}={}){
  const result={root,project};
  const reject=reason=>({...result,kind:'unknown',reason});
  const allowedOwners=new Set([0,owner?.uid,process.getuid?.()].filter(Number.isInteger));
  const allowedGroups=new Set([0,owner?.gid,process.getgid?.()].filter(Number.isInteger));
  function check(file,directory=false,privateFile=false){
    const s=fs.lstatSync(file);
    if(s.isSymbolicLink())throw Error('Link simbólico não pode ser usado para recuperação.');
    if((directory?!s.isDirectory():!s.isFile())||(!directory&&s.nlink!==1)||!allowedOwners.has(s.uid)||!allowedGroups.has(s.gid))throw Error('Tipo de arquivo ou proprietário não confirmado: '+path.relative(root,file).replace(/[\x00-\x1f\x7f]/g,''));
    if(privateFile&&(s.mode&0o077))throw Error('Arquivo privado com permissões abertas.');
    if(directory&&(s.mode&0o022))throw Error('Diretório gravável por terceiros; proprietário e permissões exigem diagnóstico.');
    return s;
  }
  try{
    if(!fs.existsSync(root)){
      if(fs.lstatSync(root,{throwIfNoEntry:false}))return reject('Link sem destino.');
      let parent=path.dirname(root);while(!fs.existsSync(parent))parent=path.dirname(parent);
      if(fs.realpathSync(parent)!==parent)return reject('Diretório pai contém link.');return {...result,kind:'absent'};
    }
    check(root,true);if(fs.realpathSync(root)!==root)return reject('Caminho contém link simbólico.');
    const entries=fs.readdirSync(root);if(!entries.length)return {...result,kind:'empty'};
    const privateDir=path.join(root,'.amanda-installer');
    if(!entries.includes('.amanda-installer'))return reject('Arquivos cuja origem não pôde ser confirmada.');
    check(privateDir,true);
    const knownPrivate=/^(?:state\.json(?:\.tmp)?|setup\.json|setup-files|install\.log|operation\.lock(?:\.guard)?|source-token|admin-access\.json|compose-names\.json|backups|config-history|docker-auth|registry-input|schedule-(?:backup|update)\.json|addon-(?:voz|hub|goflow)(?:\.json|\.env|-source-token))$/;
    const privateDirectories=new Set(['setup-files','backups','config-history','docker-auth']);
    for(const name of fs.readdirSync(privateDir)){
      if(!knownPrivate.test(name))return reject('Arquivo privado não reconhecido.');
      const file=path.join(privateDir,name),s=check(file,privateDirectories.has(name),!privateDirectories.has(name)&&name!=='operation.lock.guard');
      if(name==='operation.lock.guard'&&(s.size!==0||(s.mode&0o022)))throw Error('Guard sem integridade ou permissões seguras.');
      if(name==='setup-files'){
        for(const entry of fs.readdirSync(file)){
          if(!['.env','.env.example','.env.backend','.secrets'].includes(entry))throw Error('Arquivo de preparação desconhecido.');
          const p=path.join(file,entry);check(p,entry==='.secrets',entry!=='.secrets');
          if(entry==='.secrets')for(const secret of fs.readdirSync(p)){if(secret!=='github_token')throw Error('Segredo de preparação desconhecido.');check(path.join(p,secret),false,true);}
        }
      }
    }
    const stateFile=path.join(privateDir,'state.json'),setupFile=path.join(privateDir,'setup.json');
    let saved;
    if(fs.existsSync(setupFile)){
      check(setupFile,false,true);const record=JSON.parse(fs.readFileSync(setupFile,'utf8'));
      if(record.schema!==1||record.sourceUrl!==SOURCE||record.root!==logicalRoot||!record.config||hash(record.config)!==record.sha256||record.config.project!==project||record.config.sourceUrl!==SOURCE)throw Error('Configuração salva sem integridade ou identidade confirmada.');
      saved=record.config;
    }
    if(!fs.existsSync(stateFile)){
      if(entries.some(n=>n!=='.amanda-installer'))return reject('Há conteúdo sem estado confirmado da instalação.');
      const known=new Set(['install.log','operation.lock','operation.lock.guard','setup.json']);
      for(const name of fs.readdirSync(privateDir)){
        if(!known.has(name))return reject('Arquivo temporário não reconhecido; nenhum conteúdo foi alterado.');
        const file=path.join(privateDir,name),s=check(file,false,name!=='operation.lock.guard');
        if(name==='operation.lock.guard'&&s.size!==0)throw Error('Guard inválido.');
        if(name==='operation.lock'){
          const lock=JSON.parse(fs.readFileSync(file,'utf8'));
          if(lock.version!==2||typeof lock.token!=='string'||!lock.at||(!lock.process&&!lock.container))throw Error('Identidade do bloqueio não confirmada.');
        }
      }
      return {...result,kind:'temporary',savedConfig:saved};
    }
    check(stateFile,false,true);const state=JSON.parse(fs.readFileSync(stateFile,'utf8'));
    if(state.schema!==1||state.sourceUrl!==SOURCE||state.project!==project||!PHASES.has(state.phase)||typeof state.initialized!=='boolean'||typeof state.seedAttempted!=='boolean'||typeof state.seedSucceeded!=='boolean'||!Array.isArray(state.profiles)||state.profiles.some(p=>!['official','whatsmeow','rabbit','edge'].includes(p)))throw Error('Estado inválido ou de outra empresa.');
    if(state.platform!==logicalRoot&&state.platform!==path.join(logicalRoot,'platform'))throw Error('Plataforma fora do caminho registrado.');
    if(state.initialized&&state.phase==='preparing'||state.phase==='ready'&&!state.initialized||state.seedSucceeded&&!state.seedAttempted)throw Error('Checkpoint inconsistente.');
    for(const key of ['freshResourcesVerified','resourcesClaimed','configurationReady'])if(state[key]!==undefined&&typeof state[key]!=='boolean')throw Error('Checkpoint de recursos inválido.');
    if(state.configurationFiles){
      if(typeof state.configurationFiles!=='object'||Array.isArray(state.configurationFiles)||!state.configurationFiles['.env']||Object.entries(state.configurationFiles).some(([name,digest])=>!['.env','.env.backend'].includes(name)||typeof digest!=='string'||!/^[a-f0-9]{64}$/.test(digest))||!/^[a-f0-9]{64}$/.test(state.adminFingerprint||''))throw Error('Manifesto da configuração em preparação inválido.');
    }
    if(state.deploymentOwner&&(state.deploymentOwner.uid!==owner?.uid||state.deploymentOwner.gid!==owner?.gid))throw Error('Proprietário deploy registrado não corresponde à conta atual.');
    if(state.platform!==logicalRoot&&entries.some(n=>!['.amanda-installer','platform','addons','instances','imports'].includes(n)))return reject('Arquivos desconhecidos ao lado da instalação.');
    const platform=state.platform===logicalRoot?root:path.join(root,'platform');
    if(fs.existsSync(platform)){check(platform,true);if(fs.realpathSync(platform)!==platform)throw Error('Plataforma é um link.');}
    else if(state.phase!=='preparing')throw Error('Código da plataforma ausente no checkpoint registrado.');
    for(const name of ['.env','.env.backend','.env.oficial']){const file=path.join(platform,name);if(fs.lstatSync(file,{throwIfNoEntry:false}))check(file,false,true);}
    return {...result,kind:state.initialized&&state.phase==='ready'?'complete':'partial',phase:state.phase,state,savedConfig:saved};
  }catch(error){return reject(error.code==='ENOENT'?'Caminho ou estado incompleto.':error instanceof SyntaxError?'Estado ou configuração JSON inválidos.':error.message);}
}
function conflict(info){return `Diretório não vazio ou estado não reconhecido. O diretório ${info.root} contém arquivos cuja origem ou estado não pôde ser confirmado. ${info.reason||''} Nenhum arquivo foi alterado. Escolha outra empresa ou consulte o diagnóstico; não apague dados para forçar a instalação.`;}
function setupRecord(root,config){return {schema:1,sourceUrl:SOURCE,root,sha256:hash(config),config};}
module.exports={inspectDirectory,conflict,setupRecord};
