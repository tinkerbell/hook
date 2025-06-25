# We are building a static acpid binary from source because the linuxkit/acpid image
# does not work 
FROM alpine:3.22 AS alpine

# Install build dependencies
RUN apk add --no-cache \
    gcc \
    musl-dev \
    make \
    git \
    autoconf \
    automake \
    libtool \
    linux-headers \
    wget \
    xz \
    patch \
    busybox-static \
    # Install the dynamically built acpid so that we can get the handler script and event files
    acpid

# Download and build acpid
ENV ACPID_VERSION=2.0.34
RUN wget https://sourceforge.net/projects/acpid2/files/acpid-${ACPID_VERSION}.tar.xz/download -O acpid-${ACPID_VERSION}.tar.xz && \
    tar -xf acpid-${ACPID_VERSION}.tar.xz

WORKDIR /acpid-${ACPID_VERSION}

# Fix musl compatibility - replace stat64/fstat64 with stat/fstat
RUN sed -i 's/struct stat64/struct stat/g' sock.c && \
    sed -i 's/fstat64/fstat/g' sock.c

# Build static binary with musl-compatible flags
RUN ./configure \
    --enable-static \
    --disable-shared \
    CFLAGS="-D_GNU_SOURCE -Os" \
    LDFLAGS="-static" && \
    make && \
    strip acpid && \
    cp acpid /usr/bin/

# Verify it's statically linked
RUN ldd /usr/bin/acpid 2>&1 | grep -q "not a dynamic executable" || echo "Warning: not statically linked"

# Copy BusyBox static binary and create poweroff symlink
RUN mkdir -p /stage/bin && cp /bin/busybox.static /bin/busybox && \
    ln -s /bin/busybox /stage/bin/poweroff && \
    ln -s /bin/busybox /stage/bin/logger && \
    # This is needed for the acpid handler scripts (/etc/acpi/handler.sh, /etc/acpi/events/anything) to work
    ln -s /bin/busybox /stage/bin/sh

FROM scratch
WORKDIR /
ENTRYPOINT []
COPY --from=alpine /usr/bin/acpid /usr/bin/
COPY --from=alpine /etc/acpi/events/anything /etc/acpi/events/anything
COPY --from=alpine /etc/acpi/handler.sh /etc/acpi/handler.sh
COPY --from=alpine /bin/busybox /bin/busybox
COPY --from=alpine /stage/ /
CMD ["/usr/bin/acpid", "-f", "-d"]