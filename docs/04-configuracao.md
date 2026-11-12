> Referência histórica: descreve os scripts preservados em legacy/. Para o instalador Docker-only atual, consulte ../README.md e 01-contexto-para-ia.md. Os caminhos antigos de scripts/tools recebem o prefixo legacy/.

# Configuração, portas e URLs

## Persistência segura existente

`tools/mf_operacoes_seguras.sh` oferece `mf_carregar_config` e `mf_gravar_config`. O leitor aceita chaves permitidas e trata os valores como dados, sem `source` ou `eval`; valida o arquivo completo antes de aplicar os campos. O gravador usa temporário, rejeita multilinha, aplica modo 600 e substitui o destino. Rejeita links simbólicos nos arquivos de configuração tratados.

Ao acrescentar uma configuração, conferir a allowlist `mf_chave_config_permitida`, o gravador, os leitores legados, os consumidores e os testes. Nem todo leitor histórico usa o mesmo parser. Não trocar o leitor por `source arquivo` para facilitar expansão de valores.

## Camadas distintas

| Camada | Conteúdo |
| --- | --- |
| VARIAVEIS_INSTALACAO* | Escolhas do instalador, nome da instância, URLs, portas, canal e acesso |
| .env do diretório Compose | Interpolação da stack e variáveis dos serviços |
| backend/.env | Configuração da aplicação principal |
| frontend/.env | URL e variáveis usadas pelo build React |
| api_oficial/.env | Banco, porta interna e integração Meta/backend |
| /root/.docker/config.json | Autenticação Docker/GHCR no fluxo de homologação |

Instalação e ferramentas podem copiar ou reescrever essas camadas. Confira qual arquivo cada consumidor lê; editar apenas uma cópia não assegura propagação. Não imprimir `docker compose config` completo em relatórios: a expansão pode revelar segredos. Para validação sintática, usar `config --quiet` quando disponível.

## Portas padrão de configuração

| Serviço | Chave de estado | Padrão |
| --- | --- | --- |
| Frontend | frontend_port / PORT_FRONTEND | 3000 |
| Backend | backend_port / PORT_BACKEND | 8080 |
| PostgreSQL | PORT_DB | 5432 |
| PgBouncer | PORT_PGBOUNCER | 6432 |
| Redis | PORT_REDIS | 6379 |
| Transcrição | PORT_TRANSCRIBER | 4002 |
| WuzAPI | PORT_WUZAPI | 8090 |
| GoFlow | PORT_DISPATCHER | 8095 |
| API Oficial | PORT_APIOFICIAL | 6000 |

São pontos de partida, não um inventário de portas abertas. `resolver_portas_automaticas` pode escolher outra porta quando houver ocupação. Distinguir porta publicada no host de porta interna do serviço. Por exemplo, `http://backend:8080`, `redis:6379` e `postgres:5432` são destinos dentro da rede Docker; `localhost` em um container aponta para esse próprio container.

## URLs e proxy

O modo sem domínio usa IP ou localhost e ignora etapas de DNS/SSL. Os demais caminhos permitem Nginx ou Traefik. O gerenciador de URLs testa conectividade e aplica reinício de serviços afetados; não é uma consulta sem efeitos.

Mudar domínio pode exigir backend, frontend, ambiente do Compose, callbacks, CORS, webhooks, proxy e certificados. A URL exibida no terminal não comprova que todas essas camadas foram sincronizadas. Validar a URL de runtime do frontend e as conexões HTTP e Socket.IO após a alteração.

## Segredos

O código e o README contêm credenciais padrão e caminhos de gravação de tokens. Os valores não são reproduzidos aqui. Restringir acesso aos arquivos e backups. Uma futura correção de segurança deve ser explícita e respeitar a instrução do AGENTS para preservar acesso Git e remotos enquanto não houver autorização de substituição.

O catálogo de chaves é uma extração de nomes, sem valores, e não representa sozinho um schema de configuração obrigatório.
