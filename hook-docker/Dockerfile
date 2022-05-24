# syntax=docker/dockerfile:experimental

FROM golang:1.17-alpine as dev
COPY . /src/
WORKDIR /src
ENV GO111MODULE=on
RUN --mount=type=cache,sharing=locked,id=gomod,target=/go/pkg/mod/cache \
    --mount=type=cache,sharing=locked,id=goroot,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -a -ldflags '-w -extldflags "-static"' -o /hook-docker

FROM docker:20.10.15-dind
RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories
RUN apk update; apk add kexec-tools
COPY --from=dev /hook-docker .
ENTRYPOINT ["/hook-docker"]
