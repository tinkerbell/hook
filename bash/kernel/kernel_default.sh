#!/usr/bin/env bash

set -e

function calculate_kernel_version_default() {
	# Make sure inventory_id is defined or exit with an error; using a one liner
	: "${inventory_id:?"ERROR: inventory_id is not defined"}"
	log debug "Starting calculate_kernel_version_default for inventory_id='${inventory_id}'"

	# Calculate the input DEFCONFIG
	declare -g INPUT_DEFCONFIG="${KCONFIG}-${KERNEL_MAJOR}.${KERNEL_MINOR}.y-${ARCH}"
	if [[ ! -f "kernel/configs/${INPUT_DEFCONFIG}" ]]; then
		log error "kernel/configs/${INPUT_DEFCONFIG} does not exist, check inputs/envs"
		exit 1
	fi

	# The default kernel output id is just the arch (for compatibility with the old hook)
	# One can override with FORCE_OUTPUT_ID, which will be prepended to ARCH.
	# If that is not set, and KCONFIG != generic, an output will be generated with KCONFIG, MAJOR, MINOR, ARCH.
	# Lastly if using USE_KERNEL_ID, that will be used instead of the default inventory_id.
	declare -g OUTPUT_ID="${ARCH}"
	if [[ "x${FORCE_OUTPUT_ID}x" != "xx" ]]; then
		declare -g OUTPUT_ID="${FORCE_OUTPUT_ID}-${ARCH}"
	elif [[ "${KCONFIG}" != "generic" ]]; then
		OUTPUT_ID="${KCONFIG}-${KERNEL_MAJOR}.${KERNEL_MINOR}.y-${ARCH}"
	elif [[ -n "${USE_KERNEL_ID}" ]]; then
		OUTPUT_ID="${inventory_id}"
	fi

	# Calculate the KERNEL_ARCH from ARCH; also what is the cross-compiler package needed for the arch
	declare -g KERNEL_ARCH="" KERNEL_CROSS_COMPILE_PKGS="" KERNEL_OUTPUT_IMAGE=""
	case "${ARCH}" in
		"x86_64")
			KERNEL_ARCH="x86"
			KERNEL_CROSS_COMPILE_PKGS="crossbuild-essential-amd64"
			KERNEL_CROSS_COMPILE="x86_64-linux-gnu-"
			KERNEL_OUTPUT_IMAGE="arch/x86_64/boot/bzImage"
			;;
		"aarch64")
			KERNEL_ARCH="arm64"
			KERNEL_CROSS_COMPILE_PKGS="crossbuild-essential-arm64"
			KERNEL_CROSS_COMPILE="aarch64-linux-gnu-"
			KERNEL_OUTPUT_IMAGE="arch/arm64/boot/Image"
			;;
		*) log error "ERROR: ARCH ${ARCH} not supported" && exit 1 ;;
	esac

	# Grab the latest version from kernel.org
	declare -g KERNEL_POINT_RELEASE="${KERNEL_POINT_RELEASE:-""}"
	resolve_latest_kernel_version_lts

	# Calculate a version and hash for the OCI image
	# Hash the Dockerfile and the input defconfig together
	declare input_hash="" short_input_hash=""
	input_hash="$(cat "kernel/configs/${INPUT_DEFCONFIG}" "kernel/Dockerfile" | sha256sum - | cut -d ' ' -f 1)"
	short_input_hash="${input_hash:0:8}"
	kernel_oci_version="${KERNEL_MAJOR}.${KERNEL_MINOR}.${KERNEL_POINT_RELEASE}-${short_input_hash}"

	kernel_id_to_use="${inventory_id}"
	if [[ -n "${USE_KERNEL_ID}" ]]; then
		log warn "USE_KERNEL_ID is set to '${USE_KERNEL_ID}'; using it instead of the default inventory_id '${inventory_id}'."
		kernel_id_to_use="${USE_KERNEL_ID}"
	fi

	kernel_oci_image="${HOOK_KERNEL_OCI_BASE}:${kernel_oci_version}"

	# Log the obtained version & images to stderr
	log info "Kernel arch: ${KERNEL_ARCH} (for ARCH ${ARCH})"
	log info "Kernel version: ${KERNEL_MAJOR}.${KERNEL_MINOR}.${KERNEL_POINT_RELEASE}"
	log info "Kernel OCI version: ${kernel_oci_version}"
	log info "Kernel OCI image: ${kernel_oci_image}"
	log info "Kernel cross-compiler: ${KERNEL_CROSS_COMPILE} (in pkgs ${KERNEL_CROSS_COMPILE_PKGS})"
}

