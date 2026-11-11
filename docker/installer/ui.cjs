// Visual recuperado do banner e das perguntas de 3e6b5cf (outubro/2026).
const LOGO = [
  '  █████╗ ███╗   ███╗ █████╗ ███╗   ██╗██████╗  █████╗ ',
  ' ██╔══██╗████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔══██╗',
  ' ███████║██╔████╔██║███████║██╔██╗ ██║██║  ██║███████║',
  ' ██╔══██║██║╚██╔╝██║██╔══██║██║╚██╗██║██║  ██║██╔══██║',
  ' ██║  ██║██║ ╚═╝ ██║██║  ██║██║ ╚████║██████╔╝██║  ██║',
  ' ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚═╝  ╚═╝',
];
function createUI({tty=Boolean(process.stdout.isTTY),env=process.env}={}) {
  const enabled=tty&&env.TERM!=='dumb'&&env.NO_COLOR===undefined;
  const rich=/xterm|256color|screen|tmux|linux|alacritty|kitty/.test(env.TERM||'')||['truecolor','24bit'].includes(env.COLORTERM)||Boolean(env.WT_SESSION);
  const color=code=>enabled?'\x1b['+code+'m':'';
  const purple=color(rich?'38;2;139;92;246':'38;5;99'),blue=color(rich?'1;38;2;139;92;246':'1;38;5;99'),white=color('1;37'),reset=color('0');
  const safe=value=>String(value).replace(/[\x00-\x1f\x7f-\x9f]/g,'');
  return {
    text:safe,
    banner(title){return (enabled?'\x1b[2J\x1b[H':'\n')+purple+LOGO.join('\n')+'\n       AMANDA - PLATAFORMA DE ATENDIMENTO MULTICANAL\n       Instalador e Gerenciador Oficial 100% Docker\n'+reset+'\n'+white+' '+safe(title)+reset+'\n';},
    item(id,label){return '   ['+blue+safe(id)+reset+'] '+safe(label);},
    question(label,fallback){return '\n'+white+' >> '+safe(label)+(fallback!==undefined?' [padrão: '+purple+safe(fallback)+white+']':'')+reset+'\n\n> ';},
  };
}
module.exports={LOGO,createUI};
