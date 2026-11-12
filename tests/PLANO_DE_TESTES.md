# Plano de testes do instalador AMANDA

## Bloqueio de operações

Oito regressões novas usam flock real dentro do container de testes: primeira
aquisição, reentrância, falha/liberação, concorrência, proprietário Docker
ativo/parado/ausente/daemon indisponível, identidade inválida, substituição do
arquivo e SIGINT/SIGTERM com recuperação posterior. Os testes anteriores mantêm
build/migrations/seed interrompidos, retomada, administração e volumes preservados.
O teste da imagem verifica flock embarcado. Nenhuma operação ocorre na VPS.
Perfil PostgreSQL continua coletado antes de lock/prepare, conforme regressões
históricas; não é uma operação administrativa. Um processo morto por sinal deixa
metadados recuperáveis: não se tenta liberar enquanto filhos ainda podem operar.

## Digitação de credenciais e senhas curtas

`ask` usa leitura visível para todas as entradas, inclusive SMTP/tokens; valores
secretos continuam fora dos padrões, resumos e logs. Regressões cobrem eco em
pseudoterminal após o prompt, senhas de 3/8/12+ caracteres em local/IP/HTTPS nos
dois assistentes, banco/MASTER literais, controle/vazio e confirmação já existente.
O seed oficial aceita senha curta; a regra de cadastro de outros usuários no
backend não participa da inicialização e não foi modificada. Limites máximos e
requisitos criptográficos dos tokens permanecem. Alteração pontual, sem runtime real.

## Restauração 7a5b31d — 12/11/2026

O padrão interativo volta à referência `7a5b31d`; o assistente adicional permanece
em `wizard`. São 90 regressões Node (77 Docker-only e 13 históricas), além dos
outros quatro grupos locais. Os comandos operacionais continuam simulados.

| ID | Cobertura acrescentada |
|---|---|
| HIS-01 | Banner/menu principal comparados a fixture extraída do hash histórico; única adaptação do rótulo Watchtower. |
| HIS-02 | Seções/ordem/números de Ferramentas e API; posições nativas inseguras mantidas como indisponíveis. |
| HIS-03 | Ordem real das perguntas padrão, e-mail, empresa, banco/MASTER, título, suporte, Facebook e repositório. |
| HIS-04 | Entradas secretas ocultas e resumo sem credenciais, com rótulos históricos. |
| HIS-05 | URLs oficiais equivalentes, IPv6, portas próprias e backend HTTPS antes de frontend. |
| HIS-06 | EOF/cancelamento/repositório não autorizado/confirmação divergente antes de criar recursos. |
| HIS-07 | Canal/confirmacão de atualização; canais sem contrato não executam operações. |
| HIS-08 | Caminhos recuperados delegam a Docker; receita indisponível retorna falha sem anunciar sucesso. |
| HIS-09 | Portas HTTPS próprias preservadas em configuração/atualização, sem seed. |
| HIS-10 | Seleção/cancelamento de instância mantém estado das demais intacto; perfil PostgreSQL limitado. |
| HIS-11 | TTY colorido mantém tabela de despacho completa e destaca números com lilás histórico. |

`bash tests/integracao_compose.sh ../AMANDA` constrói a imagem do gerenciador e
executa seis testes com fonte somente para leitura, container sem rede e sem
socket do daemon: os quatro contratos anteriores, portas HTTPS próprias e
presença da apresentação histórica na imagem. Não inicia a plataforma nem executa
migrations/seeds. Ver [registro e limites](../docs/RESTAURACAO_7a5b31d.md).

## Assistente completo — 11/11/2026

O grupo `docker_only.test.cjs` passa a 75 testes. O executor examina agora
48 scripts Shell, incluindo a integração opt-in (somente sintaxe nessa etapa).
Continuam sendo cinco grupos locais, com comandos de plataforma simulados.

