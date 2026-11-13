function acmeHints(logs){
  const hints=[];
  if(/Invalid response[\s\S]{0,1500}(?:404|403)|(?:HTTP|status(?: code)?)[ :"=]+(?:404|403)/i.test(logs))hints.push('HTTP-01: resposta 404/403 no desafio. O endpoint público não entregou o token ACME esperado; confira destino DNS, porta 80 e encaminhamento /.well-known/acme-challenge/ até este Caddy.');
  if(/no application protocol|unsupported application protocols/i.test(logs))hints.push('TLS-ALPN-01: o destino público em 443 não negociou acme-tls/1. Confira proxy TLS intermediário e encaminhamento TCP/SNI; conexão TCP ou ping não comprovam o desafio.');
  if(/rateLimited|rate limit/i.test(logs))hints.push('ACME: limite de emissão; preserve /data e respeite o prazo da autoridade, sem reiniciar ou forçar emissões.');
  if(/urn:ietf:params:acme:error:caa/i.test(logs))hints.push('ACME: política CAA recusou a autoridade certificadora.');
  return hints;
}
function activeSummary(config){
  const hosts=new Set(),listeners=new Set(),upstreams=new Set();
  function visit(value){if(!value||typeof value!=='object')return;
    if(Array.isArray(value.host))for(const v of value.host)hosts.add(v);
    if(Array.isArray(value.listen))for(const v of value.listen)listeners.add(v);
    if(typeof value.dial==='string')upstreams.add(value.dial);
    for(const child of Object.values(value))if(typeof child==='object')visit(child);
  }visit(config);return{hosts:[...hosts],listeners:[...listeners],upstreams:[...upstreams]};
}
async function diagnoseEdge(manager){
  const report={readOnly:true,hostProcesses:'Não inspecionados. Na VPS: ss -ltnp para 80/443.',firewall:'Não verificado; porta Docker publicada não comprova entrada pública.'};
  async function attempt(label,fn){try{return await fn();}catch{return{unavailable:label};}}
  report.publishers=await attempt('docker ps',async()=> (await manager.docker(['ps','--format','{{json .}}'],{quiet:true})).stdout.trim().split(/\r?\n/).filter(Boolean).map(l=>{const r=JSON.parse(l);return{name:r.Names,ports:r.Ports};}));
  report.hostNetwork=await attempt('DNS/IP na rede do host Docker',async()=>JSON.parse((await manager.docker(['run','--rm','--network','host','--entrypoint','node',process.env.AMANDA_MANAGER_IMAGE||'amanda-installer:local','-e',`(${require('./domain-preflight.cjs').scanDomains.toString()})(${JSON.stringify([manager.state.frontendUrl,manager.state.backendUrl])}).then(r=>console.log(JSON.stringify(r))).catch(()=>process.exit(1))`],{quiet:true})).stdout));
  const edge=await attempt('container edge',async()=> (await manager.compose(['ps','--all','--format','json','edge'],{quiet:true})).stdout.trim().split(/\r?\n/).filter(Boolean).flatMap(l=>{const r=JSON.parse(l);return Array.isArray(r)?r:[r];}));
  report.edge=edge;
  const id=Array.isArray(edge)?edge[0]?.ID:undefined;
  if(id)report.container=await attempt('docker inspect edge',async()=>{
    const r=JSON.parse((await manager.docker(['inspect',id],{quiet:true})).stdout)[0];
    return{status:r.State?.Status,health:r.State?.Health?.Status,ports:r.NetworkSettings?.Ports,
      domains:(r.Config?.Env||[]).filter(v=>/^(FRONTEND_HOST|BACKEND_HOST|OFICIAL_HOST)=/.test(v)),
      certificateVolumes:(r.Mounts||[]).filter(v=>['/data','/config'].includes(v.Destination)).map(v=>({name:v.Name,destination:v.Destination,type:v.Type,rw:v.RW}))};
  });
  report.activeConfig=await attempt('API administrativa Caddy desativada ou inacessível',async()=>activeSummary(JSON.parse((await manager.compose(['exec','-T','edge','wget','-qO-','http://127.0.0.1:2019/config/'],{quiet:true})).stdout)));
  const logs=await attempt('logs Caddy',async()=> (await manager.compose(['logs','--no-color','--tail','200','edge'],{quiet:true})).stdout);
  report.acme=typeof logs==='string'?acmeHints(logs):logs;
  const targets=[{url:manager.state.frontendUrl,exact:true},{url:manager.state.backendUrl+'/healthz',exact:true}];
  report.publicFromManager=await attempt('DNS/HTTPS a partir do gerenciador',()=>require('./https-check.cjs').inspectHttps(targets,{connectivity:true}));
  manager.runner.emit(JSON.stringify(report,null,2)+'\n');return report;
}
module.exports={acmeHints,activeSummary,diagnoseEdge};
