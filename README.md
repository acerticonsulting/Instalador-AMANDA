# Instalador AMANDA em Docker

O menu principal anterior (opções 1 a 11), as ferramentas e a gestão da API Oficial
foram restaurados. O menu aparece **antes** do download das ferramentas. Após uma
operação ele retorna ao menu; 0 permite sair. Configurações da plataforma e seleção
de instâncias estão também nas opções 12 e 13.

Consulte a [matriz de todos os menus](docs/MENUS_E_COMPATIBILIDADE.md), incluindo
as opções compatíveis com a plataforma atual.

O único requisito adicional no Linux é o Docker Engine com containers Linux,
BuildKit e acesso ao socket local. O ponto de entrada usa o `sh` do sistema.
Node, Git, Compose, Buildx, compiladores, migrations, bancos e microserviços
executam em containers. Não instalar Node, Python, PM2, PostgreSQL, Redis ou
Nginx no host para usar este instalador. Compose e Buildx já vêm no gerenciador.

Use Docker Engine atual, conexão a GitHub/registros e espaço/memória compatíveis
com a plataforma. O usuário precisa ter acesso ao Docker; root e sudo não são
requisitos. Sockets Unix locais, inclusive rootless, são aceitos; contextos TCP/SSH
remotos não são aceitos. O fluxo não depende de APT, systemd ou distribuição
específica. Isso não certifica kernels antigos ou todas as arquiteturas: as imagens
utilizadas precisam suportar a arquitetura do servidor.

## Baixar e instalar sem Git no host

Na pasta onde deseja guardar o instalador:

```sh
docker run --rm -v "$PWD:/workspace" -w /workspace alpine/git clone https://github.com/alansuporteamanda/Instalador-AMANDA.git instalador
sh instalador/instalador_single.sh install --dir "$HOME/amanda"
```

O endereço histórico do instalador foi preservado. Na pergunta **Link da
plataforma**, informe obrigatoriamente:

```text
https://github.com/acerticonsulting/AMANDA
```

Também são aceitas terminações `.git` e `/`. Outros repositórios, links com
credenciais e entrada vazia são recusados. O código vem da branch `main`.
Os Dockerfiles e o Compose da raiz da plataforma são usados diretamente.

O menu permite escolher URLs, publicação de portas, HTTPS e acesso administrativo.
O acesso inicial padrão é **admin@amanda.com.br / adminamanda**; pode ser
personalizado antes de criar o banco. Atualizações preservam as contas.
Logo AMANDA e cores `#9905D8` / `#8A00FA` vêm do código oficial;
personalizações salvas pela plataforma continuam tendo prioridade.

No modo local, mantenha `http://localhost:3000` e `http://localhost:8080`.
Para acesso pela rede, informe URLs com o endereço do servidor e confirme a
publicação de portas. Para HTTPS, habilite Caddy e informe dois domínios DNS
diferentes já apontados para o servidor, com portas 80/443 disponíveis.
Caddy permanece desabilitado no modo local.

## O que é instalado

| Serviço | Execução/configuração |
|---|---|
| Frontend | Imagem construída do código oficial; porta local 3000 |
| Backend / Baileys | Node na imagem oficial; porta local 8080 |
| PostgreSQL | Banco persistente; sem porta publicada |
| Redis | Persistência AOF; sem porta publicada |
| Transcrição | Python e dependências dentro da imagem |
| API Oficial | Imagem própria, banco api_oficial; porta local 6000 |
| WuzAPI / WhatsMeow | Imagem indicada pelo Compose; porta local 8090 |
| RabbitMQ | Broker interno persistente |
| Caddy (opcional) | HTTPS em container, portas 80/443 |

Os perfis `official,whatsmeow,rabbit` ficam habilitados. Pareamento WhatsApp,
contas Meta, SMTP, Google e integrações externas exigem suas respectivas contas.
GoFlow/HUB/VOZ externos não têm implementação neste Compose e não são instalados
por imagens inventadas. Transcrição e conectores locais usam a rede interna Docker.

## Configuração sem interação

Crie um JSON privado **fora** da pasta nova de instalação, por exemplo
`$HOME/amanda-setup.json`:

```json
{
  "sourceUrl": "https://github.com/acerticonsulting/AMANDA",
  "project": "amanda",
  "frontendUrl": "http://localhost:3000",
  "backendUrl": "http://localhost:8080",
  "public": false,
  "edge": false,
  "adminEmail": "admin@amanda.com.br",
  "adminPassword": "adminamanda"
}
```

```sh
sh instalador/instalador_single.sh install --dir "$HOME/amanda" --config "$HOME/amanda-setup.json"
```

Omitir e-mail/senha mantém o padrão. Campos opcionais `sourceToken` e `buildToken`
são distintos: o primeiro autentica a leitura da plataforma privada; o segundo
dá acesso ao conector privado e é entregue somente pelo segredo BuildKit oficial.
Não colocar tokens em links Git. Sem acesso válido ao conector, o build falha
e a instalação não é declarada concluída. Proteja o JSON (modo 600), retire sua
cópia após configurar e não o versione.