| ID | Cenário | Cobertura |
|---|---|---|
| ASS-01 | Padrão localhost e apresentação | 11 etapas, padrões, diretório no resumo, NO_COLOR e banner. |
| ASS-02 | IP personalizado | IPv4/IPv6, publicação e portas de frontend/backend diferentes. |
| ASS-03 | Domínios HTTPS | URLs distintas, domínio da Oficial, conta personalizada e segredos fora do resumo. |
| ASS-04 | Retorno, revisão, cancelamento | `:voltar`, edição por etapa, respostas mantidas e cancelamento antes de recursos. |
| ASS-05 | Entrada inválida | Modo, domínio, confirmação da senha, URL com credenciais/caminho, portas e allowlists. |
| ASS-06 | Banco e segredos | Perfil inválido/grande antes de clone; senhas com `$VAR`, aspas e caracteres reservados; chaves geradas e pares VAPID. |
| ASS-07 | SMTP com/sem configuração | MAIL_SECURE, senha oculta, nome remetente, verificação sem envio e falha opcional sem invalidar o core. |
| ASS-08 | Serviços opcionais | Base mínima sem API Oficial/WuzAPI/RabbitMQ; build/migrations/backup/restore/update respeitam seleção. |
| ASS-09 | Habilitação posterior | Backup antes de migration, sem seed; falha mantém estado retomável, sem alegar rollback de schema. |
| ASS-10 | Configuração posterior | SMTP recria só backend; suporte/URLs preservam contratos, rollback de arquivos e perfis existentes. |
| ASS-11 | Portas ocupadas | Reprovação antes de migration/seed; checagem ignora bindings inalterados e usa helper Docker. |
| ASS-12 | Diagnóstico HTTPS | Erros DNS, TLS, conexão e HTTP distinguidos; nenhum segredo no diagnóstico. |
| ASS-13 | Identidade | Nome comercial só na empresa inicial; chamada parametrizada e estado novo obrigatórios. |
| ASS-14 | Consulta segura | Allowlist pública e formulário de identidade; nada de dump completo do ambiente. |
| ASS-15 | Dados preservados | Testes existentes de build/migration/seed interrompidos, configuração em update, backup/hashes e propriedade de exclusões. |

### Integração real do parser e build do gerenciador

Disponibilize uma cópia da fonte oficial da AMANDA para **leitura**, sem executar
seu instalador. Na raiz deste repositório:

```sh
bash tests/integracao_compose.sh /caminho/da/fonte/AMANDA
```

Essa etapa constrói `amanda-installer:wizard-validation` e executa quatro testes
em container `--network none`, sem montar socket Docker. Somente o CLI Compose
embarcado analisa os arquivos; não há daemon acessível de dentro do container.
A fonte é montada para leitura, e apenas Compose, `.env.example`, gerador e
arquivos do Caddy são copiados para temporários. `.env` e segredos reais não são
copiados. Os temporários e containers são descartados; a imagem permanece como
cache/tag de desenvolvimento. A construção pode obter imagens base pela rede.

Os testes comprovam resolução de URLs/portas/CORS, endpoints internos, precedência
de env_file, SMTP/Google, senha literal e URI codificada, perfis mínimos, nomes
explícitos, domínio da Oficial no Caddyfile e geração distinta/privada de chaves.
A representação escapada `$$` emitida por `compose config` é normalizada somente
na comparação, seguindo o contrato testado pela própria plataforma.

### Classificação dos resultados desta entrega

| Camada | Resultado | Limite |
|---|---|---|
| Estática | Sintaxe Shell e contratos aprovados | Scanner conservador não é parser completo nem prova contra ofuscação. |
| Unitária/regressão | 75 testes Docker-only aprovados, além dos grupos históricos | Docker/Git/SQL simulados; fixtures fictícias. |
| Integração | Quatro testes com Compose/gerador/Caddyfile reais aprovados | Sem emitir certificado ou iniciar plataforma. |
| Build Docker | Imagem do gerenciador construída | Backend/frontend e microserviços não foram alterados nem reconstruídos. |
| Runtime da plataforma | Não executado | Não foi fornecida VPS/alvo de instalação. |
| Contas e recuperação reais | Pendentes | Meta, WuzAPI, SMTP do provedor, Google, push, pagamentos, login real e restauração em Linux descartável. |

HOM-01/02/04/05/10/11 continuam necessários para aceitar homologação ponta a ponta.
Uma opção de menu, parser aprovado ou build do gerenciador não substitui essas
evidências. Não executar instalações, migrations ou restaurações reais na suíte local.

