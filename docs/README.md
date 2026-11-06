# Documentação do instalador AMANDACHAT

Este conjunto orienta manutenção, diagnóstico e continuidade por outra IA. Referência: cópia local analisada em 6 de novembro de 2026, a partir do commit `7501a44`. O instalador provisiona e altera a plataforma AMANDA; não é o código da aplicação. A entrada principal é `instalador_single.sh`.

## Leitura inicial

1. [Contexto para a próxima IA](01-contexto-para-ia.md).
2. [Arquitetura e integração com a plataforma](02-arquitetura.md).
3. [Instalação e estado persistente](03-instalacao.md).
4. [Configuração, portas e URLs](04-configuracao.md).
5. [Atualizações e homologação](05-atualizacoes.md).
6. [API Oficial e componentes auxiliares](06-integracoes.md).
7. [Backup, restauração e desinstalação](07-recuperacao.md).
8. [Testes e manutenção](08-testes-manutencao.md).
9. [Diagnóstico e riscos conhecidos](09-diagnostico-riscos.md).
10. [Cobertura e fontes](10-fontes-cobertura.md).

## Referências geradas

- [Funções por arquivo e linha](referencia-funcoes.md).
- [Arquivos e responsabilidades](referencia-arquivos.md).
- [Chaves de configuração](referencia-configuracao.md).
- [Inventário e hashes dos arquivos de origem](inventario-fontes.tsv).
- [Resultado da validação local](validacao-local.txt).

## Plataforma relacionada

A análise da aplicação está em [AMANDA/documentos](../../AMANDA/documentos/README.md), pasta irmã deste repositório no workspace original. Esse link depende da organização local das pastas e não estará disponível em um clone isolado do instalador. O documento de arquitetura contém o resumo necessário para reconhecer os componentes sem depender dele.

Os documentos tratam a implementação atual separadamente de planos, compatibilidade legada e recomendações. Nenhuma instalação real foi executada para produzir esta análise. As orientações operacionais exigem identificar a instância, os arquivos e a versão reais antes de agir.
