> Referência histórica: descreve os scripts preservados em legacy/. Para o instalador Docker-only atual, consulte ../README.md e 01-contexto-para-ia.md. Os caminhos antigos de scripts/tools recebem o prefixo legacy/.

# Diagnóstico e riscos conhecidos

## Diagnóstico por sintoma

| Sintoma | Primeira verificação | Evitar como atalho |
| --- | --- | --- |
| Instância não aparece | Configuração individual, diretório e critérios de detecção | Criar nova configuração global por cima da existente |
| Porta ocupada | Processo, publicação Docker e estado gravado da instância | Encerrar processo desconhecido |
| Frontend chama URL antiga | Runtime, build, env e cache de entrada | Alterar só o proxy e declarar correção |
| Backend reinicia | Logs limitados, exit code, memória, banco e migrations | Executar seeds novamente |
| API Oficial não sobe | Dist, cliente Prisma, banco e Compose desse caminho | Resetar schema ou aplicar db push com perda de dados |
| Atualização Git falha | Branch, árvore local, acesso e remoto sem imprimir token | Reset hard indiscriminado |
| Transcrição usa porta errada | Modalidade Docker/PM2 e configuração por instância | Usar configuração global de outra instância |
| Desinstalação deixa volume | Labels, volume externo e propriedade | docker volume prune ou exclusão por prefixo |
| Local passou e VPS falha | Saúde real e contratos da aplicação | Tratar aprovação estática como homologação |

## Achados da revisão estática

| Prioridade | Evidência | Implicação |
| --- | --- | --- |
| Alta | Credenciais padrão e chaves literais em README e scripts; persistência de acesso Git em arquivos e remotos | Proteger arquivos e logs; planejar substituição de credenciais com autorização explícita, preservando a regra atual do AGENTS. |
| Alta | Atualização pode restaurar Compose com checkout forçado; bibliotecas Git fazem reset hard | Alterações locais podem se perder; registrar diff e backup antes de executar. |
| Alta | Dockerfiles da API Oficial gerados nos trechos lidos iniciam dist/main.js sem compilar TypeScript | Build pode falhar ou usar dist anterior; conferir revisão e artefatos antes da publicação. Não foi feito build real. |
| Alta | Templates montam URLs PostgreSQL interpolando senha diretamente | Senhas com caracteres reservados de URI podem produzir conexão inválida; testar codificação e consumidores. |
| Média | Instalação principal remove api_oficial do Compose, contrariando a apresentação de stack completa do README | Usar gerenciador 11 e conferir serviço real; não presumir presença da API. |
| Média | Cópia local AMANDA não fornece o Compose esperado nem todo o conjunto de serviços anunciado | O instalador e a aplicação local podem representar revisões distintas; conciliar antes de reproduzir implantação. |
| Média | Modificação de YAML por regex e código gerado em heredoc | Mudanças de indentação ou formato podem quebrar transformações; validar saída com parser real. |
| Média | Alguns comandos de reinício, pull e recuperação usam retorno ignorado | Mensagens intermediárias não garantem que a ação ocorreu; usar verificações finais específicas. |
| Média | Volumes externos são criados por nome e a remoção segura exige labels | Recursos sem label podem permanecer; inventariar sem ampliar escopo de exclusão. |
| Média | Scripts nativos e Docker coexistem, com seleção por caminhos e globais | Risco de operar modo ou instância incorretos se a identificação for incompleta. |
| Média | Imagens por latest, branches móveis e instalação npm durante build | Revisão Git não determina sozinha as dependências e imagens executadas; registrar digests e versões na homologação. |

Os itens são indícios verificáveis no código, não exploração demonstrada ou diagnóstico de uma VPS. Nenhum comportamento operacional foi alterado nesta tarefa documental.

## Relação com os achados da aplicação

A análise anterior da AMANDA apontou credencial em manifesto, segredos JWT de fallback e autenticação comentada na transcrição. O instalador não elimina automaticamente esses problemas. Uma avaliação integrada deve conferir o código efetivamente baixado, variáveis injetadas e acessibilidade dos serviços. Não é possível concluir que uma falha local esteja presente ou ausente no servidor sem essa comparação.