O gerador oficial cria chaves aleatórias dentro do gerenciador. Configurações
ficam em `amanda/platform/.env` e nos opcionais `.env.backend` / `.env.oficial`;
o segredo de build fica em `platform/.secrets/github_token`. Estado, logs filtrados,
credenciais escolhidas e backups ficam em `amanda/.amanda-installer/`, com arquivos
privados em modo 600. A senha inicial escolhida fica em `admin-access.json` nessa
pasta. Não compartilhar essa pasta nem os backups.

## Operar e atualizar

Use sempre o mesmo `--dir` e projeto. O diretório é montado no gerenciador no
**mesmo caminho absoluto do host**, necessário aos bind mounts do Compose.
Não mover a instalação nem trocar nomes de volumes/projeto como atualização.

```sh
sh instalador/instalador_single.sh doctor
sh instalador/instalador_single.sh status --dir "$HOME/amanda"
sh instalador/instalador_single.sh logs --dir "$HOME/amanda"
sh instalador/instalador_single.sh backup --dir "$HOME/amanda"
sh instalador/instalador_single.sh update --dir "$HOME/amanda"
sh instalador/instalador_single.sh stop --dir "$HOME/amanda"
sh instalador/instalador_single.sh start --dir "$HOME/amanda"
sh instalador/instalador_single.sh restart --dir "$HOME/amanda"
```

Atualize o próprio instalador com Git em container:

```sh
docker run --rm -v "$PWD/instalador:/repo" -w /repo alpine/git -c safe.directory=/repo pull --ff-only
```

`update` exige código sem alterações rastreadas e aplica somente avanço de histórico.
Constrói imagens antes da interrupção, pausa gravadores e faz dump dos dois bancos
mais arquivo dos volumes de mídia, sessões, Redis, RabbitMQ e certificados.
Copia configurações privadas e registra imagens/revisão. Aplica migrations,
inicia e verifica os oito serviços. **Não executa seed nem troca configurações.**
O backup causa interrupção temporária. Guarde cópia protegida fora do servidor.

`stop` preserva volumes. O menu 9 permite remover containers preservando dados ou remover os volumes com backup obrigatório e confirmação digitada; código, configurações e backups permanecem preservados.
`logs` mostra os últimos 200 registros, filtrando credenciais conhecidas;
o log operacional é `.amanda-installer/install.log`. Logs da aplicação podem conter
dados de atendimento e devem permanecer privados.

## Retomada, adoção e recuperação

```sh
sh instalador/instalador_single.sh resume --dir "$HOME/amanda"
sh instalador/instalador_single.sh build-token --dir "$HOME/amanda"
```

`resume` repete build/migrations interrompidos e não repete seed concluído.
Se o próprio seed falhar, a retomada automática é recusada: preservar volumes e
revisar os registros do Sequelize antes da correção manual. Nunca usar seed sobre
uma instalação existente para corrigir login.

Falha de build/backup em atualização restaura referências de imagens/código anteriores.
Falha durante migrations mantém a aplicação parada; `resume` tenta concluir as
migrations da mesma revisão. Não voltar ao código antigo contra esquema parcialmente
migrado. Para restauração integral, usar backup completo em ambiente isolado,
revisão/imagens registradas e `pg_restore` no container PostgreSQL; validar bancos,
arquivos e acesso antes de substituir a instalação. O menu 7 restaura backups gerenciados com hashes; Ferramentas 4 recupera código/imagens/dados juntos, 9 restaura Redis, 23 restaura WuzAPI e 10/12 importam arquivos SQL ou pg_dump custom. Todas exigem confirmação e backup prévio.

Uma instalação **já baseada no Compose oficial**, completa e saudável, pode ser
registrada sem seed nem mudança de configurações/volumes:

```sh
sh instalador/instalador_single.sh adopt --dir /caminho/da/AMANDA
```

A adoção pede o link autorizado e verifica Git, configuração, serviços e HTTP.
Não migra automaticamente instalações antigas com PM2, banco no host, Compose gerado
ou componentes independentes. Essas exigem planejamento de migração com backup.
Scripts antigos foram preservados em `legacy/` para referência e regressão;
não são chamados pelo ponto de entrada oficial.

Se uma interrupção forçada deixar lock, verifique o gerenciador anterior e use
`unlock --dir ...`; a operação recusa remover lock de gerenciador ainda ativo.

## Validação de desenvolvimento

```sh
bash tests/validar_instalador.sh
```

Git/Bash/utilitários são ferramentas da suíte de desenvolvimento, não requisitos do
instalador em produção. Os testes do gerenciador usam Node 22 em container sem rede
e simulam Docker/Git/migrations. Consulte [o plano](tests/PLANO_DE_TESTES.md) e
[o registro de continuidade](docs/01-contexto-para-ia.md). Instalação completa em VPS
limpa, certificados públicos e contas externas exigem homologações separadas;
testes simulados não certificam esses cenários.

