// Self-contained so it can also execute inside the backend without copying files.
async function probeHttp(urls,attempts=6){
  let message='HTTP não verificado';
  for(let i=0;i<attempts;i++){
    try{for(const p of urls){const r=await fetch(p.url,{signal:AbortSignal.timeout(10000),redirect:'error'});if(p.exact?r.status!==200:r.status<200||r.status>=500)throw Error('HTTP '+r.status+': verifique a rota no proxy e a saúde da aplicação.');}console.log('HTTPS público e certificados validados; contas externas não verificadas.');return;}
    catch(error){const code=String(error.cause?.code||error.code||'');message=/ENOTFOUND|EAI_AGAIN/.test(code)?'DNS: domínio não resolvido; revise os registros e o resolvedor.':/CERT|TLS|SSL/.test(code)?'TLS: certificado não validado; revise emissão, validade e domínio.':/ECONN|ETIMEDOUT|ENETUNREACH|UND_ERR_CONNECT_TIMEOUT/.test(code)?'REDE: conexão recusada ou expirada; revise firewall, portas e proxy Docker.':error.message.startsWith('HTTP ')?error.message:'HTTPS: falha de rede, redirecionamento ou proxy; consulte os logs do Caddy.';if(i<attempts-1)await new Promise(r=>setTimeout(r,5000));}
  }
  throw Error(message);
}
module.exports={probeHttp};
