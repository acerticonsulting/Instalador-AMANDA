# Bloqueio de DNS direto incorreto — 13/11/2026

Causa informada pelo diagnóstico da VPS: IPs 157.173.200.50 e
2605:a140:2372:3218::1, enquanto os hosts homolog3/api.homolog3 resolvem para
209.145.62.30. Consulta pública confirmou A antigo, sem AAAA/CNAME; zona
appamanda.com.br delegada a ns1–ns4.bdm.microsoftonline.com. Não há acesso ao
painel DNS nem confirmação administrativa de proxy; nenhuma alteração DNS feita.

Brechas do código anterior: exceção DNS PENDENTE aceitava divergência comprovada;
JSON/savedConfig não eram rechecados antes de provisionar; resume não comparava
destino DNS/VPS. Removido bypass direto. Proxy exige destinos IP explícitos
compatíveis com todos os resolvedores, motivo/declaração de encaminhamento e
confirmação. Consulta atual obrigatória em deploy.install antes de provisionar,
em resume antes de retomar, e antes de startServices. Metadados antigos não
autorizam DNS incorreto. Nenhuma necessidade de repetir questionário no resume.

probe/evaluate reutilizados para classificar portas: Caddy próprio por labels
Compose (aceito apenas em instalação existente), outro serviço AMANDA,
serviço desconhecido ou indisponível sem dono identificado. Diagnóstico mostra
o veredito DNS com IP esperado/encontrado. Estado starting preservado na falha.
TLS rejeita também emissor staging; certificados/volumes não são alterados.

Regressões incluem IPs do caso real, bloqueio de fresh install/resume antes de
build/provision/seed, .env preservado, labels de portas, bypass antigo recusado,
proxy declarado e staging. Suíte completa: 178 testes Node aprovados, dois opt-in
ignorados, 84 scripts e cinco suítes; imagem dns-block-validation construída.
Pendente externo: confirmar publicação direta/topologia autorizada e alterar os
dois A para a VPS; após propagação executar resume. Não se declara HTTPS resolvido.

# Diagnóstico do encaminhamento ACME — 13/11/2026

Evidências: usuário relata HTTP-01 404 e TLS-ALPN-01 "no application protocol".
Consulta externa em container confirma A=209.145.62.30, porta 80 acessível e
certificado válido apenas para homolog/homologapi, sem os hosts homolog3.
Isso comprova falha de hostname no endpoint observado e desafios não satisfeitos;
não identifica qual proxy/processo os recebe nem comprova o IP de saída da VPS.
SSH em modo não interativo foi recusado (Permission denied); sem alterações remotas.

Compose/Caddyfile oficiais mantêm publicação 80/443 e volumes persistentes; não
há evidência para mudar esses arquivos. Plataforma sem alterações.
edge-diagnostics.cjs e comando https-diagnose consultam publicações Docker,
configuração ativa Caddy resumida, hosts, portas, volumes, DNS/IP na rede host e
HTTPS. Somente consulta e um container efêmero de diagnóstico; sem up/restart,
reload, alteração de firewall, seeds ou reemissão. Configuração completa e logs
brutos não são impressos. Fallback inconclusivo quando admin API estiver desligada.
https-check.cjs agora identifica respostas erradas HTTP-01 e falta de ALPN e
encerra espera sem tentar mascarar erros de roteamento como atraso de emissão.

Testes: classificação de desafios, redação de configuração, API indisponível,
preservação de volumes e ausência de comandos mutantes, parada da espera por
erro ALPN. Suíte completa e build de ferramentas registrados na entrega.
Pendente na VPS: executar https-diagnose e ss para confirmar IP/destino e donos
de 80/443; corrigir encaminhamento/DNS apenas conforme evidência. Depois resume.
Emissão pública válida e saúde remota ainda não comprovadas.

# Pré-validação de domínios — 13/11/2026

