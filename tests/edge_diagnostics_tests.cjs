const {test}=require('node:test'),assert=require('node:assert/strict');
const {acmeHints,activeSummary,diagnoseEdge}=require('../docker/installer/edge-diagnostics.cjs');
test('ACME 404 and ALPN diagnostics name the failed challenges without claiming a proxy identity',()=>{
 assert.match(acmeHints('Invalid response from http://app.example.test/.well-known/acme-challenge/token: 404')[0],/HTTP-01/);
 assert.match(acmeHints('remote error: tls: no application protocol')[0],/TLS-ALPN-01/);
 assert.match(acmeHints('urn:ietf:params:acme:error:caa')[0],/CAA/);
 assert.deepEqual(acmeHints('obtaining certificate'),[]);
});
test('active Caddy summary keeps hosts/listeners/upstreams and omits credentials',()=>{
 const s=activeSummary({apps:{http:{servers:{s:{listen:[':443'],routes:[{match:[{host:['app.example.test']}],handle:[{upstreams:[{dial:'frontend:80'}],password:'private'}]}]}}}},token:'secret'});
 assert.deepEqual(s.hosts,['app.example.test']);assert.deepEqual(s.listeners,[':443']);assert.deepEqual(s.upstreams,['frontend:80']);assert.ok(!JSON.stringify(s).includes('secret'));
});
test('diagnostic continues if Caddy admin API is unavailable and does not mutate Docker',async()=>{
 const calls=[],original=require('../docker/installer/https-check.cjs').inspectHttps;
 require('../docker/installer/https-check.cjs').inspectHttps=async()=>({ok:false,results:[]});
 try{const manager={state:{frontendUrl:'https://front.example.test',backendUrl:'https://api.example.test'},runner:{emit(){}},
 docker:async args=>{calls.push(args);if(args[0]==='run')return{stdout:'{"publicSources":[],"records":[],"ports":[]}'};if(args[0]==='ps')return{stdout:'{"Names":"other-proxy","Ports":"0.0.0.0:443->443/tcp"}'};return{stdout:JSON.stringify([{State:{Status:'running'},Config:{Env:['FRONTEND_HOST=front.example.test','SECRET=private']},Mounts:[{Name:'amanda_caddy_data',Destination:'/data',Type:'volume',RW:true}]}])};},
 compose:async args=>{calls.push(args);if(args[0]==='ps')return{stdout:'{"ID":"fixture","Service":"edge","State":"running"}'};if(args[0]==='exec')throw Error('admin disabled');return{stdout:'Invalid response from http://front.example.test/challenge: 404'};}};
 const report=await diagnoseEdge(manager);assert.equal(report.readOnly,true);assert.equal(report.container.certificateVolumes[0].name,'amanda_caddy_data');assert.ok(report.activeConfig.unavailable);assert.match(report.acme[0],/HTTP-01/);assert.ok(!JSON.stringify(report).includes('private'));
 assert.ok(calls.every(a=>['ps','inspect','exec','logs','run'].includes(a[0])));assert.ok(!calls.some(a=>a.includes('up')||a.includes('restart')||a.includes('down')));
 }finally{require('../docker/installer/https-check.cjs').inspectHttps=original;}
});
test('ALPN failure stops waiting even if issuance messages exist',async()=>{
 await assert.rejects(require('../docker/installer/https-check.cjs').awaitHttps({probe:async()=>({ok:false,results:[{hostname:'app',failures:[{code:'ECONNREFUSED'}]}]}),caddy:async()=> 'obtaining certificate remote error: tls: no application protocol',emit(){},sleep:async()=>assert.fail('no retry')}),/TLS-ALPN-01/);
});
