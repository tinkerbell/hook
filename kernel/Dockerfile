FROM debian:stable as kernel-source-unpacked
ENV DEBIAN_FRONTEND=noninteractive

# crossbuild-essentials are pretty heavy; here we install for both architecures to maximize Docker layer hit cache rate during development, but only one will be used
RUN set -x && apt -o "Dpkg::Use-Pty=0" -y update && \
      apt -o "Dpkg::Use-Pty=0" -y install curl xz-utils gnupg2 flex bison libssl-dev libelf-dev bc libncurses-dev kmod \
                     crossbuild-essential-amd64 crossbuild-essential-arm64 && \
      apt -o "Dpkg::Use-Pty=0" -y clean

ARG KERNEL_MAJOR_V
ARG KERNEL_VERSION
ARG KERNEL_SOURCE=https://www.kernel.org/pub/linux/kernel/${KERNEL_MAJOR_V}/linux-${KERNEL_VERSION}.tar.xz
ARG KERNEL_SHA256_SUMS=https://www.kernel.org/pub/linux/kernel/${KERNEL_MAJOR_V}/sha256sums.asc
ARG KERNEL_PGP2_SIGN=https://www.kernel.org/pub/linux/kernel/${KERNEL_MAJOR_V}/linux-${KERNEL_VERSION}.tar.sign

# PGP keys: 589DA6B1 (greg@kroah.com) & 6092693E (autosigner@kernel.org) & 00411886 (torvalds@linux-foundation.org)
COPY /keys.asc /keys.asc

# Download and verify kernel
RUN set -x &&  \
    curl -fsSLO ${KERNEL_SHA256_SUMS} && \
    gpg2 -q --import keys.asc && \
    gpg2 --verify sha256sums.asc && \
    KERNEL_SHA256=$(grep linux-${KERNEL_VERSION}.tar.xz sha256sums.asc | cut -d ' ' -f 1) && \
    [ -f linux-${KERNEL_VERSION}.tar.xz ] || curl -fsSLO ${KERNEL_SOURCE} && \
    echo "${KERNEL_SHA256}  linux-${KERNEL_VERSION}.tar.xz" | sha256sum -c - && \
    xz -T 0 -d linux-${KERNEL_VERSION}.tar.xz && \
    curl -fsSLO ${KERNEL_PGP2_SIGN} && \
    gpg2 --verify linux-${KERNEL_VERSION}.tar.sign linux-${KERNEL_VERSION}.tar && \
    cat linux-${KERNEL_VERSION}.tar | tar --absolute-names -x && mv /linux-${KERNEL_VERSION} /linux


FROM kernel-source-unpacked as kernel-with-config

ARG INPUT_DEFCONFIG
ARG KERNEL_ARCH
ARG KERNEL_CROSS_COMPILE

ENV KERNEL_ARCH=${KERNEL_ARCH}
ENV ARCH=${KERNEL_ARCH}
ENV CROSS_COMPILE=${KERNEL_CROSS_COMPILE}
ENV KCFLAGS="-fdiagnostics-color=always -fno-pie"
ENV KBUILD_BUILD_USER="hook"
ENV KBUILD_BUILD_HOST="tinkerbell"

# Copy just the defconfig needed for this build
WORKDIR /linux
COPY /configs/${INPUT_DEFCONFIG} /linux/.config

# Kernel config; copy the correct defconfig as .config, and run olddefconfig
RUN set -x && make "ARCH=${KERNEL_ARCH}" olddefconfig

# Use this stage to run kernel configuration tasks like menuconfig / savedefconfig etc with:
#   docker buildx build --load --progress=plain --build-arg KERNEL_VERSION=5.10.212 --build-arg KERNEL_SERIES=5.10.y -t hook-kernel:builder --target kernel-configurator .
#   docker run -it -v "$(pwd)":/out-config hook-kernel:builder
# Otherwise, since this stage is not referenced anywhere during normal build, it is completely skipped
FROM kernel-with-config as kernel-configurator
VOLUME /host


FROM kernel-with-config AS kernel-build

ARG KERNEL_OUTPUT_IMAGE

RUN mkdir /out

RUN sed -i 's/#define COMMAND_LINE_SIZE 2048/#define COMMAND_LINE_SIZE 4096/' arch/x86/include/asm/setup.h

# Kernel build. ENVs in previous stages are inherited; thus ARCH, CROSS_COMPILE, KCFLAGS, KBUILD_BUILD_USER, KBUILD_BUILD_HOST are available
RUN set -x && \
    echo "Cross compiler: ${CROSS_COMPILE}" && \
    make -j"$(getconf _NPROCESSORS_ONLN)" && \
    cp ${KERNEL_OUTPUT_IMAGE} /out/kernel && \
    cp System.map /out


# Modules, from lib/modules go into kernel.tar (will be extracted in root filesystem by linuxkit)
RUN set -x && \
    make -s -j"$(getconf _NPROCESSORS_ONLN)" INSTALL_MOD_PATH=/tmp/kernel-modules modules_install && \
    ( DVER=$(basename $(find /tmp/kernel-modules/lib/modules/ -mindepth 1 -maxdepth 1)) && \
      cd /tmp/kernel-modules/lib/modules/$DVER && \
      rm -f build source ) && \
    ( cd /tmp/kernel-modules && tar cf /out/kernel.tar . )

# For arches that have DTB's, eg arm64; they go separately into dtbs.tar; for arches that don't (x86), an empty dtbs.tar is created
RUN set -x && \
    mkdir -p /tmp/kernel-dtb && \
    case "$KERNEL_ARCH" in \
    arm64) \
        make -s -j"$(getconf _NPROCESSORS_ONLN)" INSTALL_DTBS_PATH=/tmp/kernel-dtb dtbs_install; \
        ;; \
    esac && \
     ( cd /tmp/kernel-dtb && tar czvf /out/dtbs.tar.gz . )

FROM scratch
ENTRYPOINT []
CMD []
WORKDIR /
COPY --from=kernel-build /out/* /
