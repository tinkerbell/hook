#!/usr/bin/env bash

function build_all_hook_linuxkit_containers() {
	log info "Building all LinuxKit containers..."
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
	log info "Consider building LK container ${container_oci_ref} from ${container_dir} for platform ${DOCKER_ARCH}"
	output_var="${container_oci_ref}" # the the name reference
	echo "${output_var}" > /dev/null  # no-op; just to avoid shellcheck SC2034 (unused var; but it is actually a bash nameref)

	# If the image is in the local docker cache, skip building
	log debug "Checking if image ${container_oci_ref} exists in local registry"
	if [[ -n "$(docker images -q "${container_oci_ref}")" ]]; then
		log info "Image ${container_oci_ref} exists in local registry, skipping build"
		return 0
	fi

	# Check if we can pull the image from registry; if so, skip the build.
	log debug "Checking if image ${container_oci_ref} can be pulled from remote registry"
	if docker pull "${container_oci_ref}"; then
		log info "Image ${container_oci_ref} pulled from remote registry, skipping build"
		return 0
	fi

	# If environment DO_BUILD_LK_CONTAINERS=no, we're being asked NOT to build this. Exit with an error.
	if [[ "${DO_BUILD_LK_CONTAINERS}" == "no" ]]; then
		log error "DO_BUILD_LK_CONTAINERS is set to 'no'; not building ${container_oci_ref}"
		exit 9
	fi

	log info "Building ${container_oci_ref} from ${container_dir} for platform ${DOCKER_ARCH}"
	(
		cd "${container_dir}" || exit 1
		docker buildx build -t "${container_oci_ref}" --load --platform "linux/${DOCKER_ARCH}" .
	)

	log info "Built ${container_oci_ref} from ${container_dir} for platform ${DOCKER_ARCH}"

	# Push the image to the registry, if DO_PUSH is set to yes
	if [[ "${DO_PUSH}" == "yes" ]]; then
		docker push "${container_oci_ref}" || {
			log error "Failed to push ${container_oci_ref} to registry"
			exit 33
		}
	else
		log info "Skipping push of ${container_oci_ref} to registry; set DO_PUSH=yes to push."
	fi

	return 0
}
