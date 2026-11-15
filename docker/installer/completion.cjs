// Resumo histórico (legacy/instalador_single.sh), sem executar provisionamento.
const fs=require('node:fs');
const path=require('node:path');
const {createUI}=require('./ui.cjs');
const clean=v=>String(v??'').replace(/[\x00-\x1f\x7f-\x9f]/g,'');
function publicUrl(value){
  try{const u=new URL(value);if(!['http:','https:'].includes(u.protocol)||u.username||u.password||u.search||u.hash||u.pathname!=='/')return null;return u;}catch{return null;}
}
function rows(text){try{const v=JSON.parse(text);return Array.isArray(v)?v:[v];}catch{return text.trim().split('\n').filter(Boolean).map(s=>JSON.parse(s));}}
function render({state,root,env,groups,checks={},unavailable=false,context},{tty=Boolean(process.stdout.isTTY),columns=process.stdout.columns||80,theme=process.env}={}){
  const ui=createUI({tty,env:theme}),width=Math.max(20,Math.min(76,columns)),rule='─'.repeat(width);
  const title=context?(context.kind==='update'?'AMANDA — ATUALIZAÇÃO CONCLUÍDA':'API OFICIAL — '+({install:'INSTALAÇÃO CONCLUÍDA',start:'SERVIÇO INICIADO',restart:'SERVIÇO REINICIADO',update:'ATUALIZAÇÃO CONCLUÍDA'}[context.action]||'OPERAÇÃO CONCLUÍDA')):'✓ AMANDA — INSTALAÇÃO CONCLUÍDA';
  const abnormal=context&&groups.some(g=>g.runtime&&g.names.some(n=>{const r=g.runtime.find(x=>x.Service===n);return !r||r.State!=='running'||['unhealthy','starting'].includes(r.Health);}));
  const partial=context&&groups.some(g=>g.names.some(n=>g.config?.services?.[n]?.healthcheck&&!g.runtime?.find(x=>x.Service===n)?.Health));
  const heading=abnormal?'OPERAÇÃO APLICADA — REVALIDAÇÃO NECESSÁRIA':title+(context&&(unavailable||partial)?' COM AVISOS':'');
  const lines=[ui.banner(heading).trimEnd()];
  const section=t=>lines.push('\n'+t,rule);
  section('EMPRESA');lines.push('Nome técnico: '+clean(state.project),'Diretório: '+clean(root));
  if(context){section('INFORMAÇÕES DA OPERAÇÃO');lines.push('Conclusão: '+clean(context.finishedAt),'Revisão anterior: '+clean(context.previousRevision||'Não verificado'),'Revisão atual: '+clean(state.revision||'Não verificado'));if(context.kind==='update'){lines.push('Canal: '+clean(context.channel||'Não verificado'));if(context.previousRevision===state.revision)lines.push('Revisão inalterada — serviços reconstruídos/revalidados conforme operação executada');}lines.push('Backup desta operação: '+clean(context.backup||'Não verificado'));}
  section('ACESSO À PLATAFORMA');
  for(const [label,value]of [['FRONTEND — PAINEL WEB',env.FRONTEND_URL||state.frontendUrl],['BACKEND — API / SOCKET',env.BACKEND_URL||state.backendUrl],...(state.profiles.includes('official')&&state.profiles.includes('edge')&&env.OFICIAL_HOST?[['API OFICIAL','https://'+env.OFICIAL_HOST]]:[])]){
    const u=publicUrl(value);lines.push('\n'+label);
    if(!u){lines.push('URL: Não verificado');continue;}
    const local=u.hostname==='localhost'||u.hostname==='[::1]'||/^127\./.test(u.hostname);
    lines.push(clean(u.href),'Protocolo: '+u.protocol.slice(0,-1).toUpperCase()+' | Porta da URL: '+(u.port||(u.protocol==='https:'?'443':'80'))+'/TCP');
    if(local)lines.push('Acesso local ao servidor; não é um link remoto.');
    lines.push('HTTPS: '+(u.protocol!=='https:'?'Não se aplica':checks.https?'VALIDADO':'Não verificado'));
    if(context&&!label.startsWith('API'))lines.push('HTTP público: '+(checks.https?'200 (rotas validadas pelo fluxo)':'Não verificado; consulte a validação interna abaixo'));
    if(state.profiles.includes('edge'))lines.push('Acesso via Caddy; publicação efetiva abaixo.');
  }
  section('PORTAS E SERVIÇOS');
  // Blocos verticais evitam tabelas horizontais largas. EXPOSE não é publicação.
  for(const group of groups)for(const name of group.names){
    const service=group.config?.services?.[name];if(!service)continue;
    const runtime=group.runtime?.filter(r=>r.Service===name)||[],ports=runtime.flatMap(r=>r.Publishers||[]),publishers=ports.filter(p=>Number(p.PublishedPort)>0);
    const targets=[...new Set([...(service.expose||[]).map(String),...(service.ports||[]).map(p=>p.target?String(p.target)+'/'+(p.protocol||'tcp'):'').filter(Boolean),...ports.filter(p=>p.TargetPort).map(p=>p.TargetPort+'/'+(p.Protocol||'tcp'))])];
    lines.push('\n'+clean(group.prefix+name),'  Interna: '+(targets.map(clean).join(', ')||'Não verificado'));
    if(context){const current=runtime[0];lines.push('  Container: '+clean(current?.Name||'Não verificado'),'  Estado: '+(!group.runtime?'NÃO VERIFICADO':!current?'AUSENTE':current.State==='running'?(current.Health?.toUpperCase()||(service.healthcheck?'RUNNING — HEALTHCHECK NÃO VERIFICADO':'RUNNING SEM HEALTHCHECK')):clean(current.State?.toUpperCase()||'NÃO VERIFICADO')));}
    if(group.runtime===null||!runtime.length)lines.push('  Publicação no host: Não verificado');
    else if(!publishers.length)lines.push('  Sem porta publicada no host (rede Docker).');
    for(const p of publishers){const bind=String(p.URL||'');const loop=bind==='::1'||/^127\./.test(bind),any=['0.0.0.0','::','[::]'].includes(bind);
      lines.push('  Host: '+clean(bind||'Não verificado')+':'+Number(p.PublishedPort)+' → '+Number(p.TargetPort)+'/'+clean(p.Protocol||'tcp'),
        '  '+(loop?'Somente loopback':any?'Todas as interfaces; acesso externo depende da rede/firewall':'Bind específico; alcance externo não verificado'));
    }
    if(group.prefix===''&&state.profiles.includes('edge')&&['frontend','backend','api_oficial'].includes(name)&& (name!=='api_oficial'||env.OFICIAL_HOST))lines.push('  Acesso por proxy reverso Caddy (portas do edge).');
  }
  if(!groups.some(g=>g.config))lines.push('Serviços e portas: Não verificado');
  if(unavailable)lines.push('\nAlguns dados Docker não estão disponíveis: Não verificado.');
  section('STATUS FINAL');
  if(context){lines.push('Estado persistido: ready','Verificações obrigatórias da operação: '+(checks.health?'APROVADAS':'Não verificadas nesta execução'),'HTTP interno frontend/backend: '+(checks.health?'200 (validação existente)':'Não verificado'),'HTTPS público: '+(checks.https?'VALIDADO':'Não verificado / não aplicável'),'Migrations: '+(context.migrations?'concluídas nesta operação':'não atribuídas a esta operação'),'Imagens reconstruídas: '+(context.rebuilt?'sim, pelo fluxo existente':'Não atribuído'),'Dados persistentes: preservados pelo fluxo existente; sem restauração adicional','Contas e credenciais: preservadas pelo fluxo existente','Nenhum seed adicional executado');
    if(state.profiles.includes('official')){section('API OFICIAL — CONEXÃO E LIMITES');const service=groups[0]?.config?.services?.api_oficial,backend=groups[0]?.config?.services?.backend;
      lines.push('Endpoint interno configurado: '+clean(publicUrl(backend?.environment?.URL_API_OFICIAL)?.href||'Não verificado'));
      if(!env.OFICIAL_HOST||!state.profiles.includes('edge'))lines.push('URL pública: não configurada; disponível somente na rede Docker ou publicação indicada acima');
      let database;try{database=new URL(service?.environment?.DATABASE_LINK).pathname.slice(1);}catch{}lines.push('Banco configurado: '+clean(database||'Não verificado'),'API → Backend / PostgreSQL / Redis / RabbitMQ: configuração não prova conectividade; testes adicionais não verificados','Meta / conta WhatsApp Business: NÃO VERIFICADAS','Webhooks Meta: NÃO HOMOLOGADOS','Templates e mensagens externas: NÃO TESTADOS');}
  }else lines.push('✓ Serviços essenciais verificados','DNS: '+(checks.dns?'VALIDADO':'Não verificado / não aplicável'),'HTTPS: '+(checks.https?'VALIDADO':'Não verificado / não aplicável'),'Login inicial: '+(checks.login?'APROVADO':'Não verificado nesta execução'),'✓ Estado persistido: ready');
  section('GERENCIAR A INSTALAÇÃO');lines.push('cd ~/Instalador-AMANDA','sh ./instalador_single.sh',rule,context?(abnormal?'REVALIDAÇÃO NECESSÁRIA':context.kind==='official'?'API OFICIAL — PRONTA PARA CONFIGURAÇÃO':heading):'AMANDA — PRONTA PARA UTILIZAÇÃO');
  // Mantém o logo histórico em terminais comuns, adapta o cabeçalho no estreito.
  if(columns<64)lines[0]=ui.item('✓',context?heading:'AMANDA — INSTALAÇÃO CONCLUÍDA');
  return lines.join('\n')+'\n';
}
async function collect(m,checks={}){
  const saved=JSON.parse(fs.readFileSync(m.stateFile,'utf8'));
  if(saved.phase!=='ready'||!saved.initialized)return;
  let env={},config,unavailable=false;
  try{env=require('./manager.cjs').envValues(path.join(saved.platform,'.env'));config=await m.configuration();}catch{unavailable=true;}
  const groups=[{prefix:'',config,names:[...m.services(),...(saved.profiles.includes('edge')?['edge']:[])],base:null},...(config?.installerAddons||[]).map(a=>({prefix:a.project+'/',names:a.services,base:a.base}))];
  for(const group of groups){try{
    if(group.base)group.config=JSON.parse((await m.docker([...group.base,'config','--format','json'],{quiet:true})).stdout);
    const result=group.base?await m.docker([...group.base,'ps','--all','--format','json'],{quiet:true}):await m.compose(['ps','--all','--format','json'],{quiet:true});
    group.runtime=rows(result.stdout||'[]');
  }catch{group.runtime=null;unavailable=true;}}
  return {state:saved,root:m.root,env,groups,checks,unavailable};
}
async function showCompletion(m,checks={}){const model=await collect(m,checks);if(model)m.runner.emit(render(model));}
function verifiedBackup(m,context){try{const real=fs.realpathSync(context.backup),base=fs.realpathSync(path.join(m.private,'backups'));if(!real.startsWith(base+path.sep))return;const meta=JSON.parse(fs.readFileSync(path.join(real,'backup.json')));if(meta.complete&&meta.project===m.state.project&&meta.revision===context.previousRevision)return real+' (metadados completos; gravados em '+fs.statSync(path.join(real,'backup.json')).mtime.toISOString()+')';}catch{}}
async function showOperation(m,context){try{const model=await collect(m,{health:!!context.health,https:!!context.health&&m.state.profiles.includes('edge')});if(!model)return;if(context.kind==='official'&&!model.state.profiles.includes('official'))return;model.context={...context,backup:verifiedBackup(m,context),finishedAt:new Date().toISOString()};m.runner.emit(render(model));}catch{m.runner.emit('Resumo complementar indisponível. Consulte status e estado persistido.\n');}}
const showUpdateCompletion=(m,context)=>showOperation(m,{...context,kind:'update'});
const showOfficialApiCompletion=(m,context)=>showOperation(m,{...context,kind:'official'});
module.exports={showCompletion,render,publicUrl,showUpdateCompletion,showOfficialApiCompletion};
