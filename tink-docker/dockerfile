# syntax=docker/dockerfile:experimental

FROM golang:1.15-alpine as dev
COPY . /src/
WORKDIR /src
ENV GO111MODULE=on
RUN --mount=type=cache,sharing=locked,id=gomod,target=/go/pkg/mod/cache \
    --mount=type=cache,sharing=locked,id=goroot,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -ldflags '-w -extldflags "-static"' -o /tink-docker

FROM docker:19.03.8-dind
COPY --from=dev /tink-docker .
ENTRYPOINT ["/tink-docker"]