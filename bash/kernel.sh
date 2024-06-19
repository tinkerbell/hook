#!/usr/bin/env bash

function obtain_kernel_data_from_id() {
	declare -g -A kernel_info=()
	declare -g kernel_oci_version="" kernel_oci_image=""

	log debug "Obtaining kernel data for kernel ID: '${1}'"

	get_kernel_info_dict "${1}"
	set_kernel_vars_from_info_dict
	kernel_calculate_version

	return 0
}

function kernel_calculate_version() {
	log debug "Running calculate version method: ${kernel_info[VERSION_FUNC]}"
	"${kernel_info[VERSION_FUNC]}"

	return 0
}

function kernel_build() {
	if [[ "${FORCE_BUILD_KERNEL:-"no"}" == "no" ]]; then
		# determine if it is already available in the OCI registry; if so, just pull and skip building/pushing
		if docker pull "${kernel_oci_image}"; then
			log info "Kernel image ${kernel_oci_image} already in registry; skipping build."
			log info "Set FORCE_BUILD_KERNEL=yes to force a build; use DO_PUSH=yes to also push after build."
			exit 0
		fi
	fi

	log debug "Kernel build method: ${kernel_info[BUILD_FUNC]}"
	"${kernel_info[BUILD_FUNC]}"

	# Push it to the OCI registry
	if [[ "${DO_PUSH:-"no"}" == "yes" ]]; then
		log info "Kernel built; pushing to ${kernel_oci_image}"
		docker push "${kernel_oci_image}"
	else
		log info "DO_PUSH not 'yes', not pushing."
	fi
}

function kernel_configure_interactive() {
	# bail if not interactive (stdin is a terminal)
	[[ ! -t 0 ]] && log error "not interactive, can't configure" && exit 1

	log debug "Configuring a kernel with $*"

	log debug "Kernel config method: ${kernel_info[CONFIG_FUNC]}"
	"${kernel_info[CONFIG_FUNC]}" "$@"
}

function resolve_latest_kernel_version_lts() { # Produces KERNEL_POINT_RELEASE
	declare -i cache_valid=0

	# As the point release can and does change frequently, Users can specify if they
	# want to use the latest known point release version. This allows users to build
	# HookOS using an existing kernel container image from the registry. This only works with
	# unauthenticated registries.
	if [[ -n "${USE_LATEST_BUILT_KERNEL}" ]]; then
		reg="$(echo ${HOOK_KERNEL_OCI_BASE} | cut -d'/' -f1)"
		repo="$(echo ${HOOK_KERNEL_OCI_BASE} | cut -d'/' -f2-)"
		# expected format is: 6.6.32-14b8be17 (major.minor.point-hash)
		latest_point_release="$(curl -sL "https://${reg}/v2/${repo}/tags/list" | jq -r ".tags[]" | grep -e "^${KERNEL_MAJOR}.${KERNEL_MINOR}" | sort -V | tail -n1 | cut -d"-" -f1 | cut -d"." -f3)"
		log info "Using latest point release from registry ${HOOK_KERNEL_OCI_BASE} for kernel ${KERNEL_MAJOR}.${KERNEL_MINOR}: ${latest_point_release}"
		KERNEL_POINT_RELEASE="${latest_point_release}"
		return 0
	fi

	if [[ -f "${CACHE_DIR}/kernel-releases.json" ]]; then
		log debug "Found disk cached kernel-releases.json"
		# if the cache is older than 2 hours, refresh it
		if [[ "$(find "${CACHE_DIR}/kernel-releases.json" -mmin +120)" ]]; then
			log warn "Cached kernel-releases.json is older than 2 hours, will refresh..."
		else
			log info "Using cached kernel-releases.json"
			cache_valid=1
		fi
	fi

	# if no valid cache found, grab for kernel.org
	if [[ ${cache_valid} -eq 0 ]]; then
		log info "Fetching kernel releases JSON info from kernel.org..."
		curl -sL "https://www.kernel.org/releases.json" -o "${CACHE_DIR}/kernel-releases.json"
	fi

	# shellcheck disable=SC2002 # cat is not useless. my cat's stylistic
	POINT_RELEASE_TRI="$(cat "${CACHE_DIR}/kernel-releases.json" | jq -r ".releases[].version" | grep -v -e "^next\-" -e "\-rc" | grep -e "^${KERNEL_MAJOR}\.${KERNEL_MINOR}\.")"
	POINT_RELEASE="$(echo "${POINT_RELEASE_TRI}" | cut -d '.' -f 3)"
	log debug "POINT_RELEASE_TRI: ${POINT_RELEASE_TRI}"
	log debug "POINT_RELEASE: ${POINT_RELEASE}"
	KERNEL_POINT_RELEASE="${KERNEL_POINT_RELEASE:-"${POINT_RELEASE}"}"
}

function get_kernel_info_dict() {
	declare kernel="${1}"
	declare kernel_data_str="${inventory_dict[${kernel}]}"
	if [[ -z "${kernel_data_str}" ]]; then
		log error "No kernel data found for '${kernel}'; valid ones are: ${inventory_ids[*]} "
		exit 1
	fi
	log debug "Kernel data for '${kernel}': ${kernel_data_str}"
	eval "kernel_info=(${kernel_data_str})"
	# Post process
	kernel_info['BUILD_FUNC']="build_kernel_${kernel_info['METHOD']}"
	kernel_info['VERSION_FUNC']="calculate_kernel_version_${kernel_info['METHOD']}"
	kernel_info['CONFIG_FUNC']="configure_kernel_${kernel_info['METHOD']}"

	# Defaults for optional settings
	kernel_info['TEMPLATE']="${kernel_info['TEMPLATE']:-"hook"}"
	kernel_info['LINUXKIT_VERSION']="${kernel_info['LINUXKIT_VERSION']:-"${LINUXKIT_VERSION_DEFAULT}"}"

	# Ensure kernel_info a valid TAG
	if [[ -z "${kernel_info['TAG']}" ]]; then
		log error "No TAG found for kernel '${kernel}'"
		exit 1
	fi

	# convert ARCH (x86_64, aarch64) to docker-ARCH (amd64, arm64)
	case "${kernel_info['ARCH']}" in
		"x86_64") kernel_info['DOCKER_ARCH']="amd64" ;;
		"aarch64") kernel_info['DOCKER_ARCH']="arm64" ;;
		*) log error "ARCH ${kernel_info['ARCH']} not supported" && exit 1 ;;
	esac
}

function set_kernel_vars_from_info_dict() {
	# Loop over the keys in kernel_info dictionary
	for key in "${!kernel_info[@]}"; do
		declare -g "${key}"="${kernel_info[${key}]}"
		log debug "Set ${key} to ${kernel_info[${key}]}"
	done
}

function get_host_docker_arch() {
	declare -g host_docker_arch="unknown"
	# convert ARCH (x86_64, aarch64) to docker-ARCH (amd64, arm64)
	case "$(uname -m)" in
		"x86_64") host_docker_arch="amd64" ;;
		"aarch64") host_docker_arch="arm64" ;;
		*) log error "ARCH $(uname -m) not supported" && exit 1 ;;
	esac
	return 0
}
