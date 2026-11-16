// Test-only transport: real CLI, discovery, directory validator and Dashboard.
// Only the external Git/Docker inventory is a fixture; mutations fail closed.
if(process.env.AMANDA_NAV_FIXTURE!=='1')throw Error('Navigation fixture requires explicit opt-in.');
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const{Runner,SOURCE}=require('../../docker/installer/manager.cjs');
function inventory(){
  const base=process.env.AMANDA_INSTALL_DIR,dir=path.join(base,'instances');
  return fs.readdirSync(dir).map(name=>JSON.parse(fs.readFileSync(path.join(dir,name,'.amanda-installer/state.json'))));
}
function services(state){return['postgres','redis','backend','frontend','api_transcricao',...(state.profiles.includes('official')?['api_oficial']:[]),...(state.profiles.includes('whatsmeow')?['wuzapi']:[]),...(state.profiles.includes('rabbit')?['rabbitmq']:[]),...(state.profiles.includes('edge')?['edge']:[])];}
function containers(state){return services(state).map(service=>({Id:crypto.createHash('sha256').update(state.project+service).digest('hex'),Name:state.project+'_'+service,Project:state.project,Service:service,Oneoff:'False',ImageId:'sha256:'+'a'.repeat(64),Image:'fixture/'+service+':readonly',State:{Status:'running',Health:{Status:'healthy'},StartedAt:'2026-11-16T00:00:00Z'},Ports:{'8080/tcp':[{HostIp:'127.0.0.1',HostPort:'18080'}]},Mounts:[{Type:'volume',Name:state.project+'_'+service+'_data',Destination:'/data'}]}));}
Runner.prototype.run=async function(bin,args){
  if(bin==='git'&&args.includes('get-url'))return{stdout:SOURCE,code:0};
  if(bin!=='docker')throw Error('Unexpected external command in read-only navigation fixture.');
  const states=inventory();
  if(args[0]==='compose'&&args.includes('config')){
    const project=args[args.indexOf('-p')+1],state=states.find(s=>s.project===project);if(!state)throw Error('Foreign project.');
    return{code:0,stdout:JSON.stringify({services:Object.fromEntries(services(state).map(name=>[name,{image:'fixture/'+name+':readonly',environment:{},restart:'unless-stopped'}])),volumes:{},networks:{default:{name:project+'_default'}}})};
  }
  if(args[0]==='ps'&&args.includes('-a')){
    const label=args[args.indexOf('--filter')+1],state=states.find(s=>label==='label=com.docker.compose.project='+s.project);if(!state)throw Error('Unscoped Docker inventory.');
    return{code:0,stdout:containers(state).map(c=>c.Id).join('\n')};
  }
  if(args[0]==='inspect'&&args.includes('--format')){
    const all=states.flatMap(containers),ids=args.slice(args.indexOf('--format')+2);if(!ids.length||ids.some(id=>!all.some(c=>c.Id===id)))throw Error('Unknown container ID.');
    return{code:0,stdout:ids.map(id=>JSON.stringify(all.find(c=>c.Id===id))).join('\n')};
  }
  throw Error('Docker mutation or unsupported command blocked by navigation fixture.');
};
