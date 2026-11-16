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
  const supported=Boolean(env.WT_SESSION||env.COLORTERM||/xterm|screen|tmux|linux|ansi|cygwin|rxvt|alacritty|kitty|putty|eterm|mlterm|konsole|foot|wezterm|^st(?:-|$)/i.test(env.TERM||''));
  const enabled=tty&&supported&&env.AMANDA_COLOR_OUTPUT!=='0'&&!/dumb|mono|^vt10[02]$|^unknown$/i.test(env.TERM||'')&&env.NO_COLOR===undefined;
  const rich=/xterm|256color|screen|tmux|linux|alacritty|kitty/.test(env.TERM||'')||['truecolor','24bit'].includes(env.COLORTERM)||Boolean(env.WT_SESSION);
  const color=code=>enabled?'\x1b['+code+'m':'';
  const purple=color(rich?'38;2;139;92;246':'38;5;99'),blue=color(rich?'1;38;2;167;139;250':'1;94'),white=color(rich?'1;38;2;255;255;255':'1;97'),reset=color('0');
  const safe=value=>require('node:util').stripVTControlCharacters(String(value)).replace(/[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069\u2028\u2029]/g,'');
  const width=Number.isFinite(columns)?Math.max(20,Math.min(100,Math.floor(columns))):80;
  const lines=rows=>{if(!Array.isArray(rows))throw TypeError('Informe uma lista de linhas.');return rows.flatMap(value=>wrap(value,width)).join('\n');};
  const palette={title:purple,info:color(rich?'38;2;56;189;248':'96'),good:color(rich?'1;38;2;74;222;128':'1;32'),warn:color(rich?'1;38;2;250;204;21':'1;33'),bad:color(rich?'1;38;2;248;113;113':'1;31'),neutral:white,muted:color('90')};
  const paint=(value,tone='neutral')=>(Object.hasOwn(palette,tone)?palette[tone]:palette.neutral)+safe(value)+reset;
  const charWidth=c=>/\p{Mark}|[\u200d\ufe0f]/u.test(c)?0:/[\u1100-\u115f\u2e80-\ua4cf\uac00-\ud7a3\uf900-\ufaff\ufe10-\ufe6f\uff01-\uff60\u{1f300}-\u{1faff}\u{20000}-\u{3fffd}]/u.test(c)?2:1;
  const visibleWidth=value=>Array.from(require('node:util').stripVTControlCharacters(String(value))).reduce((n,c)=>n+charWidth(c),0);
  const wrap=(value,size)=>{const result=[];let row='',used=0;for(const c of Array.from(safe(value))){const n=charWidth(c);if(used+n>size){result.push(row);row='';used=0;}row+=c;used+=n;}result.push(row);return result;};
  return {
    text:safe,
    width,
    paint,
    visibleWidth,
    heading(title){return '\n'+wrap('AMANDA • '+safe(title),width).map(row=>paint(row,'title')).join('\n')+'\n';},
    panel(title,rows){
      if(!Array.isArray(rows))throw TypeError('Informe linhas estruturadas.');
      const size=Math.min(56,width),inner=size-4,border=(left,right)=>paint(left+'─'.repeat(size-2)+right,'title');
      const row=(text,tone)=>paint('│','title')+' '+paint(text,tone)+' '.repeat(Math.max(0,inner-visibleWidth(text)))+' '+paint('│','title');
      return[border('╭','╮'),...wrap('AMANDA • '+safe(title),inner).map(text=>row(text,'title')),border('├','┤'),...rows.flatMap(entry=>wrap(typeof entry==='string'?entry:entry.text,inner).map(text=>row(text,typeof entry==='string'?'neutral':entry.tone))),border('╰','╯')].join('\n');
    },
    // Accept structured rows only: dynamic newlines/escapes are discarded before
    // our own wrapping and separators introduce trusted line breaks.
    lines,
    banner(title){if(width<64)return '\n'+white+lines(['AMANDA — '+safe(title)])+reset+'\n';return (enabled?'\x1b[2J\x1b[H':'\n')+purple+LOGO.join('\n')+'\n       AMANDA - PLATAFORMA DE ATENDIMENTO MULTICANAL v1.0.0\n       Instalador e Gerenciador Oficial 100% Docker\n'+reset+'\n'+white+' '+safe(title)+reset+'\n';},
    item(id,label,tone){return '   ['+(tone&&Object.hasOwn(palette,tone)?palette[tone]:blue)+safe(id)+reset+'] '+safe(label);},
    question(label,fallback){return '\n'+white+' >> '+safe(label)+(fallback!==undefined?' [padrão: '+purple+safe(fallback)+white+']':'')+reset+'\n\n> ';},
  };
}
module.exports={LOGO,createUI};
