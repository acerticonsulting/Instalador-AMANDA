const fs=require('node:fs');
const path=require('node:path');
// Conservative release contract, not a general Shell parser. Dockerfiles execute
// their RUN instructions in an image and are deliberately outside this scan.
function forbiddenHostCommand(shell){
  const code=shell.replace(/\\\r?\n/g,' ').split(/\r?\n/).filter(l=>!/^\s*#/.test(l)).join('\n');
  return /(?:^|[\n;|&{}()]|\bthen\s+|\bdo\s+)\s*(?:(?:sudo|env|command)\s+)*(?:\/[^\s;|&]*\/)?(?:apt(?:-get)?|yum|dnf|apk|snap|node(?:js)?|npm|npx|python[0-9.]*|pip[0-9.]*|pm2|git|nginx|postgres|redis-server|rabbitmq-server|ffmpeg|gcc|g\+\+|make|curl|wget)\b/m.test(code);
}
function activeShellFiles(root){
  const files=[];
  for(const entry of fs.readdirSync(root,{withFileTypes:true})){
    if(entry.name.startsWith('.')||['legacy','tests','node_modules'].includes(entry.name))continue;
    const file=path.join(root,entry.name);
    if(entry.isDirectory())files.push(...activeShellFiles(file));
    else if(entry.isFile()&&entry.name.endsWith('.sh'))files.push(file);
  }
  return files;
}
module.exports={forbiddenHostCommand,activeShellFiles};
