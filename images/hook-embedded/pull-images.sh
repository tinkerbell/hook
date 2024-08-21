#!/bin/bash

# This script is used to pull 
# This script is used to build an image that is embedded in HookOS.
# The image contains the /var/lib/docker directory which has pulled images
# from the images.txt file. When HookOS boots up, the DinD container will
# have all the images in its cache.

# The purpose of doing this is so that EKS Anywhere doesn't have to set registry
# and registry credentials in each Hardware object.

# In my testing the initramfs for HookOS with these embedded images was about 334MB.
# The machine booting HookOS needed 6GB of RAM to boot up successfully.

set -euo pipefail

function main() {
    local dind_container="$1"
    local images_file="$2"
    # as this function maybe called multiple times, we need to ensure the container is removed
    trap "docker rm -f ${dind_container} &> /dev/null" RETURN
    # we're using set -e so the trap on RETURN will not be executed when a command fails
    trap "docker rm -f ${dind_container} &> /dev/null" EXIT
    # start DinD container
    # In order to avoid the src bind mount directory (./images/) ownership from changing to root
    # we don't bind mount to /var/lib/docker in the container because the DinD container is running as root and
    # will change the permissions of the bind mount directory (images/) to root.
    echo -e "Starting DinD container"
    echo -e "-----------------------"
    docker run -d --rm --privileged --name "${dind_container}" -v ${PWD}/images/:/var/lib/docker-embedded/ -d docker:dind

    # wait until the docker daemon is ready
    until docker exec "${dind_container}" docker info &> /dev/null; do
        sleep 1
    done

    # pull images from list
    # this expects a file named images.txt in the same directory as this script
    # the format of this file is line separated: <image> <optional tag>
    #
    # the || [ -n "$first_image" ] is to handle the last line of the file that doesn't have a newline.
    while IFS=" " read -r first_image image_tag || [ -n "$first_image" ] ; do
        echo -e "----------------------- $first_image -----------------------"
        docker exec "${dind_container}" docker pull $first_image
        if [[ $image_tag != "" ]]; then
            docker exec "${dind_container}" docker tag $first_image $image_tag
        fi
    done < "${images_file}"

    # remove the contents of /var/lib/docker-embedded so that any previous images are removed. Without this it seems to cause boot issues.
    docker exec "${dind_container}" sh -c "rm -rf /var/lib/docker-embedded/*"
    # We need to copy /var/lib/docker to /var/lib/docker-embedded in order for HookOS to use the Docker images in its build.
    docker exec "${dind_container}" sh -c "cp -a /var/lib/docker/* /var/lib/docker-embedded/"
}

arch="amd64"
dind_container_name="hookos-dind-${arch}"
images_file="images.txt"
main "${dind_container_name}" "${images_file}" "${arch}"