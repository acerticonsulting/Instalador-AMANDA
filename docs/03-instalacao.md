# Instalação atual

O procedimento vigente está no [README principal](../README.md).

1. Disponibilizar Docker Engine Linux atual e acesso ao socket Unix local.
2. Baixar este repositório com Git em container, conforme README.
3. Executar `sh instalador_single.sh install --dir "$HOME/amanda"`.
4. Informar `https://github.com/acerticonsulting/AMANDA`.
5. Percorrer as 11 etapas: tipo local/IP/HTTPS, URLs/portas, empresa, administrador, banco, segredos, WhatsApp, SMTP, integrações e SSL.
6. Fornecer acesso de leitura ao conector privado quando necessário para o build.
7. Revisar o resumo, confirmar e aguardar build, migrations, seed exclusivo de banco novo, saúde e login.

Node, Python, Git, bancos, filas e proxy executam em containers. Não há criação de
usuário de sistema, instalação APT, serviços PM2 ou Nginx no host.

A instalação só é declarada concluída após todos os serviços selecionados saudáveis, HTTP interno,
login inicial e sessão. Falha não autoriza repetir seeds nem apagar volumes.
Consulte retomada/backup/adoção no README. Instalações históricas no host não são
convertidas automaticamente pelo instalador novo.

Use :voltar, :cancelar e a revisão por etapa para corrigir respostas. O modo JSON é
a autorização automatizada da instalação. Consulte CONFIGURACAO_E_COMPATIBILIDADE.md
para perguntas, variáveis e consumidores. Serviços opcionais podem ser habilitados
posteriormente no menu 12/20, com backup e migrations, sem seed.
