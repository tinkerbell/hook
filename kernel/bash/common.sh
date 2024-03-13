#!/usr/bin/env bash

set -e

function resolve_latest_kernel_version_lts() { # Produces KERNEL_POINT_RELEASE
	if [[ ! -f kernel-releases.json ]]; then
		echo "Getting kernel-releases.json from kernel.org" >&2
		curl "https://www.kernel.org/releases.json" > kernel-releases.json
	else
		echo "Using disk cached kernel-releases.json" >&2
	fi

	# shellcheck disable=SC2002 # cat is not useless. my cat's stylistic
	POINT_RELEASE_TRI="$(cat kernel-releases.json | jq -r ".releases[].version" | grep -v -e "^next\-" -e "\-rc" | grep -e "^${KERNEL_MAJOR}\.${KERNEL_MINOR}\.")"
	POINT_RELEASE="$(echo "${POINT_RELEASE_TRI}" | cut -d '.' -f 3)"
	echo "POINT_RELEASE_TRI: ${POINT_RELEASE_TRI}" >&2
	echo "POINT_RELEASE: ${POINT_RELEASE}" >&2
	KERNEL_POINT_RELEASE="${KERNEL_POINT_RELEASE:-"${POINT_RELEASE}"}"
}

function get_kernel_info_dict() {
	declare kernel="${1}"
	declare kernel_data_str="${kernel_data[${kernel}]}"
	if [[ -z "${kernel_data_str}" ]]; then
		echo "ERROR: No kernel data found for '${kernel}'; valid ones are: ${kernels[*]} " >&2
		exit 1
	fi
	echo "Kernel data for '${kernel}': ${kernel_data_str}" >&2
	eval "kernel_info=(${kernel_data_str})"
	# Post process
	kernel_info['BUILD_FUNC']="build_kernel_${kernel_info['METHOD']}"
	kernel_info['VERSION_FUNC']="calculate_kernel_version_${kernel_info['METHOD']}"
	kernel_info['CONFIG_FUNC']="configure_kernel_${kernel_info['METHOD']}"

	# convert ARCH (x86_64, aarch64) to docker-ARCH (amd64, arm64)
	case "${kernel_info['ARCH']}" in
		"x86_64") kernel_info['DOCKER_ARCH']="amd64" ;;
		"aarch64") kernel_info['DOCKER_ARCH']="arm64" ;;
		*) echo "ERROR: ARCH ${kernel_info['ARCH']} not supported" >&2 && exit 1 ;;
	esac
}

function set_kernel_vars_from_info_dict() {
	# Loop over the keys in kernel_info dictionary
	for key in "${!kernel_info[@]}"; do
		declare -g "${key}"="${kernel_info[${key}]}"
		echo "Set ${key} to ${kernel_info[${key}]}" >&2
	done
}
