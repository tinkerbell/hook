FROM golang:1.20-alpine as dev
COPY . /src/
WORKDIR /src
RUN go mod download
RUN CGO_ENABLED=0 go build -a -ldflags '-w -extldflags "-static"' -o /bootkit

FROM scratch
COPY --from=dev /bootkit .
ENTRYPOINT ["/bootkit"]
