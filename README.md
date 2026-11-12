# Instalador AMANDA — referência histórica 7a5b31d

O instalador oficial está em https://github.com/acerticonsulting/Instalador-AMANDA.
A plataforma vem exclusivamente de https://github.com/acerticonsulting/AMANDA,
branch `main`. O endereço histórico do remote deste clone e a chave Git foram
preservados; não é necessário alterar remotes para usar o assistente.

O host Linux precisa de Docker Engine/CLI e acesso ao daemon por socket Unix local.
Git, Node, Python, Compose v2, Buildx, bancos, filas, migrations e proxy executam em
containers. O gerenciador embarca Compose/Buildx; não exige esses plugins no host.
Não instala pacotes APT, PM2, Nginx ou dependências da aplicação na VPS.
Se Docker estiver ausente, o bootstrap interrompe com orientação para disponibilizar
Docker oficial. Sockets rootless são aceitos; contextos TCP/SSH não são suportados.

## Obter e executar

Na pasta onde deseja guardar o instalador:

```sh
docker run --rm --name "amanda_download_$$" -v "$PWD:/workspace" -w /workspace alpine/git clone https://github.com/acerticonsulting/Instalador-AMANDA.git Instalador-AMANDA
sh Instalador-AMANDA/instalador_single.sh install
```

Ou execute `sh ./instalador_single.sh` dentro do clone para abrir o menu principal.
O menu aparece antes de preparar as ferramentas. Use `sudo` somente se a sua conta
precisar dele para acessar Docker. O instalador não altera grupos/permissões do socket.
A preparação da imagem pode baixar ferramentas; instalar a plataforma exige a
confirmação final. Use sempre o mesmo diretório absoluto nas operações seguintes.

### Conferir qual revisão será executada

`git pull` atualiza a branch selecionada. A mensagem `[new branch]` apenas
informa que uma referência remota foi baixada: não integra essa branch à `main`.
O bootstrap corrigido consulta Git dentro da imagem de ferramentas, com o clone
montado somente para leitura, e informa branch, commit e alterações locais ao
iniciar o gerenciador. Arquivos sem metadados Git são identificados como revisão
não informada. O banner e as cores permanecem iguais. Depois da seleção da empresa,
o diagnóstico mostra o diretório exato e a revisão da plataforma registrada no estado.

Para homologar a correção antes da integração, dentro do clone do instalador:

```sh
docker run --rm -v "$PWD:/repo" -w /repo alpine/git -c safe.directory=/repo fetch origin &&
docker run --rm -v "$PWD:/repo" -w /repo alpine/git -c safe.directory=/repo switch fix/retomada-diretorio-existente &&
docker run --rm -v "$PWD:/repo" -w /repo alpine/git -c safe.directory=/repo pull --ff-only origin fix/retomada-diretorio-existente
```

