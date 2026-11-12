const {test}=require('node:test');const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');const {spawnSync}=require('node:child_process');
const {render,collectHistorical}=require('../docker/installer/historical.cjs');
const {installInput}=require('../docker/installer/cli.cjs');
const {MAIN,TOOLS,API,Menus}=require('../docker/installer/menus.cjs');
const {SOURCE,normalizeConfig}=require('../docker/installer/manager.cjs');
const original=require('./fixtures/7a5b31d-menus.json');

async function runBootstrapTTY(input,mode='sh',transport){
 const os=require('node:os'),{spawn}=require('node:child_process'),root=fs.mkdtempSync(path.join(os.tmpdir(),'amanda-bootstrap-tty-')),copy=path.join(root,'installer with spaces'),bin=path.join(root,'bin'),log=path.join(root,'docker-calls');
 fs.mkdirSync(bin);fs.writeFileSync(path.join(bin,'docker'),`#!/bin/sh
case "$1" in
info) echo linux ;;
context) echo unix:///var/run/docker.sock ;;
run) printf '%s\\n' "$@" >> "$BOOTSTRAP_TEST_LOG"
 if [ -n "\${AMANDA_TTY_TEST_IMAGE:-}" ]; then
  for arg do
   if [ "$arg" = --init ]; then
    flag=-i
    for option do [ "$option" != -it ] || flag=-it; done
    [ "$BOOTSTRAP_FORCE_NO_TTY" != 1 ] || flag=-i
    /usr/local/bin/docker run --rm "$flag" --network none --name "$BOOTSTRAP_PROBE_NAME" -e AMANDA_INSTALL_DIR=/tmp/amanda-tty-probe -e NO_COLOR=1 --entrypoint node "$AMANDA_TTY_TEST_IMAGE" /opt/amanda-installer/cli.cjs menu --initial 0
    result=$?
    printf '%s' "$result" > "$BOOTSTRAP_PROBE_STATUS"
    exit "$result"
   fi
  done
 fi ;;
*) exit 2 ;;
esac
`,{mode:0o755});
 fs.mkdirSync(path.join(copy,'docker/installer'),{recursive:true});
 for(const file of ['instalador_single.sh','docker/installer/historical.sh'])fs.copyFileSync(path.join(__dirname,'..',file),path.join(copy,file));
 const entry=path.join(copy,'instalador_single.sh');fs.chmodSync(entry,0o755);
 const quote=s=>"'"+s.replaceAll("'","'\\''")+"'",command=(mode==='executable'?'':['stdout-pipe','noninteractive'].includes(mode)?'sh ':mode+' ')+quote(entry)+(mode==='stdout-pipe'?' | cat':mode==='noninteractive'?' < /dev/null | cat':'');
 try{return await new Promise((resolve,reject)=>{
  const child=spawn('script',['-q','-e','-c',command,'/dev/null'],{cwd:root,env:{...process.env,AMANDA_TTY_TEST_IMAGE:transport?process.env.AMANDA_TTY_TEST_IMAGE:'',BOOTSTRAP_FORCE_NO_TTY:transport==='control'?'1':'0',BOOTSTRAP_PROBE_NAME:path.basename(root),BOOTSTRAP_PROBE_STATUS:path.join(root,'probe-status'),PATH:bin+':'+process.env.PATH,BOOTSTRAP_TEST_LOG:log,TERM:'dumb',NO_COLOR:'1',HOME:root,AMANDA_INSTALL_DIR:path.join(root,'company')},stdio:['pipe','pipe','pipe']});let output='',sent=false;
  const timeout=setTimeout(()=>{child.kill('SIGKILL');if(transport)spawnSync('/usr/local/bin/docker',['rm','-f',path.basename(root)],{timeout:5000});reject(Error('Bootstrap TTY timeout'));},transport?20000:5000);
  child.on('error',error=>{clearTimeout(timeout);reject(error);});
  child.stdout.on('data',chunk=>{output+=chunk;if(!sent&&output.includes('Diretório da instalação:')&&output.includes('> ')){sent=true;child.stdin.write(input);}});
  child.stderr.on('data',chunk=>output+=chunk);
  child.on('close',status=>{clearTimeout(timeout);resolve({status,output,sent,probeStatus:fs.existsSync(path.join(root,'probe-status'))?fs.readFileSync(path.join(root,'probe-status'),'utf8'):undefined,changed:fs.existsSync(path.join(root,'company')),commands:fs.existsSync(log)?fs.readFileSync(log,'utf8'):''});});
 });}finally{fs.rmSync(root,{recursive:true,force:true});}
}

