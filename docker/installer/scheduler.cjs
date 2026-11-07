const fs=require('node:fs');
const path=require('node:path');
const {Manager}=require('./manager.cjs');
const action=process.argv[2];
if(!['backup','update'].includes(action))throw Error('Agendamento inválido.');
const m=new Manager(process.env.AMANDA_INSTALL_DIR);
async function tick(){
  try{
    const file=path.join(m.private,'schedule-'+action+'.json'),spec=JSON.parse(fs.readFileSync(file,'utf8')),now=new Date(),day=now.toISOString().slice(0,10);
    if(spec.action!==action||!Number.isInteger(spec.hour)||spec.hour<0||spec.hour>23)throw Error('Configuração de agendamento inválida.');
    if(now.getUTCHours()!==spec.hour||spec.lastAttempt===day)return;
    await m.lock(async()=>{m.write(file,{...spec,lastAttempt:day});await m.execute(action);m.write(file,{...spec,lastAttempt:day,lastSuccess:new Date().toISOString()});});
  }catch(error){m.runner.emit('Falha no agendador: '+error.message+'\n');}
}
tick();setInterval(tick,60000);
