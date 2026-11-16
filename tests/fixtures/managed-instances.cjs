const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {SOURCE,Manager}=require('../../docker/installer/manager.cjs');
const {setupRecord}=require('../../docker/installer/directory-state.cjs');
function workspace(){
  const base=fs.mkdtempSync(path.join(os.tmpdir(),'amanda-discovery-'));
  fs.chmodSync(base,0o700);fs.mkdirSync(path.join(base,'instances'),{mode:0o700});
  function add(project='amanda',{profiles=['official','whatsmeow','rabbit','edge'],phase='ready',root=path.join(base,'instances',project)}={}){
    const platform=path.join(root,'platform'),privateDir=path.join(root,'.amanda-installer');
    fs.mkdirSync(platform,{recursive:true,mode:0o700});fs.mkdirSync(privateDir,{mode:0o700});fs.chmodSync(root,0o700);
    const state={schema:1,sourceUrl:SOURCE,project,platform,phase,profiles,initialized:phase==='ready',seedAttempted:true,seedSucceeded:true,revision:'a'.repeat(40)};
    const file=path.join(privateDir,'state.json'),write=()=>fs.writeFileSync(file,JSON.stringify(state),{mode:0o600});write();
    fs.writeFileSync(path.join(platform,'.env'),`COMPOSE_PROJECT_NAME=${project}\nFRONTEND_URL=https://front.${project}.example.test\nBACKEND_URL=https://back.${project}.example.test\nOFICIAL_HOST=oficial.${project}.example.test\nTOKEN_API_OFICIAL=synthetic-private-token\nWUZAPI_ADMIN_TOKEN=synthetic-wuzapi-token\n`,{mode:0o600});
    fs.writeFileSync(path.join(privateDir,'setup.json'),JSON.stringify(setupRecord(root,{project,sourceUrl:SOURCE})),{mode:0o600});
    return{root,platform,privateDir,file,state,write,manager:new Manager(root)};
  }
  function snapshot(){const files={};function walk(dir){for(const item of fs.readdirSync(dir,{withFileTypes:true})){const file=path.join(dir,item.name);if(item.isDirectory())walk(file);else if(item.isFile())files[path.relative(base,file)]=fs.readFileSync(file).toString('base64');}}walk(base);return files;}
  return{base,add,snapshot,cleanup(){fs.rmSync(base,{recursive:true,force:true});}};
}
module.exports={workspace};
