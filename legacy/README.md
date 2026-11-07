> ARQUIVO HISTÓRICO: não executar estas receitas no fluxo atual. Consulte o README da raiz; os scripts e tools antigos estão em legacy/.

# 🚀 Instalador Oficial AMANDA

Suite oficial de instalação, atualização e gerenciamento 100% Docker para a plataforma **AMANDA**.

Ao abrir `instalador_single.sh`, é obrigatório informar
`https://github.com/acerticonsulting/AMANDA`. O instalador encerra antes das
operações no host quando a entrada é vazia ou aponta para outro repositório.
O mesmo endereço com `.git` ou barra final também é aceito. URLs com credenciais,
query string, outros protocolos ou caminhos adicionais são rejeitadas. O download
valida novamente o endereço, inclusive em instalações retomadas; configurações
antigas precisam apontar para o repositório autorizado. Essa validação restringe
a origem do código; o acesso a repositórios privados continua exigindo autenticação.

### Validação depois de alterações

Execute `bash tests/validar_instalador.sh` antes de cada commit. Para ativar a
verificação automática neste clone, execute `bash tests/ativar_validacao.sh`.
O [plano de testes](tests/PLANO_DE_TESTES.md) descreve a cobertura, os testes de
homologação e o modo `--plataforma` para consultar uma instalação Docker existente.

---

### 📥 Download do Instalador & Primeira Instalação:

Execute no terminal da sua VPS Linux (Ubuntu / Debian como root):

```bash
sudo apt update && sudo apt install -y git && git clone https://github.com/alansuporteamanda/Instalador-AMANDA.git instalador && cd instalador && sudo chmod -R 775 *.sh tools/*.sh && sudo ./instalador_single.sh
```

---

### 🔄 Para Abrir Novamente ou Atualizar o Instalador:

```bash 
cd /root/instalador && git pull && sudo chmod -R 775 *.sh tools/*.sh && sudo ./instalador_single.sh
```

---

### 🧪 Homologação com GHCR e Watchtower

Depois de instalar a plataforma, abra o instalador, escolha a instância e selecione a opção **10 - Homologação GHCR / Configurar Watchtower**. A opção **9** continua reservada à desinstalação. Essa opção:

- Confirma antes de trocar o código da plataforma para a branch `v1.0131012a`; exige que o repositório esteja sem alterações locais.
- Solicita o usuário GitHub e um token com permissão `read:packages`. O token é digitado sem aparecer na tela e não é gravado no `.env` nem no repositório.
- Salva as credenciais do Docker em `/root/.docker/config.json` com permissão restrita e configura `APP_VERSION` e `DOCKER_CONFIG_FILE` no `.env` do Compose.
- Valida a configuração, baixa e aplica somente as imagens de backend, frontend, transcrição e GoFlow. PostgreSQL, PgBouncer, Redis e WuzAPI não são atualizados.
- Pergunta separadamente se deseja iniciar o Watchtower. Se aceitar, ele consulta novas imagens no intervalo configurado (30 minutos por padrão); se não, permanece desligado.

Use essa opção somente na VPS de homologação: ela troca a branch ativa da plataforma e aplica a versão publicada no GHCR. O token deve pertencer a uma conta com acesso de leitura aos pacotes da organização. Alertas ainda precisam de um provedor configurado em `WATCHTOWER_NOTIFICATION_URL`.

Na opção **2 - Atualizar**, o instalador mantém a branch de homologação quando ela está ativa e atualiza apenas os quatro serviços publicados no GHCR, sem recompilá-los localmente.

Para recuperar uma instalação padrão existente após a publicação de correções na branch `main`, atualize e abra novamente o instalador e escolha **2 - Atualizar**. O instalador reconstruirá os serviços da instância selecionada e verificará se o backend e a API Oficial permanecem em execução; em caso de falha, exibirá os logs em vez de informar sucesso. Não remova volumes nem altere o histórico de migrações manualmente.

---

### 🌟 Destaques da Suite Oficial v1.0.0:
- **100% Docker-Only:** Orquestração completa de 9 contêineres otimizados (PostgreSQL 17, PgBouncer, Redis 7.4, AMANDA Backend Node 20 + Rust Nativo, AMANDA Frontend React, WhatsApp Meta Cloud API Oficial, WuzAPI WhatsMeow, Go Campaign Dispatcher e API de Transcrição).
- **Modo Sem Domínio (Apenas IP / Localhost):** Suporte nativo para testes locais, WSL ou VPS sem domínio público, com acesso direto pelas portas HTTP (3000, 8080 e 6000) e bypass automático de checagens de DNS e SSL.
- **Gerenciador de URLs Interativo:** Permite inspecionar e alterar individualmente as URLs de todos os microsserviços, com teste de conectividade (DNS/Ping/HTTP) e reinício automático imediato dos contêineres afetados.
- **Identidade Visual Roxa AMANDA:** Interface moderna harmonizada na paleta roxa oficial (`#9905D8` no tema claro / `#8A00FA` no tema escuro).
- **Acesso inicial padrão:** `admin@amanda.com.br` / `adminamanda`. Na instalação é possível escolher outro e-mail e senha; a senha personalizada é digitada e confirmada sem aparecer. A escolha é passada ao seed com `AMANDA_ADMIN_EMAIL` / `AMANDA_ADMIN_PASSWORD`. Contas existentes são preservadas nas atualizações, e a senha do painel é independente da senha do banco/deploy e dos tokens das APIs.
- **Compatibilidade do acesso inicial:** use a versão atualizada da plataforma AMANDA. O fluxo Docker verifica o suporte ao seed configurável e interrompe versões antigas, em vez de anunciar credenciais que não foram aplicadas.
- **Banco de Dados Oficial:** `DB_USER=amanda` / `DB_NAME=amanda` / `Acertitech13@`.
- **Repositório da Aplicação:** exige o endereço [acerticonsulting/AMANDA](https://github.com/acerticonsulting/AMANDA) na abertura e valida a origem antes do download.
