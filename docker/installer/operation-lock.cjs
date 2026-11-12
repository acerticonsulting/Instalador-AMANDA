const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {spawn}=require('node:child_process');
function processIdentity(pid){
  const stat=fs.readFileSync('/proc/'+pid+'/stat','utf8');
  return stat.slice(stat.lastIndexOf(')')+2).split(' ')[19];
}
function identity(){return {boot:fs.readFileSync('/proc/sys/kernel/random/boot_id','utf8').trim(),pid:process.pid,start:processIdentity(process.pid)};}
async function guard(file){
  const child=spawn('flock',['-n',file,'sh','-c','printf READY; cat >/dev/null'],{stdio:['pipe','pipe','pipe']});
  const closed=new Promise(resolve=>child.once('close',resolve));
  child.stdin.on('error',()=>{});
  await new Promise((resolve,reject)=>{child.once('error',()=>reject(Error('Ferramenta flock indisponível no gerenciador.')));child.once('close',code=>reject(Error(code===1?'Outra operação AMANDA está em andamento; aguarde seu encerramento.':'Falha na proteção atômica do diretório (código '+code+'). Verifique permissões e filesystem.')));child.stdout.once('data',()=>resolve());});
  return async()=>{child.stdin.end();await closed;};
}
function read(file){const stat=fs.lstatSync(file);if(!stat.isFile()||stat.isSymbolicLink())throw Error('Lock sem identidade segura; revisão manual necessária.');let data;try{data=JSON.parse(fs.readFileSync(file,'utf8'));if(!data||typeof data!=='object')throw Error();}catch{throw Error('Lock inválido; revisão manual necessária.');}return {stat,data};}
function same(file,record){const current=read(file);return current.stat.ino===record.stat.ino&&current.stat.dev===record.stat.dev&&JSON.stringify(current.data)===JSON.stringify(record.data);}
async function abandoned(manager,data){
  if(data.container){
    if(!/^[a-f0-9]{12,64}$/.test(data.container))throw Error('Lock sem identificação Docker; revisão manual necessária.');
    const r=await manager.docker(['inspect','--format','{{.State.Running}}',data.container],{quiet:true,allowFailure:true});
    if(r.code===0){if(r.stdout.trim()==='true')return false;if(r.stdout.trim()==='false')return true;throw Error('Estado do proprietário desconhecido.');}
    // Falha de inspect não comprova ausência: exigir consulta bem-sucedida ao daemon.
    const list=await manager.docker(['container','ls','-a','--no-trunc','--format','{{.ID}}'],{quiet:true});
    if(list.code!==0)throw Error('Não foi possível validar o proprietário do lock.');
    return !list.stdout.trim().split(/\s+/).some(id=>id.startsWith(data.container));
  }
  if(!data.process||!Number.isInteger(data.process.pid)||data.process.pid<1||!/^\d+$/.test(data.process.start||''))throw Error('Lock sem identificação do proprietário; revisão manual necessária.');
  const current=identity();if(data.process.boot!==current.boot)throw Error('Identidade do host não confirmada; revisão manual necessária.');
  try{return processIdentity(data.process.pid)!==data.process.start;}catch(e){if(e.code==='ENOENT')return true;throw e;}
}
async function recover(manager,file){
  if(!fs.existsSync(file))return;
  const record=read(file);
  if(!await abandoned(manager,record.data))throw Error('Outra operação AMANDA está em andamento. Proprietário: '+(record.data.container||'processo '+record.data.process.pid)+'; iniciada em: '+String(record.data.at||'desconhecida').replace(/[^0-9TZ:.+-]/g,'')+'. Diretório: '+manager.root);
  if(!same(file,record))throw Error('O proprietário do lock mudou durante a verificação.');
  fs.unlinkSync(file);manager.runner.emit('Bloqueio comprovadamente abandonado recuperado; dados preservados.\n');
}
async function withLock(manager,fn,unlock=false){
  fs.mkdirSync(manager.private,{recursive:true,mode:0o700});
  const file=path.join(manager.private,'operation.lock');let release;
  try{release=await guard(file+'.guard');}catch(e){
    if(fs.existsSync(file)){try{const {data}=read(file),owner=/^[a-f0-9]{12,64}$/.test(data.container||'')?data.container:Number.isInteger(data.process?.pid)?'processo '+data.process.pid:'não confirmado';e.message+=' Proprietário: '+owner+'; início: '+String(data.at||'').replace(/[^0-9TZ:.+-]/g,'')+'; diretório: '+manager.root;}catch{}}
    throw e;
  }
  try{
    await recover(manager,file);if(unlock)return;
    const data={version:2,token:crypto.randomUUID(),at:new Date().toISOString(),...(process.env.AMANDA_MANAGER_CONTAINER?{container:process.env.HOSTNAME}:{process:identity()})};
    fs.writeFileSync(file,JSON.stringify(data),{flag:'wx',mode:0o600});const record=read(file);
    try{return await fn();}catch(e){manager.runner.emit('Operação encerrada com falha; consulte o estado e use resume se necessário.\n');throw e;}
    finally{if(fs.existsSync(file)&&same(file,record))fs.unlinkSync(file);}
  }finally{await release();}
}
module.exports={withLock,identity};
