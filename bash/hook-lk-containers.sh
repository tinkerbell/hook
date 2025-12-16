#!/usr/bin/env bash

function build_all_hook_linuxkit_containers() {
	log info "Building all LinuxKit containers..."
	: "${DOCKER_ARCH:?"ERROR: DOCKER_ARCH is not defined"}"

	# when adding new container builds here you'll also want to add them to the
	# `linuxkit_build` function in the linuxkit.sh file.
	# # NOTE: linuxkit containers must be in the images/ directory
	build_hook_linuxkit_container hook-bootkit "HOOK_CONTAINER_BOOTKIT_IMAGE" "${EXPORT_LK_CONTAINERS}" "${EXPORT_LK_CONTAINERS_DIR}"
	build_hook_linuxkit_container hook-docker "HOOK_CONTAINER_DOCKER_IMAGE" "${EXPORT_LK_CONTAINERS}" "${EXPORT_LK_CONTAINERS_DIR}"
	build_hook_linuxkit_container hook-udev "HOOK_CONTAINER_UDEV_IMAGE" "${EXPORT_LK_CONTAINERS}" "${EXPORT_LK_CONTAINERS_DIR}"
	build_hook_linuxkit_container hook-acpid "HOOK_CONTAINER_ACPID_IMAGE" "${EXPORT_LK_CONTAINERS}" "${EXPORT_LK_CONTAINERS_DIR}"
	build_hook_linuxkit_container hook-containerd "HOOK_CONTAINER_CONTAINERD_IMAGE" "${EXPORT_LK_CONTAINERS}" "${EXPORT_LK_CONTAINERS_DIR}"
	build_hook_linuxkit_container hook-runc "HOOK_CONTAINER_RUNC_IMAGE" "${EXPORT_LK_CONTAINERS}" "${EXPORT_LK_CONTAINERS_DIR}"
	build_hook_linuxkit_container hook-embedded "HOOK_CONTAINER_EMBEDDED_IMAGE" "${EXPORT_LK_CONTAINERS}" "${EXPORT_LK_CONTAINERS_DIR}"

	# We also use a bunch of linuxkit/xxx:v1.0.0 images; those would be pulled from Docker Hub (and thus subject to rate limits) for each Hook build.
	# Instead, we'll wrap them into a Dockerfile with just a FROM line, and build/push them ourselves.
	# Those versions are obtained from the references in https://github.com/linuxkit/linuxkit/tree/master/examples
	declare -A linuxkit_proxy_images=()
	linuxkit_proxy_images+=(["init"]="linuxkit/init:b5506cc74a6812dc40982cacfd2f4328f8a4b12a")
	linuxkit_proxy_images+=(["ca_certificates"]="linuxkit/ca-certificates:256f1950df59f2f209e9f0b81374177409eb11de")
	linuxkit_proxy_images+=(["firmware"]="linuxkit/firmware:68c2b29f28f2639020b9f8d55254d333498a30aa")
	linuxkit_proxy_images+=(["rngd"]="linuxkit/rngd:984eb580ecb63986f07f626b61692a97aacd7198")
	linuxkit_proxy_images+=(["sysctl"]="linuxkit/sysctl:97e8bb067cd9cef1514531bb692f27263ac6d626")
	linuxkit_proxy_images+=(["sysfs"]="linuxkit/sysfs:6d5bd933762f6b216744c711c6e876756cee9600")
	linuxkit_proxy_images+=(["modprobe"]="linuxkit/modprobe:4248cdc3494779010e7e7488fc17b6fd45b73aeb")
	linuxkit_proxy_images+=(["dhcpcd"]="linuxkit/dhcpcd:b87e9ececac55a65eaa592f4dd8b4e0c3009afdb")
	linuxkit_proxy_images+=(["openntpd"]="linuxkit/openntpd:2508f1d040441457a0b3e75744878afdf61bc473")
	linuxkit_proxy_images+=(["getty"]="linuxkit/getty:a86d74c8f89be8956330c3b115b0b1f2e09ef6e0")
	linuxkit_proxy_images+=(["sshd"]="linuxkit/sshd:08e5d4a46603eff485d5d1b14001cc932a530858")

	# each of those will handled the following way:
	# - create+clean a directory under images; eg for key "init" create images/hook-linuxkit-init
	#  (all of images/hook-linuxkit-* are .gitignored)
	# - create a Dockerfile with "FROM --platform=xxx linuxkit/init:v1.1.0" in that directory
	# - determine HOOK_CONTAINER_LINUXKIT_<key:toUpper>_IMAGE variable name
	# - call build_hook_linuxkit_container with that directory and variable name
	# that way, everything else works exactly as with the other images, and there's  now a DockerHub-free way of getting those images
	# it works because build_hook_linuxkit_container does content-based hashing; so tags should be stable for the same version
	# that potentializes the use of caching with docker save/load or other local caching mechanisms.
	declare lk_proxy_image_key="undetermined" lk_proxy_image_ref="undetermined" lk_proxy_image_dir="undetermined" lk_proxy_image_var="undetermined"
	for lk_proxy_image_key in "${!linuxkit_proxy_images[@]}"; do
		lk_proxy_image_ref="${linuxkit_proxy_images[${lk_proxy_image_key}]}"
		lk_proxy_image_dir="hook-linuxkit-${lk_proxy_image_key}"
		lk_proxy_image_var="HOOK_CONTAINER_LINUXKIT_$(echo "${lk_proxy_image_key}" | tr '[:lower:]' '[:upper:]')_IMAGE"
		log info "Preparing LinuxKit proxy image ${lk_proxy_image_ref} in ${lk_proxy_image_dir}, variable name ${lk_proxy_image_var}"
		rm -rf "images/${lk_proxy_image_dir}"
		mkdir -p "images/${lk_proxy_image_dir}"
		echo "FROM --platform=\${TARGETARCH} ${lk_proxy_image_ref}" > "images/${lk_proxy_image_dir}/Dockerfile"
		build_hook_linuxkit_container "${lk_proxy_image_dir}" "${lk_proxy_image_var}" "${EXPORT_LK_CONTAINERS}" "${EXPORT_LK_CONTAINERS_DIR}"
	done
}