Referência consultada: scriptswhitelabel/instalador_single_oficial, funções
questoes_dns_base/verificar_dns_base/instalacao_base. Mantida a ordem URLs → DNS →
demais perguntas, sem copiar instalação de dnsutils ou alteração do host.
domain-preflight.cjs usa Node nativo em container efêmero com rede host Linux:
consulta A/AAAA/CNAME pelo resolvedor do sistema, Cloudflare e Google, com timeout;
compara endereços com IPs de saída confirmados por duas fontes HTTPS e interfaces
públicas atribuídas. IPv6 desconhecido, falha de rede ou resolvedores divergentes
produzem resultado inconclusivo. Bind temporário em 80/443 e publicações Docker
detectam conflitos locais; não comprovam entrada pública e não param serviços.

Integrado nos assistentes histórico e wizard pela CLI, antes de dados pessoais,
empresa, senhas e credenciais. Correção individual, diagnóstico, nova tentativa,
voltar/cancelar e limite de 12 consultas. Exceção DNS/CDN requer motivo e frase
explícita; conflito de portas e hostname inválido não têm bypass. Registro salvo
no setup e estado após confirmação. Sem criação de recursos da aplicação nesta fase.
Modos IP/local não fazem DNS público. Configuração JSON não interativa mantém
o caminho existente; validação final HTTPS permanece obrigatória em todos os modos edge.

Atualizações/URLs existentes mantêm sua validação final; pré-validação não é
executada na retomada para não confundir portas do próprio Caddy com conflito.
O módulo é reutilizável sem alterações administrativas automáticas.
Testes com mocks cobrem sintaxe, DNS, CNAME, IPs, AAAA, divergência, portas,
correções, repetição, cancelamento, exceção e ordem antes de credenciais.
Validação completa: 169 testes Node aprovados, dois opt-in ignorados, 84 scripts
e cinco suítes; imagem amanda-installer:domain-validation construída e scanner
executado em rede none retornou inconclusivo sem presumir sucesso.
Nenhuma VPS, DNS real, volume ou configuração da plataforma foi alterada.

# HTTPS público e retomada — 13/11/2026

Causa comprovada externamente: ambos os hosts homolog3 resolvem para
209.145.62.30 e recebem certificado Let's Encrypt com SANs de homolog/homologapi,
não homolog3/api.homolog3. Validade 09/11/2026–07/02/2027. Porta 80 acessível;
TLS retorna ERR_TLS_CERT_ALTNAME_INVALID. Não há acesso SSH à VPS para identificar
o proxy/listener ou corrigir DNS. Não se presume corrida de emissão.

Novo https-check.cjs mantém confiança TLS, SNI e hostname, consulta A/AAAA e testa
todos os endereços separadamente; registra código técnico, metadados e HTTP.
Backoff limitado somente com evidência de emissão e erros transitórios; falhas
ACME definitivas param a espera. IP esperado é opcional para não rejeitar proxies.
manager.cjs persiste https-pending e retoma também starting legado com seed
concluído, sem build/migrations/up/seed. Bootstrap transmite opções de timeout/IP.

Validação: 155 testes Node aprovados, dois opt-in ignorados, 84 scripts e cinco
suítes. Novos mocks cobrem SAN, expiração, cadeia, data futura, DNS ausente/IP
divergente/AAAA inacessível, 443, diagnóstico 80, HTTP, emissão/backoff/timeout,
ACME e retomada sem recriação com .env preservado. Imagem de ferramentas construída.
--plataforma executado no daemon local: REPROVADO (instalação VPS não acessível
nesse daemon e endpoints públicos rejeitados); não representa saúde remota dos
containers. Plataforma AMANDA e volumes reais não foram alterados.
Pendente: corrigir destino/certificado público na VPS e executar resume.

# Preservação do terminal no Docker — 12/11/2026

Base: main 31fa043. Reproduzido o erro de terminal interativo quando stdin é
TTY, mas stdout passa por pipe: o menu shell aceita a opção, enquanto o bootstrap
envia apenas -i ao Docker. A decisão agora usa stdin, igual ao menu, enviando -it
nesse caso e mantendo -i para entradas não interativas.

Regressão anterior falhou com -i; teste corrigido e controle não interativo cobertos.
Integração opt-in com Docker real: sem TTY a CLI reproduz o erro e retorna 1;
com o argumento do bootstrap corrigido retorna 0. A CLI recebe menu --initial 0,
sem executar instalação. O socket do controlador serve apenas para containers de
ferramentas descartáveis; containers internos não montam dados/socket da plataforma.
A VPS relatada não foi acessada; a causa remota exata não foi inspecionada.
Validação local aprovada: 142 testes Node, dois opt-in ignorados na suíte padrão,
84 scripts Shell e cinco suítes; os dois casos opt-in passaram com Docker real.

