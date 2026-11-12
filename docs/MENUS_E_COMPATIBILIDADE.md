# Menus restaurados e compatibilidade Docker

Referência vigente: **7a5b31d**, conforme
[registro de restauração](RESTAURACAO_7a5b31d.md). O assistente histórico é o padrão;
o assistente em 11 etapas continua disponível pelo comando `wizard`.

O menu principal é mostrado antes de baixar a imagem de ferramentas. Não é
necessário Buildx no host: o próprio Docker executa o cliente com Buildx em
container. Falta de permissão no socket é reportada com orientação; o instalador
não muda grupos/permissões do servidor. O menu volta após as operações e tem saída 0.

## Menu principal

| Número | Operação | Implementação atual |
|---|---|---|
| 1 | Instalar | Perguntas históricas, gerador oficial, build/migrations e seed exclusivo de banco novo |
| 2 | Atualizar | Código oficial + build + backup + migrations; preserva contas/configurações |
| 3 | URLs | Frontend, backend, Oficial, transcrição, WuzAPI, todas as URLs e SSL |
| 4 | Status/reiniciar | Todos ou backend/frontend/Oficial/WuzAPI/transcrição; iniciar/parar |
| 5 | Logs | Últimos 200 registros filtrados; acesso privado |
| 6 | Backup | Dois bancos + volumes + configurações + imagens/revisões + SHA-256 |
| 7 | Restaurar | Backup gerenciado, integridade/instância/revisão validadas, backup anterior e confirmação digitada |
| 8 | Ferramentas | Numeração histórica preservada, tabela abaixo |
| 9 | Desinstalar | Preservar dados ou remover volumes com confirmação e propriedade comprovada; mantém arquivos/backups |
| 10 | GHCR/agendamento | Login por stdin; backup/atualização diários em container, hora UTC |
| 11 | API Oficial | Nove opções históricas, detalhadas abaixo |

As extensões anteriores 12–15 permanecem pelos comandos `configure`, `instances`,
`doctor` e `resume`. A seleção de instância também precede as operações
administrativas quando há vários estados gerenciados.

## Ferramentas adicionais

| Número | Ferramenta | Comportamento |
|---|---|---|
| 2 | Push | Gera P-256/VAPID no container; preserva chaves existentes e assinaturas |
| 3 | Instalar WhatsMeow | Inicia WuzAPI do Compose oficial |
| 4 | Rollback | Código, imagens e dados do backup; não inicia código novo sobre esquema antigo |
| 5 | Nova instância | Projeto/volumes próprios em instances/NOME; escolher portas livres |
| 6 | Agendar backup | Executa em container; não usa cron nem banco no host |
| 7 | Agendar backup nativo | Posição histórica mantida; indisponibilidade explícita, sem instalar banco no host |
| 8 | Backup Redis | Incluído no snapshot completo; pausa os gravadores |
| 9 | Restaurar Redis | Somente o volume redis_data do snapshot validado |
| 10 | Importar banco AMANDA | .sql ou pg_dump custom em imports/; backup antes e migrations depois, sem seed |
| 11 | Backup banco | Snapshot completo |
| 12 | Importar API Oficial | Mesmo fluxo, restrito a api_oficial |
| 13 | Listar bancos | Consulta PostgreSQL somente desta instância |
| 14 | Restaurar alta performance | Restauração gerenciada do banco AMANDA |
| 15 | Trocar domínios | Atualiza configuração privada e recria/verifica serviços |
| 16 | Atualizar Baileys | Usa revisão oficial e lockfile, sem npm no host ou instalação avulsa de pacote |
| 17 | Atualizar WhatsMeow | Backup, pull da imagem indicada pelo Compose, recriação e espera de saúde |
| 18 | Otimizar PostgreSQL | Presets de conexões/shared_buffers no container, com backup e verificação |
| 19 | Portainer | Posição histórica mantida; instalação indisponível sem contrato autenticado validado |
| 20 e 21 | Domínio/porta/SSL | Caddy em Docker substitui Nginx/Certbot no host; HTTPS da API Oficial opcional |
| 22 | Backup WhatsMeow | Volume wuzapi_data/SQLite incluído no snapshot; não pressupõe um PostgreSQL inexistente |
| 23 | Restaurar WhatsMeow | Somente wuzapi_data do snapshot validado |
| 30 | Token + FAST | Tokens de clone/conector separados; atualização oficial com backup/migrations |
| 31 | Gestão API Oficial | Abre submenu completo |
| 32 | Atualizar API Oficial | Atualização sincronizada de código e esquema da plataforma |

