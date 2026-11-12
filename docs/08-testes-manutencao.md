> Referência histórica: descreve os scripts preservados em legacy/. Para o instalador Docker-only atual, consulte ../README.md e 01-contexto-para-ia.md. Os caminhos antigos de scripts/tools recebem o prefixo legacy/.

# Testes e manutenção do instalador

O contrato obrigatório está em [AGENTS.md](../AGENTS.md) e a matriz detalhada em [PLANO_DE_TESTES.md](../tests/PLANO_DE_TESTES.md). Após cada conjunto de alterações, executar:

```bash
bash tests/validar_instalador.sh
```

No PowerShell desta máquina:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' --noprofile --norc tests/validar_instalador.sh
```

## O que o executor cobre

O executor exige Bash 4 e ferramentas Unix, encontra scripts Shell, verifica sintaxe e executa quatro suítes com timeout individual de 120 segundos e até cinco segundos para encerramento. Não requer root, Docker, rede ou npm no modo local.

| Suíte | Papel |
| --- | --- |
| verificar_contratos.sh | Arquivos obrigatórios, exemplo env e operações proibidas pelo contrato |
| regressao_instalador.sh | Funções extraídas, configurações, isolamento, erro de restauração e pontos críticos |
| regressao_plataforma.sh | Docker e HTTP simulados para validar o verificador |
| regressao_executor.sh | Comportamento do executor, erros e caminhos com espaços |

Não executar instaladores completos, migrações ou exclusões reais como complemento da suíte local. Ao corrigir comportamento, atualizar regressão correspondente. Alteração só documental não exige criar teste espelhando o texto, mas a execução obrigatória continua valendo.

Os cenários negativos imprimem mensagens de erro intencionais, como falha de restauração, branch ausente e APT ocupado. Interpretar essas mensagens junto do resultado da suíte e do código de saída; uma mensagem de erro de fixture não significa que a máquina sofreu essa falha.

## Verificação de uma plataforma existente

O modo `--plataforma` é leitura real e necessita do servidor e alvo explicitamente fornecidos. Exemplo a adaptar:

```bash
bash tests/validar_instalador.sh --plataforma \
  --projeto INSTANCIA \
  --frontend-url https://app.exemplo.com/ \
  --backend-url https://api.exemplo.com/ENDPOINT_REAL \
  --servico pgbouncer --servico api_transcricao --servico goflow_dispatcher
```

Não assumir `/health`: usar endpoint implementado, público e adequado a GET. O verificador exige backend, frontend, postgres e redis e aceita serviços adicionais obrigatórios. Usa `docker ps`, `inspect` e GET, sem `exec` nem mudanças de containers. Exige HTTP 2xx, não segue redirecionamentos, valida TLS e rejeita URLs com credenciais, query ou fragmento.

Container running sem healthcheck gera aviso e não comprova prontidão interna. Ausência total de serviço opcional exige incluí-lo como obrigatório para ser detectada. O resultado não substitui teste de mensagem, anexos ou autorização.

## Hooks e commit

`tests/ativar_validacao.sh` configura `core.hooksPath=tests/hooks` sem sobrescrever hooks divergentes. Neste clone, esse caminho já estava configurado na análise. O pre-commit valida a cópia do índice Git, incluindo `git diff --cached --check`; não valida simplesmente a árvore de trabalho.

Preparar apenas arquivos da tarefa, executar testes e criar commit. Não usar `--no-verify`. Preservar LF para Shell conforme `.gitattributes`. Registrar o resultado local separadamente de qualquer evidência da VPS.

## Homologação necessária

Instalação nova, segunda instância, retomada, atualização com dados, restauração, falta de rede/disco, TLS, rollback e integrações reais pertencem a VM ou homologação. O plano original descreve os casos HOM-01 a HOM-12. Sintaxe Bash aprovada não valida genericamente Python, SQL, YAML ou Dockerfile gerados.
