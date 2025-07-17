#!/bin/bash

set -xeuo pipefail

# This script downloads the Linux kernel source code and verifies it using GPG.

function verify() {
    local kernel_sha256_sums="$1"
    local kernel_version="$2"
    local kernel_source="$3"
    local kernel_pgp2_sign="$4"

    curl -fsSL ${kernel_sha256_sums} -o sha256sums.asc
    [ -f linux-${kernel_version}.tar.xz ] || curl -fsSLO ${kernel_source}
    gpg2 -q --import keys.asc
    gpg2 --verify sha256sums.asc
    KERNEL_SHA256=$(grep linux-${kernel_version}.tar.xz sha256sums.asc | cut -d ' ' -f 1)
    echo "${KERNEL_SHA256}  linux-${kernel_version}.tar.xz" | sha256sum -c -
    if [ $? -ne 0 ]; then
        return 1
    fi
    # Verify the signature of the kernel source
    [ -f linux-${kernel_version}.tar ] || xz -T 0 -d linux-${kernel_version}.tar.xz
    curl -fsSLO ${kernel_pgp2_sign}
    gpg2 --verify linux-${kernel_version}.tar.sign linux-${kernel_version}.tar
    if [ $? -ne 0 ]; then
        return 1
    fi
}

function extract() {
    local kernel_version="$1"

    if [ -d linux-${kernel_version} ]; then
        echo "Directory linux-${kernel_version} already exists, skipping extraction."
    else
        tar --absolute-names -xf linux-${kernel_version}.tar
        rm -rf ./linux
        mv ./linux-${kernel_version} ./linux
    fi
}

# Main script execution
function main() {
    local kernel_version="$1"
    local kernel_source="$2"
    local kernel_sha256_sums="$3"
    local kernel_pgp2_sign="$4"
    local kernel_source_backup="$5"
    local kernel_sha256_sums_backup="$6"
    local kernel_pgp2_sign_backup="$7"

    verify "${kernel_sha256_sums}" "${kernel_version}" "${kernel_source}" "${kernel_pgp2_sign}" || \
    verify "${kernel_sha256_sums_backup}" "${kernel_version}" "${kernel_source_backup}" "${kernel_pgp2_sign_backup}"

    extract "${kernel_version}"
}

main "$@"