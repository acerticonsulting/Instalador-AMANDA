const {test}=require('node:test'),assert=require('node:assert/strict');
const {pair,evaluate,interactive}=require('../docker/installer/domain-preflight.cjs');
const urls={frontendUrl:'https://front.example.test',backendUrl:'https://api.example.test'};
const report=()=>({publicSources:[{family:4,values:['203.0.113.10','203.0.113.10']}],ports:[80,443].map(port=>({port,status:'free-local'})),records:['api.example.test','front.example.test'].map(hostname=>({hostname,resolvers:['system','1.1.1.1','8.8.8.8'].map(server=>({server,A:['203.0.113.10'],AAAA:[],CNAME:[],errors:[]}))}))});
test('domain syntax normalizes HTTPS and refuses identical hosts, paths ports IP and HTTP',()=>{
 assert.equal(pair(' FRONT.example.test/ ','api.example.test').frontendUrl,urls.frontendUrl);
 for(const bad of ['http://front.example.test','https://front.example.test/path','https://front.example.test:8443','https://127.0.0.1','https://bad_host.example.test'])assert.throws(()=>pair(bad,urls.backendUrl));
 assert.throws(()=>pair(urls.frontendUrl,urls.frontendUrl));
});
test('direct DNS valid, CNAME and multiple public addresses supported',()=>{
 const r=report();assert.equal(evaluate(r).ok,true);r.records[0].resolvers.forEach(a=>a.CNAME=['target.example.test']);assert.equal(evaluate(r).ok,true);
 r.publicSources.push({family:6,values:['2001:db8::1','2001:db8::1']});r.records.forEach(h=>h.resolvers.forEach(a=>a.AAAA=['2001:db8::1']));assert.equal(evaluate(r).ok,true);
});
for(const hosts of [[0],[1],[0,1]])test('incompatible DNS detected for hosts '+hosts,()=>{
 const r=report();for(const n of hosts)r.records[n].resolvers.forEach(a=>a.A=['198.51.100.1']);assert.equal(evaluate(r).ok,false);
});
test('missing DNS, wrong AAAA, transient DNS, divergent resolver and unknown public IP',()=>{
 const r=report();r.records[0].resolvers.forEach(a=>a.A=[]);assert.equal(evaluate(r).hosts[0].status,'incompatible');
 const v6=report();v6.records[0].resolvers.forEach(a=>a.AAAA=['2001:db8::bad']);assert.equal(evaluate(v6).ok,false);
 const tmp=report();tmp.records[0].resolvers[0].errors=[{code:'ETIMEOUT'}];assert.equal(evaluate(tmp).hosts[0].status,'inconclusive');
 const diff=report();diff.records[0].resolvers[0].A=['198.51.100.1'];assert.equal(evaluate(diff).hosts[0].divergent,true);
 const unknown=report();unknown.publicSources[0].values=[null,null];assert.equal(evaluate(unknown).hosts[0].status,'inconclusive');
});
test('local port conflicts are blocking and free ports do not claim public reachability',()=>{
 for(const port of [80,443]){const r=report();r.ports.find(p=>p.port===port).status='occupied-or-unavailable';assert.equal(evaluate(r).portsOk,false);}
 assert.equal(report().inbound,undefined);
});
test('correct backend without losing frontend and recheck before proceeding',async()=>{
 let n=0;const answers=['2','https://fixed.example.test'];const seen=[];
 const result=await interactive(urls,{out(){},question:async()=>answers.shift(),probe:async u=>{seen.push({...u});const r=report();if(n++===0)r.records[0].resolvers.forEach(a=>a.A=[]);return r;}});
 assert.equal(result.frontendUrl,urls.frontendUrl);assert.equal(result.backendUrl,'https://fixed.example.test');assert.equal(seen.length,2);
});
test('advanced CDN exception requires reason and exact confirmation; cancellation and back work',async()=>{
 const r=report();r.records.forEach(h=>h.resolvers.forEach(a=>a.A=['198.51.100.1']));
 const answers=['5','CDN externa configurada no provedor','CONTINUAR DNS PENDENTE'];
 const result=await interactive(urls,{out(){},probe:async()=>r,question:async()=>answers.shift()});assert.equal(result.domainPreflight.status,'exception');assert.match(result.domainPreflight.reason,/CDN/);
 await assert.rejects(interactive(urls,{out(){},probe:async()=>r,question:async()=>':cancelar'}),/cancelada/);
 assert.equal((await interactive(urls,{out(){},probe:async()=>r,question:async()=>':voltar'})).back,true);
});
test('historical preflight runs before admin credentials and cancels without collecting them',async()=>{
 const {collectHistorical}=require('../docker/installer/historical.cjs');let calls=0;
 await assert.rejects(collectHistorical({out(){},question:async()=>['2',urls.backendUrl,urls.frontendUrl][calls++],checkDomains:async()=>{assert.equal(calls,3);throw Error('cancelada no DNS');}}),/cancelada/);assert.equal(calls,3);
});
test('wizard preflight runs before personalization and credentials',async()=>{
 const {collectInstallation}=require('../docker/installer/wizard.cjs');let calls=0;
 await assert.rejects(collectInstallation({out(){},question:async()=>['1',urls.backendUrl,urls.frontendUrl][calls++],checkDomains:async()=>{assert.equal(calls,3);throw Error('cancelada no DNS');}}),/cancelada/);assert.equal(calls,3);
});
test('retry and frontend correction preserve backend',async()=>{
 let n=0;const answers=['1','3','https://fixed.example.test'];
 const result=await interactive(urls,{out(){},question:async()=>answers.shift(),probe:async()=>{const r=report();if(n++<2)r.records[1].resolvers.forEach(a=>a.A=[]);return r;}});
 assert.equal(result.backendUrl,urls.backendUrl);assert.equal(result.frontendUrl,'https://fixed.example.test');assert.equal(n,3);
});
test('port conflicts cannot be bypassed and failed probe remains inconclusive',async()=>{
 const r=report();r.ports[0].status='published-by-container';const answers=['5','0'];let asked=0;
 await assert.rejects(interactive(urls,{out(){},probe:async()=>r,question:async()=>{asked++;return answers.shift();}}),/cancelada/);assert.equal(asked,2);
 await assert.rejects(interactive(urls,{out(){},probe:async()=>{throw Error('offline');},question:async()=> '0'}),/cancelada/);
});
test('preflight retry count is bounded and localhost cannot enter HTTPS preflight',async()=>{
 let n=0;const r=report();r.records[0].resolvers.forEach(a=>a.A=[]);
 await assert.rejects(interactive(urls,{out(){},probe:async()=>{n++;return r;},question:async()=> '1'}),/Limite/);assert.equal(n,12);
 assert.throws(()=>pair('http://localhost:3000','http://127.0.0.1:8080'));
});
