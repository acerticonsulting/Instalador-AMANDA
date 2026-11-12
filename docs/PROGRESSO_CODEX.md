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
