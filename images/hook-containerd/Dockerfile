FROM alpine:3.22 AS builder

ARG TARGETPLATFORM

# checkout and compile containerd
# Update `FROM` in `pkg/containerd/Dockerfile`, `pkg/init/Dockerfile` and
# `test/pkg/containerd/Dockerfile` when changing this.
ENV CONTAINERD_REPO=https://github.com/containerd/containerd.git

ENV CONTAINERD_COMMIT=v2.1.3
ENV NERDCTL_VERSION=2.1.2
ENV GOPATH=/go
RUN apk add go git
RUN mkdir -p $GOPATH/src/github.com/containerd && \
  cd $GOPATH/src/github.com/containerd && \
  git clone https://github.com/containerd/containerd.git && \
  cd $GOPATH/src/github.com/containerd/containerd && \
  git checkout $CONTAINERD_COMMIT
RUN apk add --no-cache btrfs-progs-dev gcc libc-dev linux-headers make libseccomp-dev
WORKDIR $GOPATH/src/github.com/containerd/containerd
RUN make binaries STATIC=1 EXTRA_FLAGS="-buildmode pie" EXTRA_LDFLAGS='-w -s -extldflags "-fno-PIC -static"' BUILDTAGS="static_build no_devmapper"

# install nerdctl
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then ARCHITECTURE=amd64; elif [ "$TARGETPLATFORM" = "linux/arm64" ]; then ARCHITECTURE=arm64; else ARCHITECTURE=amd64; fi \
  && wget https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION}-linux-${ARCHITECTURE}.tar.gz \
  && tar -zxvf nerdctl-${NERDCTL_VERSION}-linux-${ARCHITECTURE}.tar.gz -C /usr/local/bin/

RUN cp bin/containerd bin/ctr bin/containerd-shim-runc-v2 /usr/bin/
RUN strip /usr/bin/containerd /usr/bin/ctr /usr/bin/containerd-shim-runc-v2
RUN mkdir -p /opt/containerd

FROM scratch AS containerd-dev
ENTRYPOINT []
WORKDIR /
COPY --from=builder /usr/bin/containerd /usr/bin/ctr /usr/bin/containerd-shim-runc-v2 /usr/bin/
COPY --from=builder /go/src/github.com/containerd/containerd /go/src/github.com/containerd/containerd
COPY --from=builder /usr/local/bin/nerdctl /usr/bin/
COPY --from=builder /opt/containerd/ /opt/containerd/

# Dockerfile to build linuxkit/containerd for linuxkit
FROM alpine:3.22 AS alpine

RUN apk add tzdata binutils
RUN mkdir -p /etc/init.d && ln -s /usr/bin/service /etc/init.d/020-containerd

FROM containerd-dev

FROM scratch
ENTRYPOINT []
WORKDIR /
COPY --from=containerd-dev /usr/bin/containerd /usr/bin/ctr /usr/bin/containerd-shim-runc-v2 /usr/bin/
COPY --from=containerd-dev /usr/bin/nerdctl /usr/bin/
COPY --from=containerd-dev /opt/containerd/ /opt/containerd/
COPY --from=alpine /usr/share/zoneinfo/UTC /etc/localtime
COPY --from=alpine /etc/init.d/ /etc/init.d/
COPY etc etc/
COPY --from=alpine /etc/apk /etc/apk/
COPY --from=alpine /lib/apk /lib/apk/
