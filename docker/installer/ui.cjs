// Visual recuperado do banner e das perguntas de 7a5b31d.
const LOGO = [
  '  █████╗ ███╗   ███╗ █████╗ ███╗   ██╗██████╗  █████╗ ',
  ' ██╔══██╗████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔══██╗',
  ' ███████║██╔████╔██║███████║██╔██╗ ██║██║  ██║███████║',
  ' ██╔══██║██║╚██╔╝██║██╔══██║██║╚██╗██║██║  ██║██╔══██║',
  ' ██║  ██║██║ ╚═╝ ██║██║  ██║██║ ╚████║██████╔╝██║  ██║',
  ' ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚═╝  ╚═╝',
];
function createUI({tty=Boolean(process.stdout.isTTY),env=process.env,columns=process.stdout.columns||80}={}) {
  const enabled=tty&&env.TERM!=='dumb'&&env.NO_COLOR===undefined;
  const rich=/xterm|256color|screen|tmux|linux|alacritty|kitty/.test(env.TERM||'')||['truecolor','24bit'].includes(env.COLORTERM)||Boolean(env.WT_SESSION);
  const color=code=>enabled?'\x1b['+code+'m':'';
  const purple=color(rich?'38;2;139;92;246':'38;5;99'),blue=color(rich?'1;38;2;167;139;250':'1;94'),white=color(rich?'1;38;2;255;255;255':'1;97'),reset=color('0');
  const safe=value=>require('node:util').stripVTControlCharacters(String(value)).replace(/[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069\u2028\u2029]/g,'');
  const width=Number.isFinite(columns)?Math.max(20,Math.min(100,Math.floor(columns))):80;
  const lines=rows=>{if(!Array.isArray(rows))throw TypeError('Informe uma lista de linhas.');return rows.flatMap(value=>{const chars=Array.from(safe(value)),result=[];do{result.push(chars.splice(0,width).join(''));}while(chars.length);return result;}).join('\n');};
  return {
    text:safe,
    width,
    // Accept structured rows only: dynamic newlines/escapes are discarded before
    // our own wrapping and separators introduce trusted line breaks.
    lines,
    banner(title){if(width<64)return '\n'+white+lines(['AMANDA — '+safe(title)])+reset+'\n';return (enabled?'\x1b[2J\x1b[H':'\n')+purple+LOGO.join('\n')+'\n       AMANDA - PLATAFORMA DE ATENDIMENTO MULTICANAL v1.0.0\n       Instalador e Gerenciador Oficial 100% Docker\n'+reset+'\n'+white+' '+safe(title)+reset+'\n';},
    item(id,label){return '   ['+blue+safe(id)+reset+'] '+safe(label);},
    question(label,fallback){return '\n'+white+' >> '+safe(label)+(fallback!==undefined?' [padrão: '+purple+safe(fallback)+white+']':'')+reset+'\n\n> ';},
  };
}
module.exports={LOGO,createUI};