## Formulário completo e uso após a atualização

No menu 1, além de URLs, proxy e credenciais iniciais, configurar título da
aplicação, número de suporte, senha PostgreSQL, senha MASTER, portas API Oficial /
WuzAPI, domínio HTTPS opcional da API Oficial, SMTP e Facebook App ID/App Secret.
Senhas vazias mantêm geração aleatória. A conta Linux Deploy não é criada: todos
os processos continuam em Docker. Título é salvo pela API administrativa, suporte
é repassado em runtime e as demais opções chegam aos serviços consumidores reais.

Para instalações existentes, menu 12 configura identidade, suporte, SMTP, Facebook,
URLs/portas/SSL, integrações, push, tokens e performance PostgreSQL. Mudar senha do
banco ou MASTER só é oferecido na instalação nova; não se rotacionam senhas/chaves
existentes silenciosamente. A opção 30 em Ferramentas atualiza credenciais e depois
executa atualização oficial com backup; o repositório continua restrito à AMANDA.

O menu 10 oferece autenticação GHCR e agendamento em container. Watchtower foi
substituído pelo atualizador que aplica build, backup e migrations em conjunto;
um Watchtower que apenas troca containers não sincroniza o esquema da plataforma.
O agendador roda diariamente na hora UTC escolhida, mantém último sucesso/tentativa
na pasta privada e usa o lock da instância para não concorrer com outra operação.
Portainer e instaladores externos VOZ/HUB não são oferecidos: não fazem parte do Compose da plataforma.

Se o Docker apresentar permission denied no socket, use a conta autorizada ao
Docker ou execute o comando com sudo. O instalador não altera permissões/grupos.
O build das ferramentas usa Buildx **dentro do container**, inclusive se o plugin
não estiver instalado no host; não é necessário instalar pacotes adicionais.

Para atualizar o clone existente, já dentro da pasta Instalador-AMANDA:

```sh
docker run --rm -v "$PWD:/repo" -w /repo alpine/git -c safe.directory=/repo pull --ff-only
sudo sh ./instalador_single.sh
```

O sudo só é necessário quando a conta atual não acessa Docker. Use `--dir` para
manter o diretório da instalação anterior, inclusive quando trocar a conta usada.
Adoção não converte automaticamente a antiga instalação no host.

Importações: coloque o arquivo confiável .sql/.dump/.backup em `<dir>/imports/`.
O nome de banco é restrito a amanda ou api_oficial. SQL de cluster e comandos
psql de troca de banco/shell são recusados. A importação faz backup, para gravadores,
recria somente o banco escolhido, aplica migrations e verifica os serviços; não faz
seed. Falhas mantêm os apps parados e permitem repetir a mesma importação. Para
restaurações gerenciadas, escolha a mesma restauração interrompida. PostgreSQL
precisa estar acessível para preservar o estado atual antes da substituição.
Backups de outra revisão devem usar rollback completo, não restauração parcial do
banco. Mudanças no conjunto de volumes exigem recuperação isolada com o contrato
original. Backups antigos sem hashes não são restaurados automaticamente.

VOZ/HUB não são instalados pelo gerenciador. Apenas as integrações de URL/chave
que existem na plataforma permanecem no menu 12. GoFlow foi retirado dos menus.

## Visual e sequência de instalação

O banner em blocos AMANDA, o roxo #8B5CF6, os destaques e a apresentação das
perguntas foram recuperados do histórico de outubro/2026 (3e6b5cf). O visual
aparece no menu inicial, nos submenus e em cada pergunta da instalação.
Terminais sem cor, TERM=dumb e NO_COLOR recebem texto simples.

1. Escolha IP/local ou domínios HTTPS (Caddy em container).
2. Informe host e portas, ou os domínios backend e frontend.
3. Mantenha ou personalize o acesso administrativo padrão.
4. Informe empresa/projeto, senhas PostgreSQL e MASTER, título e suporte.
5. Informe Facebook, tokens separados, link obrigatório AMANDA, portas APIs e SMTP.
6. Revise URLs, projeto e administrador; confirme para iniciar. Senhas não aparecem na revisão.

Contas Linux Deploy, PM2, Nginx no host e escolha de serviços nativos não são
reintroduzidos. A numeração histórica é mantida nos itens compatíveis; os números
dos componentes removidos não são reutilizados. ENTER permite ler o resultado
antes de voltar ao menu principal. Para atualizar este instalador usando apenas Docker:

```sh
cd ~/Instalador-AMANDA
sudo docker run --rm -v "$PWD:/repo" -w /repo alpine/git -c safe.directory=/repo pull --ff-only
sudo sh ./instalador_single.sh
```

Use sudo somente se sua conta precisar dele para acessar o Docker.
