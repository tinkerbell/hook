FROM golang:1.20-alpine as dev
COPY . /src/
WORKDIR /src
RUN CGO_ENABLED=0 go build -a -ldflags '-s -w -extldflags "-static"' -o /hook-docker

FROM docker:26.1.0-dind
RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories
RUN apk update && apk add kexec-tools binutils && rm -rf /var/cache/apk/*
# Won't use docker-buildx nor docker-compose
RUN rm -rf /usr/local/libexec/docker/cli-plugins
# Strip some large binaries
RUN strip /usr/local/bin/docker /usr/local/bin/dockerd /usr/local/bin/docker-proxy /usr/local/bin/runc
# Purge binutils package after stripping
RUN apk del binutils
COPY --from=dev /hook-docker .
ENTRYPOINT ["/hook-docker"]