# Entrada do menu em terminal — 12/11/2026

Objetivo: tratar a saída Opção inválida ao iniciar instalador_single.sh.
Base analisada: main 6e7630e. A versão atual mostra o menu normalmente em PTY;
foi reproduzida a mensagem e saída 2 quando a entrada inicial contém uma linha
vazia, CRLF com espaços ou uma seleção inválida. A revisão efetiva da VPS não
foi inspecionada, portanto não se presume que essa seja a única causa remota.

Correção: leitura inicial em laço POSIX, preservando a apresentação; ignora
linhas vazias, remove espaços/CR das extremidades e permite corrigir entrada
inválida. Não inicia instalação por Enter vazio. Opções válidas mantêm --initial
para o gerenciador. Entrypoint versionado com modo executável Linux (100755).
Arquivos: instalador_single.sh, tests/historical.test.cjs, README e plano de testes.

Validação: controle anterior passou na abertura normal e falhou nos dois casos
de entradas residuais/repetição. Após correção, quatro testes PTY aprovados com
sh, bash e execução direta, desde outra pasta e com espaços no caminho. Sair não
chama Docker nem cria diretório; opções 1 e 11 são encaminhadas a Docker simulado.
Suíte completa aprovada: 140 testes Node, 83 scripts e cinco suítes locais.
Nenhuma aplicação, conta ou instalação real foi executada/alterada na VPS.

Atualização: um repositório Git descartável confirmou que o chmod local do
script anterior pode impedir o fast-forward de uma alteração no mesmo arquivo.
As instruções preservam somente esse arquivo em stash antes do pull, sem reset
ou exclusão de dados; o stash fica disponível para revisão posterior.

Publicação por commit/push e PR com integração à main, conforme autorização
permanente. Depois, atualizar o clone do instalador antes de abrir o menu ou usar
resume --dir /home/deploy/amanda para a instalação interrompida registrada.

# Histórico anterior
# Preparação da integração à main — 12/11/2026

Objetivo: entregar a correção por PR e explicar por que baixar a branch não muda
o instalador executado na main. Em 12/11/2026, o usuário autorizou integrar os
dois PRs e definiu como preferência permanente commit, push e integração à main
após as validações exigidas. A autorização está registrada nos dois AGENTS.md.

Revisões analisadas: official/main 8d748f1; fix/retomada-diretorio-existente
8704c51 (43ce96f, 52c4618 e registro de push). Os 18 arquivos do diff foram
revisados: classificação, fluxo CLI/menus/assistentes, preparo recuperável,
credenciais, locks, bootstrap, documentos e regressões. Main é ancestral, sem
commits exclusivos ou conflitos a resolver. O erro da VPS é coerente com executar
a main antiga depois de git pull: a branch foi baixada, mas não integrada.

Complementações: revision.cjs e bootstrap informam branch/commit/alterações locais
com Git apenas em containers, clone somente leitura e sem nova dependência no
host; CLI/menu mostram diretório e revisão da plataforma registrada. Retomada
antiga validada solicita apenas e-mail/senha administrativos ausentes depois da
prova de recursos vazios; preserva o restante e não adota defaults. Erros de JSON
privado não expõem conteúdo. Testes usam uma cópia exata de deploy.cjs da main
8d748f1 (blob de407108a2e8bb50a97640ef730f9c81fb3f206c).

Arquivos desta complementação: cli/deploy/manager/revision, instalador_single.sh,
README, testes deploy/Docker-only/compose, fixture da main, driver de integração
e PLANO_DE_TESTES. Reutilizadas as funções existentes; sem remover proteções ou
provisionar novamente uma instalação parcial já reconhecida.

