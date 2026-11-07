> Referência histórica: descreve os scripts preservados em legacy/. Para o instalador Docker-only atual, consulte ../README.md e 01-contexto-para-ia.md. Os caminhos antigos de scripts/tools recebem o prefixo legacy/.

# API Oficial e componentes auxiliares

## API Oficial pelo menu 11

`menu_gerenciar_api_oficial` oferece instalação, atualização, status, controle do serviço, logs, sincronização e remoção. O fluxo atual da instalação principal remove o bloco API Oficial da stack para instalação separada pelo gerenciador, apesar da descrição geral do README.

`instalar_api_oficial_docker` recebe instância e diretório Compose, localiza o código, pode restaurar a pasta do Git e encerra processos PM2 legados de API Oficial. Solicita porta publicada e URL, prepara banco e ambiente, escreve Dockerfile e insere o serviço no Compose.

O bloco gerado utiliza nome `<empresa>_apioficial`, serviço `api_oficial`, porta interna 6000, PostgreSQL e Redis internos. Usa banco `api_oficial` nesse caminho. A função de atualização do gerenciador reescreve o Dockerfile e ajusta dependência `@nestjs/mapped-types`. O Dockerfile observado gera o cliente Prisma e inicia `dist/main.js`, mas não contém `npm run build`; confirmar a origem e atualização do `dist` antes de declarar que código TypeScript novo foi publicado.

## Scripts autônomos da API Oficial

`instalador_apioficial.sh` e `atualizar_apioficial.sh` possuem seleção e configuração próprias. O instalador autônomo contém nomenclatura de banco `oficial<empresa>` e `oficialseparado` no caso principal legado. Isso difere do gerenciador Docker atual; não misturar env, banco e nomes de container entre os caminhos.

A configuração de banco desses scripts considera ambiente do backend, instalações nativas e alta performance. Uma alteração deve cobrir os pontos de entrada pertinentes e manter interrupção em caso de falha; a regressão local já verifica parte desse contrato.

## WhatsMeow e WuzAPI

`instalador_whatsmeow.sh` e rotinas do monólito instalam ou atualizam essa integração. O fluxo Compose principal prepara imagem WuzAPI e volume persistente. Credenciais, chaves de criptografia/HMAC, webhook e dados de sessão precisam permanecer consistentes. Backup apenas do banco principal não assegura recuperação do canal.

## Transcrição

A aplicação utiliza Flask, FFmpeg e reconhecimento externo. `tools/mf_transcricao_manutencao.sh` atende especialmente instalação nativa e PM2: resolve porta por instância, preserva informação antes de operações Git e recria wrapper. A ordem documentada no código parte do `TRANSCRIBE_URL` do backend da instância, passa por metadados locais e configuração individual e termina no padrão 4002.

Existem `tools/reparar_transcricoes_instancias.sh` e rotina nativa no monólito. Não aplicar reparo PM2 em instalação Docker sem identificar a modalidade. No backend, conferir se o consumidor usa `TRANSCRIBE_URL`; o nome da porta do host não é suficiente.

## Alta performance

`tools/instalador_alta_performance.sh` e `tools/stack_altaPerformance` tratam PostgreSQL, Redis e PgBouncer em Docker para coexistência com caminhos históricos da aplicação. Não equivalem automaticamente ao fluxo Docker principal. Antes de migrar, mapear onde banco e backend realmente executam e as portas publicadas.

## Demais ferramentas

Há provisionadores de HUB, VOZ e RabbitMQ, push, certificados, alteração de domínio, backup agendado e otimização PostgreSQL. O catálogo de arquivos serve de índice. O nome de uma ferramenta não comprova configuração ou suporte ativo numa instalação. Leia o fluxo completo antes de executá-la.