function build_hook_linuxkit_container() {
	declare container_dir="${1}"
	declare template_var="${2}" # bash name reference, kind of an output var but weird
	declare container_base_dir="images"
	declare export_container_images="${3:-false}"
	declare export_container_images_dir="${4:-/tmp}"

	# Lets hash the contents of the directory and use that as a tag
	declare container_files_hash
	# NOTE: linuxkit containers must be in the images/ directory
	container_files_hash="$(find "${container_base_dir}/${container_dir}" -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)"
	declare container_files_hash_short="${container_files_hash:0:8}"

	declare container_oci_ref="${HOOK_LK_CONTAINERS_OCI_BASE}${container_dir}:${container_files_hash_short}-${DOCKER_ARCH}"
	log info "Consider building LK container ${container_oci_ref} from ${container_base_dir}/${container_dir} for platform ${DOCKER_ARCH}"
	hook_template_vars["${template_var}"]="${container_oci_ref}" # set the template var for envsubst

	# If the image is in the local docker cache, skip building
	log debug "Checking if image ${container_oci_ref} exists in local registry"
	if [[ -n "$(docker images -q "${container_oci_ref}")" ]]; then
		log info "Image ${container_oci_ref} exists in local registry, skipping build"
		# we try to push here because a previous build may have created the image
		# this is the case for GitHub Actions CI because we build PRs on the same self-hosted runner
		push_hook_linuxkit_container "${container_oci_ref}"

		# If export_container_images=yes then export images as tar.gzs to export_container_images_dir
		# This is mainly for CI to be able to pass built images between jobs
		if [[ "${export_container_images}" == "yes" ]]; then
			save_docker_image_to_tar_gz "${container_oci_ref}" "${export_container_images_dir}"
		fi
		return 0
	fi

	# Check if we can pull the image from registry; if so, skip the build.
	log debug "Checking if image ${container_oci_ref} can be pulled from remote registry"
	if docker pull "${container_oci_ref}"; then
		log info "Image ${container_oci_ref} pulled from remote registry, skipping build"
		# If export_container_images=yes then export images as tar.gzs to export_container_images_dir
		# This is mainly for CI to be able to pass built images between jobs
		if [[ "${export_container_images}" == "yes" ]]; then
			save_docker_image_to_tar_gz "${container_oci_ref}" "${export_container_images_dir}"
		fi
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

	# If export_container_images=yes then export images as tar.gzs to export_container_images_dir
	# This is mainly for CI to be able to pass built images between jobs
	if [[ "${export_container_images}" == "yes" ]]; then
		save_docker_image_to_tar_gz "${container_oci_ref}" "${export_container_images_dir}"
	fi

	return 0
}

function save_docker_image_to_tar_gz() {
	declare container_oci_ref="${1}"
	declare export_dir="${2:-/tmp}"

	# Create the export directory if it doesn't exist
	mkdir -p "${export_dir}"

	# Save the Docker image as a tar.gz file
	docker save "${container_oci_ref}" | gzip > "${export_dir}/$(basename "${container_oci_ref}" | sed 's/:/-/g').tar.gz"
	log info "Saved Docker image ${container_oci_ref} to ${export_dir}/$(basename "${container_oci_ref}" | sed 's/:/-/g').tar.gz"
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
