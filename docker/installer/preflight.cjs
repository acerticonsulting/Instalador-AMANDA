function publishedPorts(config,services){
  return services.flatMap(name=>(config.services[name]?.ports||[]).map(p=>{if(typeof p!=='object'||!/^\d+$/.test(String(p.published))||+p.published<1||+p.published>65535)throw Error('Contrato Compose com porta externa inválida: '+name);return {port:+p.published,host:p.host_ip||'0.0.0.0',protocol:p.protocol||'tcp'};}));
}
const bindingKey=p=>p.protocol+'|'+p.host+'|'+p.port;
async function probeBindings(ports){
  const net=require('node:net'),dgram=require('node:dgram');
  for(const p of ports)await new Promise((resolve,reject)=>{
    const s=p.protocol==='udp'?dgram.createSocket(p.host.includes(':')?'udp6':'udp4'):net.createServer();
    s.once('error',()=>reject(Error('Porta '+p.port+' indisponível no host Docker.')));
    const done=()=>s.close(resolve);if(p.protocol==='udp')s.bind(p.port,p.host,done);else s.listen(p.port,p.host,done);
  });
}
async function assertPorts(manager,config,previous){
  const services=manager.services().concat(manager.state.profiles.includes('edge')?['edge']:[]),skip=new Set(previous?publishedPorts(previous,Object.keys(previous.services)).map(bindingKey):[]);
  const ports=publishedPorts(config,services).filter(p=>!skip.has(bindingKey(p)));if(!ports.length)return;
  const ids=(await manager.docker(['ps','-q'],{quiet:true})).stdout.trim().split(/\s+/).filter(Boolean);
  if(ids.length){
    const containers=JSON.parse((await manager.docker(['inspect',...ids],{quiet:true})).stdout);
    for(const container of containers)for(const[key,bindings]of Object.entries(container.NetworkSettings?.Ports||{}))for(const b of bindings||[])if(ports.some(p=>p.port===+b.HostPort&&p.protocol===key.split('/')[1]&&(p.host===b.HostIp||['0.0.0.0','::',''].includes(b.HostIp)||['0.0.0.0','::'].includes(p.host))))throw Error('Porta externa ocupada por um container: '+b.HostPort+'. Escolha outra porta.');
  }
  const script=`(${probeBindings.toString()})(${JSON.stringify(ports)}).catch(e=>{console.error(e.message);process.exit(1)})`;
  await manager.docker(['run','--rm','--network','host','--entrypoint','node',process.env.AMANDA_MANAGER_IMAGE||'amanda-installer:local','-e',script],{quiet:true,label:'Verificando portas TCP/UDP no host Docker (sem instalar dependências)'});
}
module.exports={publishedPorts,assertPorts,probeBindings};
