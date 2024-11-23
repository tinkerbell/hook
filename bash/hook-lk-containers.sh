#!/usr/bin/env bash

function build_all_hook_linuxkit_containers() {
	log info "Building all LinuxKit containers..."
	: "${DOCKER_ARCH:?"ERROR: DOCKER_ARCH is not defined"}"

	# when adding new container builds here you'll also want to add them to the
	# `linuxkit_build` function in the linuxkit.sh file.
	# # NOTE: linuxkit containers must be in the images/ directory
	build_hook_linuxkit_container hook-bootkit HOOK_CONTAINER_BOOTKIT_IMAGE
	build_hook_linuxkit_container hook-docker HOOK_CONTAINER_DOCKER_IMAGE
	build_hook_linuxkit_container hook-mdev HOOK_CONTAINER_MDEV_IMAGE
	build_hook_linuxkit_container hook-containerd HOOK_CONTAINER_CONTAINERD_IMAGE
	build_hook_linuxkit_container hook-runc HOOK_CONTAINER_RUNC_IMAGE
	build_hook_linuxkit_container hook-embedded HOOK_CONTAINER_EMBEDDED_IMAGE
}

function build_hook_linuxkit_container() {
	declare container_dir="${1}"
	declare -n output_var="${2}" # bash name reference, kind of an output var but weird
	declare container_base_dir="images"

	# Lets hash the contents of the directory and use that as a tag
	declare container_files_hash
	# NOTE: linuxkit containers must be in the images/ directory
	container_files_hash="$(find "${container_base_dir}/${container_dir}" -type f -print | LC_ALL=C sort | xargs sha256sum | sha256sum | cut -d' ' -f1)"
	declare container_files_hash_short="${container_files_hash:0:8}"

	declare container_oci_ref="${HOOK_LK_CONTAINERS_OCI_BASE}${container_dir}:${container_files_hash_short}-${DOCKER_ARCH}"
	log info "Consider building LK container ${container_oci_ref} from ${container_base_dir}/${container_dir} for platform ${DOCKER_ARCH}"
	output_var="${container_oci_ref}" # the the name reference
	echo "${output_var}" > /dev/null  # no-op; just to avoid shellcheck SC2034 (unused var; but it is actually a bash nameref)

	# If the image is in the local docker cache, skip building
	log debug "Checking if image ${container_oci_ref} exists in local registry"
	if [[ -n "$(docker images -q "${container_oci_ref}")" ]]; then
		log info "Image ${container_oci_ref} exists in local registry, skipping build"
		# we try to push here because a previous build may have created the image
		# this is the case for GitHub Actions CI because we build PRs on the same self-hosted runner
		push_hook_linuxkit_container "${container_oci_ref}"
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

	log info "Building ${container_oci_ref} from ${container_base_dir}/${container_dir} for platform ${DOCKER_ARCH}"
	(
		cd "${container_base_dir}/${container_dir}" || exit 1
		docker buildx build --load "--progress=${DOCKER_BUILDX_PROGRESS_TYPE}" -t "${container_oci_ref}" --platform "linux/${DOCKER_ARCH}" .
	)

	log info "Built ${container_oci_ref} from ${container_base_dir}/${container_dir} for platform ${DOCKER_ARCH}"

	push_hook_linuxkit_container "${container_oci_ref}"

	return 0
}


function push_hook_linuxkit_container() {
	declare container_oci_ref="${1}"

	# Push the image to the registry, if DO_PUSH is set to yes
	if [[ "${DO_PUSH}" == "yes" ]]; then
		docker push "${container_oci_ref}" || {
			log error "Failed to push ${container_oci_ref} to registry"
			exit 33
		}
	else
		log info "Skipping push of ${container_oci_ref} to registry; set DO_PUSH=yes to push."
	fi
}