function common_build_args_kernel_default() {
	build_args+=(
		"--build-arg" "KERNEL_OUTPUT_IMAGE=${KERNEL_OUTPUT_IMAGE}"
		"--build-arg" "KERNEL_CROSS_COMPILE_PKGS=${KERNEL_CROSS_COMPILE_PKGS}" # This is not used in the Dockerfile, to maximize cache hits
		"--build-arg" "KERNEL_CROSS_COMPILE=${KERNEL_CROSS_COMPILE}"
		"--build-arg" "KERNEL_ARCH=${KERNEL_ARCH}"
		"--build-arg" "KERNEL_MAJOR=${KERNEL_MAJOR}"
		"--build-arg" "KERNEL_MAJOR_V=v${KERNEL_MAJOR}.x"
		"--build-arg" "KERNEL_MINOR=${KERNEL_MINOR}"
		"--build-arg" "KERNEL_VERSION=${KERNEL_MAJOR}.${KERNEL_MINOR}.${KERNEL_POINT_RELEASE}"
		"--build-arg" "KERNEL_SERIES=${KERNEL_MAJOR}.${KERNEL_MINOR}.y"
		"--build-arg" "KERNEL_POINT_RELEASE=${KERNEL_POINT_RELEASE}"
		"--build-arg" "INPUT_DEFCONFIG=${INPUT_DEFCONFIG}"
	)
}

function configure_kernel_default() {
	log info "Configuring default kernel: $*"

	declare -a build_args=()
	common_build_args_kernel_default
	log info "Will configure with: ${build_args[*]}"

	declare configurator_image="${kernel_oci_image}-configurator"

	# Build the config stage
	log info "Building kernel-configurator Dockerfile stage..."
	(
		cd kernel
		# Build the "kernel-configurator" target from the Dockerfile; tag it separately
		docker buildx build --load "--progress=${DOCKER_BUILDX_PROGRESS_TYPE}" "${build_args[@]}" --target kernel-configurator -t "${configurator_image}" .
	)
	log info "Built kernel-configurator Dockerfile stage..."

	if [[ "$1" == "one-shot" ]]; then
		log info "Running one-shot configuration, modifying ${INPUT_DEFCONFIG} ..."
		(
			cd kernel
			# Run the built container; mount kernel/configs as /host; run config directly and extract from container
			docker run -it --rm -v "$(pwd)/configs:/host" "${configurator_image}" bash "-c" "make menuconfig && make savedefconfig && cp -v defconfig /host/${INPUT_DEFCONFIG}"
		)
		log info "Kernel config finished. File ${INPUT_DEFCONFIG} is modified in your local copy."
	else
		log info "Starting an interactive shell in Dockerfile kernel-configurator stage..."
		(
			cd kernel
			# Run the built container; mount kernel/configs as /host
			cat <<- INSTRUCTIONS
				*** Starting a shell in the Docker kernel-configurator stage.
				*** The config ${INPUT_DEFCONFIG} is already in place in .config (and already expanded).
				*** You can run "make menuconfig" to interactively configure the kernel.
				*** After configuration, you should run "make savedefconfig" to obtain a "defconfig" file.
				*** You can then run "cp -v defconfig /host/${INPUT_DEFCONFIG}" to copy it to the build host for commiting.
			INSTRUCTIONS
			docker run -it --rm -v "$(pwd)/configs:/host" "${configurator_image}" bash
		)
	fi
	return 0
}

function build_kernel_default() {
	log info "Building default kernel"
	declare -a build_args=()
	common_build_args_kernel_default
	log info "Will build with: ${build_args[*]}"

	(
		cd kernel
		docker buildx build --load "--progress=${DOCKER_BUILDX_PROGRESS_TYPE}" "${build_args[@]}" -t "${kernel_oci_image}" .
	)

}
