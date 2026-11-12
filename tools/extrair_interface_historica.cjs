// Ferramenta de desenvolvimento: recupera apresentação, nunca provisionamento.
// O hash completo impede trocar silenciosamente a referência visual.
const fs=require('node:fs');
const {execFileSync}=require('node:child_process');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const REF='7a5b31da3ce48fb50fe451fbcbe840f725fa8838';
const source=execFileSync('git',['show',REF+':instalador_single.sh'],{cwd:root,encoding:'utf8',maxBuffer:4*1024*1024}).replace(/\r/g,'');
function section(name){const start=source.indexOf('\n'+name+'() {')+1;if(!start)throw Error(name);const end=source.indexOf('\n}\n',start);return source.slice(start,end+3);}
function screen(name,start,end){const body=section(name);return body.slice(body.indexOf(start),body.indexOf(end));}
const replacements=[
 ['Proxy Reverso Nginx','Proxy Reverso Caddy em Docker'],
 ['Homologação GHCR / Configurar Watchtower','Homologação GHCR / Configurar Atualização Agendada'],
 ['Agendar Backup Diário do Banco Nativo','Agendar Backup Diário do Banco Nativo (indisponível neste modo)'],
 ['Backup do Redis (instância / Docker ou nativo)','Backup do Redis (instância / Docker)'],
 ['Importar backup do banco da API Oficial (nativo ou Alta Performance)','Importar backup do banco da API Oficial (Docker)'],
 ['Backup do banco WhatsMeow (PostgreSQL Docker)','Backup do WhatsMeow (volume WuzAPI / SQLite)'],
 ['Aplicar certificado SSL no Nginx','Aplicar certificado SSL no Caddy (Docker)'],
 ['Domínio + porta + SSL no Nginx (proxy reverso)','Domínio + porta + SSL no Caddy (Docker)'],
 ['Atualizar Baileys PRO (Heineken)','Atualizar Baileys pela versão oficial da plataforma'],
 ['Atualizar API WhatsMeow (WuzAPI — git pull + rebuild)','Atualizar API WhatsMeow (WuzAPI — imagem oficial)'],
 ['Otimizar Postgres Nativo','Otimizar Postgres em Docker'],
 ['Atualizar token GitHub + FAST (qualquer repo)','Atualizar token GitHub + FAST (repositório oficial)'],
 ['Configurar Nginx e Emitir Certificado SSL para API Oficial','Configurar Caddy e Emitir Certificado SSL para API Oficial'],
];
const adapt=text=>replacements.reduce((s,[a,b])=>s.replaceAll(a,b),text);
let main=screen('menu','    banner','    read -p');
let tools=screen('menu_ferramentas','    banner','    read -p').split('\n').filter(l=>!/[[]\$\{BLUE\}(24|25|26|27)\$/.test(l)).join('\n');
let api=screen('menu_gerenciar_api_oficial','    banner','    read -r');
const channel=screen('selecionar_canal_branch_amanda','  banner','  read -r').replace('banner 2>/dev/null || true','banner');
const status=screen('menu_status_reiniciar_containers','  banner','  read -r').split('\n').filter(l=>/^\s*(banner|printf|echo)\b/.test(l)).join('\n').replaceAll('${emp}_apioficial','${emp}_api_oficial').replaceAll('${emp}_transcricao','${emp}_api_transcricao');
const update=screen('atualizar_amanda_docker','  banner','  if [ "${branch_atual}"');
const optimize=screen('questoes_otimizacao_nativa','  banner','  read -p').split('\n').filter(l=>/^\s*(banner|printf|echo)\b/.test(l)&&!l.includes('Com Nginx selecionado')).join('\n').replace('PostgreSQL nativo','PostgreSQL em container');
const summary=section('dados_instalacao_base').split('\n').filter(l=>/^\s*printf/.test(l)&&!/(PgBouncer|GoFlow)/.test(l)).map(l=>{
 const m=l.match(/printf "   \$\{WHITE\}(.+?)\$\{YELLOW\}\$\{([^}]+)\}(?:\$\{WHITE\})?\\n"/);
 if(!m)return l;
 const secret=/(Senha|FACEBOOK_APP_SECRET|Token GitHub)/.test(m[1]);
 return "  printf '   %b"+m[1]+"%b%s\\n' \"$WHITE\" \"$YELLOW\" "+(secret?'\"[oculta]\"':'\"${'+m[2]+'}\"');
}).join('\n');
// O estado da API é consultado pelo gerenciador; aqui só ficam os printf originais.
api=api.split('\n').filter(l=>/^\s*(banner|echo|printf)\b/.test(l)).join('\n');
const questions={};
for(const name of ['questoes_dns_base','questoes_variaveis_base','define_proxy_base','define_portas_base','confirma_dados_instalacao_base']){
 const lines=section(name).split('\n');
 for(let i=0;i<lines.length;i++)if(/read -p/.test(lines[i])){
   const key=lines[i].match(/read -p "> " (\w+)/)?.[1]||lines[i].match(/" (\w+)\s*$/)?.[1];
   if(!key)continue;
   let start=i-1;while(start>=0&&!/\b(banner|read -p)/.test(lines[start]))start--;
   const prints=lines.slice(start,i).filter(l=>/^\s*(banner|echo|printf)\b/.test(l));
   if(!prints.length)continue;
   questions[key]=adapt(prints.join('\n'));
 }
}
// Atualizar apenas o endereço autorizado e o mecanismo de proxy incompatível.
questions.repo_url=questions.repo_url.replaceAll('https://github.com/alansuporteamanda/AMANDA.git','https://github.com/acerticonsulting/AMANDA.git');
questions.modo_rede+='\n  printf " Selecione a opção [1 ou 2, padrão: 1]: "';
questions.proxy='  banner\n  printf "${WHITE} >> Proxy reverso HTTPS em container: Caddy (substitui Nginx/Traefik no host).${WHITE}\\n"';
// Nenhuma porta de banco/cache/transcrição é publicada pelo Compose oficial.
questions.use_default_ports=questions.use_default_ports.split('\n').filter(l=>!/(PgBouncer|GoFlow|st_pgb|st_disp|st_db|st_redis|st_transc|st_wuzapi|AJUSTE 100|alterados automaticamente)/.test(l)).join('\n');
for(const key of ['backend_port','frontend_port'])questions[key]=questions[key].split('\n').filter(l=>!/(alocado|alocada|já está em uso)/.test(l)).join('\n');
questions.senha_deploy=questions.senha_deploy.replace('para o usuario Deploy, Redis e Banco de Dados [padrão: Acertitech13@]','do Banco de Dados [ENTER gera senha segura; Deploy nativo dispensado]');
questions.senha_master=questions.senha_master.replace('[padrão: Acertitech13@M]','[ENTER gera chave segura]');
const body=[
 '#!/bin/sh',
 '# Apresentação extraída de '+REF+'. Não contém operações de instalação.',
 '# Gerado por tools/extrair_interface_historica.cjs; adaptações explícitas nesse arquivo.',
 'historical_theme() {',
 '  PURPLE= BLUE= MAGENTA= GREEN= WHITE= RED= YELLOW= CYAN= NC= RESET=',
 '  if { [ -t 1 ] || [ "${AMANDA_UI_TTY:-}" = 1 ]; } && [ "${TERM:-}" != dumb ] && [ "${NO_COLOR+x}" != x ]; then',
 "    PURPLE='\\033[38;5;99m'; BLUE='\\033[1;94m'; GREEN='\\033[1;92m'; WHITE='\\033[1;97m'; RED='\\033[1;91m'; YELLOW='\\033[1;93m'; CYAN='\\033[1;96m'",
 '    case "${COLORTERM:-}:${TERM:-}:${WT_SESSION:-}" in *truecolor*|*24bit*|*xterm*|*256color*|*screen*|*tmux*|*linux*|*alacritty*|*kitty*)',
 "      PURPLE='\\033[38;2;139;92;246m'; BLUE='\\033[1;38;2;167;139;250m'; GREEN='\\033[1;38;2;74;222;128m'; WHITE='\\033[1;38;2;255;255;255m'; RED='\\033[1;38;2;248;113;113m'; YELLOW='\\033[1;38;2;250;204;21m'; CYAN='\\033[1;38;2;56;189;248m' ;;",
 '    esac',"    NC='\\033[0m'; RESET=$NC",'  fi', '}',
 section('banner').replace('  clear','  if { [ -t 1 ] || [ "${AMANDA_UI_TTY:-}" = 1 ]; } && [ "${TERM:-}" != dumb ] && [ "${NO_COLOR+x}" != x ]; then printf \'\\033[2J\\033[H\'; fi'),
 'historical_main() {\n'+adapt(main)+'\n}',
 'historical_tools() {\n'+adapt(tools)+'\n}',
 'historical_api() {\n'+adapt(api)+'\n}',
 'historical_channel() {\n'+channel+'\n}',
 'historical_status() {\n'+status+'\n}',
 'historical_update() {\n'+update+'\n}',
 'historical_optimize() {\n'+optimize+'\n}',
 'historical_summary() {\n'+summary+'\n}',
 'historical_question() {\n  case "$1" in',
 ...Object.entries(questions).map(([key,value])=>'    '+key+')\n'+value+'\n      ;;'),
 '    *) return 2 ;;','  esac','}',
 'historical_theme','nome_titulo=${nome_titulo:-AMANDA}',
 'case "${1:-}" in --main) historical_main ;; --tools) historical_tools ;; --api) historical_api ;; --channel) historical_channel ;; --status) historical_status ;; --update) historical_update ;; --optimize) historical_optimize ;; --summary) historical_summary ;; --question) historical_question "$2" ;; esac','',
].join('\n');
fs.writeFileSync(path.join(root,'docker/installer/historical.sh'),body);
console.log('Interface recuperada de '+REF+'; '+Object.keys(questions).length+' perguntas.');
