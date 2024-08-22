#!/bin/sh

set -xeuo pipefail

# This allows us to embed container images into HookOS.
# We assume that any images are stored in /etc/embedded-images.
# The /etc directory in Linuxkit is a read-only filesystem.
# DinD requires that its data directory is writable.
# So we bind mount /etc/embedded-images to /var/lib/docker to make it writable.
mount --bind /etc/embedded-images/ /var/lib/docker
mount -o remount,rw /var/lib/docker

/hook-docker