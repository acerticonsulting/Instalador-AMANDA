> Referência histórica: descreve os scripts preservados em legacy/. Para o instalador Docker-only atual, consulte ../README.md e 01-contexto-para-ia.md. Os caminhos antigos de scripts/tools recebem o prefixo legacy/.

# Backup, restauração e desinstalação

## Backup do menu principal

A opção 6 seleciona a instância, valida seu nome e resolve o PostgreSQL pelas labels Compose com `mf_container_servico`. Gera `pg_dump` do banco principal em arquivo temporário sob `/home/deploy/backups`; só publica o `.sql` quando o comando termina com sucesso e o arquivo não está vazio.

Esse caminho não inclui automaticamente banco da API Oficial, Redis, mídias, volume de autenticação, WuzAPI, configurações e certificados. Para recuperação completa, inventariar e proteger cada conjunto de dados.

`tools/mf_backup_banco_empresa.sh` é outra implementação: consulta `backend/.env`, resolve o banco por instância, tenta dump Docker e depois acesso pelo host, grava em `/home/deploy/backup-<empresa>` e exige pelo menos 1024 bytes. Tamanho mínimo não comprova restaurabilidade.

## Restauração SQL

A opção 7 exige arquivo existente e confirmação. Importa com `psql -X -v ON_ERROR_STOP=1 --single-transaction`. A base precisa estar preparada para o dump; conflitos encerram a importação. Não pressupor que o restaurador recria banco vazio, elimina registros antigos ou converte versões.

Após sucesso, o caminho tenta reiniciar o backend pelo nome e ignora erro desse reinício. Assim, a importação bem-sucedida não comprova que o serviço voltou. Verificar saúde separadamente.

## Roteiro de recuperação

1. Identificar instância, versão de código, schema e dados persistentes.
2. Preservar o estado atual antes de modificar ou substituir backups.
3. Criar ambiente isolado com versões compatíveis de banco e aplicação.
4. Restaurar os conjuntos necessários e configuração sem expor credenciais.
5. Validar contagens, anexos, login, isolamento e automações.
6. Validar canais com conta de teste e evitar consumidores duplicados na mesma sessão.
7. Registrar resultado e tempo de recuperação antes de aplicar a estratégia ao ambiente alvo.

## Redis e WhatsMeow

O menu de ferramentas possui rotinas específicas de backup e restauração para Redis nativo/Docker e dados WhatsMeow. Elas selecionam origem e destino e podem interromper serviços. Confirmar consistência com os produtores de mensagens; restaurar filas antigas pode provocar reprocessamento e duplicação.

## Desinstalação

A opção 9 diferencia preservação e apagamento de dados. `mf_remover_recursos_instancia` aceita apenas slug válido e revalida propriedade de containers e volumes por labels antes de remover. Sem apagar dados, não remove volumes; no modo de apagar, remove apenas volumes com label do projeto e sem force.

Volumes externos criados manualmente podem não ter essas labels. Nesse caso, preservá-los é comportamento esperado e não prova falha do filtro. Não ampliar a remoção usando apenas prefixos para “limpar o restante”. Os dados de bind mounts, recursos legados e configurações precisam de inspeção separada.

Preservar volumes não garante reinstalação funcional. Guardar também configuração e versões compatíveis. Remover container é ação com interrupção de serviço mesmo quando os volumes permanecem.
