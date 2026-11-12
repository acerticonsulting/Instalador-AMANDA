# Remoção do conector privado — 12/11/2026

Objetivo: clonar somente acerticonsulting/AMANDA main e construir a plataforma
corrigida com dependências públicas, sem solicitar acesso ao Hineken.
Alterados: cli/historical/wizard/manager/menus, testes Docker-only/históricos,
README, CONFIGURACAO_E_COMPATIBILIDADE e PLANO_DE_TESTES.

Implementado: retirada das perguntas de token do conector; buildToken antigo
aceito e ignorado; comando legado build-token apenas informa que é dispensável.
Credencial de origem da AMANDA, posições dos menus, Docker-only e layout deploy
mantidos. Arquivos antigos de segredo não são removidos nem enviados ao build.
Resume na fase build anterior ao seed busca main e aceita apenas fast-forward
limpo. Sem reset, limpeza de volumes ou sobrescrita de .env; erro de rede ou
histórico mantém o checkpoint. Fases posteriores não atualizam código sozinhas.

Validação: cinco suítes locais, 83 scripts e 112 testes Node aprovados; regressão cobre
recusa de histórico divergente/checkout alterado antes de build ou seed. O teste de interrupção aguarda a liberação observável do flock para evitar corrida com os filhos do proprietário; a proteção de produção não mudou. O hook
valida novamente o conteúdo preparado para commit. Testes usam comandos
simulados; nenhuma VPS ou instalação existente foi alterada.
Na plataforma: npm ci, TypeScript e imagem Docker aprovados; 5 testes Baileys
sem rede e 2 integrações reais isoladas (saúde PostgreSQL, Socket.IO, Bull/Redis)
aprovados. Sem uso de conta WhatsApp; QR apenas simulado.

Pendências: publicar ambos os commits somente quando autorizado e homologar
WhatsApp real com conta de teste autorizada. A retomada obterá a correção apenas
quando ela estiver disponível na main da AMANDA. Para retomar depois disso:
sh instalador_single.sh resume --dir /home/deploy/{empresa}
Não apagar estado nem volumes, não repetir seeds.

# Histórico anterior
# Estrutura deploy — tarefa atual

Objetivo: novas empresas em `/home/deploy/{empresa}`, com conta deploy e arquivos
privados, mantendo a origem de instalações existentes. Alterados: bootstrap,
deploy.cjs, cli/manager/menus/operations/wizard/historical, imagem, testes,
README e MIGRACAO_DEPLOY.md. Conta criada por helper em container com shadow;
não se adicionam grupos sudo/docker. Conta existente não tem senha/grupos/shell
alterados. Propriedade é inventariada por empresa, sem seguir links, e persistida
no estado para operações posteriores. Flags --dir/AMANDA_INSTALL_DIR preservam
destinos explícitos. Sem indicação explícita, detecta-se a instalação histórica
para administração; novas empresas no fluxo automático continuam na base deploy.

Migração separada: `migration-plan --dir /origem` inspeciona stack/montagens e
verifica o backup existente com os contratos atuais. Não move ou copia a VPS.
Procedimento de cópia, validação e recuperação está em MIGRACAO_DEPLOY.md e exige
autorização operacional específica. Nenhuma instalação real foi migrada.

Testes: 110 regressões e suíte completa aprovadas; imagem construída e oito
integrações aprovadas, incluindo useradd real em cadastro descartável. O ajuste
final de modos privados é validado novamente no hook e na imagem antes da entrega.
Pendências externas: homologar conta/montagens em Linux descartável com daemon
administrativo; não foi fornecido alvo completo de VPS nem autorizada migração.

# Correção anterior do bloqueio de operações

Objetivo: recuperar locks comprovadamente abandonados e preservar exclusão mútua,
sem alterar interface nem dados. Arquivos: manager.cjs, operation-lock.cjs,
cli.cjs/menus.cjs (orientação de retomada), Dockerfile, bootstrap e testes/matriz.

Causa reproduzida: lock residual sempre impede operações; a implementação antiga
não verifica proprietário ao adquirir e transforma qualquer erro de criação em
"outra operação". O unlock anterior considera qualquer falha de inspect como
ausência. Não há evidência de que o perfil PostgreSQL crie lock aninhado: ele
apenas atribui options.pg antes de prepare. Chamadas aninhadas no mesmo Manager
continuam reentrantes via AsyncLocalStorage; outro Manager mantém exclusão.

Correção: flock embarcado em container mantém uma guarda do kernel por operação.
Arquivo .guard permanece como âncora e não é apagado. Sob essa guarda, o registro
operation.lock é criado exclusivamente e contém token/identidade/início. Locks
legados só são recuperados com proprietário Docker parado ou ausência confirmada
por consulta bem-sucedida ao daemon. Falhas de daemon, identidade desconhecida e
gerenciador ativo bloqueiam. Execuções locais de teste usam PID/início/boot Linux,
sem idade arbitrária. Remoção verifica identidade e inode, inclusive no finally.
Nenhum proprietário ativo é encerrado automaticamente.

Bootstrap mantém --rm e passa --init para encaminhamento de sinais e coleta de
filhos. Ao morrer por SIGINT/SIGTERM, os metadados podem permanecer; a próxima
operação verifica o proprietário e recupera sob a guarda. Não libera lock antes
de comprovar encerramento. O container do menu continua ativo enquanto aguarda
uma opção, mas não mantém lock entre operações. Idade não prova abandono.

Retomada: resume mantém verificação de fonte/recursos, build e migrations; seed
incompleto exige revisão, sem repetição automática. Preparação sem prova de banco
novo exige intervenção orientada. Estado existente impede repetir o formulário
de instalação. Bancos, volumes e configurações não são removidos.

Testes direcionados: 101 regressões aprovadas; imagem construída e sete testes de
integração aprovados. Suíte completa e hook são exigidos antes do commit. Pendência externa:
não há acesso SSH ou alvo completo da VPS. Não foi possível identificar o dono
real do lock relatado nem certificar o container 8063d5bf8093; não foi encerrado.
