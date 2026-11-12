# Correção do bloqueio de operações

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