test('bootstrap displays its real menu before reading and exits without Docker or installation writes',async()=>{
 for(const mode of ['sh','bash','executable']){const result=await runBootstrapTTY('0\n',mode);assert.equal(result.status,0,result.output);assert.equal(result.sent,true);assert.ok(result.output.includes('[1] Instalar AMANDA'));assert.ok(!result.output.includes('Preparando ferramentas em container'));assert.equal(result.changed,false);assert.equal(result.commands,'');}
});

test('bootstrap ignores buffered blank lines and accepts padded CRLF choices in sh bash and direct execution',async()=>{
 for(const mode of ['sh','bash','executable']){const result=await runBootstrapTTY('\n 0 \r\n',mode);assert.equal(result.status,0,result.output);assert.ok(!result.output.includes('Opção inválida'));assert.equal(result.changed,false);}
});

test('bootstrap retries an invalid selection instead of closing the terminal menu',async()=>{
 const result=await runBootstrapTTY('not-an-option\n0\n');assert.equal(result.status,0,result.output);assert.equal((result.output.match(/Opção inválida/g)||[]).length,1);assert.equal(result.changed,false);
});

test('bootstrap forwards the selected menu option after buffered blank lines without executing real Docker',async()=>{
 for(const choice of ['1','11']){const result=await runBootstrapTTY('\n '+choice+' \r\n','executable');assert.equal(result.status,0,result.output);assert.ok(!result.output.includes('Opção inválida'));assert.ok(result.commands.includes('--initial\n'+choice+'\n'));assert.equal(result.changed,false);}
});

test('bootstrap keeps Docker TTY when stdin is interactive and stdout is piped',async()=>{
 const result=await runBootstrapTTY('1\n','stdout-pipe');assert.equal(result.status,0,result.output);assert.ok(result.commands.split('\n').includes('-it'),result.commands);assert.ok(result.commands.includes('--initial\n1\n'));assert.equal(result.changed,false);
});

test('bootstrap keeps noninteractive Docker input without allocating a TTY',async()=>{
 const result=await runBootstrapTTY('','noninteractive');assert.equal(result.status,0,result.output);assert.ok(result.commands.split('\n').includes('-i'));assert.ok(!result.commands.split('\n').includes('-it'));assert.equal(result.sent,false);assert.equal(result.changed,false);
});

test('real Docker terminal transport: missing TTY reproduces the reported CLI error',{skip:!process.env.AMANDA_TTY_TEST_IMAGE},async()=>{
 const result=await runBootstrapTTY('1\n','stdout-pipe','control');assert.equal(result.probeStatus,'1',result.output);assert.match(result.output,/O menu requer terminal interativo/);assert.equal(result.changed,false);
});

