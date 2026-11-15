const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const MODES=['quick','backend','runtime','frontend','official','wuzapi','transcription','infrastructure','unit','all'];
function compare(a,b){const old=new Map(a.map(r=>[r.id,r])),now=new Map(b.map(r=>[r.id,r]));return {newFailures:b.filter(r=>r.status==='failed'&&old.get(r.id)?.status!=='failed'),fixed:b.filter(r=>r.status==='passed'&&old.get(r.id)?.status==='failed'),persistent:b.filter(r=>r.status==='failed'&&old.get(r.id)?.status==='failed'),notRetested:a.filter(r=>!now.has(r.id)),newTests:b.filter(r=>!old.has(r.id))};}
class Audit{
 constructor(m){this.m=m;this.base=path.join(m.private,'diagnostics');}
 list(){return fs.existsSync(this.base)?fs.readdirSync(this.base).filter(n=>/^audit_[0-9TZ_-]+_[a-f0-9]{12}$/.test(n)&&!fs.lstatSync(path.join(this.base,n)).isSymbolicLink()).sort():[];}
 read(id){if(!this.list().includes(id))throw Error('Relatório fora desta instância.');const dir=path.join(this.base,id);const files=fs.readdirSync(dir).filter(n=>/^amanda_audit_\d+_[a-f0-9]{6}$/.test(n)&&!fs.lstatSync(path.join(dir,n)).isSymbolicLink());const file=files[0]&&path.join(dir,files[0],'results.json');return {execution:JSON.parse(fs.readFileSync(path.join(dir,'execucao.json'))),report:file&&fs.existsSync(file)?JSON.parse(fs.readFileSync(file)):null};}
 async run(mode){
  if(!MODES.includes(mode))throw Error('Categoria não suportada.');const m=this.m;
  const id='audit_'+new Date().toISOString().replace(/[:.]/g,'_')+'_'+crypto.randomBytes(6).toString('hex'),dir=path.join(this.base,id);
  const record={id,mode,project:path.basename(m.root),startedAt:new Date().toISOString(),localStart:new Date().toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'})+' America/Sao_Paulo',complete:false,functionalStatus:'NÃO VALIDADA'};
  m.write(path.join(dir,'execucao.json'),record);m.write(path.join(dir,'diagnostico.log'),'Início UTC: '+record.startedAt+'\n');
  try{
   await new(require('./operations.cjs').Operations)(m).ready();const config=await m.configuration();
   Object.assign(record,{project:m.state.project,revision:await m.revision(),profiles:m.state.profiles,images:Object.fromEntries(Object.entries(config.services).map(([k,s])=>[k,s.image]).filter(([,v])=>v))});m.write(path.join(dir,'execucao.json'),record);
   if(mode==='quick'){await m.verifyHealth();record.operationalStatus='Verificações existentes aprovadas; saúde funcional não medida';}
   else{
    const runner=path.join(m.state.platform,'tests/platform/run.cjs');if(!fs.existsSync(runner))throw Error('Suíte tests/platform ausente; atualize a plataforma antes de usar a central.');
    // Versão com adaptador é necessária para nunca usar imagens de outra instalação.
    if(!fs.readFileSync(runner,'utf8').includes('AUDIT_RUN_BASE'))throw Error('Suíte antiga: requer adaptador AUDIT_RUN_BASE/imagens dinâmicas.');
    const env={AUDIT_RUN_BASE:dir,TZ:'America/Sao_Paulo'};
    for(const[key,service]of Object.entries({BACKEND:'backend',FRONTEND:'frontend',OFFICIAL:'api_oficial',TRANSCRIPTION:'api_transcricao'})){
     if(!config.services[service]?.image)throw Error('Suíte isolada atual requer imagem '+service+'; serviço opcional ausente não é falha funcional.');env['AUDIT_'+key+'_IMAGE']=config.services[service].image;
    }
    await m.runner.run(process.execPath,[runner,'--'+mode],{cwd:m.state.platform,env,label:'Auditoria isolada: '+mode});
    record.operationalStatus='Consulte resultados por serviço';record.functionalStatus='VALIDAÇÃO PARCIAL — lacunas em inventory.json/results.json';
   }
   record.complete=true;
  }catch(error){record.error=m.runner.mask?m.runner.mask(error.message):'Execução bloqueada ou falhou; consulte log privado.';record.operationalStatus='INCOMPLETO';}
  finally{record.finishedAt=new Date().toISOString();m.write(path.join(dir,'execucao.json'),record);fs.appendFileSync(path.join(dir,'diagnostico.log'),JSON.stringify(record)+'\n');}
  m.runner.emit('AUDITORIA '+(record.complete?'FINALIZADA (cobertura parcial)':'INCOMPLETA')+'\nSaúde funcional: '+record.functionalStatus+'\nRelatórios privados: '+dir+'\n');return record;
 }
}
module.exports={Audit,MODES,compare};
