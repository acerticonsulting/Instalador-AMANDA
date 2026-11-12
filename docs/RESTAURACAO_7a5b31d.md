# Restauração do instalador — continuidade técnica

Referência obrigatória: `7a5b31da3ce48fb50fe451fbcbe840f725fa8838`.
Branch: `restauracao-instalador-7a5b31d`, criada nessa revisão. A incorporação da
branch anterior preserva todos os commits posteriores; main não foi modificada.
Nenhum push ou deploy faz parte desta entrega.

## Comparação e decisões

Na referência há um instalador principal de aproximadamente 12 mil
linhas e scripts administrativos na raiz/tools. A main local, em 3e6b5cf, ainda
mantinha essa organização. A branch de trabalho anterior, f6dad5c, havia movido
as receitas para legacy/, bloqueado execução nativa e colocado um gerenciador
novo no fluxo principal. As telas usavam outra referência e o assistente padrão
tinha 11 etapas; menu principal e seções de Ferramentas divergiam de 7a5b31d.

Foram recuperados os blocos originais de banner, menus principal/Ferramentas/API,
status, atualização/canais, perguntas, resumo e otimização. O extrator lê o hash
completo e copia apenas apresentação, sem executar o instalador histórico.
Uma fixture independente guarda os blocos originais usados na regressão visual.
O fluxo padrão segue novamente a ordem histórica; os 34 caminhos de scripts
Shell auxiliares foram recuperados. Os corpos nativos permanecem arquivados e
bloqueados em legacy/, porque reativá-los violaria Docker-only e segurança de dados.

As operações seguras existentes foram reaproveitadas: configuração, autenticação
via askpass/segredo BuildKit, clone main, Compose oficial, migrations Sequelize e
Prisma, seed apenas em banco novo, nomes por empresa, backup com hashes,
recuperação, volumes/mídias, instâncias e agendamento em container. Não se
reativaram PM2, instalação APT de aplicações, importação de estado Shell nem
comandos antigos de perda de dados. Atualização mantém backup antes das
migrations e não redefine contas, segredos ou nomes de volumes.

## Contrato da plataforma examinado

Fonte oficial local: AMANDA em `4c579aa`, branch main. Foram consultados README,
AGENTS, docs/DOCKER, docker-compose.yml, configure.cjs, Dockerfiles e exemplos
de ambiente. A plataforma não foi modificada. Esta evidência refere-se à cópia
local; não afirma sincronização com um HEAD remoto posterior.

| Componente | Decisão e evidência |
|---|---|
| PostgreSQL/Redis/transcrição | Manter serviços oficiais e portas internas; não publicar banco/cache no host. |
| Oficial/WuzAPI/RabbitMQ | Manter perfis, imagens, migrations e contratos oficiais; WuzAPI usa volume/SQLite, não PostgreSQL próprio presumido. |
| GoFlow independente | Remover dos fluxos/portas/build/saúde. Ausente no Compose; `USE_GO_CAMPAIGN_DISPATCHER=false` é contrato do backend, preservado. |
| PgBouncer | Remover porta/obrigatoriedade operacional; ausente no Compose. |
| HUB/VOZ | Sem instalação automática de repositórios externos. Manter integração funcional: Settings hubLocalUrl/hubLocalAdminKey e amandaVozUrl, consumidas pelo backend. |
| Portainer | Manter posição 19, informar indisponibilidade; não abrir administração Docker sem contrato autenticado. |
| Watchtower | Manter posição 10 e usar agendamento com backup/migrations em container. |
| Nginx/Traefik nativos | Substituir por Caddy em container; manter números de ferramentas SSL/domínios. |
| Baileys PRO/Heineken | Atualização segue fonte/lockfile oficial, sem troca avulsa de pacote. Receita auxiliar antiga fica indisponível. |
| Helpers nativos de build/reparo | Não executar nem anunciar reparo concluído; erro explícito orienta os fluxos oficiais. |

## Arquivos e adaptações

- `docker/installer/historical.sh`, `historical.cjs` e
  `tools/extrair_interface_historica.cjs`: apresentação original e coleta validada.
- `instalador_single.sh`, `cli.cjs`, `menus.cjs`, `ui.cjs`, Dockerfile:
  entrada/menu históricos e scripts compatíveis; operações continuam nos containers.
- `manager.cjs`, `options.cjs`, `operations.cjs`: portas frontend/backend HTTPS
  personalizáveis, validadas e preservadas em reconfiguração/atualização.
- Oito scripts administrativos da raiz e 26 em tools/: adaptadores pequenos;
  receitas incompatíveis retornam erro antes de qualquer alteração operacional.
- `tests/historical.test.cjs`, fixture `7a5b31d-menus.json`, testes Docker/Compose
  e executor: fidelidade, perguntas, privacidade, cancelamento, canais, isolamento
  e persistência das portas; testes anteriores de dados permanecem ativos.
- README, matriz e documento de menus: uso padrão histórico e limites explícitos.

Senhas compartilhadas padrão foram substituídas por geração segura/entrada oculta.
O resumo mantém rótulos históricos, com `[oculta]` nos segredos; a conta
administrativa usa senha própria confirmada. O token de clone não entra na URL.
Canal main é o único validado; demais posições não executam atualizações.
Configurações complementares continuam acessíveis por `configure`, instâncias
por `instances`, diagnóstico por `doctor` e retomada por `resume`. O assistente
adicional de 11 etapas foi preservado sob `wizard`, sem substituir o padrão histórico.
Diretórios históricos de instância com hífen continuam selecionáveis, sem renomear
projeto, containers ou volumes; links simbólicos não entram na seleção automática.

## Validação e limites

90 regressões Docker-only/históricas, além dos grupos Shell, contratos, saúde
simulada e executor. A integração constrói a imagem do gerenciador e executa
seis testes do parser Compose, gerador e Caddy com a fonte oficial em leitura,
sem socket do Docker e sem rede no container de testes.

A suíte local não instala plataformas, não executa migrations reais, não restaura
dados reais e não comprova a saúde de uma VPS. Não foi fornecido alvo de instalação
para `--plataforma`. Permanecem para homologação Linux descartável os cenários
HOM-01–12 aplicáveis: instalação completa, atualização com dados, recuperação,
duas empresas, SSL público e contas externas. Build do gerenciador e parse
aprovados não equivalem a build/runtime de todos os serviços da AMANDA.
