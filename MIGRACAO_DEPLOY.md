# Migração autorizada para /home/deploy

Novas instalações não executam migração. `--dir` conserva a instalação existente.
O comando `migration-plan --dir /caminho/antigo` produz um inventário restrito:
origem/destino, serviços ativos, volumes, binds e validação do último backup.
Não exibe configurações privadas, não move arquivos e não altera a stack.
Falha de integridade reprova o plano; ausência de backup é marcada como pendência.

Procedimento separado, a executar apenas após autorização explícita do alvo:

1. Identificar a revisão, empresa, estado e agendadores; conferir o plano e os
   serviços reais. Preparação incompleta exige resolução antes de migrar.
2. Criar backup pelo comando `backup --dir /origem`. Repetir o plano para validar
   hashes e formato dos dumps. Copiar também esse backup para destino independente
   e conferir os hashes; preservar integralmente a origem.
3. Definir janela de manutenção e parar apenas gravadores e agendadores da empresa.
   Inventariar binds absolutos: seu conteúdo deve estar no snapshot/cópia. Manter
   exatamente os nomes de projeto, redes e volumes Docker.
4. Preparar deploy e um destino novo e vazio. Copiar, sem remover a origem,
   preservando modos e links. Revisar inventário antes de ajustar propriedade;
   não seguir symlinks nem executar chown recursivo sobre diretórios genéricos.
5. Atualizar somente referências absolutas de origem no estado e manifestos dos
   backups copiados, binds e agendadores. Tokens, `.env`, revisão, nomes Docker e
   conteúdo dos dumps/volumes não devem ser alterados. Conferir os backups copiados
   novamente antes de habilitar operações no novo estado.
6. Validar configuração Compose, propriedade/modes, fonte, caminhos, locks e hashes.
   Recriar apenas os containers que precisem trocar binds, usando o mesmo projeto
   e volumes. Não executar seed nem migrations de versão como parte da mudança.
7. Validar saúde HTTP, login, mídia, sessões e registros representativos; comparar
   com a origem. Recriar agendadores apontando para o destino após aprovação.
8. Recuperação: manter agendadores parados; interromper os novos gravadores e voltar
   aos binds/estado originais. Se houve escrita após o corte, reconciliar dados ou
   restaurar o backup validado antes de retomar. Não iniciar dois gravadores sobre
   o mesmo banco. Não apagar origem, volumes ou backup até aceitação explícita.

Este procedimento exige homologação em Linux descartável e autorização operacional.
O instalador fornece o plano de leitura; não automatiza a cópia/troca de uma VPS
existente nem afirma que uma mudança de caminho equivale a uma migração validada.