## Docker e nomenclatura por empresa — 2026-11-11

A suíte Docker-only tem 59 casos. As novas regressões cobrem:

| ID | Contrato | Evidência local |
|---|---|---|
| DOC-01 | Sem dependências nativas | Scanner conservador dos `.sh` ativos e bootstrap com executáveis proibidos simulados; Dockerfiles são excluídos porque seus comandos executam na imagem. |
| DOC-02 | Receitas históricas inativas | Verifica barreira de encerramento antes do código histórico em cada receita arquivada. |
| DOC-03 | Empresa e nomes | Normalização, caracteres inválidos, `container_name` de serviços/jobs/Caddy e renomeação do gerenciador simulada. |
| DOC-04 | Identidade efetiva | Status rejeita divergência em `docker compose ps` e `docker ps`; consulta de plataforma confere `.Name` via inspect com `--nomes-padronizados`. |
| DOC-05 | Tarefas temporárias | UUIDs exclusivos com prefixo da empresa e `--rm` em migrations, seed, backup e manutenção. |
| DOC-06 | Coexistência | Duas configurações com nomes, redes, volumes e quatro portas diferentes; colisões de nomes e redes bloqueiam seed. |
| DOC-07 | Compatibilidade | Estados anteriores continuam sem o override; atualização conserva nomes/recursos existentes e recuperação regenera override para a revisão restaurada. |
| DOC-08 | Backup/recuperação | Regressões existentes de hashes, propriedade, importação, rollback e falhas continuam passando com containers auxiliares nomeados. |

O scanner é um contrato conservador de comandos conhecidos, não um parser Shell
completo nem uma prova contra ofuscação. Examina os pontos de entrada de produção,
exclui testes e receitas históricas bloqueadas e não examina `RUN` em Dockerfiles
como instalação no host. A barreira das receitas históricas tem regressão própria.

Para instalações novas, acrescente `--nomes-padronizados` à consulta
`--plataforma`; a flag confere nomes reais via Docker inspect, inclusive o sufixo
`caddy` para o serviço `edge` e UUID de one-offs. Estados históricos devem ser
consultados sem essa flag até uma migração explicitamente planejada.

Resultado local não certifica instalação nova, ferramentas dos repositórios
externos, build completo, duas plataformas simultâneas nem recuperação real.
HOM-01, HOM-02, HOM-04 e HOM-05 continuam obrigatórios em Linux descartável sem
dependências nativas da aplicação; registrar `docker ps`, `docker compose ps`,
portas, redes/volumes, processos no host e integridade após recuperação.
Não executar instalação, migration ou restauração reais na suíte local.

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

### Regressão de interface e operações dos menus

A versão atual restaura o menu principal histórico, Ferramentas e API Oficial.
O grupo Node tem agora 42 testes: menus repetidos e numeração, exibição antes de
Docker, saída sem recursos, configuração avançada e falhas, locks reentrantes,
push persistente, backup/hashes, importação SQL, restauração/rollback antes do
startup, confirmação/propriedade de exclusões, agendamento em containers, credenciais
GHCR via stdin e rejeição de componente sem contrato Docker. Docker/Git/SQL são
simulados; os testes não modificam a instalação existente.

Na plataforma, tests/docker.test.cjs cobre também suporte em runtime, URI codificada
com senha contendo dólar/caracteres reservados, parâmetros PostgreSQL, URLs internas
e geração segura do Caddyfile com domínio opcional da API Oficial. Esses testes não
emitem certificados. Fonte VOZ/HUB/GoFlow, integrações e recuperação completa em VPS
continuam pendentes conforme docs/MENUS_E_COMPATIBILIDADE.md.

## Regressão visual e perguntas — 2026-11-11

Referência histórica 3e6b5cf (16/10/2026). A suíte Docker-only passa a 48 testes.
Verifica banner/paleta, NO_COLOR e TERM=dumb, paridade bootstrap/menus antes de
download, ordem das perguntas, domínios sem protocolo, padrões administrativos
e personalização, confirmação/cancelamento, portas e status após o banner.
As opções ausentes da plataforma deixam de integrar a tabela de menus.
A suíte continua sem realizar operações reais na instalação existente.
