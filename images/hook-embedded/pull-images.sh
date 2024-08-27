#!/bin/bash

# This script is used to build container images that are embedded in HookOS.
# When HookOS boots up, the DinD container will have all the images in its cache.

set -euo pipefail

function docker_save_image() {
    local image="$1"
    local output_dir="$2"
    local output_file="${output_dir}/$(echo "${image}" | tr '/' '-')"

    docker save -o "${output_file}".tar "${image}"
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

function trap_handler() {
    local dind_container="$1"

    if [[ "${remove_dind_container}" == "true" ]]; then
        docker rm -f "${dind_container}" &> /dev/null
    else
        echo "DinD container NOT removed, please remove it manually"
    fi
}

function main() {
    local dind_container="$1"
    local images_file="$2"
    local arch="$3"
    local dind_container_image="$4"

    # Pull the images
    while IFS=" " read -r first_image image_tag || [ -n "${first_image}" ] ; do
        echo -e "----------------------- $first_image -----------------------"
        # Remove the image if it exists so that the image pulls the correct architecture
        docker_remove_image "${first_image}"
        docker_pull_image "${first_image}" "${arch}"
    done < "${images_file}"

    # Save the images
    local output_dir="${PWD}/images_tar"
    mkdir -p "${output_dir}"
    while IFS=" " read -r first_image image_tag || [ -n "${first_image}" ] ; do
        docker_save_image "${first_image}" "${output_dir}"
    done < "${images_file}"

    export remove_dind_container="true"
    # as this function maybe called multiple times, we need to ensure the container is removed
    trap "trap_handler ${dind_container}" RETURN
    # we're using set -e so the trap on RETURN will not be executed when a command fails
    trap "trap_handler ${dind_container}" EXIT

    # start DinD container
    # In order to avoid the src bind mount directory (./images/) ownership from changing to root
    # we don't bind mount to /var/lib/docker in the container because the DinD container is running as root and
    # will change the permissions of the bind mount directory (images/) to root.
    echo -e "Starting DinD container"
    echo -e "-----------------------"
    docker run -d --privileged --name "${dind_container}" -v "${PWD}/images_tar":/images_tar -v "${PWD}"/images/:/var/lib/docker-embedded/ -d "${dind_container_image}"

    # wait until the docker daemon is ready
    until docker exec "${dind_container}" docker info &> /dev/null; do
        sleep 1
        if [[ $(docker inspect -f '{{.State.Status}}' "${dind_container}") == "exited" ]]; then
            echo "DinD container exited unexpectedly"
            docker logs "${dind_container}"
            exit 1
        fi
    done

    # As hook-docker uses the overlay2 storage driver the DinD must use the overlay2 storage driver too.
    # make sure the overlay2 storage driver is used by the DinD container.
    # The VFS storage driver might get used if /var/lib/docker in the DinD container cannot be used by overlay2.
    storage_driver=$(docker exec "${dind_container}" docker info --format '{{.Driver}}')
    if [[ "${storage_driver}" != "overlay2" ]]; then
        export remove_dind_container="false"
        echo "DinD container is not using overlay2 storage driver, storage driver detected: ${storage_driver}"
        exit 1
    fi

    # remove the contents of /var/lib/docker-embedded so that any previous images are removed. Without this it seems to cause boot issues.
    docker exec "${dind_container}" sh -c "rm -rf /var/lib/docker-embedded/*"

    # Load the images
    for image_file in "${output_dir}"/*; do
        echo -e "Loading image: ${image_file}"
        docker exec "${dind_container}" docker load -i "/images_tar/$(basename ${image_file})"
    done

    # clean up tar files
    rm -rf "${output_dir}"/*

    # Create any tags for the images and remove any original tags
    while IFS=" " read -r first_image image_tag remove_original || [ -n "${first_image}" ] ; do
        if [[ "${image_tag}" != "" ]]; then
            docker exec "${dind_container}" docker tag "${first_image}" "${image_tag}"
            if [[ "${remove_original}" == "true" ]]; then
                docker exec "${dind_container}" docker rmi "${first_image}"
            fi
        fi
    done < "${images_file}"

    # We need to copy /var/lib/docker to /var/lib/docker-embedded in order for HookOS to use the Docker images in its build.
    docker exec "${dind_container}" sh -c "cp -a /var/lib/docker/* /var/lib/docker-embedded/"    
}

arch="${1-amd64}"
dind_container_name="hookos-dind"
images_file="images.txt"
dind_container_image="${2-docker:dind}"
main "${dind_container_name}" "${images_file}" "${arch}" "${dind_container_image}"
