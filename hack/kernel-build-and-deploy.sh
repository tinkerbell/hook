#!/usr/bin/env nix-shell
#!nix-shell -i bash ../shell.nix

BRANCH=$(git rev-parse --abbrev-ref HEAD)
IMG_REPOSITORY_ORG="docker.io/gianarb"
KERNEL_VERSION="5.10.x"

cd ./kernel

make -j 100 build_${KERNEL_VERSION}

if [[ "$BRANCH" == "master" ]]; then
    make -j 100 push_${KERNEL_VERSION} ORG=${IMG_REPOSITORY_ORG} NOTRUST=1
fi


