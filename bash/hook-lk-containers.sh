#!/usr/bin/env bash

function build_all_hook_linuxkit_containers() {
	: "${DOCKER_ARCH:?"ERROR: DOCKER_ARCH is not defined"}"

	build_hook_linuxkit_container hook-bootkit HOOK_CONTAINER_BOOTKIT_IMAGE
	build_hook_linuxkit_container hook-docker HOOK_CONTAINER_DOCKER_IMAGE
	build_hook_linuxkit_container hook-mdev HOOK_CONTAINER_MDEV_IMAGE
}

function build_hook_linuxkit_container() {
	declare container_dir="${1}"
	declare -n output_var="${2}" # bash name reference, kind of an output var but weird

	# Lets hash the contents of the directory and use that as a tag
	declare container_files_hash
	container_files_hash="$(find "${container_dir}" -type f -print0 | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)"
	declare container_files_hash_short="${container_files_hash:0:8}"

	declare container_oci_ref="${HOOK_LK_CONTAINERS_OCI_BASE}${container_dir}:${container_files_hash_short}-${DOCKER_ARCH}"
	echo "Going to build container ${container_oci_ref} from ${container_dir} for platform ${DOCKER_ARCH}" >&2
	output_var="${container_oci_ref}" # the the name reference

	# Check if we can pull the image from registry; if so, skip the build.
	if docker pull "${container_oci_ref}"; then
		echo "Image ${container_oci_ref} already exists in registry, skipping build" >&2
		return 0
	fi

	(
		cd "${container_dir}" || exit 1
		docker buildx build -t "${container_oci_ref}" --load --platform "linux/${DOCKER_ARCH}" .
	)

	echo "Built ${container_oci_ref} from ${container_dir} for platform ${DOCKER_ARCH}" >&2

	# Push the image to the registry
	docker push "${container_oci_ref}" || {
		echo "Failed to push ${container_oci_ref} to registry" >&2
		exit 33
	}

	return 0
}
