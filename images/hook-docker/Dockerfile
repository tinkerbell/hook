FROM golang:1.24-alpine AS dev
COPY . /src/
WORKDIR /src
RUN CGO_ENABLED=0 go build -a -ldflags '-s -w -extldflags "-static"' -o /hook-docker

FROM docker:28.2.2-dind AS docker
RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories
RUN apk update && apk add kexec-tools binutils && rm -rf /var/cache/apk/*
# Won't use docker-buildx nor docker-compose
RUN rm -rf /usr/local/libexec/docker/cli-plugins
# Strip some large binaries
RUN strip /usr/local/bin/docker /usr/local/bin/dockerd /usr/local/bin/docker-proxy /usr/local/bin/runc /usr/local/bin/containerd /usr/local/bin/containerd-shim-runc-v2
# Purge binutils package after stripping
RUN apk del binutils

FROM alpine:3.22
COPY --from=dev /hook-docker .
COPY --from=docker /usr/local/bin/docker-init /usr/local/bin/docker /usr/local/bin/dockerd /usr/local/bin/docker-proxy /usr/local/bin/runc /usr/local/bin/
COPY --from=docker /usr/local/bin/containerd /usr/local/bin/containerd-shim-runc-v2 /usr/local/bin/
COPY --from=docker /usr/local/bin/dockerd-entrypoint.sh /usr/local/bin/dockerd-entrypoint.sh

RUN apk add --no-cache ca-certificates iptables

ENTRYPOINT ["/hook-docker"]