Validação: 136 testes Node aprovados, 83 scripts e cinco suítes locais aprovados.
Imagem do gerenciador construída; 11 contratos da imagem e uma reprodução de
fluxo aprovados. O controle da main reproduz a mensagem antiga imediatamente
após perfil PostgreSQL 1; o menu corrigido retoma /home/deploy/amanda, conserva
os mesmos bytes do ambiente e executa seed uma vez. Docker de aplicação é
simulado nesse fluxo. Os contratos reais de ferramentas não têm rede nem socket
do daemon; useradd usa cadastro descartável. Nenhuma VPS foi operada.

PR do instalador: https://github.com/acerticonsulting/Instalador-AMANDA/pull/1
A main da plataforma ainda usa Hineken, portanto também foi preparado o PR
https://github.com/acerticonsulting/AMANDA/pull/1 com a correção já validada em
Docker anteriormente. Homologação real com WhatsApp permanece pendente.

Entrega organizada em Pull Requests dos dois repositórios, com integração
autorizada pelo usuário. Próximo passo operacional: atualizar a main na VPS e
retomar no diretório original; nenhuma operação foi realizada no servidor. A VPS
pode usar a branch de correção explicitamente na homologação. Depois do merge,
atualizar main e retomar no mesmo diretório, sem excluir estado ou volumes.

# Histórico anterior
# Recuperação de diretório existente — 12/11/2026

Objetivo: reconhecer /home/deploy/{empresa} antes do questionário e retomar
instalações interrompidas, preservando arquivos, credenciais, imagens e volumes.

Causa comprovada: prepare grava state.json, fonte e ambiente antes do build.
Uma nova escolha de Instalar repetia o questionário e chamava provision, que
rejeitava qualquer estado/fonte existente, inclusive o checkpoint legítimo da
falha anterior. O perfil PostgreSQL apenas precedia essa chamada; não era a
causa. Locks de /root/amanda e /home/deploy/amanda têm escopos diferentes.

Alterados: directory-state.cjs (novo); deploy, manager, cli, menus, historical,
wizard; bootstrap; README; testes deploy/Docker-only/históricos/contratos da
imagem e PLANO_DE_TESTES.

Concluído: inspeção somente leitura distingue ausente, vazio, temporários
conhecidos, parcial, concluído e desconhecido. Verifica identidade da empresa,
origem, caminhos reais, links/hardlinks, proprietário/grupo, modos privados e
checksums. Empresa identificada antes das demais perguntas e mantida nos dois
assistentes. Parcial oferece retomada/diagnóstico; concluída oferece gestão.
A retomada não chama provision nem apaga estado. A conta deploy do host é lida
por montagem somente leitura; provisionamento novo mantém o helper Docker.

Preparação: escolhas aprovadas são salvas antes de doctor; novos ambientes são
montados em área privada, com manifesto antes da publicação exclusiva. Arquivo
existente diferente nunca é substituído. Reentrada mantém chaves e senhas. A
cópia nova do exemplo recebe proprietário do processo que a criou; não há
chown recursivo sobre diretório desconhecido. Estado antigo sem draft só avança
com configuração coerente, Git validado e ausência comprovada de recursos.

Validação: suíte completa (83 scripts, cinco suítes, 131 testes Node) aprovada.
O hook revalida o conteúdo preparado para commit.
Imagem do gerenciador construída; dez contratos isolados aprovados, incluindo
useradd em cadastro descartável, caminhos lógicos no helper, gerador real e
parser Compose real após interrupção, sem regenerar credenciais. Novas regressões
cobrem preparação/clone/build/migrations, falha de doctor, arquivos divergentes,
seleção antecipada, PostgreSQL, duas empresas e gerenciamento de concluídas.
Concorrência e recuperação após SIGINT/SIGTERM continuam cobertas.

Limites: nenhuma VPS foi acessada; não foi fornecido endereço/acesso operacional
para leitura --plataforma. Os testes não iniciam aplicações, bancos ou volumes
reais. Estado insuficiente/corrompido, permissões inseguras e seed incompleto
continuam bloqueados com diagnóstico, sem exclusões ou reinicialização.

Próximo passo: revisar/publicar o commit somente quando autorizado, atualizar
o instalador na VPS e executar resume --dir /home/deploy/amanda. O conserto
anterior do Baileys precisa estar na main da plataforma para o fetch obtê-lo.

# Histórico das tarefas anteriores
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