Após aprovação e merge do [PR do instalador](https://github.com/acerticonsulting/Instalador-AMANDA/pull/1),
use a mesma sequência com `main` no lugar da branch de correção. Se Git recusar
por alterações locais ou divergência, preserve-as e revise o diagnóstico;
não use reset forçado. A integração do
[PR da plataforma](https://github.com/acerticonsulting/AMANDA/pull/1) também é necessária
para que o build obtido de `main` deixe de depender de Hineken.

Depois de verificar a revisão, a retomada usa o diretório original:

```sh
sh instalador_single.sh resume --dir /home/deploy/amanda
```

Em preparação antiga reconhecida e sem recursos preexistentes, a retomada
interativa pede somente e-mail ou senha administrativa ausentes, com confirmação
da nova senha. Campos já salvos e demais configurações são preservados. JSON
corrompido, credenciais internas ausentes ou recursos sem origem comprovada
continuam bloqueados; não são reconstruídos por suposição. Retomada não interativa
com acesso administrativo incompleto informa os campos faltantes sem usar senhas padrão.

## Instalação com a interface histórica

Novas instalações usam `/home/deploy/{empresa}`: `amanda` fica em
`/home/deploy/amanda` e `acerti` em `/home/deploy/acerti`. O caminho exibido no
resumo acompanha o identificador informado. O usuário de sistema `deploy` é
criado após a confirmação, quando necessário, com shell sem login; contas
existentes mantêm senha, grupos, shell e configuração. Não são concedidos sudo
nem acesso ao grupo Docker. A aplicação continua executando em containers.

O helper administrativo roda em container, com montagem restrita do cadastro
Linux e da base deploy. Os diretórios exclusivos ficam com modo 700; `.env`,
estado e credenciais mantêm seus modos privados e pertencem a deploy. O gerenciador
continua precisando de autorização administrativa para acessar o daemon.
Criar contas no host exige um daemon com essa autoridade; Docker rootless continua
utilizável para instalações já preparadas selecionadas explicitamente por `--dir`.

Instalações registradas nos caminhos históricos são detectadas e preservadas;
use `--dir /caminho/existente` para selecionar explicitamente outra instalação.
Esse parâmetro também mantém o destino explícito em homologação isolada. Nenhuma
instalação é movida ou tem sua propriedade convertida automaticamente.
Para avaliar uma migração separada:

```sh
sh instalador_single.sh migration-plan --dir /root/amanda
```

O comando confere fonte, serviços, montagens, volumes e eventual backup com hashes,
sem copiar ou mover dados. Siga o [procedimento de migração](MIGRACAO_DEPLOY.md)
somente com autorização específica e backup validado.

`install` e a opção 1 usam as perguntas extraídas do commit
`7a5b31da3ce48fb50fe451fbcbe840f725fa8838`: modo IP/local ou domínio, backend
antes do frontend, e-mail, empresa, banco, MASTER, título, suporte, Facebook,
token GitHub, repositório, proxy, portas, resumo e perfil PostgreSQL.
O banner inclui `v1.0.0`, a paleta mantém os números lilás, e o menu principal
volta às opções 1–11. Ferramentas mantém suas seções e números históricos.

As senhas de banco/MASTER podem ser geradas com ENTER; os padrões públicos
históricos foram substituídos. Senhas e tokens são visíveis durante a digitação e permanecem ocultos no resumo.
O e-mail informado identifica a conta administrativa inicial; sua senha, confirmada
separadamente, não é a senha do banco. Senhas obrigatórias devem ser não vazias; não há comprimento mínimo ou complexidade exigida.
O token do conector é separado do token de clone. Use `:cancelar` durante as
perguntas históricas ou responda N na confirmação para sair sem criar a plataforma.

O proxy é Caddy em Docker. PostgreSQL, Redis e transcrição usam portas internas,
sem exposição no host; frontend/backend aceitam portas personalizadas inclusive
com HTTPS. Instalação histórica habilita Oficial, WuzAPI e RabbitMQ pelo Compose;
seleção fina de serviços e SMTP permanecem no assistente adicional/JSON e nas
configurações posteriores. Otimização usa perfis limitados e valida a memória
do Docker antes de clonar; não aplica as receitas nativas antigas.

O menu de atualização conserva confirmação, seleção da instância e tela de canal.
Somente `main` possui contrato validado; selecionar outro canal informa
indisponibilidade antes de atualizar. Os scripts antigos recuperaram seus caminhos
e encaminham operações compatíveis para containers. Receitas sem adaptação segura
retornam erro explícito. Nada é executado no host além de Shell/Docker.

Administração complementar, sem reorganizar o menu histórico:

```sh
sh instalador_single.sh configure --dir /pasta/da/instalacao
sh instalador_single.sh instances --dir /pasta/da/instalacao
sh instalador_single.sh doctor --dir /pasta/da/instalacao
sh instalador_single.sh resume --dir /pasta/da/instalacao
```

`configure` mantém SMTP, suporte, Facebook, Google, integrações, portas, SSL,
push e PostgreSQL. Operações administrativas oferecem seleção quando há várias
instâncias gerenciadas. Instalações oficiais existentes exigem adoção explícita
por `adopt`; configurações/volumes históricos não são convertidos automaticamente.
Leia o [registro de restauração e limites](docs/RESTAURACAO_7a5b31d.md).

## Assistente adicional em 11 etapas (`wizard`)

Mantido para compatibilidade: `sh instalador_single.sh wizard --dir /pasta`.
As funcionalidades abaixo descrevem esse assistente adicional.

| Etapa | O que configurar |
|---|---|
| 1 | Domínios/HTTPS, IP do servidor ou ambiente local. |
| 2 | URLs e portas. No modo IP, IPv4/IPv6 e publicação na rede; no local, loopback. |
| 3 | Nome comercial, título da plataforma, projeto Docker e telefone de suporte. |
| 4 | Acesso padrão ou e-mail/senha personalizados, com digitação visível e confirmação. |
| 5 | Senha PostgreSQL automática/personalizada e perfil econômico/intermediário/alto/personalizado. |
| 6 | MASTER_KEY opcional, tokens Git separados e link obrigatório da plataforma. |
| 7 | API Oficial, WuzAPI e RabbitMQ opcionais; portas/tokens e Facebook/Meta. |
| 8 | SMTP opcional, TLS, remetente e teste de conexão sem enviar e-mail. |
| 9 | Google OAuth, chave de IA para IVR e push; outras integrações podem ser configuradas depois. |
| 10 | Revisão dos requisitos DNS, firewall e Caddy para HTTPS. |
| 11 | Resumo sem segredos: confirmar, revisar uma etapa ou cancelar. |

Digite `:voltar` em uma pergunta para retornar à etapa anterior ou `:cancelar` para
sair. A revisão mantém respostas já informadas; senhas não aparecem como padrões. Em um campo secreto já preenchido, ENTER preserva e `:limpar` remove o valor (quando o campo permite geração automática ou ausência).
Entradas inválidas são solicitadas novamente. `NO_COLOR`, `TERM=dumb` e terminais
sem cor recebem texto simples. Sem TTY, use JSON privado.

Local: `http://localhost:3000` e `http://localhost:8080`, sem Caddy.
IP: informe o endereço do servidor e portas diferentes; HTTP público não protege
credenciais em trânsito. Use HTTPS antes de atender usuários pela internet.
HTTPS: informe dois domínios diferentes, como `app.empresa.com.br` e
`api.empresa.com.br`. A API Oficial pode ter um terceiro domínio próprio.
DNS deve resolver antes de preparar bancos. Caddy publica 80/TCP e 443/TCP/UDP;
as portas HTTP diretas ficam em loopback. Certificados só são considerados
validados após resposta HTTPS com verificação TLS ativa. Erros distinguem DNS,
TLS, acesso de rede e respostas HTTP do proxy/aplicação. Não há correção automática
de firewall ou DNS do host.

O padrão administrativo é **admin@amanda.com.br / adminamanda**. Em produção, o
assistente permite personalização sem exigir comprimento mínimo ou complexidade.
Se optar explicitamente pelo padrão, altere-o antes de liberar acesso aos usuários.
Atualizações nunca redefinem contas; seed é exclusivo de projeto novo com tabela
Users vazia. Não use seed para reparar login.

Perfis PostgreSQL: 100 conexões/128MB, 200/256MB, 300/512MB ou personalizado
(20–500 conexões, 32MB–4GB de shared_buffers). O gerenciador consulta memória/CPUs
do daemon Docker e rejeita buffers acima de 25% da memória ou orçamento estimado
acima de 75%. É uma barreira conservadora, não um dimensionamento de carga;
considere as demais empresas/serviços da VPS. Nenhum perfil muda a senha de banco
existente por simples edição do ambiente.

## Serviços e isolamento

PostgreSQL, Redis, backend/Baileys, frontend e transcrição formam a base.
API Oficial, WuzAPI/WhatsMeow e RabbitMQ podem ser desabilitados na instalação;
RabbitMQ só tem consumidor neste contrato quando a Oficial está habilitada.
Sem seleção explícita em um JSON antigo, os três permanecem habilitados.
Pareamento, webhooks Meta, filas e contas externas precisam de configuração e
homologação próprias; container saudável não significa WhatsApp conectado.

Instalações novas usam `{empresa}_{servico}`: `amanda_backend`, `amanda_frontend`,
`amanda_postgres`, `amanda_redis`, `amanda_api_transcricao` e os opcionais
`amanda_api_oficial`, `amanda_wuzapi`, `amanda_rabbitmq`, `amanda_caddy`.
O projeto é normalizado para letras minúsculas/números/underscore, até 40 caracteres,
começando por letra/número. `ÁCERTI Filial-2` vira `acerti_filial_2`.
O nome comercial e o título preservam maiúsculas, espaços e acentos; identificadores
históricos de banco não mudam. O nome comercial é aplicado somente à empresa 1
recém-criada; o título usa a API autenticada de Settings.

`.amanda-installer/compose-names.json` complementa o Compose oficial com nomes
explícitos para todos os perfis. Chamadas manuais ao Compose também precisam
incluir esse segundo `-f`. O código Git da plataforma não é reescrito.
O gerenciador assume `{empresa}_installer` depois de identificar a instalação.
Antes disso, ferramentas usam `amanda_bootstrap_<pid>` e `_build`, removidos ao sair.
Jobs/manutenção usam prefixo da empresa e UUID, com `--rm`; agendadores usam
`{empresa}_scheduler_backup` e `_scheduler_update`.
`container_name` impede `--scale` para múltiplas réplicas: uma arquitetura de
réplicas exige convenção e planejamento explícitos.

Redes e volumes são próprios, por exemplo `acerti_default` e `acerti_postgres_data`.
Cada empresa precisa de diretório/projeto/portas diferentes. Não há compartilhamento
automático de bancos, credenciais, sessões, mídias ou backups. Portas são conferidas
contra containers existentes e por um helper Docker no namespace de rede do host.
Essa checagem requer Linux local; em Docker Desktop depende do suporte a host
networking e não certifica as regras de publicação do Windows. Há uma janela normal
entre checagem e bind; o erro final do Docker também impede declarar sucesso.
Dois Caddys não podem publicar 80/443 no mesmo IP. Use IPs/portas distintos ou
planeje um proxy Docker comum, que este instalador não gerencia automaticamente.

Estados antigos sem `company-v1` e adoções mantêm sua convenção de nomes.
Atualizar não troca projeto/volumes; alterações em nomes ou recursos declarados
são recusadas antes de parar a plataforma. Não edite a política no estado para
converter uma instalação: faça migração planejada, com backup e ambiente isolado.

## Instalação por JSON

Crie `$HOME/amanda-setup.json`, fora do diretório novo, com permissão 600:

```json
{
  "sourceUrl": "https://github.com/acerticonsulting/AMANDA",
  "companyName": "ACERTI",
  "project": "acerti",
  "frontendUrl": "http://localhost:3300",
  "backendUrl": "http://localhost:8800",
  "public": false,
  "edge": false,
  "adminEmail": "owner@example.com",
  "adminPassword": "SUBSTITUA-POR-SENHA-EXCLUSIVA",
  "options": {
    "appName": "AMANDA ACERTI",
    "supportPhone": "5511999999999",
    "pg": { "maxConnections": 100, "sharedBuffers": "128MB" },
    "services": { "official": true, "wuzapi": false, "rabbit": false },
    "officialPort": 6100,
    "testSmtp": true,
    "backendEnv": {
      "MAIL_HOST": "smtp.example.com",
      "MAIL_PORT": "465",
      "MAIL_SECURE": "true",
      "MAIL_USER": "sender@example.com",
      "MAIL_PASS": "SUBSTITUA-PELA-SENHA-SMTP",
      "MAIL_FROM": "sender@example.com"
    },
    "initialSettings": { "signupSmtpFromName": "ACERTI" }
  }
}
```

```sh
sh Instalador-AMANDA/instalador_single.sh install --dir "$HOME/acerti" --config "$HOME/amanda-setup.json"
```

Executar `install --config` é a confirmação automatizada; não há pergunta final.
Para IP, use URLs HTTP com o IP e `public: true`. Para HTTPS, use URLs HTTPS,
`edge: true` e, opcionalmente, `options.officialUrl` com o domínio da Oficial.
Não altere portas internas Docker. `options.databasePassword`, `masterPassword`,
`officialToken` e `wuzapiToken` são opcionais e exclusivos de instalação nova;
omiti-los usa geração criptográfica. Cifrões, aspas e caracteres reservados são
serializados com segurança; a senha Prisma recebe codificação URI separada.

`sourceToken` autentica somente a leitura da própria plataforma AMANDA. O backend usa Baileys público e não solicita token de terceiros. `buildToken` de configurações antigas é aceito para compatibilidade e ignorado. Não coloque tokens em URLs Git. Proteja/remova o JSON após configurar; não publique segredos nem a pasta privada.

## Configurar depois de instalar

Menu principal **12 — Configurações da plataforma** preserva os itens históricos
1–9 e acrescenta consulta segura (10), URL frontend/backend (11/12), portas/HTTPS
(13), Oficial (14), WuzAPI (15), Google OAuth (16), IA de IVR (17), teste SMTP (18),
pagamentos (19) e habilitação de serviços opcionais (20).
A Oficial também pode ser habilitada no menu principal 11; WuzAPI em Ferramentas 3.
Habilitação exige `HABILITAR <projeto> <serviço>`, faz backup e migrations, sem seed.
Se uma migration falhar, mantém o estado para **Retomar operação**.
Não se oferece desabilitação com exclusão automática de dados.

SMTP/integrações são arquivos de runtime. Mudanças de SMTP recriam apenas backend;
suporte recria frontend; rede/portas recriam os consumidores e proxy envolvidos.
O gerenciador valida Compose, guarda histórico privado, confere saúde e restaura
arquivos anteriores se a aplicação da configuração falhar. PostgreSQL exige backup
e reinício próprio. Não há rollback automático de schema após migrations.
Senhas existentes são preservadas ao deixar campos secretos em branco.
A consulta segura mostra o ambiente do instalador; títulos, empresa e configurações
alterados diretamente no banco/interface devem ser consultados no painel.

SMTP usa `MAIL_SECURE=true` para TLS implícito, normalmente 465; `false` usa SMTP
com negociação STARTTLS quando oferecida, normalmente 587. Não há opção fictícia
para obrigar STARTTLS no consumidor atual. `testSmtp`/menu 18 verificam conexão e
autenticação sem enviar e-mail; falha opcional gera aviso e preserva a plataforma.
Settings SMTP salvos na interface têm prioridade sobre variáveis de ambiente.
Google OAuth usa callback `${BACKEND_URL}/auth/google/callback`; registre a URL no
provedor. A chave de IA aqui cobre o fallback OpenAI do IVR, não todos os agentes.
VOZ/HUB exigem serviços externos; há configuração de URL/chave, sem provisionamento
inventado. GoFlow/Portainer não integram este Compose. Pagamentos usam Settings pela
API administrativa; verifique contas, sandbox, callbacks e cobrança no provedor.

## Atualização, backup e recuperação

```sh
sh Instalador-AMANDA/instalador_single.sh status --dir "$HOME/acerti"
sh Instalador-AMANDA/instalador_single.sh logs --dir "$HOME/acerti"
sh Instalador-AMANDA/instalador_single.sh backup --dir "$HOME/acerti"
sh Instalador-AMANDA/instalador_single.sh update --dir "$HOME/acerti"
sh Instalador-AMANDA/instalador_single.sh resume --dir "$HOME/acerti"
```

`doctor` verifica ferramentas/daemon; `stop`, `start` e `restart` operam a instância.
`adopt` registra somente uma instalação oficial já saudável e completa; não converte
PM2 ou bancos nativos. `unlock` recusa liberar lock de gerenciador ainda ativo.

Atualização exige Git sem alterações rastreadas e avanço de histórico. Constrói
imagens antes de parar gravadores; faz backup antes das migrations. Preserva URLs,
perfis, contas, chaves, dados, sessões e mídia. Não executa seed.
Backup inclui bancos habilitados, volumes utilizados, configuração privada,
revisão/imagens e SHA-256. Volumes de Caddy que já foram habilitados permanecem
preservados e incluídos mesmo quando HTTPS for desabilitado depois.
Guarde cópia protegida fora do servidor. Backup envolve interrupção temporária.

Menu 7 restaura backups gerenciados compatíveis; Ferramentas 4 restaura código,
imagens e dados juntos. Imports confiáveis `.sql`/`.dump`/`.backup` ficam em
`<dir>/imports/`; exigem confirmação, backup prévio e banco pertencente à instalação.
Não há restauração de bancos opcionais desabilitados. Backups com seleção de bancos,
volumes ou revisão incompatíveis exigem recuperação isolada com o contrato original.
Falhas de migration mantêm estado para retomada; voltar imagem não reverte schema.
Falha durante seed não permite repetição automática: preserve os dados e investigue.
Falha na preparação não autoriza apagar estado ou volumes para forçar seed.
Use o reconhecimento inicial ou `resume` no mesmo diretório. Configuração salva
validada é reutilizada; estado insuficiente ou conflitante recebe diagnóstico.

Configurações ficam em `platform/.env`, `.env.backend`, `.env.oficial` quando usado,
e arquivos legados `.secrets/github_token` preservados, sem uso no build. Estado, histórico, logs filtrados, acesso inicial e
backups ficam em `.amanda-installer/`, com arquivos privados em modo 600.
Não mova o diretório nem altere nomes de volumes para atualizar.
Receitas de `legacy/` estão bloqueadas antes do código histórico.

Para atualizar o código deste instalador, dentro do clone:

```sh
docker run --rm --name "amanda_source_update_$$" -v "$PWD:/repo" -w /repo alpine/git -c safe.directory=/repo pull --ff-only
sh ./instalador_single.sh
```

## Testes e limites

```sh
bash tests/validar_instalador.sh
```

A suíte local usa comandos simulados, sem instalar/migrar/restaurar plataformas.
O hook verifica o índice antes de cada commit. Há testes de integração adicionais
com o Compose real e o gerador oficial, em container sem rede e sem socket Docker.
Consulte [o plano](tests/PLANO_DE_TESTES.md) para executar e interpretar resultados.
Consulta de uma instalação existente é feita por `--plataforma`, com alvo explícito;
`--nomes-padronizados` confere nomes efetivos da convenção nova.

Build da imagem do gerenciador e parser Compose não certificam uma VPS.
Instalação completa, certificados públicos, login real, restauração representativa,
Meta/WhatsApp, SMTP do provedor, OAuth, push e pagamentos continuam sujeitos a
homologação em ambiente descartável e contas de teste.
A [matriz de configuração](docs/CONFIGURACAO_E_COMPATIBILIDADE.md) identifica cada
consumidor e compara a experiência com o instalador original.

### Retomar build interrompido

Após disponibilizar a correção na main da AMANDA, execute o comando resume no mesmo diretório da empresa. Na fase build, antes de qualquer seed, o gerenciador busca origin/main e aceita apenas avanço fast-forward de um checkout limpo. Mantém .env, credencial de origem, estado e volumes. Falha de rede ou histórico divergente interrompe a retomada sem reset. Fases posteriores não atualizam o código automaticamente.

O comando legado build-token apenas informa que a credencial não é necessária. A opção histórica de credenciais mantém sua posição no menu e configura somente o acesso à AMANDA.

### Reconhecimento antes do questionário

Ao escolher instalar, o gerenciador pede primeiro o nome técnico da empresa e
verifica `/home/deploy/{empresa}` antes das perguntas administrativas, URLs e
PostgreSQL. Essa empresa fica fixa nos dois assistentes. `--dir` mantém o caminho
explicitamente escolhido; não há migração automática entre `/root/amanda` e
`/home/deploy/amanda`.

| Diretório | Comportamento |
|---|---|
| Inexistente ou vazio | Instalação nova, com conta deploy criada/reutilizada. |
| Somente temporários privados conhecidos | Verifica nomes, tipos, proprietário, permissões e integridade; reutiliza escolhas salvas quando comprovadas. |
| Estado válido não concluído | Oferece retomar, diagnóstico sem segredos ou voltar; não reprovisiona. |
| Estado válido concluído | Oferece gerenciamento/atualização; não repete instalação ou seed. |
| Origem desconhecida, estado inválido ou links inseguros | Bloqueia antes de gravar configuração e explica o conflito. |

As escolhas confirmadas ficam em `.amanda-installer/setup.json`, privado (600),
com empresa, origem, caminho e checksum. A configuração é preparada em
`.amanda-installer/setup-files/`; um manifesto de hashes é registrado antes de
publicá-la. Um arquivo de destino existente só é aceito quando tem exatamente o
conteúdo esperado. Diferenças são preservadas e bloqueiam a continuação; não são
resolvidas por sobrescrita. Senhas e chaves já geradas não são regeneradas.
Esses arquivos contêm segredos: não os publique nem altere seus modos privados.

Estados antigos de preparação sem esse registro só avançam quando ambiente,
acesso administrativo, empresa, origem Git e Compose são coerentes e o Docker
comprova ausência dos recursos que seriam inicializados. Informação ausente,
clone incompleto sem fonte verificável, corrupção ou recursos sem prova de origem
exigem diagnóstico; nenhum dado é removido para contornar a proteção.

Para a empresa do exemplo, depois de atualizar o código do instalador:

```sh
sh instalador_single.sh resume --dir /home/deploy/amanda
```

Também é possível escolher instalar e informar `amanda`: o estado existente é
reconhecido antes do restante do questionário. Um `unlock --dir /root/amanda`
atua somente naquele diretório e não desbloqueia `/home/deploy/amanda`.
Falhas de build reutilizam configuração/código e cache de imagens; migrations
retomam seus checkpoints. Seed iniciado e não concluído continua bloqueado para
evitar repetição indiscriminada. Não remova diretórios, estado ou volumes.
