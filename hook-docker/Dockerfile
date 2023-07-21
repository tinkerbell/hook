FROM golang:1.20-alpine as dev
COPY . /src/
WORKDIR /src
RUN CGO_ENABLED=0 go build -a -ldflags '-w -extldflags "-static"' -o /hook-docker

FROM docker:24.0.4-dind
RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories
RUN apk update; apk add kexec-tools
COPY --from=dev /hook-docker .
ENTRYPOINT ["/hook-docker"]
