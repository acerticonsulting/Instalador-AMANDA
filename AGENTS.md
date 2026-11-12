# Validação e commits neste projeto

- Depois de qualquer alteração, execute `bash tests/validar_instalador.sh` e corrija as falhas antes de concluir o trabalho.
- Atualize os testes de regressão quando corrigir um bug ou mudar um comportamento. Consulte `tests/PLANO_DE_TESTES.md` para a matriz de cobertura.
- A validação local não comprova a saúde de uma VPS. Não execute instaladores, migrações, restaurações ou exclusões reais como parte da suíte local.
- Se a tarefa incluir uma instalação existente e fornecer o alvo, use também o modo `--plataforma` de leitura e reporte os resultados separadamente.
- Faça um commit para cada conjunto de alterações concluído, como solicitado pelo usuário. Não finalize deixando alterações próprias sem commit.
- Ao concluir alterações, faça também push para o GitHub, conforme autorização permanente do usuário. Preserve alterações e commits existentes do usuário.
- Preserve a chave Git e os endereços dos repositórios, conforme solicitado pelo usuário, salvo nova instrução explícita.
- O hook em `tests/hooks/pre-commit` valida o conteúdo preparado para commit. Ative-o em novos clones com `bash tests/ativar_validacao.sh`; não sobrescreva hooks existentes nem use `--no-verify` para contornar falhas.
