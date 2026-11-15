const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const MODES=['quick','backend','runtime','frontend','official','wuzapi','transcription','infrastructure','unit','all','flowbuilder','campaigns','webhooks','tickets'];
function selection(value){const names=value.split(',');if(names.some(n=>!MODES.includes(n))||(names.length>1&&names.some(n=>['quick','all','runtime'].includes(n))))throw Error('Categoria não suportada.');return [...new Set(names)].join(',');}
function completion(dir,code){const children=fs.readdirSync(dir).filter(n=>/^amanda_audit_\d+_[a-f0-9]{6}$/.test(n));if(children.length!==1)return 'INCOMPLETA';const base=path.join(dir,children[0]),read=n=>fs.existsSync(path.join(base,n))?JSON.parse(fs.readFileSync(path.join(base,n))):null;if(read('orchestrator-error.json'))return 'INCOMPLETA';const marker=read('execution.json'),report=read('results.json'),unit=read('unit-status.json');if((marker?.complete&&report)||(!report&&unit?.resultsWritten&&unit?.coverageWritten))return code!==0||report?.results.some(r=>['failed','timeout'].includes(r.status))||unit?.passed===false?'CONCLUÍDA COM FALHAS':'CONCLUÍDA SEM FALHAS';return 'INCOMPLETA';}
function compare(a,b){const old=new Map(a.map(r=>[r.id,r])),now=new Map(b.map(r=>[r.id,r]));return {newFailures:b.filter(r=>r.status==='failed'&&old.get(r.id)?.status!=='failed'),fixed:b.filter(r=>r.status==='passed'&&old.get(r.id)?.status==='failed'&&old.get(r.id)?.fingerprint===r.fingerprint),changedTests:b.filter(r=>old.has(r.id)&&old.get(r.id)?.fingerprint!==r.fingerprint),persistent:b.filter(r=>r.status==='failed'&&old.get(r.id)?.status==='failed'),notRetested:a.filter(r=>!now.has(r.id)),newTests:b.filter(r=>!old.has(r.id))};}
class Audit{
 constructor(m){this.m=m;this.base=path.join(m.private,'diagnostics');}
 list(){return fs.existsSync(this.base)?fs.readdirSync(this.base).filter(n=>/^audit_[0-9TZ_-]+_[a-f0-9]{12}$/.test(n)&&!fs.lstatSync(path.join(this.base,n)).isSymbolicLink()).sort():[];}
 read(id){if(!this.list().includes(id))throw Error('Relatório fora desta instância.');const dir=path.join(this.base,id);const files=fs.readdirSync(dir).filter(n=>/^amanda_audit_\d+_[a-f0-9]{6}$/.test(n)&&!fs.lstatSync(path.join(dir,n)).isSymbolicLink());const file=files[0]&&path.join(dir,files[0],'results.json');return {execution:JSON.parse(fs.readFileSync(path.join(dir,'execucao.json'))),report:file&&fs.existsSync(file)?JSON.parse(fs.readFileSync(file)):null};}
 async retry(id){const previous=this.read(id),ids=previous.report?.results.filter(r=>['failed','timeout'].includes(r.status)).map(r=>r.id)||[];if(!ids.length)throw Error('Nenhum teste com falha disponível.');return this.run(previous.execution.mode,{parent:id,retryIds:ids});}
 async run(mode,options={}){
  mode=selection(mode);const m=this.m;let launched=false;
  const id='audit_'+new Date().toISOString().replace(/[:.]/g,'_')+'_'+crypto.randomBytes(6).toString('hex'),dir=path.join(this.base,id);
  const record={id,mode,parent:options.parent||null,retryIds:options.retryIds||[],project:path.basename(m.root),startedAt:new Date().toISOString(),localStart:new Date().toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'})+' America/Sao_Paulo',complete:false,state:'BLOQUEADA',functionalStatus:'NÃO VALIDADA'};
  m.write(path.join(dir,'execucao.json'),record);m.write(path.join(dir,'diagnostico.log'),'Início UTC: '+record.startedAt+'\n');
  try{
   await new(require('./operations.cjs').Operations)(m).ready();const config=await m.configuration();
   Object.assign(record,{project:m.state.project,revision:await m.revision(),profiles:m.state.profiles,images:Object.fromEntries(Object.entries(config.services).map(([k,s])=>[k,s.image]).filter(([,v])=>v))});m.write(path.join(dir,'execucao.json'),record);
   if(mode==='quick'){await m.verifyHealth();record.operationalStatus='Verificações existentes aprovadas; saúde funcional não medida';record.state='CONCLUÍDA SEM FALHAS';record.complete=true;}
   else{
    const runner=path.join(m.state.platform,'tests/platform/run.cjs');if(!fs.existsSync(runner))throw Error('Suíte tests/platform ausente; atualize a plataforma antes de usar a central.');
    // Versão com adaptador é necessária para nunca usar imagens de outra instalação.
    if(!fs.readFileSync(runner,'utf8').includes('AUDIT_RUN_BASE'))throw Error('Suíte antiga: requer adaptador AUDIT_RUN_BASE/imagens dinâmicas.');
    const env={AUDIT_RUN_BASE:dir,TZ:'America/Sao_Paulo',AUDIT_RETRY_IDS:(options.retryIds||[]).join(',')};
    const planFile=path.join(m.state.platform,'tests/platform/lib/selection.cjs');
    const planner=fs.existsSync(planFile)?require(planFile):null;
    const required=typeof planner?.servicesFor==='function'?planner.servicesFor(planner.select(mode)):['backend','frontend','api_oficial','api_transcricao'];
    for(const[key,service]of Object.entries({BACKEND:'backend',FRONTEND:'frontend',OFFICIAL:'api_oficial',TRANSCRIPTION:'api_transcricao'})){
     if(!config.services[service]?.image){if(required.includes(service))throw Error('Suíte isolada requer imagem '+service+'; serviço opcional ausente não é falha funcional.');continue;}env['AUDIT_'+key+'_IMAGE']=config.services[service].image;
    }
    launched=true;const result=await m.runner.run(process.execPath,[runner,'--'+mode],{cwd:m.state.platform,env,allowFailure:true,label:'Auditoria isolada: '+mode});
    record.state=completion(dir,result.code);record.complete=record.state.startsWith('CONCLUÍDA');
    record.operationalStatus='Consulte resultados por serviço';record.functionalStatus='VALIDAÇÃO PARCIAL — lacunas em inventory.json/results.json';
   }
  }catch(error){record.error=m.runner.mask?m.runner.mask(error.message):'Execução bloqueada ou falhou; consulte log privado.';record.state=launched?'INCOMPLETA':'BLOQUEADA';record.operationalStatus=record.state;}
  finally{record.finishedAt=new Date().toISOString();m.write(path.join(dir,'execucao.json'),record);fs.appendFileSync(path.join(dir,'diagnostico.log'),JSON.stringify(record)+'\n');}
  m.runner.emit('AUDITORIA '+record.state+'\nSaúde funcional: '+record.functionalStatus+'\nRelatórios privados: '+dir+'\n');return record;
 }
}
module.exports={Audit,MODES,compare,selection,completion};
