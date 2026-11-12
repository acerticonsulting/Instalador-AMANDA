> Referência histórica: descreve os scripts preservados em legacy/. Para o instalador Docker-only atual, consulte ../README.md e 01-contexto-para-ia.md. Os caminhos antigos de scripts/tools recebem o prefixo legacy/.

# Cobertura e fontes da análise

## Origem

Análise em 6 de novembro de 2026 do diretório local Instalador do AMANDACHAT. Base Git inicialmente limpa, último commit observado `7501a44`, com regra local em AGENTS.md. Não houve consulta a repositórios remotos nem uso de credenciais.

## Leitura dirigida

- AGENTS, README, gitignore e gitattributes.
- Plano de testes, executor, ativação e pre-commit.
- No monólito: entrada e saída, funções de salvar/carregar variáveis e etapas, localização do Compose, instalação Docker, etapas finais e verificação de containers críticos, seleção de canais, atualização padrão e GHCR, menu principal e trechos dos gerenciadores de backup, restauração, desinstalação e API Oficial.
- Biblioteca de operações seguras: parser, gravação, validação de instância, resolução de serviço, remoção de recursos e atualização de env.
- Scripts autônomos da API Oficial: funções e trechos de seleção, banco, integração Compose e ponto de entrada.
- Bibliotecas de sincronização Git e manutenção de transcrição: comentários, contratos e mapa de funções.
- Biblioteca de backup: implementação de dump, diretórios, fallback e validação mínima.
- Inventário dos demais scripts, ferramentas e funções; nomes de chaves do exemplo env sem incorporar valores.

Não houve revisão linha a linha de todos os ramos do monólito nem execução de cada ferramenta. O catálogo de funções é extração estática, podendo conter funções dentro de código gerado; não é um grafo completo de chamadas.

## Evidência reproduzível

`inventario-fontes.tsv` lista tamanho e SHA-256 dos arquivos de origem incluídos, excluindo Git, saídas, dependências, estado privado e esta pasta de documentação. Os hashes identificam a cópia analisada; não são uma assinatura de segurança. O mapa de funções fornece arquivo e linha, sem corpo ou valores sensíveis.

`referencia-configuracao.md` contém nomes de atribuições e variáveis referenciadas, sem valores. Inclui variáveis internas e de testes; não é lista de requisitos da implantação.

O resultado dos testes locais está em `validacao-local.txt`. O alvo fornecido nesta tarefa é uma pasta de código, não uma instalação Docker acessível. Portanto o modo real de plataforma não foi aplicado. Builds, migrações, TLS, restauração, WhatsApp e serviços remotos permanecem dependentes de homologação.

## Como manter

Após mudança funcional, revisar o documento da área, atualizar regressão e executar a suíte. Após mover funções, renovar arquivo e linha no catálogo. Quando uma homologação confirmar ou rejeitar um risco, registrar versão, cenário e resultado sem expor credenciais. Manter recomendações e hipóteses separadas de comportamento observado.
