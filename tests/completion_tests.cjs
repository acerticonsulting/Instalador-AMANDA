const {test}=require('node:test');
const assert=require('node:assert/strict');
const {render,publicUrl,showCompletion}=require('../docker/installer/completion.cjs');
function data(){return {state:{project:'outra-empresa',profiles:['edge','official'],frontendUrl:'https://painel.example.test',backendUrl:'https://api.example.test'},root:'/home/deploy/outra-empresa',env:{OFICIAL_HOST:'meta.example.test',DB_PASS:'secret-db',JWT_SECRET:'secret-jwt'},checks:{https:true,dns:true,login:true},groups:[{prefix:'',names:['frontend','backend','postgres','edge','api_oficial'],config:{services:{frontend:{expose:['81']},backend:{expose:['9000']},postgres:{expose:['5439']},edge:{ports:[{target:444,published:'8443',protocol:'tcp'}]},api_oficial:{expose:['6123']}}},runtime:[{Service:'frontend',Publishers:[]},{Service:'backend',Publishers:[{URL:'127.0.0.1',TargetPort:9000,PublishedPort:9010,Protocol:'tcp'}]},{Service:'postgres',Publishers:[]},{Service:'edge',Publishers:[{URL:'::',TargetPort:444,PublishedPort:8443,Protocol:'tcp'}]}]}]};}
test('completion uses dynamic URLs, optional services and actual bindings without leaking secrets',()=>{
 const out=render(data(),{tty:false});for(const s of ['outra-empresa','https://painel.example.test','https://api.example.test','https://meta.example.test','Porta da URL: 443/TCP','5439','127.0.0.1:9010','Somente loopback',':::8443','Todas as interfaces','Acesso por proxy','HTTPS: VALIDADO','Login inicial: APROVADO'])assert.ok(out.includes(s),s);
 for(const s of ['secret-db','secret-jwt','homolog3','rabbitmq','wuzapi'])assert.ok(!out.includes(s),s);
 assert.match(out,/postgres\n  Interna: 5439\n  Sem porta publicada/);
});
test('HTTP, IP and local URLs preserve protocol and configured ports',()=>{
 for(const url of ['http://203.0.113.18:4200','http://[2001:db8::5]:8088','http://localhost:3001']){const d=data();d.state.profiles=[];d.state.frontendUrl=url;d.checks={};const out=render(d);assert.ok(out.includes(url));assert.match(out,/HTTPS: Não se aplica/);assert.ok(!out.includes('https://meta'));if(url.includes('localhost'))assert.match(out,/não é um link remoto/);}
});
test('URLs containing credentials, paths, queries or control sequences are not printed',()=>{
 for(const u of ['https://user:password@example.test','https://example.test/?token=secret','https://example.test/secret','ftp://example.test'])assert.equal(publicUrl(u),null);
 const d=data();d.state.frontendUrl='https://user:password@example.test';const out=render(d);assert.ok(!out.includes('password'));assert.match(out,/URL: Não verificado/);
});
test('completion reuses color theme and compact layout with NO_COLOR and TERM=dumb',()=>{
 const d=data();assert.match(render(d,{tty:true,theme:{TERM:'xterm'}}),/\x1b\[/);
 for(const theme of [{TERM:'xterm',NO_COLOR:'1'},{TERM:'dumb'}])assert.ok(!render(d,{tty:true,theme}).includes('\x1b'));
 const compact=render(d,{tty:false,columns:38});assert.ok(!compact.includes('████'));assert.ok(!compact.includes('─'.repeat(39)));assert.match(compact,/INSTALAÇÃO CONCLUÍDA/);
});
test('missing observations are not invented and unavailable optional services stay absent',()=>{
 const d=data();d.state.profiles=[];d.checks={};d.groups[0].runtime=null;const out=render(d);assert.match(out,/Publicação no host: Não verificado/);assert.match(out,/Login inicial: Não verificado/);assert.ok(!out.includes('meta.example.test'));
});
test('persisted pending state prevents completion and Docker calls',async()=>{
 const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),dir=fs.mkdtempSync(path.join(os.tmpdir(),'completion-'));
 try{const file=path.join(dir,'state.json');fs.writeFileSync(file,JSON.stringify({phase:'https-pending',initialized:false}));await showCompletion({stateFile:file,runner:{emit(){assert.fail('false success');}},configuration(){assert.fail('Docker called');}});}finally{fs.rmSync(dir,{recursive:true});}
});
