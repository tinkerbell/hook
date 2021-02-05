# syntax=docker/dockerfile:experimental

FROM golang:1.15-alpine as dev
COPY . /src/
WORKDIR /src
ENV GO111MODULE=on
RUN --mount=type=cache,sharing=locked,id=gomod,target=/go/pkg/mod/cache \
    --mount=type=cache,sharing=locked,id=goroot,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -a -ldflags '-w -extldflags "-static"' -o /tink-docker

FROM docker:19.03.8-dind
RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories
RUN apk update; apk add kexec-tools
COPY --from=dev /tink-docker .
ENTRYPOINT ["/tink-docker"]