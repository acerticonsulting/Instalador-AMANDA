# Plano de testes do instalador AMANDA

## 1. Objetivo e regra de execução

Executar a validação depois de cada conjunto de alterações e antes de cada commit. O comando padrão é:

```bash
bash tests/validar_instalador.sh
```

A regra também está em `AGENTS.md`. O hook `tests/hooks/pre-commit` executa a mesma validação sobre uma cópia temporária do **conteúdo do índice Git**, que será registrado no commit. Mudanças ainda não preparadas não mascaram erros da versão preparada.

Para ativar o hook em um clone novo:

```bash
bash tests/ativar_validacao.sh
```

O ativador recusa substituir outro caminho de hooks ou hooks existentes em `.git/hooks` (exceto os exemplos `.sample`). Nesse caso, integrar a chamada aos hooks atuais manualmente. A configuração é local ao clone; não é transferida por `git clone`. Não usar `--no-verify` para contornar uma falha.

Não há monitoramento de cada tecla ou salvamento do editor. A execução depois de alterações é a regra de trabalho; o hook é a barreira automática antes do commit.

## 2. Ambiente e comandos

### Validação local obrigatória

- Git (para a fixture isolada do hook), Bash 4 ou superior e utilitários `awk`, `find`, `grep`, `sort`, `mktemp`, `timeout`, `cmp`, `cp`, `chmod` e `rm`.
- Linux ou Git Bash no Windows. No PowerShell, usar:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' --noprofile --norc tests/validar_instalador.sh
```

- A suíte nova precisa de Docker acessível (Node 22 em container) ou Node 22 em Linux para desenvolvimento. PostgreSQL, root e pacotes npm no host não são necessários. A primeira obtenção da imagem requer rede; a execução dos testes usa --network none. Isso é requisito da suíte de desenvolvimento; o instalador de produção só requer Docker e sh.
- Os testes usam diretórios temporários e comandos simulados. Não executar o instalador completo como teste local.
- Cada suíte tem limite de 120 segundos, seguido de até 5 segundos para encerramento forçado. Timeout reprova a etapa.

### Verificação de uma instalação Docker existente

Executar no servidor que tem acesso ao Docker da instalação:

```bash
bash tests/validar_instalador.sh --plataforma \
  --projeto amanda \
  --frontend-url https://app.exemplo.com/ \
  --backend-url https://api.exemplo.com/healthz \
  --servico api_oficial \
  --servico api_transcricao \
  --servico wuzapi \
  --servico rabbitmq
