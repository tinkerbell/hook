FROM golang:1.24-alpine AS dev
COPY . /src/
WORKDIR /src
RUN go mod download
RUN CGO_ENABLED=0 go build -a -ldflags '-s -w -extldflags "-static"' -o /bootkit

FROM scratch
COPY --from=dev /bootkit .
ENTRYPOINT ["/bootkit"]
