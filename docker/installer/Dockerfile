FROM docker:27.5.1-cli AS dockercli
FROM node:22-alpine
RUN apk add --no-cache git ca-certificates
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=dockercli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins
WORKDIR /opt/amanda-installer
COPY docker/installer/*.cjs docker/installer/historical.sh ./
RUN chmod 755 source-askpass.cjs
ENTRYPOINT ["node", "/opt/amanda-installer/cli.cjs"]
