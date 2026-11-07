# Instalação atual

O procedimento vigente está no [README principal](../README.md).

1. Disponibilizar Docker Engine Linux atual e acesso ao socket Unix local.
2. Baixar este repositório com Git em container, conforme README.
3. Executar `sh instalador_single.sh install --dir "$HOME/amanda"`.
4. Informar `https://github.com/acerticonsulting/AMANDA`.
5. Escolher URLs, HTTPS opcional e manter ou personalizar o acesso inicial.
6. Fornecer acesso de leitura ao conector privado quando necessário para o build.
7. Aguardar build, migrations, seed exclusivo de banco novo, saúde e login.

Node, Python, Git, bancos, filas e proxy executam em containers. Não há criação de
usuário de sistema, instalação APT, serviços PM2 ou Nginx no host.

A instalação só é declarada concluída após oito serviços saudáveis, HTTP interno,
login inicial e sessão. Falha não autoriza repetir seeds nem apagar volumes.
Consulte retomada/backup/adoção no README. Instalações históricas no host não são
convertidas automaticamente pelo instalador novo.