## API Oficial

1. Instalar/iniciar; 2. atualizar junto da plataforma; 3. status/teste de conexão;
4. reiniciar; 5. parar; 6. logs; 7. sincronizar URL interna com backend;
8. domínios/SSL em Docker (inclui domínio HTTPS próprio da Oficial);
9. remover somente o container, preservando banco e mídia. Iniciar a stack completa
recria esse container, quando a Oficial pertence aos perfis habilitados. Se estiver desabilitada na instalação, a opção 1 oferece habilitação com backup, migrations e confirmação, sem seed.

## Dependências externas e limites observados

Os instaladores de VOZ/HUB e o serviço GoFlow independente foram retirados dos
fluxos por não integrarem o Compose atual. O item Portainer permanece como
indisponível. Permanece a configuração das integrações
VOZ/HUB já implementadas no backend. Registros de componentes anteriormente
gerenciados continuam preservados para compatibilidade de backup/recuperação.

Watchtower direto foi substituído por atualização agendada com build, backup e
migrations. O provedor GHCR só fornece autenticação para imagens; a plataforma
continua construída da fonte oficial. SSL exige DNS e acesso público 80/443.
Quando Caddy está habilitado, o gerenciador verifica também HTTP público e TLS;
na validação local foi testada a geração/parse do Caddyfile, sem emitir certificados.

A suíte local testa os caminhos com Docker/Git/SQL simulados. Não foram executadas
restaurações, imports, exclusões ou atualizações reais sobre os dados locais. Um
ciclo completo em VPS descartável, restauração representativa, envio push no
navegador, contas Meta/VOZ/HUB e certificados públicos continuam pendentes.

## Referência visual

Banner, roxo #8B5CF6, lilás #A78BFA, perguntas em telas separadas e escolha
inicial IP/domínio recuperados diretamente de 7a5b31d. Os printf em
`docker/installer/historical.sh` são usados tanto antes do download quanto no
gerenciador. O extrator registra as adaptações necessárias. Os itens 7 e 19 de
Ferramentas mantêm a posição e informam indisponibilidade.

## Configurações após a reestruturação de 11/11/2026

A numeração 1–9 do submenu foi preservada. Itens adicionais:

| Número | Operação real |
|---|---|
| 10 | Consulta por allowlist pública do ambiente; não revela senhas/tokens nem presume identidade atualizada no banco. |
| 11 / 12 | Alterar URL frontend / backend. |
| 13 | Alterar portas/publicação/HTTPS. |
| 14 / 15 | API Oficial / porta WuzAPI; credenciais de sessões são geridas na plataforma. |
| 16 | Google OAuth por variáveis de fallback consumidas pelo backend. |
| 17 | Chave OpenAI para fallback do IVR, sem confundir com configuração dos demais agentes. |
| 18 | Nodemailer verify no backend, sem envio de e-mail. |
| 19 | Stripe/Asaas/Mercado Pago via Settings da API administrativa; contas/cobranças exigem homologação. |
| 20 | Habilitar Oficial, WuzAPI ou RabbitMQ após a instalação, com confirmação, backup e retomada de migrations. |

O formulário inicial agora distingue nome comercial, título e projeto; IP, local e
HTTPS são modos próprios. Permite rever qualquer etapa e cancelar sem provisionar
a plataforma. Perfis PostgreSQL consideram memória do daemon Docker. SMTP opcional
não bloqueia a instalação principal quando seu teste falha. Detalhes dos contratos,
consumidores e classificação da referência original estão em
[Configuração e compatibilidade](CONFIGURACAO_E_COMPATIBILIDADE.md).
