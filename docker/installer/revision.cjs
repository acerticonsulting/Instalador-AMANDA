function revisionLine(env=process.env){
  const clean=value=>typeof value==='string'&&!/[\x00-\x1f\x7f]/.test(value)&&value.length<=200?value:'não informada';
  const branch=clean(env.AMANDA_INSTALLER_BRANCH);
  const commit=/^[a-f0-9]{40,64}$/.test(env.AMANDA_INSTALLER_COMMIT||'')?env.AMANDA_INSTALLER_COMMIT.slice(0,12):'não informado';
  const dirty=env.AMANDA_INSTALLER_DIRTY==='dirty'?' (arquivos locais alterados)':env.AMANDA_INSTALLER_DIRTY==='clean'?'':' (integridade Git não informada)';
  return `Instalador: branch ${branch}; commit ${commit}${dirty}. Plataforma selecionada: main.`;
}
module.exports={revisionLine};
