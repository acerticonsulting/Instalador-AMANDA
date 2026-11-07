# Instalador AMANDA em Docker

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
docker run --rm -v "$PWD/instalador:/repo" -w /repo alpine/git pull --ff-only
```

`update` exige código sem alterações rastreadas e aplica somente avanço de histórico.
Constrói imagens antes da interrupção, pausa gravadores e faz dump dos dois bancos
mais arquivo dos volumes de mídia, sessões, Redis, RabbitMQ e certificados.
Copia configurações privadas e registra imagens/revisão. Aplica migrations,
inicia e verifica os oito serviços. **Não executa seed nem troca configurações.**
O backup causa interrupção temporária. Guarde cópia protegida fora do servidor.

`stop` preserva volumes. Não existe desinstalação destrutiva neste fluxo.
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
arquivos e acesso antes de substituir a instalação. Não há restauração automática
destrutiva.

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

Bash/utilitários são ferramentas da suíte de desenvolvimento, não requisitos do
instalador em produção. Os testes do gerenciador usam Node 22 em container sem rede
e simulam Docker/Git/migrations. Consulte [o plano](tests/PLANO_DE_TESTES.md) e
[o registro de continuidade](docs/01-contexto-para-ia.md). Instalação completa em VPS
limpa, certificados públicos e contas externas exigem homologações separadas;
testes simulados não certificam esses cenários.
