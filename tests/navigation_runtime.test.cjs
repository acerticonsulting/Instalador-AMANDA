const{test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const{spawn}=require('node:child_process');const{workspace}=require('./fixtures/managed-instances.cjs');
const enabled=process.env.AMANDA_NAV_RUNNER_CONTAINER&&process.env.AMANDA_NAV_TEST_IMAGE;
// The outer runner mounts /suite and a disposable /navigation volume; child CLI
// containers inherit both read-only. No application containers are inspected.
for(const route of ['4','11','12','wuzapi','11-bravo','12-bravo','4-switch'])test('real Shell → container CLI → company → read-only dashboard: '+route,{skip:!enabled,timeout:30000},async()=>{
  const choice=route.split('-')[0],bravo=route.endsWith('-bravo'),switchCompany=route==='4-switch';
  const t=workspace();try{
    const a=t.add('acerti'),b=t.add('bravo',{profiles:[]}),before=t.snapshot(),copy=path.join(t.base,'installer'),bin=path.join(t.base,'bin');
    fs.mkdirSync(path.join(copy,'docker/installer'),{recursive:true});fs.mkdirSync(bin);
    for(const file of ['instalador_single.sh','docker/installer/historical.sh'])fs.copyFileSync(path.join(__dirname,'..',file),path.join(copy,file));
    const source=path.resolve(__dirname,'..');
    fs.writeFileSync(path.join(bin,'docker'),`#!/bin/sh
case "$1" in
info) echo linux ;;
context) echo unix:///var/run/docker.sock ;;
run)
  actual=0
  for arg do [ "$arg" != --init ] || actual=1; done
  if [ "$actual" = 1 ]; then
    initial=; next=0
    for arg do
      if [ "$next" = 1 ]; then initial=$arg; next=0; fi
      [ "$arg" != --initial ] || next=1
    done
    set -- /usr/local/bin/docker run --rm -it --network none --name "$NAV_CHILD_NAME" --volumes-from "$AMANDA_NAV_RUNNER_CONTAINER:ro" --entrypoint node -e AMANDA_NAV_FIXTURE=1 -e "AMANDA_INSTALL_DIR=$NAV_BASE" -e AMANDA_DEPLOY_LAYOUT=0 -e NO_COLOR=1 -e TERM=dumb -e "NODE_OPTIONS=--require=$NAV_SOURCE/tests/fixtures/menu-readonly-runtime.cjs" "$AMANDA_NAV_TEST_IMAGE" "$NAV_SOURCE/docker/installer/cli.cjs"
    if [ -n "$initial" ]; then set -- "$@" menu --initial "$initial"; else set -- "$@" wuzapi; fi
    exec "$@"
  fi ;;
*) echo 'Unexpected bootstrap operation' >&2; exit 90 ;;
esac
`,{mode:0o755});
    const entry=path.join(copy,'instalador_single.sh'),quote=v=>"'"+v.replaceAll("'","'\\''")+"'",direct=choice==='wuzapi';
    const command='sh '+quote(entry)+(direct?' wuzapi':'');
    let output='',step=direct?1:0,offset=0,secondPanel='';
    const result=await new Promise((resolve,reject)=>{
      const child=spawn('script',['-q','-e','-c',command,'/dev/null'],{env:{...process.env,AMANDA_INSTALL_DIR:t.base,PATH:bin+':'+process.env.PATH,NAV_BASE:t.base,NAV_SOURCE:source,NAV_CHILD_NAME:path.basename(t.base)+'_cli',NO_COLOR:'1',TERM:'dumb'},stdio:['pipe','pipe','pipe']});
      const timeout=setTimeout(()=>{child.kill('SIGKILL');reject(Error('Navigation timeout at stage '+step+': '+output.slice(-1800)));},25000);
      child.on('error',reject);
      child.stdout.on('data',data=>{output+=data;const pending=output.slice(offset);let reply;
        if(step===0&&pending.includes('Diretório da instalação:')&&pending.includes('> ')){reply=choice+'\n';step=1;}
        else if(step===1&&pending.includes('Selecione a instância (0 cancela)')){reply=bravo?'2\n':'1\n';step=2;}
        else if(step===2&&pending.includes('Selecione a opção')){reply=switchCompany?'12\n':'0\n';step=switchCompany?6:3;}
        else if(step===6&&pending.includes('Selecione a instância (0 cancela)')){reply='2\n';step=7;}
        else if(step===7&&pending.includes('Selecione a opção')){secondPanel=pending;reply='0\n';step=3;}
        else if(step===3&&pending.includes('Pressione ENTER para voltar ao menu principal')){reply='\n';step=4;}
        else if(step===4&&pending.includes('Selecione a opção desejada')){reply='0\n';step=5;}
        if(reply!==undefined){offset=output.length;child.stdin.write(reply);}
      });child.stderr.on('data',d=>output+=d);
      child.on('close',status=>{clearTimeout(timeout);resolve(status);});
    });
    assert.equal(result,0,output);assert.equal(step,direct?3:5,output);
    assert.ok(!/Nenhuma instalação reconhecida|OPERAÇÃO NÃO CONCLUÍDA|ERRO:|INCOMPLETO/.test(output),output);
    assert.match(output,choice==='4'?/STATUS DA PLATAFORMA/:choice==='11'?/API Oficial/:/WhatsMeow\/WuzAPI/);
    if(choice!=='4'){
      const project=bravo?'bravo':'acerti';
      assert.match(output,new RegExp('│ Empresa: '+project+' +│'));
      assert.match(output,new RegExp('● Container: '+(bravo?'NÃO INSTALADO':'HEALTHY')));
      assert.match(output,/│ URL pública: +│/);assert.match(output,/HTTPS: NÃO VERIFICADO/);
      assert.ok(!output.includes('ID da imagem:'));assert.ok(!output.includes('URL interna:'));assert.equal((output.match(new RegExp('AMANDA • '+(choice==='11'?'API OFICIAL':'WhatsMeow/WuzAPI'),'g'))||[]).length,1);
      if(!bravo)assert.match(output,/Já instalada — domínio em \[8\]/);
    }
    if(bravo){assert.match(output,/Empresa: bravo/);assert.match(output,/API: NÃO INSTALADA/);assert.ok(!output.includes('acerti_api_oficial'));assert.ok(!output.includes('acerti_wuzapi'));}
    else{if(choice==='4')assert.match(output,/acerti_backend/);else assert.match(output,/Empresa: acerti/);assert.match(output,/HEALTHY|Healthy:/);}
    if(switchCompany){assert.match(secondPanel,/bravo_backend/);assert.ok(!secondPanel.includes('acerti_backend'));}else assert.ok(!output.includes('bravo_backend'));
    assert.ok(!output.includes('synthetic-private-token'));assert.ok(!output.includes('synthetic-wuzapi-token'));
    const after=t.snapshot();for(const[key,value]of Object.entries(before))assert.equal(after[key],value,key);
    assert.equal(Object.keys(after).filter(k=>k.startsWith('instances/')).length,Object.keys(before).length);
    assert.equal(a.state.project,'acerti');assert.equal(b.state.project,'bravo');
  }finally{t.cleanup();}
});
