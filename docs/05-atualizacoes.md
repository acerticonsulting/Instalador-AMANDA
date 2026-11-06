# Atualizações e homologação

## Caminho principal Docker

A opção 2 seleciona a instância e detecta a branch da plataforma. Fora da branch especial de homologação, oferece canal `main`, `davi-alteracoes`, `alan-alteracoes` ou branch personalizada. Nomes e disponibilidade remota são os declarados no código local, não verificados no GitHub.

O caminho padrão sincroniza código, prepara configurações auxiliares e tenta validar Compose. Havendo configuração inválida, contém fallback `git checkout -f docker-compose.yml`. Depois realiza pull e reconstrói explicitamente `backend frontend api_transcricao goflow_dispatcher` com recriação. Executa migrations Sequelize e, quando localiza API Oficial no projeto, migrations Prisma; verifica containers críticos.

Não interpretar a mensagem de atualização de “todos os contêineres” como reconstrução individual de todos os serviços. A lista explícita de `up` é mais restrita; `pull` sem lista pode consultar imagens de outros serviços. A atualização da API Oficial possui caminho próprio no menu 11.

## Preservação e Git

Há funções de sincronização no monólito e na biblioteca `tools/git_sincronizar_repositorio.sh`. A biblioteca documenta `fetch` e `reset --hard`, tratamento de autenticação e preservação de arquivos locais em caminhos específicos. Não chamar essas funções sem revisar sua implementação e o alvo; podem descartar alterações rastreadas.

Antes de atualização real, registrar commit, branch, estado de arquivos, imagem e backup. Um backup do código não substitui banco, mídias ou estado dos conectores. Não inferir rollback automático de uma opção chamada atualização.

## Homologação GHCR

A opção 10 usa a branch literal `v1.0131012a`. Exige confirmação, repositório oficial reconhecido, usuário deploy e árvore Git limpa. Solicita acesso GHCR com `read:packages`, faz login por entrada protegida e mantém configuração Docker em `/root/.docker/config.json`, com diretório 700 e arquivo 600.

Após trocar branch, exige Compose e ambiente, confere quatro imagens e labels de atualização. Configura `APP_VERSION`, `DOCKER_CONFIG_FILE` e intervalo padrão de 1800 segundos. Valida Compose com perfil `auto-update`, baixa e inicia sem build apenas:

- backend;
- frontend;
- api_transcricao;
- goflow_dispatcher.

PostgreSQL, PgBouncer, Redis e WuzAPI não integram essa lista de atualização. A API Oficial também não faz parte dos quatro serviços. O Watchtower é uma confirmação separada; notificações dependem de `WATCHTOWER_NOTIFICATION_URL`.

A opção 2 reconhece essa branch e mantém o fluxo GHCR com árvore limpa, pull fast-forward, imagens sem build, migrations do backend e verificação do backend. Não assumir que ativar Watchtower por si só executa os mesmos passos de migração da atualização manual; validar como as imagens e seus entrypoints tratam schema.

## Atualizadores alternativos

`atualizador_remoto.sh`, `atualizador_remoto_FAST.sh`, `atualizador_fast_sistema.sh` e `atualizador_pro.sh` permanecem na árvore. Contêm caminhos históricos de build, integração e manutenção. Não substituir a opção Docker por um deles apenas por prometer ser mais rápido. Rastrear chamador, modo de implantação, backup e processo alvo antes de escolher.

`tools/roolback_versao.sh` conserva esse nome com erro de grafia. É uma ferramenta distinta, não uma garantia de reversibilidade de migrations. Voltar imagem ou commit pode deixar código incompatível com o banco atual.
