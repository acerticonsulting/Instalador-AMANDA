const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),{spawnSync}=require('node:child_process');
test('firewall inspection only queries rules, preserves SSH port and never invokes mutations',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'amanda-fw-readonly-'));
 try{const log=path.join(dir,'calls');for(const tool of ['ss','ufw','firewall-cmd','nft','iptables-save','ip6tables-save'])fs.writeFileSync(path.join(dir,tool),'#!/bin/sh\nprintf "%s\\n" "'+tool+' $*" >> "$TEST_LOG"\n',{mode:0o755});
 const result=spawnSync('/bin/bash',[path.join(__dirname,'../tools/diagnosticar_firewall.sh')],{encoding:'utf8',env:{PATH:dir,TEST_LOG:log,SSH_CONNECTION:'192.0.2.1 5111 198.51.100.1 2228'}});
 assert.equal(result.status,0,result.stderr);assert.match(result.stdout,/2228/);assert.match(result.stdout,/NÃO VERIFICADO/);assert.deepEqual(fs.readFileSync(log,'utf8').trim().split('\n').map(v=>v.trimEnd()),['ss -ltnp','ufw status verbose','firewall-cmd --state','firewall-cmd --list-all-zones','nft list ruleset','iptables-save','ip6tables-save']);
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
