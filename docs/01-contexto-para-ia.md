# Continuidade — instalador Docker-only

## Estado em 07/11/2026

O ponto de entrada oficial é `sh instalador_single.sh`. O único executável externo
que ele chama no host é `docker`; todos os comandos Node/Git/Compose/Buildx rodam
na imagem `docker/installer/Dockerfile`. O gerenciador usa exclusivamente o
Compose/Dockerfiles da raiz de `acerticonsulting/AMANDA`, branch main.

Oito serviços: frontend, backend/Baileys, postgres, redis, api_transcricao,
api_oficial, wuzapi e rabbitmq. Perfis official/whatsmeow/rabbit sempre ativos;
edge/Caddy opcional. Recursos sem implementação no repositório não são instalados.
Logo, temas, credenciais padrão e correções vêm da mesma revisão da aplicação.

Os scripts anteriores, ferramentas, chave e endereços foram preservados em
`legacy/`, sem reescrever seus conteúdos. A entrada oficial não os chama.
A documentação histórica identificada como tal não descreve o fluxo atual.

## Decisões e proteção de dados

- Clonar somente o link autorizado, obrigatório na instalação/adoção.
- Não gerar Compose ou Dockerfiles alternativos; manter uma única definição.
- Montar instalação no gerenciador no mesmo caminho absoluto do host.
- Separar token de leitura do código do segredo privado BuildKit do conector.
- Criar configurações com o gerador oficial; arquivos privados fora do Git.
- Seeds somente em projeto sem containers/volumes/rede existentes, após migrations
  e confirmação de tabela Users vazia. Registrar tentativa antes de executar.
- Não repetir seed falho ou concluído. Atualizar/adotar nunca executa seeds.
- Atualização exige Git limpo, avanço de histórico e backup antes de migrations.
- Backup inclui dumps amanda/api_oficial e volumes não PostgreSQL, configuração,
  referência de imagens e revisão. Para consistência, pausar gravadores.
- Falha de build/backup restaura imagens/revisão; falha de migration mantém apps
  parados e estado retomável. Não há downgrade automático do banco.
- stop não remove volumes; não existe remoção ou restauração destrutiva automática.
- Adoção somente de Compose oficial saudável. Migração de PM2/bancos no host
  requer procedimento específico, com backup e homologação.

## Comandos e recuperação

Veja [README](../README.md) para download usando Git em container e JSON opcional.
Operações: install, update, resume, adopt, start, stop, restart, status, logs,
backup, doctor, build-token, unlock. Usar sempre `--dir` da mesma instalação.

Estado/log/backups/acesso escolhido: `<dir>/.amanda-installer/`.
Código/configuração: `<dir>/platform/`; na adoção, pode ser o próprio `<dir>`.
Arquivos privados 600; pastas privadas 700. Customização administrativa é pergunta
opcional; padrão admin@amanda.com.br / adminamanda. Senha customizada não entra
na linha de comando nem em arquivo versionado.

Em falha, ler install.log, corrigir causa e executar resume. Seed incompleto exige
revisão manual preservando os dados. Lock abandonado: unlock verifica se o container
anterior encerrou. Restaurar backup somente com plano validado em ambiente isolado;
não apagar volumes nem repetir seeds para resolver erro. Manter cópia de backup
protegida fora da máquina.

## Evidências e limites

- Suíte local: 47 scripts Shell e cinco grupos aprovados; gerenciador com 26 testes
  de comandos simulados (inclui bootstrap POSIX executado com Docker simulado).
- Não são executadas instalações, migrations ou restaurações reais pela suíte.
- Build real da imagem e doctor contra daemon Linux aprovados: Compose 2.33.0, Buildx 0.20.1, Docker Engine 29.9.2/x86_64.
- Verificação somente leitura do projeto local amanda aprovada: oito serviços obrigatórios running/healthy, três jobs encerrados com código 0, frontend e /healthz HTTP 200. Há um container adicional histórico de transcrição sem healthcheck, reportado como aviso e preservado.
- Ainda pendentes: ciclo completo de instalação/atualização/recuperação em VPS
  Linux limpa, certificados públicos, outras arquiteturas e contas externas.

