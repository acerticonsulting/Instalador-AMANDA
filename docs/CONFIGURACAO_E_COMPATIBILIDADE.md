# Configuração e compatibilidade do assistente Docker

Análise realizada em 11/11/2026 sobre o código dos três projetos, sem executar as
receitas históricas ou alterar uma instalação existente. O instalador local partiu
do commit `cc734db`. O remote local/chave Git foram preservados; o endereço oficial
de obtenção informado para esta tarefa é `acerticonsulting/Instalador-AMANDA`.

## Fontes verificadas

| Projeto | Fonte consultada | Identificação |
|---|---|---|
| AMANDA | [Compose](https://github.com/acerticonsulting/AMANDA/blob/main/docker-compose.yml), README, AGENTS e docs/DOCKER.md | Blob Compose `575d5332fc44590a211292a091c788b6e92ee8d3`; cópia local usada para integração somente de leitura. |
| Instalador atual | [cli.cjs](https://github.com/acerticonsulting/Instalador-AMANDA/blob/main/docker/installer/cli.cjs), README e código local completo do gerenciador/menus/operações/opções/UI/addons/testes | Blob remoto CLI `ffaac84ba87d81b992f71d0db5481754c9131dd8`; implementação entregue neste repositório. |
| Scripts White Label | [instalador_single.sh](https://github.com/scriptswhitelabel/instalador_single_oficial/blob/main/instalador_single.sh), .env.exemplo, instalador_apioficial.sh, instalar_nginx_ssl.sh e atualizador_remoto.sh | Blob principal `db786a0afd7550c58ccc495bb73fd448b3f57633`; perguntas em torno das linhas 3267–3520. |

Também foram lidos os consumidores reais da plataforma: `docker/configure.cjs`,
`docker/caddy-entry.sh`, `backend/src/helpers/SendMail.ts`,
`signupVerificationSettings.ts`, `GoogleAuthConfig.ts`,
`paymentGatewaySettings.ts`, `libs/wuzapi.ts`, controlador/serviços de Settings,
autenticação, seeds e `CallService/InterpretVoiceIvrSpeechService.ts`.
Os arquivos remotos são fontes de análise, não scripts executados pelo instalador.

## Comparação com o original

As classificações abaixo descrevem disponibilidade no código e cobertura local.
“Implementada” não significa homologada em VPS/contas externas.

| Funcionalidade | Original | AMANDA antes | Situação entregue / classificação |
|---|---|---|---|
| URL frontend/backend | Questões DNS e portas; Nginx/Traefik | IP/local agrupados, sem revisão de etapa | Implementada: três modos, duas URLs, validação e aplicação em runtime/CORS/proxy. |
| IP/local | Opções e configuração nativa | Modo único com host informado | Implementada: IPv4/IPv6 para rede e modo local dedicado. |
| Nome da empresa | `empresa` também define usuário/banco | Projeto técnico usado como empresa | Implementada: nome comercial separado; personalização delimitada da empresa inicial; IDs internos preservados. |
| Nome do sistema/suporte | `nome_titulo`/`numero_suporte` | Já havia title via API e suporte em runtime | Mantida e testada; consulta distingue ambiente e identidade gerenciada no painel. |
| Administrador | `email_deploy` e senha compartilhada de deploy | Seed com conta padrão ou personalizada | Implementada: confirmação oculta, recomendação de senha forte e seed exclusivamente novo. |
| PostgreSQL | Nativo ou alta performance; senha de deploy compartilhada | Senha própria, presets apenas no menu | Implementada: senha própria/aleatória, quatro perfis e orçamento de memória Docker antes de aplicar. |
| Segredos | OpenSSL e variáveis históricas | Gerador criptográfico oficial | Mantido: chaves distintas; tokens oficiais/WuzAPI personalizáveis só na criação. |
| SMTP | Variáveis MAIL_* no ambiente | Cinco campos; sem TLS explícito ou teste | Implementada: MAIL_SECURE, remetente, teste sem envio e preservação de segredos. |
| API Oficial | PM2, cliente PostgreSQL/SSL nativos | Sempre instalada; menu próprio | Implementada: seleção opcional e habilitação posterior com backup/migrations. Contas Meta permanecem no painel. |
| WuzAPI | Ferramenta separada | Sempre habilitada | Implementada: escolha/porta/token, habilitação posterior e preservação das chaves de sessões. |
| RabbitMQ | Instalador adicional | Sempre habilitado | Implementada: opcional e condicionado ao consumidor API Oficial. |
| Transcrição/FFmpeg | Dependências/porta ajustadas no host | Serviço Docker obrigatório | Mantida: base oficial com autenticação compartilhada; comunicação interna não vira URL pública. |
| Facebook/Meta | APP_ID/SECRET perguntados individualmente | Campos iniciais e menu | Mantida, agora agrupada como opcional. Conectar conta/webhook é etapa externa. |
| Google | Dependente da plataforma | Ausente no formulário/menu | Implementada: fallback real GOOGLE_CLIENT_ID/SECRET; callback deriva da URL backend. Settings do painel podem prevalecer. |
| IA | Variáveis/recursos externos heterogêneos | Não exposta no menu | Implementada somente para OPENAI_API_KEY no fallback de IVR existente. Demais agentes são configurados pela interface. |
| Pagamentos | Variáveis Stripe/MP/Asaas/Efi do exemplo | Não agrupado no menu | Implementada configuração Settings para Stripe/Asaas/Mercado Pago pela API administrativa; Efi/certificados permanecem no painel. Sem cobrança automática de teste. |
| Push | Ferramenta auxiliar | Geração VAPID pelo menu | Implementada também na instalação; chaves preservadas posteriormente. |
| HTTPS | Nginx/Certbot/snap ou proxy histórico | Caddy e verificação pública | Implementada: domínio opcional Oficial e diagnósticos distintos; sem instalação nativa nem alegação antecipada de certificado. |
| Backup/restore | Receitas nativas/Docker | Snapshot dos dois bancos sempre | Adaptado: seleção real de bancos/volumes, hashes/propriedade/revisão e preservação de recursos desabilitados. |
| Revisar/voltar/cancelar | Confirmação final sem editor de etapas | Confirmação s/n | Implementada: 11 etapas, `:voltar`, revisão pelo número da etapa e cancelamento. |
| Deploy Linux, PM2, Nginx nativo | Provisionamento no host | Receitas arquivadas e bloqueadas | Incompatível com a arquitetura atual: não reintroduzido. |
| VOZ/HUB | Instaladores externos | Integrações de URL/chave | Parcial por contrato: integrações reais mantidas; sem provisionamento na ausência de fonte/imagem. |
| GoFlow/PgBouncer/Watchtower direto | Ferramentas/variáveis antigas | Não fazem parte da stack oficial | Ausentes/incompatíveis ou obsoletos para este caminho. Atualização agendada usa backup/build/migrations. |

## Matriz pergunta → armazenamento → consumidor

| Escolha | Persistência | Consumidor e aplicação | Verificação / preservação |
|---|---|---|---|
| Frontend/backend | `.env`: FRONTEND_URL, BACKEND_URL, ALLOWED_ORIGINS, *_HOST | Backend HTTP/CORS/WebSockets; frontend gera env.js em runtime; Caddy usa hosts. Recriação sem build. | Validação de URLs, Compose real, HTTP interno e HTTPS público quando ativo. Update não reescreve escolhas. |
| Portas/publicação | `.env`: BIND_ADDRESS, PORT_FRONTEND, PORT_BACKEND, PORT_APIOFICIAL, PORT_WUZAPI | `ports` do Compose; bancos/brokers sem portas externas. | Conflitos entre escolhas, Docker inspect e helper Node/Docker em rede host antes de dados; bind final do Docker. |
| Projeto técnico | `.env`: COMPOSE_PROJECT_NAME; state.json e override de nomes | Projeto, rede, volumes, containers, jobs e backups. | Normalização; colisões e nomes efetivos. Mudança em atualização é recusada. |
| Nome comercial | state.json e admin-access.json; campo `Companies.name` após seed | Atualização parametrizada somente de `Companies.id=1` recém-criada, pelo driver pg dentro do backend. Não modifica usuários/credenciais. | Exige seedSucceeded e instalação ainda não inicializada; uma linha deve ser atualizada. Update/adopt não aplicam essa personalização. |
| Nome de exibição | admin-access.json; Settings/appName | PUT autenticado `/settings/appName`; sem build. | Login/sessão e HTTP 200; alterações posteriores pela API. Identidade salva na plataforma tem prioridade. |
| Suporte | `.env`: REACT_APP_NUMBER_SUPPORT | Frontend em runtime; recriação de frontend. | Compose real e regressão de alvo afetado. |
| E-mail/senha admin | admin-access.json privado; env transitório apenas no seed | Seed Sequelize calcula hash, somente em banco novo. | Tabela Users vazia, seed único e login/sessão após startup. Update nunca executa seed. |
| Senha DB | `.env`: DB_PASS e DB_URI_PASSWORD codificada | PostgreSQL/backend recebem literal; Prisma recebe URI codificada. | Compose real com `$`, `#`, `@`, `:` e `/`. Não há rotação implícita em banco existente. |
| Perfil PostgreSQL | `.env`: PG_MAX_CONNECTIONS/PG_SHARED_BUFFERS | Comando do PostgreSQL em Docker; backup/recriação no menu. | Limites sintáticos e orçamento de memória informado pelo daemon; update preserva. |
| JWT/refresh/MASTER/transcrição | `.env`: JWT_SECRET, JWT_REFRESH_SECRET, MASTER_KEY, TRANSCRIBE_API_KEY | Gerador oficial; backend e transcrição autenticam por chave comum específica. | Gerador real: distintos, privados, sem sobrescrita. MASTER opcional só na criação. |
| Oficial/WuzAPI/Rabbit | Perfis em `.env`/state.json; USE_WHATSAPP_OFICIAL, WUZAPI_URL, RABBITMQ_ENABLED_GLOBAL | Somente serviços selecionados são construídos/iniciados/verificados. API usa endpoint interno; WuzAPI mantém webhook `http://backend:8080`. | Testes de stack mínima, backup/restore/update e habilitação posterior sem seed. |
| Tokens internos oficiais | `.env`: TOKEN_API_OFICIAL, WUZAPI_ADMIN_TOKEN, chaves WuzAPI e RABBITMQ_PASS | Compose repassa aos pares consumidores. | Geração oficial e validação de entrada; valores existentes nunca rotacionados por menu genérico. |
| SMTP | `.env.backend`: MAIL_HOST/PORT/SECURE/USER/PASS/FROM | SendMail/signupVerificationSettings em runtime; recria somente backend. | Validação dos campos; nodemailer.verify no backend, sem envio. Settings SMTP do banco podem prevalecer. Falha opcional gera aviso. |
| Nome remetente SMTP | admin-access.json e Settings/signupSmtpFromName | API Settings autenticada após criação; SendMail lê o setting. | Sem variável MAIL_FROM_NAME inventada. |
| Facebook | `.env.backend`: FACEBOOK_APP_ID/SECRET | Controlador de conexões/Meta em runtime; recria backend. | Campos permitidos e proteção em logs; conta externa não conectada automaticamente. |
| Google | `.env.backend`: GOOGLE_CLIENT_ID/SECRET | GoogleAuthConfig lê fallback; callback deriva de BACKEND_URL/auth/google/callback. | Contrato do consumidor; requer cadastro/consentimento no provedor. Settings do banco prevalecem. |
| IA IVR | `.env.backend`: OPENAI_API_KEY | InterpretVoiceIvrSpeechService lê o fallback para IVR. | Somente consumidor existente; não configura agentes ou faz chamadas pagas automaticamente. |
| Push | `.env.backend`: VAPID_PUBLIC_KEY/PRIVATE_KEY/SUBJECT | Backend em runtime, P-256 no gerenciador. | Par correspondente, segredos preservados e recriação do backend. Navegador/rede exigem homologação. |
| Pagamentos | Settings via API administrativa | paymentGatewaySettings lê chaves do gateway; sem build. | Allowlist, autenticação e valores secretos em ambiente do exec, sem URL/comando contendo credencial. Provedor exige homologação. |
| Tokens Git | source-token privado e platform/.secrets/github_token | Git askpass no gerenciador; BuildKit para conector. | Não vão para remote, URL ou imagem final. Segredos separados e logs filtrados. |
| HTTPS | `.env`, perfil edge e volumes Caddy | Script oficial prepara Caddyfile com domínio opcional e proxy interno. | DNS antes de dados, parser/Caddyfile e GET público com TLS. Não promete emissão quando teste falhar. |

## Operação e recuperação

O assistente só retorna configuração normalizada depois da confirmação. O caminho
JSON é autorização de execução automatizada. A imagem/ferramentas e o diretório
montado podem ser preparados antes, mas build da plataforma, migrations e seed não.
O menu principal e Ferramentas/API preservam numeração histórica compatível.
Novos itens de Configurações foram acrescentados após 1–9, sem reusar seus números.

Arquivos são salvos em modo 600. Histórico de configuração fica na pasta privada.
Validação de Compose precede recriação. SMTP só afeta backend; suporte só frontend;
rede afeta consumidores/proxy e PostgreSQL tem fluxo próprio com backup.
Falha antes da aplicação restaura arquivos sem reiniciar desnecessariamente.
Falha após tentativa de aplicar restaura configuração e verifica o estado anterior.
Falhas de migrations mantêm estado de retomada, sem alegar rollback de schema. O histórico/rollback de arquivos não é uma transação dos Settings da API: atualizações de múltiplas chaves podem ser parciais se interrompidas. O gateway de pagamento é ativado após suas credenciais; revise os Settings no painel se a API falhar.

Habilitar serviço opcional prepara imagem, faz backup dos serviços atuais e aplica
migrations/configuração com o mesmo projeto, chaves e volumes. Atualização continua
sem seed. Backups anteriores com outra seleção de bancos/volumes não são restaurados
silenciosamente; exigem recuperação isolada com o contrato original.

## Evidências e limites

As regressões locais usam Docker/Git/SQL simulados. A integração adicional usa
Compose real, gerador oficial e geração do Caddyfile em container sem rede/socket;
copia somente arquivos de exemplo para diretório temporário. O build afetado é
a imagem do gerenciador. Não houve mudança na fonte da plataforma nem build de
backend/frontend nesta tarefa.

Essas evidências não provam instalação completa, emissão pública de certificados,
conexões Meta/WuzAPI, Google, entrega SMTP, push, cobrança, carga PostgreSQL ou
restauração real. Esses cenários precisam de ambiente Linux descartável e contas
de teste, conforme `tests/PLANO_DE_TESTES.md`. Nenhuma VPS foi fornecida como alvo.
