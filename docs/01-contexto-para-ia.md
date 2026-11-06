# Contexto para a próxima IA

A AMANDA é uma plataforma de atendimento com contatos, tickets, filas, campanhas, automações e múltiplas empresas. O instalador coordena a infraestrutura, a obtenção do código, os arquivos de ambiente, construções, migrações e publicação. O código conserva nomes Multiflow, Mult100 e whitelabel. Não renomear recursos existentes por mera padronização textual.

## Antes de alterar qualquer coisa

Leia [AGENTS.md](../AGENTS.md), [plano de testes](../tests/PLANO_DE_TESTES.md) e o documento desta pasta correspondente ao problema. Confira o estado Git, o ramo em uso e alterações do usuário. Para localizar funções, use a referência por arquivo e linha; as linhas podem mudar e o nome da função é a âncora principal.

O AGENTS exige validação após alterações e commit do conjunto concluído. Exige também preservar a chave Git e endereços dos repositórios, salvo nova instrução explícita. Não copie esses valores para documentação, respostas ou logs. Encontrar um segredo não autoriza removê-lo ou substituir o acesso durante outra tarefa.

## Identidades diferentes

| Conceito | Significado |
| --- | --- |
| Repositório do instalador | Scripts de provisionamento e ferramentas deste diretório |
| Repositório da plataforma | Código baixado para a instalação; repositório oficial AMANDA indicado no README |
| Instância | Implantação identificada por `empresa`, diretório, projeto Compose e configuração próprios |
| Empresa da aplicação | Registro de negócio e `companyId` dentro do banco; não equivale automaticamente a uma instância Docker |
| Branch da plataforma | Canal de código da aplicação; não é necessariamente a branch do instalador |
| Volume | Estado persistente independente do checkout Git e do ciclo de vida de um container |

## Regras práticas

- Não execute nem dê `source` no instalador completo para descobrir funções. O topo já faz consultas ao sistema e à rede e exige root; o final abre menus ou processa argumentos.
- Prefira leitura e testes de funções extraídas, como a suíte existente faz.
- Não assuma que `/home/deploy/amanda` é o único alvo ou que o Compose fica na raiz.
- Confirme labels `com.docker.compose.project` e `com.docker.compose.service`. Prefixos de nome e o primeiro resultado de `docker ps` são insuficientes para operações de dados.
- Não use `docker compose down -v`, exclusões globais, reset de schema ou edição de histórico de migrações como solução genérica.
- Não confunda teste local aprovado com VPS saudável. O modo de leitura `--plataforma` requer alvo real explícito.
- Não trate um retorno ignorado com `|| true` como confirmação de sucesso.

## O que perguntar em manutenção de uma VPS

Se o alvo não estiver no contexto, obtenha instância, ambiente, sintoma e operação desejada antes de executar comandos que mudem o servidor. Registre branch e commit da aplicação, projeto e diretório Compose, serviços esperados, portas e local de backup. Não peça envio de senhas ou dumps completos para o chat.

## Entrega de mudanças

Descreva problema, efeito final, arquivos alterados, testes executados e limites. Atualize os catálogos quando mover ou criar funções relevantes. Preserve mudanças anteriores do usuário e prepare para commit apenas o conjunto da tarefa. Não publique nem envie mensagens a terceiros sem autorização.