Os testes do gerenciador são executados com Node 22 dentro de Docker sem rede,
sem montar o socket. O hook obrigatório testa a árvore preparada para commit.
A regra está em AGENTS.md; executar bash tests/validar_instalador.sh e manter
core.hooksPath=tests/hooks. Nunca usar --no-verify.

### Recuperação de atualização interrompida

O estado preparing-update é gravado antes de alterar código/imagens. Uma retomada
nessa fase restaura as referências anteriores e orienta repetir update. O estado
migration-update registra pendingRevision; resume recusa migrar outra revisão.
Assim, start não recria silenciosamente imagens novas antes das migrations.
Backups exigem os serviços saudáveis antes de qualquer parada. Dumps binários são
transmitidos com controle de fluxo, sem acumular o banco inteiro na memória.

O teste de whitespace do hook usa um repositório Git temporário, sem dados do
projeto. O hook reconhece reescritas/renomes para não tratar espaços históricos do
arquivo arquivado como código novo; continua reprovando whitespace introduzido,
com regressão dedicada. Os 42 arquivos históricos foram comparados por hash Git
e permaneceram idênticos. A prova de projeto novo é repetida após o build, antes
da primeira criação de recursos/migrations.

## Correção de regressão — restauração dos menus (07/11/2026)

A versão Docker-only reduziu indevidamente a interface anterior. Os menus principal
1–11, Ferramentas (IDs históricos) e API Oficial 1–9 foram recolocados em português,
com retorno ao menu e saída. Menu inicial aparece antes de qualquer download;
build do gerenciador usa Buildx embarcado via docker run e não exige plugin no host.
Diagnóstico de permissão do socket explica a necessidade de conta autorizada/sudo.

Os novos módulos são menus.cjs, options.cjs, operations.cjs, addons.cjs e scheduler.cjs.
As opções adicionais chegam aos consumidores reais: appName pela API, telefone em
runtime no frontend, SMTP/Facebook em env_file, senha nova do PostgreSQL com URI
codificada, MASTER na instalação inicial, portas e Caddy/HTTPS da API Oficial.
A matriz docs/MENUS_E_COMPATIBILIDADE.md lista cada entrada e suas dependências.

Restaurações/imports/desinstalação exigem confirmação do projeto e backup. Hashes
validam backups; SQL é limitado a um banco e recusa comandos psql de troca de
banco/shell. Falhas deixam apps parados e a mesma operação pode ser retomada.
Rollback restaura dados e revisão antes de iniciar. Agendadores são containers;
locks são reentrantes na mesma operação, sem liberar concorrência entre processos.
Configuração privada tem histórico e volta aos valores anteriores se a aplicação
falhar. Chaves VAPID existentes não são trocadas silenciosamente.

VOZ/HUB dependem de Compose mantido pelo fornecedor e acesso próprio, ainda não
fornecidos/homologados. GoFlow não possui consumidor no backend; depende de fonte
e contrato do adaptador. Esses itens não foram declarados funcionais no runtime.
Nunca voltar a scripts APT/PM2 para simular compatibilidade. Usar os registros e
backups privados para recuperação; não remover volumes reais como teste.

Validação desta correção: 42 regressões Node do gerenciador e cinco grupos locais;
cinco testes da plataforma, incluindo Compose real, passaram. Build frontend em tag
isolada e HTTP / + /env.js em container sem rede passaram. Build do gerenciador foi
executado por cliente Docker/Buildx em container, sem usar plugin do host; doctor
real aprovou o engine. Caddy real adaptou três domínios sem rede. Verificação local
somente leitura manteve oito serviços obrigatórios saudáveis e endpoints HTTP 200;
um container histórico adicional de transcrição sem healthcheck foi preservado.
O hook repete as regressões sobre o índice preparado. Homologação VPS/contas externas
continua pendente, conforme a matriz.

Após seed concluído e falha de arranque, configurações de URLs/portas permitem
corrigir o acesso antes de Retomar. O estado continua incompleto até login/sessão
serem verificados; não há repetição de seed. Portas que conflitam com Caddy ou
outros serviços são recusadas antes de criar dados.
