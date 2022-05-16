# syntax=docker/dockerfile:experimental

FROM golang:1.17-alpine as dev
COPY . /src/
WORKDIR /src
ENV GO111MODULE=on
RUN --mount=type=cache,sharing=locked,id=gomod,target=/go/pkg/mod/cache \
    --mount=type=cache,sharing=locked,id=goroot,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -a -ldflags '-w -extldflags "-static"' -o /bootkit

FROM scratch
COPY --from=dev /bootkit .
ENTRYPOINT ["/bootkit"]
