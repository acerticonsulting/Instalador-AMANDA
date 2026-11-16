# URLs próprias e APIs independentes

O painel inicial dos menus 11/12 é compacto e colorido conforme o estado real.
Saúde, instalação confirmada e HTTPS validado são verdes; pendências amarelas;
falhas vermelhas; ausência cinza. NO_COLOR, TERM=dumb e saída redirecionada
desativam cores. A opção 3 apresenta o relatório técnico completo.

Instalar pede somente um domínio público (hostname ou origem HTTPS), seguido de
validação e confirmação. O instalador gerencia automaticamente endpoints/portas
internas. Para uma API existente, use 8 — Configurar URL / HTTPS; ENTER mantém
a URL sem reaplicar configurações. A opção 1 nunca reinstala uma API encontrada.

Em 3, digite VERIFICAR HTTPS para consultar DNS/TLS/HTTP sem reconfigurar serviços.
O resultado da verificação é registrado no estado da empresa. DNS compatível
não implica TLS validado; abrir o menu não executa a verificação. URL antiga
sem registro HTTPS correspondente aparece como NÃO VERIFICADO.

Selecione a empresa reconhecida antes de entrar no menu 11 (API Oficial) ou 12
(WhatsMeow/WuzAPI). O cabeçalho informa projeto e diretório reais. Status consulta
containers por labels de projeto e serviço; uma declaração no Compose não conta
como instalação. São apresentados imagem/ID, estado/healthcheck, uptime, portas,
volumes, backup e revisão, sem valores de tokens. HTTPS é registrado com data;
ausência de validação aparece como não verificado.

Os dois menus possuem instalar, atualizar, diagnóstico, iniciar/reiniciar, parar,
logs limitados, sincronizar integração interna, domínio próprio e remoção do
container. Atualizar API Oficial significa **atualizar plataforma AMANDA (inclui
API Oficial)**, com a confirmação do atualizador existente. WuzAPI atualiza só
sua imagem, sem migrations, utilizando ID imutável e override privado por empresa;
rollback não retagueia imagens compartilhadas. Um rollback malsucedido deixa
checkpoint explícito para diagnóstico, sem apagar recursos.

## Instalar e publicar

1. Escolha instalar. Confirme empresa, diretório, perfil, volume, porta e presença
   de token. A URL solicitada pertence somente à API selecionada.
2. Informe um domínio, como `oficial.exemplo.com.br`, ou uma origem HTTPS completa.
   O campo normaliza para HTTPS; recusa porta explícita, caminho, usuário/senha,
   query e fragmento. Domínios de frontend, backend e outras APIs/empresas
   reconhecidas não podem ser reutilizados.
3. Sem Caddy, escolha `INTERNO` e confirme `CONFIRMAR INTERNO`. Não é criada uma
   URL pública. A publicação WuzAPI fica bloqueada mesmo com Caddy: a imagem
   configurável não garante um contrato homologado de autenticação por rota e
   bloqueio de endpoints administrativos. Não contorne essa restrição com proxy.
4. Para API Oficial pública, a pré-validação existente verifica DNS e portas
   80/443, reconhecendo o Caddy do mesmo projeto. DNS incorreto/inconclusivo
   permite guardar uma proposta mediante confirmação; não altera Caddy, não
   constrói imagem, não cria banco e não tenta ACME. Reabra instalar/domínio para
   corrigir a URL ou execute `resume` depois de corrigir o DNS.
5. Digite `HABILITAR empresa api_oficial` ou `HABILITAR empresa wuzapi`.
   Há preparação somente da API, backup consistente (com pausa temporária dos
   gravadores), verificação de ownership e aplicação da integração no backend.
   Não são executados seeds nem migrations Sequelize. Só a API Oficial executa
   inicialização não destrutiva do próprio banco e migrations Prisma.
6. A porta da nova API fica em loopback. Backend continua usando os endpoints
   Docker `http://api_oficial:6000` e `http://wuzapi:8080`. A URL pública Oficial
   altera `OFICIAL_HOST` e somente o Caddy; não muda frontend/backend.
7. Falhas antes de migrations restauram configuração anterior. Depois do início
   de migrations, preservam checkpoint para retomada; não há rollback de schema
   automático. TLS pendente mantém `migration-update` com operação da API em
   estágio `https`, sem declarar a instalação validada. `resume` revalida DNS/TLS
   sem reconstruir a plataforma nem repetir migrations já concluídas.

```sh
cd ~/Instalador-AMANDA
sh ./instalador_single.sh resume --dir /home/deploy/amanda
```

Uma pendência HTTPS da instalação base continua em `https-pending`; instalar API
não desbloqueia esse ou outros estados parciais. Corrija primeiro os domínios da
plataforma no menu 3 e conclua a validação. A exceção de alterar domínio de uma API
é limitada ao checkpoint de HTTPS dessa mesma API, depois das suas migrations.

## Preservação

Remover exige `REMOVER empresa serviço`, executa somente `compose rm -s -f
serviço`, informa impacto e volumes e preserva bancos, credenciais, certificados e
sessões. Para voltar, use iniciar; não repita instalação. Nenhuma dessas opções
executa `down -v`. Logs são limitados e sanitizados pelo dashboard existente.
WuzAPI continua sendo o serviço `wuzapi`, perfil `whatsmeow`; não há segunda API
WhatsMeow. Seu SQLite persistente guarda sessões e não deve ser removido.

Instalações existentes não recebem novos padrões de perfis/binds em update,
resume ou adoção. Propostas/erros e históricos ficam em `.amanda-installer`, com
permissões privadas. Homologação Meta/WhatsApp, DNS público, TLS e conectividade
de uma VPS devem ser validados no ambiente autorizado; testes locais não os
comprovam.
