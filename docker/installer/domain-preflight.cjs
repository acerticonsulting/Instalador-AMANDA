const {domain}=require('./wizard.cjs');
function pair(frontendUrl,backendUrl){
  const result={frontendUrl:domain(frontendUrl.trim()),backendUrl:domain(backendUrl.trim())};
  for(const url of Object.values(result)){const host=new URL(url).hostname;if(host.length>253||host.split('.').some(label=>label.length>63))throw Error('Domínio excede o tamanho DNS permitido.');}
  if(result.frontendUrl===result.backendUrl)throw Error('Frontend e backend devem usar domínios diferentes.');
  return result;
}
// Runs in an ephemeral tools container using the Docker host network namespace.
async function scanDomains(urls){
  const {Resolver}=require('node:dns').promises,net=require('node:net'),https=require('node:https');
  const ip=async(host,family)=>new Promise(resolve=>{
    const req=https.get({hostname:host,path:host==='api64.ipify.org'?'/':'/ip',family},res=>{let body='';res.on('data',c=>{body+=c;if(body.length>128)req.destroy();});res.on('end',()=>resolve(res.statusCode===200&&net.isIP(body.trim())===family?body.trim():null));});
    const timer=setTimeout(()=>req.destroy(),4000);req.on('close',()=>{clearTimeout(timer);resolve(null);});req.on('error',()=>resolve(null));
  });
  const publicSources=await Promise.all([4,6].map(async family=>({family,values:await Promise.all(['api64.ipify.org','ifconfig.co'].map(host=>ip(host,family)))})));
  const blocked=new net.BlockList();
  for(const [base,prefix] of [['0.0.0.0',8],['10.0.0.0',8],['100.64.0.0',10],['127.0.0.0',8],['169.254.0.0',16],['172.16.0.0',12],['192.168.0.0',16],['224.0.0.0',4],['240.0.0.0',4]])blocked.addSubnet(base,prefix,'ipv4');
  for(const entries of Object.values(require('node:os').networkInterfaces()))for(const entry of entries||[]){
    const family=net.isIP(entry.address),address=entry.address;
    if(!entry.internal&&(family===4&&!blocked.check(address,'ipv4')||family===6&&/^[23][0-9a-f]{3}:/i.test(address)))publicSources.push({family,source:'host-interface',values:[address,address]});
  }
  const ports=await Promise.all([80,443].map(port=>new Promise(resolve=>{
    const server=net.createServer();server.once('error',e=>resolve({port,status:'occupied-or-unavailable',code:e.code}));
    server.listen(port,'::',()=>server.close(()=>resolve({port,status:'free-local'})));
  })));
  const records=await Promise.all(urls.map(async url=>{
    const hostname=new URL(url).hostname;
    const resolvers=await Promise.all([null,'1.1.1.1','8.8.8.8'].map(async server=>{
      const resolver=new Resolver({timeout:1500,tries:1});if(server)resolver.setServers([server]);
      const row={server:server||'system',A:[],AAAA:[],CNAME:[],errors:[]};
      await Promise.all([['resolve4','A'],['resolve6','AAAA'],['resolveCname','CNAME']].map(async([method,key])=>{
        try{row[key]=await resolver[method](hostname);}catch(e){if(e.code!=='ENODATA')row.errors.push({type:key,code:e.code});}
      }));return row;
    }));return{hostname,resolvers};
  }));return{publicSources,ports,records,inbound:'not-verified'};
}
function evaluate(report){
  const expected=report.publicSources.filter(s=>s.values.length>=2&&s.values.every(v=>v&&v===s.values[0])).map(s=>s.values[0]);
  const portsOk=report.ports.every(p=>p.status==='free-local');
  const hosts=report.records.map(row=>{
    const answers=row.resolvers.map(r=>[...r.A,...r.AAAA].sort());
    const divergent=answers.some(a=>JSON.stringify(a)!==JSON.stringify(answers[0]));
    const addresses=[...new Set(answers.flat())];
    const unknownFamily=addresses.some(a=>!expected.some(ip=>require('node:net').isIP(ip)===require('node:net').isIP(a)));
    const status=!expected.length||unknownFamily||divergent||row.resolvers.some(r=>r.errors.some(e=>!['ENOTFOUND','ENODATA'].includes(e.code)))?'inconclusive':!addresses.length||addresses.some(a=>!expected.includes(a))?'incompatible':'compatible';
    return{hostname:row.hostname,status,addresses,divergent};
  });return{ok:portsOk&&hosts.every(h=>h.status==='compatible'),portsOk,expected,hosts};
}
async function interactive(config,{question,out=console.log,probe}){
  let urls=pair(config.frontendUrl,config.backendUrl),checks=0;
  while(true){
    out(require('./ui.cjs').createUI().banner('VERIFICAÇÃO DE DOMÍNIOS AMANDA'));
    out('Consultando DNS e destino público; nenhuma aplicação será instalada.');
    let report;
    try{report=await probe(urls);}catch(error){report={publicSources:[],ports:[80,443].map(port=>({port,status:'unknown'})),records:Object.values(urls).map(url=>({hostname:new URL(url).hostname,resolvers:[{A:[],AAAA:[],CNAME:[],errors:[{code:'PROBE_FAILED'}]}]})),error:'Diagnóstico Docker indisponível; verifique o daemon e a rede.'};}
    const verdict=evaluate(report);checks++;
    out('IPs públicos confirmados por duas fontes: '+(verdict.expected.join(', ')||'INCONCLUSIVO'));
    for(const host of verdict.hosts)out(`${host.hostname}: ${host.addresses.join(', ')||'sem resposta'} — ${host.status}${host.divergent?' (resolvedores divergentes)':''}`);
    for(const port of report.ports)out(`Porta ${port.port}: ${port.status}${port.code?' ('+port.code+')':''}`);
    out('Acessibilidade de entrada pela internet: pendente. TLS será validado após o deploy.');
    if(verdict.ok)return{...urls,domainPreflight:{status:'compatible',checkedAt:new Date().toISOString(),report}};
    out('[1] Verificar novamente\n[2] Corrigir backend\n[3] Corrigir frontend\n[4] Diagnóstico detalhado\n[5] Avançado: proxy/CDN ou DNS pendente\n[0] Cancelar');
    const action=await question('Como deseja continuar','0');
    if(action==null||['0',':cancelar',':sair'].includes(action))throw Error('Instalação cancelada antes de criar recursos.');
    if(action===':voltar')return{back:true,...urls};
    if(action==='2'||action==='3'){
      const key=action==='2'?'backendUrl':'frontendUrl';
      const value=await question('Corrigir '+key,urls[key]);
      if(value==null||[':cancelar',':sair'].includes(value))throw Error('Instalação cancelada antes de criar recursos.');
      if(value===':voltar')continue;
      try{urls=pair(key==='frontendUrl'?value:urls.frontendUrl,key==='backendUrl'?value:urls.backendUrl);}catch(e){out(e.message);}
    }else if(action==='4')out(JSON.stringify(report,null,2));
    else if(action==='5'){
      if(!verdict.portsOk){out('Portas locais indisponíveis não permitem exceção. Resolva o conflito antes de continuar.');continue;}
      const reason=await question('Motivo técnico (proxy/CDN ou DNS pendente)');
      if(reason==null||[':cancelar',':sair'].includes(reason))throw Error('Instalação cancelada antes de criar recursos.');
      if(reason===':voltar')continue;
      if(reason.trim().length<10||reason.length>500||/[\x00-\x1f\x7f]/.test(reason)){out('Informe motivo técnico entre 10 e 500 caracteres.');continue;}
      if(await question('HTTPS continua obrigatório. Digite CONTINUAR DNS PENDENTE','')==='CONTINUAR DNS PENDENTE')return{...urls,domainPreflight:{status:'exception',reason,checkedAt:new Date().toISOString(),report}};
    }
    if(checks>=12)throw Error('Limite de 12 verificações atingido. Instalação cancelada antes de criar recursos.');
  }
}
function checker(manager){return(config,options)=>interactive(config,{...options,probe:async urls=>{
  const result=await manager.docker(['run','--rm','--network','host','--entrypoint','node',process.env.AMANDA_MANAGER_IMAGE||'amanda-installer:local','-e',`(${scanDomains.toString()})(${JSON.stringify([urls.backendUrl,urls.frontendUrl])}).then(r=>console.log(JSON.stringify(r))).catch(()=>process.exit(1))`],{quiet:true,label:'Pré-validação DNS dentro do Docker'});
  const report=JSON.parse(result.stdout);
  const published=(await manager.docker(['ps','--format','{{.Ports}}'],{quiet:true})).stdout;
  for(const port of report.ports)if(new RegExp(':'+port.port+'->').test(published))port.status='published-by-container';
  return report;
}});}
module.exports={pair,scanDomains,evaluate,interactive,checker};