```

Trocar os exemplos pelos valores reais. O caminho `/healthz` é o endpoint da stack oficial: informar um endpoint de saúde realmente implementado pela aplicação. Acrescentar `--servico api_oficial`, `--servico wuzapi` ou outros nomes **conforme os serviços Compose esperados na instalação**.

O verificador exige `backend`, `frontend`, `postgres` e `redis` e aceita serviços obrigatórios adicionais com `--servico`. Também verifica todos os demais containers encontrados no projeto, exceto tarefas Compose com label `oneoff=True`. Um serviço opcional completamente ausente só será detectado se tiver sido informado como obrigatório.

Os jobs `migrate`, `seed`, `official-db-init` e `official-migrate` são aceitos
somente quando encerrados com código 0, sem OOM e sem reinício automático.
Jobs ainda em execução, pendentes ou falhos reprovam. Serviços contínuos parados
continuam reprovando, inclusive com saída 0. Há regressões para essas distinções.

O modo consulta apenas `docker ps`, `docker inspect` e endpoints HTTP via GET. Não inicia, reinicia ou remove containers, não usa `docker exec`, não faz migrações e não autentica com credenciais administrativas. As requisições podem produzir os logs normais de acesso do servidor.

Cada consulta Docker tem limite de 20 segundos; cada consulta HTTP usa timeout de conexão de 5 segundos e total de 20 segundos. Há um limite externo adicional para encerrar processos travados. A verificação TLS permanece ativa. O resultado exige HTTP 2xx: 3xx, 4xx, 5xx e falha de conexão reprovam. Informar a URL final, pois redirecionamentos não são seguidos. URLs com credenciais, query string ou fragmento são rejeitadas.

## 3. Resultado e critério de aprovação

| Resultado | Significado |
|---|---|
| `RESULTADO LOCAL: APROVADO` | Todos os scripts examinados passaram na sintaxe e todas as suítes locais passaram. |
| `Plataforma em execução: NÃO VERIFICADA` | O modo Docker não foi solicitado. Não afirmar que a VPS está saudável. |
| `RESULTADO DA PLATAFORMA: CHECAGENS DE SAÚDE APROVADAS` | Os containers consultados e os endpoints informados passaram naquele momento. |
| `REPROVADO` ou saída diferente de zero | Corrigir a falha e executar novamente antes do commit. |

Códigos: **0** = verificações solicitadas aprovadas; **1** = falha de teste/saúde; **2** = uso inválido ou dependência necessária ausente. Outros códigos não zero de erro inesperado também bloqueiam o commit.

Um container `running` sem healthcheck gera aviso e não tem sua prontidão interna comprovada. Os endpoints informados verificam a disponibilidade HTTP, não a correção de todas as funcionalidades.

## 4. Inventário e níveis de cobertura

A quinta etapa executa tests/docker_only.test.cjs: 26 regressões do novo gerenciador, com Docker/Git simulados, incluindo instalação nova, colisão de recursos, tokens separados, seed exclusivo, retomada, falhas de build/backup/migration, atualização sem seeds, filtros de log e bootstrap POSIX sem comandos extras no host. Não monta socket Docker no container de testes. Os demais grupos abaixo cobrem scripts históricos agora em legacy/.


O executor encontra todos os arquivos regulares `*.sh` da árvore, incluindo novos arquivos ainda não preparados no Git. Exclui `.git`, `node_modules`, `.venv`, `venv`, `dist`, `build`, `logs`, `tmp` e `instalador-oplanov2`; não segue links simbólicos. No hook, a árvore é a versão preparada para commit. O arquivo `tests/hooks/pre-commit`, sem extensão, tem verificação sintática própria.

| Grupo | Cobertura automática local | Complemento necessário |
|---|---|---|
| Scripts históricos em `legacy/`, incluindo o antigo instalador e `tools/mf_operacoes_seguras.sh` | Sintaxe, funções críticas extraídas, configuração, seleção de instâncias, retornos de erro e contratos. | Instalação, atualização e recuperação completas em VM. |
| `instalador_apioficial.sh`, `atualizar_apioficial.sh` | Sintaxe e interrupção dos pontos de entrada quando instalação/atualização falha. | API real, build da imagem, migrações e integração com backend. |
| Atualizadores remoto, FAST, sistema e PRO | Sintaxe e busca por operações proibidas definidas no contrato. | Atualização real de cada modalidade suportada. |
| WhatsMeow, HUB, VOZ, RabbitMQ, alta performance e instâncias | Sintaxe e contratos estáticos aplicáveis. | Smoke tests específicos e coexistência entre instâncias. |
| Backup, restauração, domínios, SSL, push e transcrição em `tools/` | Sintaxe; restauração SQL simulada e lock do APT nos caminhos selecionados. | Restauração de dados representativos e testes funcionais. |
| `.env.exemplo` | Formato das atribuições e ausência de chaves duplicadas, sem imprimir valores. | Compatibilidade com os consumidores reais. |
| Python/SQL/YAML/Dockerfile gerados dentro dos scripts | Sintaxe do Shell que os contém; contrato pontual do argumento URL da API. | Gerar em ambiente descartável e validar com os parsers reais. Não há validação geral destes idiomas na suíte local. |
| `tools/stack_altaPerformance`, HTML e catálogo de versões | Incluídos no inventário documental; não possuem parser/validação semântica local nesta suíte. | Compose config, navegador e resolução de versões em homologação. |
| Código e imagens de repositórios externos | Fora da árvore e da suíte local. | Build, testes da aplicação, versões/digests e homologação. |

**Cobertura de sintaxe em todos os scripts não significa cobertura de todos os ramos.** Nenhum resultado local certifica ausência de bugs ou vulnerabilidades na plataforma. Os valores da chave Git e os endereços dos repositórios não são modificados pelos testes.

## 5. Casos automatizados

Credenciais iniciais: `regressao_instalador.sh` valida o padrão AMANDA,
personalização com caracteres literais, exportação para o seed, confirmação,
rejeição de e-mail inválido/EOF/senha vazia e ausência da senha personalizada
na saída. Também impede a volta do UPDATE forçado do e-mail do usuário 1.
Criação, hash e preservação de conta existente são verificados na suíte da plataforma.

O arquivo `regressao_instalador.sh` também verifica a restrição do repositório:
URL autorizada com/sem `.git` e barra final; rejeição de vazio/EOF, forks, domínio
semelhante, HTTP/SSH, credenciais, query e subcaminhos; normalização para clone e
bloqueio de download quando uma configuração antiga contém outro repositório.

| ID | Caso | Resultado esperado | Implementação |
|---|---|---|---|
| EST-01 | Sintaxe de todos os scripts e do hook | Qualquer erro bloqueia as regressões/commit. | `validar_instalador.sh`, `verificar_contratos.sh` |
| EST-02 | Reintrodução de `--accept-data-loss`, encerramento do APT ou remoção de lock dpkg | Reprovar e indicar o arquivo, sem imprimir segredos. | `verificar_contratos.sh` |
| EST-03 | Arquivo obrigatório ausente/vazio ou exemplo env inválido/duplicado | Reprovar. | `verificar_contratos.sh` |
| ISO-01 | Nome válido e nomes com traversal/metacaracteres | Aceitar slug válido e rejeitar os inválidos. | `regressao_instalador.sh` |
| ISO-02 | Container ausente, ambíguo ou de outra empresa | Rejeitar; não remover o recurso intruso. | `regressao_instalador.sh` |
| ISO-03 | Desinstalação com preservação | Nenhum volume removido. | `regressao_instalador.sh` |
| ISO-04 | Falha na remoção de container/volume | Retornar erro. | `regressao_instalador.sh` |
| CFG-01 | Escrita de chave nova/existente/duplicada com caracteres especiais | Valor literal, chave única, outros campos preservados. | `regressao_instalador.sh` |
| CFG-02 | Configuração com aspas, substituição de comandos e operadores | Não executar comandos; manter os valores. | `regressao_instalador.sh` |
| CFG-03 | Arquivo inválido ou valor multilinha | Não aplicar estado parcial nem substituir arquivo válido. | `regressao_instalador.sh` |
| CFG-04 | Campos `PATH` e `BASH_ENV` em configuração | Não alterar o ambiente Shell. | `regressao_instalador.sh` |
| CFG-05 | Gravação após mudança do diretório corrente | Checkpoint permanece na raiz configurada. | `regressao_instalador.sh` |
| MIG-01 | Restauração SQL retorna erro | Exigir transação/`ON_ERROR_STOP` e retornar falha. | `regressao_instalador.sh` |
| VER-01 | Branch selecionada e branch inexistente | Usar a solicitada e interromper quando ausente. | `regressao_instalador.sh` |
| API-01 | Falha na instalação/atualização da API | Não prosseguir com reinício/integração. | `regressao_instalador.sh` |
| SO-01 | APT ocupado nos dois provisionadores Docker | Não matar processos, não remover locks, retornar falha. | `regressao_instalador.sh` |
| SAU-01 | Nenhum container crítico ou healthcheck negativo | Rejeitar conclusão. | `regressao_instalador.sh` |
| SAU-02 | Serviço ausente, parado, unhealthy/starting, OOM ou identidade divergente | Verificador de plataforma retorna falha. | `regressao_plataforma.sh` |
| SAU-03 | Docker indisponível, inspect falha, HTTP 3xx/4xx/5xx, TLS ou timeout | Retornar falha. | `regressao_plataforma.sh` |
| SAU-04 | Containers saudáveis, tarefa oneoff e container sem healthcheck | Aceitar saudáveis; ignorar oneoff; avisar sobre ausência de healthcheck. | `regressao_plataforma.sh` |
| SAU-05 | Serviço adicional obrigatório ausente ou argumentos inválidos | Rejeitar; entrada inválida não chega ao Docker/rede. | `regressao_plataforma.sh` |
| EXE-01 | Script inválido ou suíte com erro | Executor retorna código não zero. | `regressao_executor.sh` |
| EXE-02 | Chamada fora da raiz e caminho com espaços | Executar corretamente e distinguir aprovação local de saúde real. | `regressao_executor.sh` |

Os testes de plataforma desta tabela usam **Docker e curl falsos**. O modo `--plataforma` é a consulta real e precisa de um alvo explícito.

## 6. Matriz de homologação antes de liberar uma versão

Executar somente em VM descartável ou ambiente de homologação com backup validado. Esses cenários não são disparados pelo hook.

| ID | Cenário | Evidência necessária para aprovar |
|---|---|---|
| HOM-01 | Instalação nova em cada distribuição/arquitetura oficialmente suportada | Versão correta, serviços esperados, portas, login e fluxo básico funcionando. |
| HOM-02 | Segunda instância com nome semelhante, como `amanda_filial` | Nenhum recurso, URL, porta, volume ou banco da primeira instância alterado. |
| HOM-03 | Reexecução e interrupção em cada etapa persistente | Dados e chaves preservados; retomada documentada; ausência de sucesso falso. |
| HOM-04 | Atualização da versão anterior com dados representativos | Schema compatível, dados preservados e versão efetivamente atualizada. |
| HOM-05 | Backup e restauração em instância nova | Comparação de registros, arquivos, chaves e funcionalidades; tempo de recuperação registrado. |
| HOM-06 | Indisponibilidade de banco, registry, Git, APT e certificados | Erro claro, código não zero e nenhuma instalação marcada como concluída indevidamente. |
| HOM-07 | Disco cheio, memória insuficiente, permissão incorreta e conflito de portas | Falha controlada e procedimento de recuperação comprovado. |
| HOM-08 | Nginx inválido, TLS e mudança de domínio | Publicação válida, URLs corretas e recuperação da configuração anterior. |
| HOM-09 | Desinstalação com e sem preservação | Escopo restrito ao alvo; preservação recuperável; recursos legados remanescentes identificados. |
| HOM-10 | API Oficial, WhatsMeow, push, transcrição, HUB/VOZ e RabbitMQ quando habilitados | Smoke test de cada integração com contas e dados próprios de homologação. |
| HOM-11 | Funcionalidade da plataforma | Login, criação de atendimento, mensagem de teste, recebimento, arquivo e processamento de fila. |
| HOM-12 | Reinício do servidor e recuperação/rollback | Serviços recuperados; compatibilidade entre release, configuração e banco demonstrada. |

## 7. Manutenção e registro

1. Alterar o código e acrescentar regressão para o comportamento afetado.
2. Executar `bash tests/validar_instalador.sh`; corrigir todas as falhas.
3. Para mudanças que dependem de Docker/aplicação, executar também as verificações de saúde e os cenários de homologação pertinentes.
4. Registrar no commit/descrição os testes executados, resultado e os testes que não puderam ser realizados. Não incluir tokens, senhas, dumps ou logs completos de produção.
5. Preparar os arquivos e criar o commit. O hook repete a validação da versão preparada para confirmar que é a mesma versão aprovada.

A saída fica no terminal, e arquivos temporários são removidos ao terminar. Se for necessário guardar evidência, salvar a saída em um diretório local de logs ignorado pelo Git. O executor não gera credenciais, não instala pacotes e não altera a configuração de serviços.

### Matriz observada em 07/11/2026

| Camada | Resultado observado | Limite |
|---|---|---|
| Sintaxe Shell e regressões históricas | 47 scripts / cinco grupos aprovados | Comandos históricos simulados |
| Gerenciador novo | 26 testes aprovados, Node 22 em Docker sem rede | Docker/Git/SQL simulados; sem instalação real |
| Imagem do gerenciador | Build real aprovado | Arquitetura x86_64 local |
| Ferramentas embarcadas | Compose 2.33.0 e Buildx 0.20.1 acessam daemon Linux 29.9.2 | Socket local do Docker Desktop |
| Plataforma existente | Oito serviços obrigatórios saudáveis; três jobs saída 0; frontend e /healthz HTTP 200 | Somente leitura; não valida instalação nova |
| Container adicional histórico | Transcrição rodando sem healthcheck, aviso do verificador | Preservado; não confundir com serviço oficial saudável |
| VPS limpa / HTTPS / outras arquiteturas / contas externas | Pendente de homologação | Não certificado pela suíte local |

O hook de commit repete os testes sobre a árvore preparada, incluindo o novo grupo.
