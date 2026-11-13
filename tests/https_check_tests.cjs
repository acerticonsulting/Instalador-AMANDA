const {test}=require('node:test');const assert=require('node:assert/strict');
const {inspectHttps,awaitHttps}=require('../docker/installer/https-check.cjs');
const targets=[{url:'https://front.example.test',exact:true},{url:'https://api.example.test/healthz',exact:true}];
const noData=()=>Promise.reject(Object.assign(Error(),{code:'ENODATA'}));
const dns={resolve4:async()=>['192.0.2.1'],resolve6:noData};
test('HTTPS checks both hosts and certificate metadata by address',async()=>{
 const calls=[];const r=await inspectHttps(targets,{}, {dns,request:async(url,ip,family)=>{calls.push([url,ip,family]);return{status:200,issuer:'CA',validTo:'future'};}});assert.equal(r.ok,true);assert.equal(calls.length,2);assert.equal(r.results[0].checks[0].issuer,'CA');
});
for(const code of ['CERT_HAS_EXPIRED','ERR_TLS_CERT_ALTNAME_INVALID','UNABLE_TO_VERIFY_LEAF_SIGNATURE','CERT_NOT_YET_VALID','ECONNREFUSED','ETIMEDOUT'])test('HTTPS retains technical reason '+code,async()=>{
 const r=await inspectHttps(targets,{}, {dns,request:async()=>{throw Object.assign(Error(),{code});}});assert.equal(r.ok,false);assert.equal(r.results[1].failures[0].code,code);
});
test('DNS missing, wrong IPv4 and wrong AAAA remain distinct',async()=>{
 const missing=await inspectHttps(targets,{}, {dns:{resolve4:noData,resolve6:noData}});assert.equal(missing.results[0].failures[0].kind,'DNS');
 const wrong=await inspectHttps(targets,{expectedAddresses:['192.0.2.2']},{dns});assert.equal(wrong.results[0].failures[0].code,'UNEXPECTED_ADDRESS');
 const v6=await inspectHttps(targets,{}, {dns:{...dns,resolve6:async()=>['2001:db8::bad']},request:async(_url,_ip,family)=>{if(family===6)throw Object.assign(Error(),{code:'ENETUNREACH'});return{status:200};}});assert.equal(v6.ok,false);assert.equal(v6.results[0].failures[0].family,6);
});
test('HTTP application errors are separate from TLS',async()=>{
 const r=await inspectHttps(targets,{}, {dns,request:async()=>({status:503})});assert.equal(r.results[0].failures[0].kind,'HTTP');
});
test('port 80 blockage is reported without invalidating an already valid HTTPS certificate',async()=>{
 const r=await inspectHttps(targets,{connectivity:true},{dns,tcp:async()=> 'ECONNREFUSED',request:async()=>({status:200})});assert.equal(r.ok,true);assert.equal(r.results[0].checks[0].httpPort80,'ECONNREFUSED');
});
const pending={ok:false,results:[{hostname:'front.example.test',failures:[{kind:'TLS',code:'ERR_SSL_TLSV1_ALERT_INTERNAL_ERROR'}]}]};
test('Caddy issuing retries with bounded backoff then succeeds',async()=>{
 let clock=0,n=0;const waits=[];await awaitHttps({probe:async()=>++n===3?{ok:true,results:[]}:pending,caddy:async()=> 'obtaining certificate',emit(){},now:()=>clock,sleep:async ms=>{clock+=ms;waits.push(ms);}});assert.deepEqual(waits,[2000,4000]);
});
test('Caddy timeout is bounded and ACME permanent errors stop immediately',async()=>{
 let clock=0;await assert.rejects(awaitHttps({probe:async()=>pending,caddy:async()=> 'obtaining certificate',emit(){},timeoutMs:3000,now:()=>clock,sleep:async ms=>clock+=ms}),/timeout/);assert.equal(clock,3000);
 await assert.rejects(awaitHttps({probe:async()=>pending,caddy:async()=> 'rateLimited',emit(){},sleep:async()=>assert.fail()}),/ACME/);
 await assert.rejects(awaitHttps({probe:async()=>pending,caddy:async()=> '',emit(){},sleep:async()=>assert.fail()}),/ERR_SSL_TLSV1_ALERT_INTERNAL_ERROR/);
});