test('real Docker terminal transport: bootstrap preserves TTY through piped stdout',{skip:!process.env.AMANDA_TTY_TEST_IMAGE},async()=>{
 const result=await runBootstrapTTY('1\n','stdout-pipe','actual');assert.equal(result.probeStatus,'0',result.output);assert.doesNotMatch(result.output,/O menu requer terminal interativo/);assert.ok(result.commands.split('\n').includes('-it'));assert.equal(result.changed,false);
});
test('short and literal passwords work in historical local, public IP and HTTPS installations',async()=>{
 for(const password of ['123','admin','teste123','123456','Amanda@123','MinhaSenhaPersonalizada','a$#\'"'])for(const mode of ['local','ip','https']){
  const t=input({0:mode==='https'?'2':'1',1:mode==='https'?'api.example.test':mode==='ip'?'192.0.2.10':'localhost',4:password,5:password,13:password,14:password}),q=t.options.question;
  t.options.question=(...args)=>/domínio\/URL do Frontend/.test(t.output.at(-1)||'')?Promise.resolve('app.example.test'):q(...args);
  const c=await collectHistorical(t.options);assert.equal(c.adminPassword,password);assert.equal(c.options.databasePassword,password);assert.equal(c.options.masterPassword,password);if(password!=='admin')assert.ok(!t.output.join('').includes(password));assert.ok(t.output.join('').includes('[oculta]'));
 }
 for(const password of ['', 'a\nb', 'a\x1bb']){const t=input({13:password,14:password});await assert.rejects(collectHistorical(t.options),/vazia\/inválida/);}
});
test('interactive credentials echo normally without showing stored defaults',async()=>{
 const {spawn}=require('node:child_process');
 const code="require('./docker/installer/cli.cjs').ask('Credencial', 'stored-private-default', true).then(v=>{if(v!=='typed$123')process.exitCode=2;console.log('READ_OK')})";
 const quote=s=>"'"+s.replaceAll("'","'\\''")+"'";
 await new Promise((resolve,reject)=>{
  const child=spawn('script',['-q','-c',quote(process.execPath)+' -e '+quote(code),'/dev/null'],{cwd:path.join(__dirname,'..'),env:{...process.env,TERM:'dumb',NO_COLOR:'1'}});let output='',sent=false;
  const timeout=setTimeout(()=>{child.kill();reject(Error('Timeout de leitura interativa'));},7000);
  child.on('error',e=>{clearTimeout(timeout);reject(e);});
  child.stdout.on('data',chunk=>{output+=chunk;if(!sent&&output.includes('> ')){sent=true;child.stdin.write('typed$123\n');}});
  child.on('close',status=>{clearTimeout(timeout);try{assert.equal(status,0,output);assert.ok(output.includes('typed$123'));assert.ok(output.includes('READ_OK'));assert.ok(!output.includes('stored-private-default'));resolve();}catch(e){reject(e);}});
 });
});
const plain=s=>s.replace(/\x1b\[[0-9;]*[A-Za-z]/g,'');
function historical(screen){const result=spawnSync('sh',['-c','clear(){ :; }\n'+original.banner+'\n'+original[screen]],{encoding:'utf8',env:{PATH:process.env.PATH,nome_titulo:'AMANDA'}});assert.equal(result.status,0,result.stderr);return result.stdout;}
function input(changes={},project){
 const answers=['1','localhost','owner@example.test','acerti','db$secure','master$secure','Minha AMANDA','5511999999999','app-id','fb$secret','gh$token',SOURCE,'s','admin$secret','admin$secret','s','0'];
 for(const[k,v]of Object.entries(changes))answers[+k]=v;
 if(project)answers.splice(3,1);
 const output=[],prompts=[];let index=0;
 return {output,prompts,options:{project,out:s=>output.push(s),directory:'/srv/acerti',question:async(label,fallback,secret)=>{prompts.push({label,secret,screen:output.at(-1)});if(index>=answers.length)throw Error('Pergunta inesperada: '+label);const value=answers[index++];return value===undefined?fallback??'':value;}}};
}
test('7a5b31d main presentation and banner are recovered verbatim except the unsafe scheduler label',()=>{
 assert.equal(plain(render('main')),historical('main').replace('Configurar Watchtower','Configurar Atualização Agendada'));
 assert.deepEqual(MAIN.map(x=>x[0]),Array.from({length:11},(_,i)=>String(i+1)));
 for(const screen of ['main','tools','api'])assert.ok(render(screen).includes('MULTICANAL v1.0.0'));
});
test('historical tool sections, ordering and valid numbers remain; unavailable operations retain their slots',()=>{
 const ids=s=>[...s.matchAll(/\[(\d+)\]/g)].map(m=>m[1]).filter(id=>id!=='0');
 assert.deepEqual(TOOLS.map(x=>x[0]),ids(historical('tools')).filter(id=>!['24','25','26','27'].includes(id)));
 assert.deepEqual(API.map(x=>x[0]),ids(historical('api')));
 assert.ok(TOOLS.some(x=>x[0]==='7'));assert.ok(TOOLS.some(x=>x[0]==='19'));
 for(const title of historical('tools').match(/━━ [^\n]+ ━━/g))assert.ok(render('tools').includes(title));
 assert.ok(TOOLS.every(x=>x[2]));assert.ok(API.every(x=>x[2]));
});
test('default interactive installation uses the historical question order and keeps credentials private',async()=>{
 const t=input(),c=await installInput(undefined,t.options);
 assert.equal(c.project,'acerti');assert.equal(c.adminEmail,'owner@example.test');assert.equal(c.options.databasePassword,'db$secure');assert.equal(c.options.masterPassword,'master$secure');assert.equal(c.options.appName,'Minha AMANDA');assert.equal(c.sourceToken,'gh$token');assert.equal(c.sourceUrl,SOURCE);assert.equal(c.public,false);assert.equal(c.backendUrl,'http://localhost:8080');
 const labels=['Selecione como deseja','Insira o IP','Digite o seu melhor email','Digite o nome da sua empresa','senha do Banco','senha para o MASTER','Titulo da Aplicação','telefone para suporte','FACEBOOK_APP_ID','FACEBOOK_APP_SECRET','TOKEN de acesso pessoal','URL do repositório','Usar as portas padrão'];
 labels.forEach((label,i)=>assert.ok(t.prompts[i].screen.includes(label),label));
 for(const i of [4,5,9,10,13,14])assert.equal(t.prompts[i].secret,true);
 assert.ok(!t.prompts.some(p=>/conector|BuildKit/.test(p.label)));assert.equal(c.buildToken,undefined);
 const visible=t.output.join('\n');for(const secret of ['db$secure','master$secure','fb$secret','gh$token','admin$secret','build$secret'])assert.ok(!visible.includes(secret));
 assert.ok(visible.includes('Minha AMANDA'));assert.ok(visible.includes('/srv/acerti'));assert.ok(visible.includes('[oculta]'));
 assert.ok(!/GoFlow|PgBouncer/.test(visible));
});

test('historical collector preserves the company checked before questionnaire and PostgreSQL selection',async()=>{
 const t=input({16:'2'},'acerti'),c=await collectHistorical(t.options);
 assert.equal(c.project,'acerti');assert.equal(c.options.pg.maxConnections,200);
 assert.ok(!t.prompts.some(p=>p.screen?.includes('Digite o nome da sua empresa')));
 assert.equal(c.adminEmail,'owner@example.test');assert.equal(c.adminPassword,'admin$secret');
});
test('official URL variants and custom IP ports survive the original form',async()=>{
 for(const url of [SOURCE,SOURCE+'/',SOURCE.replace('.git',''),SOURCE.replace('.git','')+'/']){
 const t=input({1:'2001:db8::1',11:url,12:'n'}),answers=['8800','3300'];
 const question=t.options.question;let portIndex=0;
 t.options.question=(label,fallback,secret)=>{
 if(/Qual porta deseja/.test(t.output.at(-1)||''))return Promise.resolve(answers[portIndex++]);
 return question(label,fallback,secret);
 };
 const c=await collectHistorical(t.options);assert.equal(c.sourceUrl,SOURCE);assert.equal(c.backendUrl,'http://[2001:db8::1]:8800');assert.equal(c.frontendUrl,'http://[2001:db8::1]:3300');assert.equal(c.public,true);
 }
});
test('historical HTTPS questions ask backend before frontend and preserve custom proxy bindings',async()=>{
 const t=input({0:'2',1:'api.example.test'}),q=t.options.question;
 t.options.question=(label,fallback,secret)=>{
 const screen=t.output.at(-1)||'';
 if(/domínio\/URL do Frontend/.test(screen))return Promise.resolve('app.example.test');
 if(/Usar as portas padrão/.test(screen))return q(label,fallback,secret).then(()=> 'n');
 if(/Qual porta deseja para o Backend/.test(screen))return Promise.resolve('8810');
 if(/Qual porta deseja para o Frontend/.test(screen))return Promise.resolve('3310');
 return q(label,fallback,secret);
 };
 const c=await collectHistorical(t.options);assert.equal(c.edge,true);assert.equal(c.backendUrl,'https://api.example.test');assert.equal(c.frontendUrl,'https://app.example.test');assert.equal(c.options.backendPort,8810);assert.equal(c.options.frontendPort,3310);
});
test('historical cancellation and EOF never invoke platform provisioning',async()=>{
 for(const changes of [{0:':cancelar'},{11:null},{13:':cancelar'},{15:':cancelar'},{15:'n'},{16:null}]){const t=input(changes);await assert.rejects(collectHistorical(t.options),/cancelada antes de criar recursos/);}
 const t=input({14:'different'});await assert.rejects(collectHistorical(t.options),/Confirmação diferente/);
});
test('historical form retries unauthorized repositories and does not echo supplied credentials',async()=>{
 const t=input({11:'https://user:private@example.test/fork.git'}),q=t.options.question;let retried=false;
 t.options.question=(label,fallback,secret)=>{
  if(retried&&/URL do repositório/.test(t.output.at(-1)||''))return Promise.resolve(SOURCE);
  return q(label,fallback,secret).then(value=>{if(value==='https://user:private@example.test/fork.git')retried=true;return value;});
 };
 const c=await collectHistorical(t.options);assert.equal(c.sourceUrl,SOURCE);assert.ok(!t.output.join('').includes('user:private'));
});
test('unvalidated historical channels and unavailable tools never execute an update or provisioning',async()=>{
 for(const branch of ['2','3','4']){
  let executions=0;const m={root:'/tmp/example',state:{project:'acerti'},load(){},execute(){executions++;}};
  const answers=['s',branch,'feature/test'];const menu=new Menus(m,async()=>answers.shift(),null,{out:()=>{}});
  await assert.rejects(menu.update(),/indisponível/);assert.equal(executions,0);
 }
 let executions=0;const m={root:'/tmp/example',state:{project:'acerti'},load(){},execute(action){assert.equal(action,'update');executions++;}};
 const answers=['s','1'];await new Menus(m,async()=>answers.shift(),null,{out:()=>{}}).update();assert.equal(executions,1);
});
test('HTTPS custom binding validation includes proxy and optional-service port collisions',()=>{
 const c={sourceUrl:SOURCE,edge:true,frontendUrl:'https://app.example.test',backendUrl:'https://api.example.test',options:{frontendPort:3310,backendPort:8810}};
 assert.equal(normalizeConfig(c).options.backendPort,8810);
 for(const options of [{backendPort:3310},{backendPort:443},{frontendPort:6000},{frontendPort:0},{backendPort:65536}])assert.throws(()=>normalizeConfig({...c,options:{...c.options,...options}}),/Porta/);
});
test('every recovered historical entry point delegates to the isolated Docker bootstrap',()=>{
 const entries=['atualizador_pro.sh','atualizador_fast_sistema.sh','atualizador_remoto.sh','atualizador_remoto_FAST.sh','atualizar_apioficial.sh','instalador_apioficial.sh','instalador_whatsmeow.sh','instalar_nginx_ssl.sh','tools/agendar_backup_bd_docker.sh','tools/instalador_instancias.sh','tools/instalar_push.sh','tools/roolback_versao.sh','tools/trocar_dominios.sh'];
 for(const file of entries){const s=fs.readFileSync(path.join(__dirname,'..',file),'utf8');assert.ok(s.includes('exec sh "$installer_root/instalador_single.sh"'));assert.ok(s.includes('"$@"'));}
});
test('unavailable administrative recipes report failure and never claim a completed operation',async()=>{
 const messages=[],m={root:'/tmp/example'},menu=new Menus(m,async()=>{throw Error('Entrada inesperada');},null,{out:s=>messages.push(s)});
 for(const action of ['native-unavailable','portainer-unavailable','external-unavailable','helper-unavailable'])await assert.rejects(menu.dispatch(action,true),/indisponível/);
 assert.equal(messages.length,0);
});
test('historical performance choices map to bounded PostgreSQL profiles in containers',async()=>{
 for(const profile of ['0','1','2','3']){const t=input({16:profile}),c=await collectHistorical(t.options);if(profile==='0')assert.equal(c.options.pg,undefined);else{assert.equal(c.options.pg.maxConnections,Number(profile)*100);assert.equal(c.options.pg.sharedBuffers,{'1':'128MB','2':'256MB','3':'512MB'}[profile]);}assert.ok(t.output.at(-1).includes('PostgreSQL em container'));assert.ok(!t.output.at(-1).includes('Nginx'));}
});
test('real color terminals retain menu dispatch while rendering the original lilac highlights',()=>{
 const script="Object.defineProperty(process.stdout,'isTTY',{value:true});const {MAIN,TOOLS}=require('./docker/installer/menus.cjs');const {render}=require('./docker/installer/historical.cjs');process.stdout.write(JSON.stringify({main:MAIN.map(x=>x[0]),tools:TOOLS.map(x=>x[0]),screen:render('main')}));";
 const result=spawnSync(process.execPath,['-e',script],{cwd:path.join(__dirname,'..'),encoding:'utf8',env:{...process.env,TERM:'xterm-256color',NO_COLOR:undefined}});assert.equal(result.status,0,result.stderr);
 const value=JSON.parse(result.stdout);assert.equal(value.main.length,11);assert.equal(value.tools.length,25);assert.ok(value.screen.includes('\x1b[1;38;2;167;139;250m'));assert.ok(value.screen.includes('\x1b[38;2;139;92;246m'));
});
