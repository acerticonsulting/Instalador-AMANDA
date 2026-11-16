// Explicit opt-in. Uses an isolated, network-disabled WuzAPI with synthetic keys.
// No WhatsApp login, external connection, production database or real session.
const{test}=require('node:test'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const{execFileSync}=require('node:child_process');
const enabled=process.env.AMANDA_OPTIONAL_RUNTIME==='1';
test('real WuzAPI: internal health/auth, stop/start/restart, container removal and volume preservation',{skip:!enabled,timeout:120000},async()=>{
  const project='amanda_optional_test_'+crypto.randomBytes(5).toString('hex'),name=project+'_wuzapi',volume=project+'_wuzapi_data',token=crypto.randomBytes(24).toString('hex');
  const docker=(...args)=>execFileSync('docker',args,{encoding:'utf8',timeout:30000,stdio:['ignore','pipe','pipe']}).trim();
  const inspect=()=>JSON.parse(docker('inspect',name))[0];
  const wait=async()=>{const end=Date.now()+45000;while(Date.now()<end){const info=inspect();if(info.State.Health?.Status==='healthy')return;assert.equal(info.State.Status,'running','fixture exited before healthy');await new Promise(r=>setTimeout(r,500));}throw Error('Isolated WuzAPI health timeout');};
  const create=()=>docker('run','-d','--name',name,'--label','com.docker.compose.project='+project,'--label','com.docker.compose.service=wuzapi','--network','none','--mount','type=volume,source='+volume+',target=/app/dbdata','-e','WUZAPI_ADMIN_TOKEN='+token,'--health-cmd','curl -fsS http://127.0.0.1:8080/ >/dev/null','--health-interval','1s','--health-timeout','3s','--health-retries','30','asternic/wuzapi:latest');
  let created=false;
  try{
    docker('volume','create','--label','com.docker.compose.project='+project,volume);create();created=true;await wait();
    let info=inspect();assert.equal(info.HostConfig.NetworkMode,'none');assert.deepEqual(info.HostConfig.PortBindings,{});
    const status=(route,header)=>docker('exec',name,'curl','-sS','-o','/dev/null','-w','%{http_code}',...(header?['-H',header]:[]),'http://127.0.0.1:8080'+route);
    assert.equal(status('/'),'200');
    for(const route of ['/admin/users','/session/status']){
      assert.ok(['401','403'].includes(status(route)),'unauthenticated route must be refused: '+route);
      assert.ok(['401','403'].includes(status(route,'token: invalid-fixture-token')),'invalid token must be refused: '+route);
    }
    docker('exec',name,'sh','-c','printf installer-synthetic-fixture > /app/dbdata/installer-fixture.txt');
    docker('stop','-t','5',name);assert.equal(inspect().State.Status,'exited');docker('start',name);await wait();
    docker('restart','-t','5',name);await wait();assert.equal(docker('exec',name,'cat','/app/dbdata/installer-fixture.txt'),'installer-synthetic-fixture');
    docker('rm','-f',name);created=false;docker('volume','inspect',volume);create();created=true;await wait();
    assert.equal(docker('exec',name,'cat','/app/dbdata/installer-fixture.txt'),'installer-synthetic-fixture');
    console.log('Isolated WuzAPI image: '+inspect().Image+'; preserved synthetic volume: '+volume);
  }finally{
    if(created){const info=inspect();assert.equal(info.Config.Labels['com.docker.compose.project'],project);docker('rm','-f',name);}
    // Deliberately retain the isolated volume; no volume-removal command exists here.
  }
});
