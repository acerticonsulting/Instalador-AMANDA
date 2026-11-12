> Referência histórica: descreve os scripts preservados em legacy/. Para o instalador Docker-only atual, consulte ../README.md e 01-contexto-para-ia.md. Os caminhos antigos de scripts/tools recebem o prefixo legacy/.

# Referência de nomes de configuração

Extração de atribuições e referências Shell em scripts e exemplo env. Inclui globais internas, testes e código gerado. Não representa obrigatoriedade, precedência ou formato completo. Até três fontes por nome; nenhum valor foi copiado.

| Nome | Fontes |
| --- | --- |
| `ALTA_PERFORMANCE` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `AMANDA_TEST_CASE` | tests/regressao_plataforma.sh |
| `AMANDA_TEST_LOG` | tests/regressao_plataforma.sh |
| `API_OFICIAL_DB_NAME` | instalador_apioficial.sh |
| `API_OFICIAL_PORTAS_EM_USO` | instalador_apioficial.sh |
| `API_OFICIAL_PORTAS_RESUMO` | instalador_apioficial.sh |
| `APP_DIR` | atualizador_pro.sh, atualizador_remoto.sh, instalador_single.sh |
| `APP_NAME` | instalador_single.sh |
| `APP_ROOT` | atualizador_pro.sh, instalador_single.sh |
| `ARCH` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `ARCH_RAW` | atualizador_pro.sh, atualizador_remoto.sh |
| `ARQUIVO` | tools/agendar_backup_bd_docker.sh |
| `ARQUIVO_BACKUP` | instalador_single.sh |
| `ARQUIVO_ETAPAS` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `ARQUIVO_VARIAVEIS` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `ARQUIVO_VARIAVEIS_ALVO` | atualizador_pro.sh, instalador_single.sh |
| `ARQUIVO_VARIAVEIS_BASE` | tools/instalador_instancias.sh |
| `ARQUIVO_VARIAVEIS_HUB` | tools/instalador_multiflow_hub.sh |
| `ARQUIVO_VARIAVEIS_INSTALADOR` | atualizador_pro.sh, instalador_single.sh, tools/roolback_versao.sh |
| `ARQUIVO_VARIAVEIS_INSTANCIA` | instalador_single.sh, tools/instalador_instancias.sh |
| `ARQUIVO_VARIAVEIS_MF` | tools/instalador_multiflow_hub.sh, tools/instalador_multiflow_voz.sh |
| `ARQUIVO_VARIAVEIS_USADO` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `ARQUIVO_VARIAVEIS_VOZ` | tools/instalador_multiflow_voz.sh |
| `ASAAS_TOKEN` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `ASAASTOKEN` | instalador_single.sh, tools/instalador_instancias.sh |
| `BACK_ENV` | tools/trocar_dominios.sh |
| `BACKEND_DIR` | atualizador_pro.sh, atualizador_remoto.sh, instalador_single.sh |
| `BACKEND_ENV` | tools/instalar_push.sh |
| `BACKEND_URL` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `BACKUP_BASE` | instalador_single.sh |
| `BACKUP_BASE_LEGACY` | instalador_single.sh |
| `BACKUP_DIR` | instalador_single.sh, tools/agendar_backup_bd_docker.sh |
| `BACKUP_DIR_LEGACY` | instalador_single.sh |
| `BACKUP_EMPRESAS` | tools/agendar_backup_bd_nativo.sh |
| `BACKUP_FILE` | instalador_single.sh |
| `BACKUP_LABELS` | instalador_single.sh |
| `BACKUP_SCRIPT` | instalador_single.sh |
| `BACKUPS_AP` | instalador_single.sh |
| `BACKUPS_SQL` | instalador_single.sh |
| `BAILEYS_LOG_LEVEL` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `BAILEYS_OUTBOUND_LID_FIRST` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `BAILEYS_SESSION_RESET_ENABLED` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `BAILEYS_STUB400_AUTO_RETRY` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `BANCOS` | tools/agendar_backup_bd_docker.sh |
| `BASH_ENV` | tests/validar_instalador.sh |
| `BLUE` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `BRANCH_AMANDA_ESCOLHIDA` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `BRANCH_AUSENTE` | tests/regressao_instalador.sh |
| `BRANCH_INSTALACAO` | instalador_single.sh, tools/instalador_instancias.sh |
| `BRANCH_ROLLBACK` | tools/roolback_versao.sh |
| `COLORTERM` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `COMMIT_ALVO` | tools/roolback_versao.sh |
| `COMMIT_SELECTED` | tools/roolback_versao.sh |
| `COMPOSE_PROJECT_NAME` | instalador_single.sh |
| `CONF_BASENAME` | tools/otimizar_postgres_nativo.sh |
| `CONFIG_RETENCAO` | tools/agendar_backup_bd_docker.sh |
| `CORS_ORIGIN` | tools/instalador_multiflow_voz.sh |
| `CREDS_SOURCE` | tools/instalador_rabbit.sh |
| `CRON_JOB1` | instalador_single.sh, tools/instalador_instancias.sh |
| `CRON_LINHA` | tools/agendar_backup_bd_docker.sh, tools/agendar_backup_bd_nativo.sh |
| `CRON_SCRIPT_PATH` | tools/agendar_backup_bd_docker.sh, tools/agendar_backup_bd_nativo.sh |
| `CURRENT_COMMIT` | tools/instalador_instancias.sh |
| `CURRENT_URL` | tools/roolback_versao.sh |
| `CUSTOM_DIR` | atualizador_pro.sh, instalador_single.sh |
| `CYAN` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `DADOS_COLETADOS_NOVA_INSTANCIA` | instalador_single.sh |
| `DATA` | tools/agendar_backup_bd_docker.sh |
| `DATABASE_LINK` | instalador_apioficial.sh, instalador_single.sh |
| `DATABASE_NAME` | instalador_apioficial.sh, instalador_single.sh |
| `DATABASE_PASSWORD` | instalador_apioficial.sh, instalador_single.sh |
| `DATABASE_PORT` | instalador_apioficial.sh, instalador_single.sh |
| `DATABASE_STORAGE` | tools/instalador_multiflow_voz.sh |
| `DATABASE_URL` | instalador_apioficial.sh, instalador_single.sh |
| `DATABASE_USER` | instalador_apioficial.sh, instalador_single.sh |
| `DB_CLEAN` | tools/agendar_backup_bd_docker.sh |
| `DB_DIALECT` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `DB_HOST` | .env.exemplo, instalador_single.sh, instalador_whatsmeow.sh |
| `DB_HOST_APIOFICIAL` | instalador_apioficial.sh |
| `DB_HOST_DEFAULT` | tools/agendar_backup_bd_nativo.sh |
| `DB_HOST_POSTGRES` | tools/instalador_instancias.sh |
| `DB_NAME` | .env.exemplo, instalador_single.sh, instalador_whatsmeow.sh |
| `DB_NAME_APIOFICIAL` | instalador_single.sh |
| `DB_PASS` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `DB_PASS_APIOFICIAL` | instalador_apioficial.sh |
| `DB_PASS_POSTGRES` | tools/instalador_instancias.sh |
| `DB_PASSWORD` | instalador_whatsmeow.sh |
| `DB_PORT` | .env.exemplo, instalador_single.sh, instalador_whatsmeow.sh |
| `DB_PORT_APIOFICIAL` | instalador_apioficial.sh |
| `DB_PORT_DEFAULT` | tools/agendar_backup_bd_nativo.sh |
| `DB_PORT_POSTGRES` | tools/instalador_instancias.sh |
| `DB_SSLMODE` | instalador_whatsmeow.sh |
| `DB_USER` | .env.exemplo, instalador_single.sh, instalador_whatsmeow.sh |
| `DB_USER_APIOFICIAL` | instalador_apioficial.sh |
| `DB_USER_POSTGRES` | tools/instalador_instancias.sh |
| `DEBIAN_FRONTEND` | instalador_apioficial.sh, instalador_single.sh, tools/instalador_multiflow_voz.sh |
| `DEFAULT_API_OFICIAL_PORT` | tools/trocar_dominios.sh |
| `DEFAULT_API_PORT` | tools/instalador_multiflow_voz.sh |
| `DEFAULT_ENGINE_PORT` | tools/instalador_multiflow_voz.sh |
| `DEFAULT_WUZAPI_PORT` | tools/trocar_dominios.sh |
| `EMAIL_ADMIN` | instalador_apioficial.sh, instalador_single.sh |
| `EMPRESA` | instalador_single.sh |
| `ENABLE_LID_DEBUG` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `ENGINE_API_KEY` | tools/instalador_multiflow_voz.sh |
| `ENGINE_URL` | tools/instalador_multiflow_voz.sh |
| `ENV_BACKEND_PRINCIPAL` | tools/instalador_instancias.sh |
| `ENV_FILE` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `ERRO_GIT_VALIDACAO` | instalador_single.sh |
| `ESTADO_HUB` | tools/instalador_multiflow_hub.sh |
| `EUID` | tools/instalador_multiflow_hub.sh, tools/instalador_multiflow_voz.sh, tools/instalador_rabbit.sh |
| `FACEBOOK_APP_ID` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `FACEBOOK_APP_SECRET` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `FERRAMENTAS_ESCOLHA` | instalador_single.sh |
| `FERRAMENTAS_INSTANCIA_POR_DB` | instalador_single.sh |
| `FERRAMENTAS_LISTA_DB` | instalador_single.sh |
| `FERRAMENTAS_REDIS_CONTAINER` | instalador_single.sh |
| `FERRAMENTAS_REDIS_CONTAINERS` | instalador_single.sh |
| `FERRAMENTAS_REDIS_FONTE` | instalador_single.sh |
| `FERRAMENTAS_REDIS_FONTES` | instalador_single.sh |
| `FERRAMENTAS_REDIS_FONTES_LABELS` | instalador_single.sh |
| `FFMPEG` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `FFMPEG_CMD` | instalador_single.sh |
| `FFMPEG_DIR` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `FFMPEG_FILE` | instalador_single.sh, tools/instalador_instancias.sh |
| `FFMPEG_PATH` | instalador_single.sh |
| `FINAL_COMMIT` | tools/instalador_instancias.sh |
| `FINAL_VERSION` | tools/instalador_instancias.sh |
| `FIX_LID_JOB_CRON` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `FIX_LID_JOB_ENABLED` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `FRDIR` | tools/trocar_dominios.sh |
| `FRONT_ENV` | tools/trocar_dominios.sh |
| `FRONT_HOST` | tools/instalador_multiflow_voz.sh |
| `FRONTEND_DIR` | atualizador_pro.sh, atualizador_remoto.sh, instalador_single.sh |
| `FRONTEND_ENV` | tools/instalar_push.sh |
| `FRONTEND_URL` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `GERENCIANET_CLIENT_ID` | instalador_single.sh, tools/instalador_instancias.sh |
| `GERENCIANET_CLIENT_SECRET` | instalador_single.sh, tools/instalador_instancias.sh |
| `GERENCIANET_PIX_CERT` | instalador_single.sh, tools/instalador_instancias.sh |
| `GERENCIANET_PIX_KEY` | instalador_single.sh, tools/instalador_instancias.sh |
| `GERENCIANET_SANDBOX` | instalador_single.sh, tools/instalador_instancias.sh |
| `GIT_ASKPASS` | atualizador_fast_sistema.sh, atualizador_remoto_FAST.sh, instalador_single.sh |
| `GIT_CONFIG_FILE` | atualizador_pro.sh |
| `GIT_TERMINAL_PROMPT` | atualizador_fast_sistema.sh, atualizador_remoto_FAST.sh, instalador_single.sh |
| `GITHUB_TOKEN` | instalador_single.sh |
| `GITHUB_TOKEN_VALIDATED` | tools/roolback_versao.sh |
| `GO_VER` | tools/instalador_multiflow_voz.sh |
| `GOFLOW_DISPATCHER_URL` | .env.exemplo |
| `GOTOOLCHAIN` | tools/instalador_multiflow_voz.sh |
| `GRAY` | instalador_single.sh |
| `GREEN` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `HANDLE_MESSAGE_LIMITER_DURATION` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `HANDLE_MESSAGE_LIMITER_MAX` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `HANDLE_MESSAGE_QUEUE_CONCURRENCY` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `HOST_DATA_PATH` | tools/instalador_rabbit.sh |
| `HUB_ROOT` | tools/instalador_multiflow_hub.sh |
| `HUB_ROOT_PADRAO` | tools/instalador_multiflow_hub.sh |
| `HUB_SCRIPT` | instalador_single.sh |
| `IFS` | tests/verificar_plataforma.sh, tools/git_sincronizar_repositorio.sh |
| `INSTALACAO_SEM_DOMINIO` | instalador_single.sh |
| `INSTALADOR_DIR` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `INSTALADOR_ROOT` | tools/nginx_dominio_porta_ssl.sh |
| `INSTALL_DATA_FILE` | tools/instalador_rabbit.sh |
| `INSTALL_OUTPUT` | instalador_single.sh |
| `INSTALL_STATUS` | instalador_single.sh |
| `JWT_EXPIRES_IN` | tools/instalador_multiflow_voz.sh |
| `JWT_REFRESH_SECRET` | .env.exemplo, instalador_apioficial.sh, instalador_single.sh |
| `JWT_SECRET` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `LDD_END` | instalador_single.sh |
| `LDD_PROBE` | instalador_single.sh |
| `LDD_RMCHK` | instalador_single.sh |
| `LIB_NAME` | instalador_single.sh |
| `LISTA_5432` | instalador_single.sh |
| `LISTA_7532` | instalador_single.sh |
| `LISTA_DB` | instalador_single.sh |
| `LOG` | tests/regressao_instalador.sh, tools/agendar_backup_bd_docker.sh |
| `LOG_FALLBACK` | tools/agendar_backup_bd_docker.sh |
| `LOG_GLOBAL` | tools/agendar_backup_bd_nativo.sh |
| `LOG_MESSAGE_UPSERT` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `LOGO_URL` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `MACHINE` | atualizador_pro.sh, atualizador_remoto.sh |
| `MAGENTA` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `MAIL_FROM` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `MAIL_HOST` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `MAIL_PASS` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `MAIL_PORT` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `MAIL_USER` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `MAIN_PY_PATH` | instalador_single.sh |
| `MASTER_KEY` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `MAX_BUFFER_SIZE_MB` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `MENSAGEM` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `MF_AVISO_OPCAO_MAIS_RECENTE` | atualizador_fast_sistema.sh, atualizador_remoto_FAST.sh, instalador_single.sh |
| `MF_BACKUP_ARQUIVO` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `MF_BACKUP_SCRIPT` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `MF_EMPRESA` | atualizador_fast_sistema.sh |
| `MF_GIT_AUTH_MARKER` | tools/git_sincronizar_repositorio.sh |
| `MF_GIT_DEPLOY_BRANCH` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `MF_GIT_ERRO_VALIDACAO` | tools/git_sincronizar_repositorio.sh |
| `MF_GIT_EXIT_AUTH` | tools/git_sincronizar_repositorio.sh |
| `MF_GIT_SYNC_BODY` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `MF_INSTALADOR_ROOT` | instalador_single.sh, tests/regressao_instalador.sh |
| `MF_OPCAO30_INSTANCIA_PRESET` | atualizador_remoto_FAST.sh, instalador_single.sh |
| `MF_SQLITE_CHECK_BODY` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `MF_TRANSC_MAINT_SCRIPT` | atualizador_fast_sistema.sh, atualizador_remoto_FAST.sh, instalador_single.sh |
| `MF_WHATSAPP_WEB_VERSION_PADRAO` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `MISSING_LIBS` | instalador_single.sh |
| `MISSING_LIBS_AFTER` | instalador_single.sh |
| `MISSING_LIBS_FINAL` | instalador_single.sh |
| `MODE_FILE` | tools/instalador_alta_performance.sh |
| `MODO` | tests/regressao_instalador.sh |
| `MODO_VPS` | tools/instalador_multiflow_hub.sh, tools/instalador_multiflow_voz.sh |
| `MP_ACCESS_TOKEN` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `MP_NOTIFICATION_URL` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `MPACCESSTOKEN` | instalador_single.sh, tools/instalador_instancias.sh |
| `MPNOTIFICATION_URL` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `MPNOTIFICATIONURL` | instalador_single.sh, tools/instalador_instancias.sh |
| `MULTIFLOW_API_URL` | tools/instalador_multiflow_voz.sh |
| `NAME` | atualizador_pro.sh, atualizador_remoto.sh, instalador_single.sh |
| `NAME_ADMIN` | instalador_apioficial.sh, instalador_single.sh |
| `NEW_REMOTE_URL` | atualizador_pro.sh |
| `NEW_URL` | tools/roolback_versao.sh |
| `NG_DOM_SSL_SCRIPT` | instalador_single.sh |
| `NGINX_CONF` | instalador_single.sh |
| `NODE_BIN` | instalador_single.sh |
| `NODE_DIR` | instalador_single.sh |
| `NODE_ENV` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `NODE_OPTIONS` | instalador_single.sh, tools/instalador_instancias.sh, tools/instalar_push.sh |
| `NODE_TARGET` | atualizador_pro.sh, atualizador_remoto.sh |
| `NODE_VERSION` | atualizador_pro.sh, atualizador_remoto.sh |
| `NPM_BIN` | instalador_single.sh |
| `NUMEROS` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `OFFICIAL_CAMPAIGN_CONCURRENCY` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `OTIMIZAR_PG_SCRIPT` | instalador_single.sh |
| `PAPEL_HUB` | tools/instalador_multiflow_hub.sh |
| `PASSWORD_ADMIN` | instalador_apioficial.sh, instalador_single.sh |
| `PATH` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `PATH_NODE_DEPLOY` | tools/instalador_multiflow_voz.sh |
| `PG_DB_NAME` | instalador_single.sh |
| `PG_HOST` | instalador_single.sh |
| `PG_PORT` | instalador_single.sh |
| `PG_SENHA` | instalador_single.sh |
| `PG_USUARIO` | instalador_single.sh, tests/regressao_instalador.sh |
| `PGCONNECT_TIMEOUT` | instalador_apioficial.sh |
| `PGPASSWORD` | atualizador_pro.sh, atualizador_remoto.sh, instalador_apioficial.sh |
| `PIP_CMD` | instalador_single.sh |
| `PM2_APP_NAME` | instalador_single.sh |
| `PM2_NAME` | instalador_single.sh |
| `PORT` | .env.exemplo, atualizador_fast_sistema.sh, atualizador_pro.sh |
| `PORT_APIOFICIAL` | instalador_single.sh, tools/instalar_docker_compartilhado.sh |
| `PORT_BACKEND` | instalador_single.sh |
| `PORT_DB` | instalador_single.sh, tools/instalar_docker_compartilhado.sh |
| `PORT_DISPATCHER` | instalador_single.sh, tools/instalar_docker_compartilhado.sh |
| `PORT_FRONTEND` | instalador_single.sh |
| `PORT_PGBOUNCER` | instalador_single.sh, tools/instalar_docker_compartilhado.sh |
| `PORT_REDIS` | instalador_single.sh, tools/instalar_docker_compartilhado.sh |
| `PORT_TRANSCRIBER` | instalador_single.sh, tools/instalar_docker_compartilhado.sh |
| `PORT_WUZAPI` | instalador_single.sh, tools/instalar_docker_compartilhado.sh |
| `PORTAINER_PORTA` | instalador_single.sh |
| `POSTGRES_CONTAINER` | instalador_single.sh, tools/agendar_backup_bd_docker.sh |
| `PRETTY_NAME` | instalador_whatsmeow.sh |
| `PRIMARY_COLOR` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `PROXY` | tools/trocar_dominios.sh |
| `PROXY_PORT` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `PUBLIC_API_URL` | tools/instalador_multiflow_voz.sh |
| `PUBLIC_APP_URL` | tools/instalador_multiflow_voz.sh |
| `PULL_OK` | tools/roolback_versao.sh |
| `PUPPETEER_SKIP_DOWNLOAD` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `PURPLE` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `PUSH_SCRIPT` | instalador_single.sh |
| `PW_FILE` | instalador_single.sh |
| `PYTHONPATH` | instalador_single.sh, tools/mf_transcricao_manutencao.sh |
| `QUEUE_ID` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `RABBIT_CONTAINER` | tools/instalador_rabbit.sh |
| `RABBIT_IMAGE` | tools/instalador_rabbit.sh |
| `RABBIT_PASS` | instalador_single.sh, tools/instalador_instancias.sh, tools/instalador_rabbit.sh |
| `RABBIT_USER` | instalador_single.sh, tools/instalador_instancias.sh, tools/instalador_rabbit.sh |
| `RABBIT_VOLUME` | tools/instalador_rabbit.sh |
| `RABBITMQ_AMQP_PORT` | instalador_whatsmeow.sh |
| `RABBITMQ_ENABLED_GLOBAL` | instalador_single.sh |
| `RABBITMQ_HOST` | instalador_single.sh, tools/instalador_instancias.sh |
| `RABBITMQ_MGMT_PORT` | instalador_whatsmeow.sh |
| `RABBITMQ_PORT` | instalador_single.sh, tools/instalador_instancias.sh |
| `RABBITMQ_QUEUE` | instalador_whatsmeow.sh |
| `RABBITMQ_URI` | instalador_single.sh, tools/instalador_instancias.sh |
| `RABBITMQ_URL` | instalador_whatsmeow.sh |
| `REACT_APP_BACKEND_URL` | instalador_single.sh, tools/instalador_instancias.sh |
| `REACT_APP_FACEBOOK_APP_ID` | instalador_single.sh, tools/instalador_instancias.sh |
| `REACT_APP_LOGO` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `REACT_APP_LOGO_URL` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `REACT_APP_NAME_SYSTEM` | instalador_single.sh, tools/instalador_instancias.sh |
| `REACT_APP_NUMBER_SUPPORT` | instalador_single.sh, tools/instalador_instancias.sh |
| `REACT_APP_PRIMARY_COLOR` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `REACT_APP_REQUIRE_BUSINESS_MANAGEMENT` | instalador_single.sh, tools/instalador_instancias.sh |
| `REACT_APP_SECONDARY_COLOR` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `RECORDINGS_PATH` | tools/instalador_multiflow_voz.sh |
| `RED` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `REDIS_CONTAINER_PADRAO` | instalador_single.sh |
| `REDIS_OPT_LIMITER_DURATION` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `REDIS_OPT_LIMITER_MAX` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `REDIS_PORT` | instalador_single.sh |
| `REDIS_SENHA` | instalador_single.sh |
| `REDIS_URI` | .env.exemplo, instalador_apioficial.sh, instalador_single.sh |
| `REDIS_URI_ACK` | instalador_single.sh |
| `REDIS_URI_APIOFICIAL` | instalador_apioficial.sh |
| `REDIS_URI_RAW` | instalador_single.sh |
| `REPO_ALVO` | instalador_single.sh |
| `REPO_HOST` | instalador_single.sh |
| `REPO_NAME` | tools/instalador_multiflow_hub.sh, tools/instalador_multiflow_voz.sh |
| `REPO_OWNER` | tools/instalador_multiflow_hub.sh |
| `REPO_PRO_CANONICO` | atualizador_pro.sh |
| `REPO_URL` | atualizador_pro.sh, instalador_single.sh, tools/roolback_versao.sh |
| `RESET` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `RETENCAO_ATUAL` | tools/agendar_backup_bd_docker.sh |
| `RETENCAO_DIAS` | tools/agendar_backup_bd_docker.sh |
| `ROLLBACK_SCRIPT` | instalador_single.sh |
| `ROOT` | tests/ativar_validacao.sh, tests/regressao_executor.sh, tests/regressao_instalador.sh |
| `ROXO` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `SCRIPT_DIR` | atualizar_apioficial.sh, instalador_apioficial.sh, instalador_single.sh |
| `SECONDARY_COLOR` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `SERVER_PORT` | atualizador_pro.sh, atualizador_remoto.sh, instalador_single.sh |
| `SESSION_DEVICE_NAME` | instalador_whatsmeow.sh |
| `SESSION_PLATFORM_TYPE` | instalador_whatsmeow.sh |
| `SKIP_HEAVY_FFMPEG_APT` | instalador_single.sh |
| `SSH_ASKPASS` | tools/git_sincronizar_repositorio.sh |
| `SSL_NGINX_SCRIPT` | instalador_single.sh |
| `STACK_TEMPLATE` | tools/instalador_alta_performance.sh |
| `STRIPE_CANCEL_URL` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `STRIPE_OK_URL` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `STRIPE_PRIVATE` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `SUPER_EMAIL` | tools/instalador_multiflow_voz.sh |
| `SUPER_NAME` | tools/instalador_multiflow_voz.sh |
| `SUPER_PASSWORD` | tools/instalador_multiflow_voz.sh |
| `TERM` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `TEST_DIR` | atualizador_pro.sh, instalador_single.sh, tools/instalador_instancias.sh |
| `TIMEOUT_TO_IMPORT_MESSAGE` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `TIMESTAMP` | instalador_single.sh |
| `TITULO_LISTA_VERSOES` | atualizador_fast_sistema.sh, atualizador_remoto_FAST.sh, instalador_single.sh |
| `TMP` | atualizador_pro.sh, atualizador_remoto.sh |
| `TMP_CRON` | instalador_single.sh, tools/instalador_instancias.sh |
| `TMP_SQL` | tools/agendar_backup_bd_docker.sh |
| `TOKEN` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `TOKEN_ADMIN` | instalador_apioficial.sh, instalador_single.sh |
| `TOKEN_API_OFICIAL` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `TOKEN_AUTH` | atualizador_pro.sh, instalador_single.sh, tools/instalador_multiflow_hub.sh |
| `TOKEN_CIPHER_KEY` | tools/instalador_multiflow_voz.sh |
| `TRANSC_DIR` | instalador_single.sh, tools/mf_transcricao_manutencao.sh |
| `TRANSCRIBE_URL` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `TROCAR_DOM_SCRIPT` | instalador_single.sh |
| `UBUNTU_CODENAME` | instalador_single.sh |
| `UBUNTU_VERSION` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `UPDATE_FILE` | instalador_single.sh |
| `URL` | atualizador_pro.sh, atualizador_remoto.sh |
| `URL_API_OFICIAL` | instalador_apioficial.sh, instalador_single.sh |
| `URL_BACKEND_MULT100` | instalador_apioficial.sh, instalador_single.sh |
| `USE_GO_CAMPAIGN_DISPATCHER` | .env.exemplo, instalador_single.sh |
| `USE_WHATSAPP_OFICIAL` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `USER_ID` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `USER_SITE` | instalador_single.sh, tools/mf_transcricao_manutencao.sh |
| `VAPID_OUTPUT` | tools/instalar_push.sh |
| `VAPID_PRIVATE` | tools/instalar_push.sh |
| `VAPID_PRIVATE_KEY` | tools/instalar_push.sh |
| `VAPID_PUBLIC` | tools/instalar_push.sh |
| `VAPID_PUBLIC_KEY` | tools/instalar_push.sh |
| `VAPID_SUBJECT` | tools/instalar_push.sh |
| `VAPID_SUBJECT_VALUE` | tools/instalar_push.sh |
| `VERIFY_TOKEN` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `VERSION` | instalador_single.sh |
| `VERSION_ALVO` | tools/roolback_versao.sh |
| `VERSION_CODENAME` | instalador_single.sh |
| `VERSION_ID` | instalador_single.sh |
| `VERSION_SELECTED` | tools/roolback_versao.sh |
| `VOZ_BRIDGE_SECRET` | tools/instalador_multiflow_voz.sh |
| `VOZ_ROOT` | tools/instalador_multiflow_voz.sh |
| `VOZ_SCRIPT` | instalador_single.sh |
| `WAVOIP_PASSWORD` | instalador_single.sh, tools/instalador_instancias.sh |
| `WAVOIP_URL` | instalador_single.sh, tools/instalador_instancias.sh |
| `WAVOIP_USERNAME` | instalador_single.sh, tools/instalador_instancias.sh |
| `WEBHOOK_FORMAT` | instalador_whatsmeow.sh |
| `WHATSAPP_WEB_VERSION` | .env.exemplo, instalador_single.sh, tools/instalador_instancias.sh |
| `WHATSMEOW_COMPOSE_LEGACY` | instalador_whatsmeow.sh |
| `WHATSMEOW_DB_CONTAINER` | instalador_single.sh |
| `WHATSMEOW_DB_NAME` | instalador_single.sh |
| `WHATSMEOW_DB_PASSWORD` | instalador_single.sh |
| `WHATSMEOW_DB_USER` | instalador_single.sh |
| `WHATSMEOW_GIT_MUDOU` | instalador_whatsmeow.sh |
| `WHATSMEOW_PORTAS_EM_USO` | instalador_whatsmeow.sh |
| `WHATSMEOW_PORTAS_RESUMO` | instalador_whatsmeow.sh |
| `WHATSMEOW_RABBIT_AMQP_USADAS` | instalador_whatsmeow.sh |
| `WHATSMEOW_RABBIT_MGMT_USADAS` | instalador_whatsmeow.sh |
| `WHATSMEOW_SCRIPT` | instalador_single.sh |
| `WHATSMEOW_SERVER_CONTAINER` | instalador_single.sh |
| `WHITE` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `WORK` | tests/regressao_executor.sh, tests/regressao_instalador.sh, tests/regressao_plataforma.sh |
| `WRAPPER_SCRIPT` | instalador_single.sh |
| `WSL_DISTRO_NAME` | instalador_single.sh |
| `WT_SESSION` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
| `WUZAPI_ADDRESS` | instalador_whatsmeow.sh |
| `WUZAPI_ADMIN_TOKEN` | .env.exemplo, instalador_single.sh, instalador_whatsmeow.sh |
| `WUZAPI_COMPOSE_PROJECT` | instalador_whatsmeow.sh |
| `WUZAPI_GLOBAL_ENCRYPTION_KEY` | instalador_single.sh, instalador_whatsmeow.sh |
| `WUZAPI_GLOBAL_HMAC_KEY` | instalador_single.sh, instalador_whatsmeow.sh |
| `WUZAPI_GLOBAL_WEBHOOK` | instalador_whatsmeow.sh |
| `WUZAPI_PORT` | instalador_whatsmeow.sh |
| `WUZAPI_READ_RECEIPT_ENABLE_DELAY_MS` | tools/instalador_instancias.sh |
| `WUZAPI_TOKEN` | instalador_single.sh |
| `WUZAPI_URL` | .env.exemplo |
| `WUZAPI_WEBHOOK_BASE_URL` | instalador_single.sh |
| `YELLOW` | atualizador_fast_sistema.sh, atualizador_pro.sh, atualizador_remoto.sh |
