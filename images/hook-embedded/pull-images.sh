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

function docker_save_image() {
    local image="$1"
    local output_dir="$2"
    local output_file="${output_dir}/$(echo "${image}" | tr '/' '-')"

    docker save -o "${output_file}" "${image}"
}

function docker_load_image() {
    local image_file="$1"
    local socket_location="$2"

    sudo -E DOCKER_HOST=unix://"${socket_location}" docker load -i "${image_file}"
}

function docker_pull_image() {
    local image="$1"
    local arch="${2-amd64}"

    docker pull --platform=linux/"${arch}" "${image}"
}

function docker_remove_image() {
    local image="$1"

    docker rmi "${image}" || true
}

function main() {
    local dind_container="$1"
    local images_file="$2"
    local arch="$3"
    local dind_container_image="$4"

    # Pull the images
    while IFS=" " read -r first_image image_tag || [ -n "${first_image}" ] ; do
        echo -e "----------------------- $first_image -----------------------"
        docker_remove_image "${first_image}"
        docker_pull_image "${first_image}" "${arch}"
    done < "${images_file}"

    # Save the images
    local output_dir="${PWD}/images_tar"
    mkdir -p "${output_dir}"
    while IFS=" " read -r first_image image_tag || [ -n "${first_image}" ] ; do
        docker_save_image "${first_image}" "${output_dir}"
    done < "${images_file}"

    # as this function maybe called multiple times, we need to ensure the container is removed
    trap "docker rm -f "${dind_container}" &> /dev/null" RETURN
    # we're using set -e so the trap on RETURN will not be executed when a command fails
    trap "docker rm -f "${dind_container}" &> /dev/null" EXIT

    # start DinD container
    # In order to avoid the src bind mount directory (./images/) ownership from changing to root
    # we don't bind mount to /var/lib/docker in the container because the DinD container is running as root and
    # will change the permissions of the bind mount directory (images/) to root.
    echo -e "Starting DinD container"
    echo -e "-----------------------"
    docker run -d --privileged --name "${dind_container}" -v ${PWD}/docker:/run -v ${PWD}/images/:/var/lib/docker-embedded/ -d "${dind_container_image}"

    # wait until the docker daemon is ready
    until docker exec "${dind_container}" docker info &> /dev/null; do
        sleep 1
        if [[ $(docker inspect -f '{{.State.Status}}' "${dind_container}") == "exited" ]]; then
            echo "DinD container exited unexpectedly"
            docker logs "${dind_container}"
            exit 1
        fi
    done

    # remove the contents of /var/lib/docker-embedded so that any previous images are removed. Without this it seems to cause boot issues.
    docker exec "${dind_container}" sh -c "rm -rf /var/lib/docker-embedded/*"

    # Load the images
    for image_file in "${output_dir}"/*; do
        docker_load_image "${image_file}" "${PWD}/docker/docker.sock"
    done

    # clean up tar files
    rm -rf "${output_dir}"/*

    # Create any tags for the images
    while IFS=" " read -r first_image image_tag || [ -n "${first_image}" ] ; do
        if [[ "${image_tag}" != "" ]]; then
            docker exec "${dind_container}" docker tag "${first_image}" "${image_tag}"
        fi
    done < "${images_file}"

    # We need to copy /var/lib/docker to /var/lib/docker-embedded in order for HookOS to use the Docker images in its build.
    docker exec "${dind_container}" sh -c "cp -a /var/lib/docker/* /var/lib/docker-embedded/"    
}

arch="${1-amd64}"
dind_container_name="hookos-dind-${arch}"
images_file="images.txt"
dind_container_image="${2-docker:dind}"
main "${dind_container_name}" "${images_file}" "${arch}" "${dind_container_image}"
