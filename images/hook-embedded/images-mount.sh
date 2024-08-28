#!/bin/sh

exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/var/log/embedded-images.log 2>&1

set -xeuo pipefail

# We can't have a Linuxkit "init" container that dumps its file contents to /var and be writable
# because the init process overwrites it and the contents are lost.
# Instead, we have the init container, with all the Docker images, dump its contents to /etc/embedded-images.
# Then we bind mount /etc/embedded-images to /run/images (/var/run is symlinked to /run) and make sure it's
# read/write. This allows the DinD container to bind mount /var/run/images to /var/lib/docker and the Docker
# images are available right away and /var/lib/docker is writable.
mkdir -p /run/images
mount -o bind,rw /etc/embedded-images/ /run/images
mount -o remount,rw /run/images
