# Instalação e estado persistente

## Ambiente de destino

O fluxo é destinado a VPS Linux Ubuntu ou Debian com privilégios root. Pode instalar pacotes, Docker, Compose, usuário deploy, timezone, firewall e proxy. A compatibilidade exata por versão de distribuição e arquitetura precisa da matriz de homologação; comentários e detecção de distribuição não certificam todas as combinações.

No Windows local, usar Git Bash somente para a suíte isolada. Não executar o provisionamento completo como teste do repositório.

## Entrada principal

Desde o ajuste de 06/11/2026, a entrada exige que o operador informe
`https://github.com/acerticonsulting/AMANDA` antes das consultas de rede,
instalação de pacotes ou abertura do menu. Não há valor padrão para entrada
vazia. `tools/mf_repositorio_amanda.sh` valida o endereço e normaliza o clone
para HTTPS com `.git`; a validação é repetida no início de `baixa_codigo_base`,
inclusive quando a configuração é recuperada de uma instalação anterior.
O questionário usa o endereço confirmado, substituindo a antiga escolha livre.
O fluxo não muda tokens, volumes ou instalações existentes automaticamente.

O README orienta baixar o repositório, entrar na pasta e executar `sudo ./instalador_single.sh`. A opção 1 chama `verificar_arquivos_existentes`, que decide o tratamento de instalação nova ou existente. O menu não chama diretamente a rotina nativa `instalacao_base`.

| Opção | Função principal | Efeito |
| --- | --- | --- |
| 1 | verificar_arquivos_existentes | Entrada para instalar ou tratar estado existente |
| 2 | atualizar_amanda_docker | Atualizar instância selecionada |
| 3 | gerenciar_urls_sistema | Alterar URLs e serviços afetados |
| 4 | menu_status_reiniciar_containers | Consultar e reiniciar |
| 5 | menu_logs_containers | Acompanhar logs |
| 6 | exec_backup_banco_docker | Dump do banco principal |
| 7 | exec_restaurar_banco_docker | Importação SQL |
| 8 | menu_ferramentas | Ferramentas adicionais |
| 9 | menu_desinstalar_plataforma | Desinstalar com decisão sobre dados |
| 10 | configurar_watchtower_homologacao | Branch GHCR e Watchtower |
| 11 | menu_gerenciar_api_oficial | Ciclo de vida da API Oficial |
| 0 | sair | Encerrar |

## Fluxo Docker de instalação

`instalar_amanda_docker_stack` coleta dados e DNS, proxy e portas, confirma e grava variáveis. Em seguida prepara a VPS, o usuário e o Docker; resolve conflitos, escolhe canal e baixa o código. Detecta o diretório Compose, escreve ambiente e configurações auxiliares, adapta o YAML e prepara volumes.

O fluxo usa `docker compose up -d --build`; em falha, tenta nova limpeza e ajuste de portas antes de `up -d`. Aguarda PostgreSQL com até trinta tentativas de dois segundos, executa migrations e seeds do backend, reinicia e configura o proxy quando aplicável. Verifica containers críticos antes de salvar etapa 21 e anunciar conclusão.

Seeds e sincronização de credenciais iniciais são ações reais sobre os dados. Não reaplicar esse caminho numa instalação existente para corrigir apenas um erro de build.

## Diretórios

Raiz usual da instância: `/home/deploy/<empresa>`. `localizar_diretorio_compose` procura, nesta ordem:

1. `<raiz>/amanda/docker-compose.yml`.
2. `<raiz>/docker-compose.yml`.
3. `<raiz>/multiflow/docker-compose.yml`.
4. Primeiro `docker-compose.yml` encontrado até profundidade dois.
5. A raiz como fallback, mesmo sem arquivo encontrado.

Portanto, o retorno dessa função não garante que exista Compose válido. Verificar arquivo e projeto antes de usar o diretório.

## Arquivos de estado

`VARIAVEIS_INSTALACAO` contém configuração global de compatibilidade; `VARIAVEIS_INSTALACAO_INSTANCIA_<empresa>` é a cópia individual. A raiz do instalador é fixada por `MF_INSTALADOR_ROOT` para as funções de persistência analisadas. Há caminhos históricos de busca em `/root` e na árvore de deploy.

`ETAPA_INSTALACAO` e `ETAPA_INSTALACAO_<empresa>` registram progresso. `carregar_etapa` aceita apenas número; conteúdo inválido reinicia o controle em zero. Isso é um checkpoint, não inspeção do estado real. Nunca inferir saúde do banco ou integridade dos containers por esse número.

`ALTA_PERFORMANCE_MODE` também pode influenciar configuração. Os arquivos locais de variáveis e etapas encontrados foram apenas inventariados; seus valores não integram os documentos e não comprovam uma instalação ativa nesta máquina.
