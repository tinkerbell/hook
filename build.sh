#!/usr/bin/env bash

# bash error control
set -o pipefail
set -e

source bash/inventory.sh
source bash/common.sh
source bash/cli.sh
source bash/docker.sh
source bash/linuxkit.sh
source bash/hook-lk-containers.sh
source bash/shellcheck.sh
source bash/json-matrix.sh
source bash/kernel.sh
source bash/kernel/kernel_default.sh
source bash/kernel/kernel_armbian.sh

### Initialize the command-line handling. This should behave similar to `make`; PARAM=value pairs are accepted in any order mixed with non-param arguments.
declare -A -g CLI_PARSED_CMDLINE_PARAMS=()
declare -a -g CLI_NON_PARAM_ARGS=()
parse_command_line_arguments "${@}" # which fills the above vars & exports the key=value pairs from cmdline into environment
# From here on, no more $1 ${1} or similar. We've parsed it all into CLI_PARSED_CMDLINE_PARAMS (already exported in environment) or CLI_NON_PARAM_ARGS

### Configuration
declare -g HOOK_KERNEL_OCI_BASE="${HOOK_KERNEL_OCI_BASE:-"quay.io/tinkerbell/hook-kernel"}"
declare -g HOOK_LK_CONTAINERS_OCI_BASE="${HOOK_LK_CONTAINERS_OCI_BASE:-"quay.io/tinkerbell/"}"

declare -g SKOPEO_IMAGE="${SKOPEO_IMAGE:-"quay.io/skopeo/stable:latest"}"

# See https://github.com/linuxkit/linuxkit/releases
declare -g -r LINUXKIT_VERSION_DEFAULT="1.5.0" # LinuxKit version to use by default; each flavor can set its own too

# Directory to use for storing downloaded artifacts: LinuxKit binary, shellcheck binary, etc.
declare -g -r CACHE_DIR="${CACHE_DIR:-"cache"}"

# Type of --progress passed to invocations of `docker buildx build`; 'plain' includes all container output; 'tty' is more concise
# If debugging, or under GitHub Actions, always use plain progress so all output is shown
if [[ -n "${GITHUB_ACTIONS}" || "${DEBUG}" == "yes" ]]; then
	declare -g DOCKER_BUILDX_PROGRESS_TYPE="plain"
else # otherwise default to tty, but allow override
	declare -g DOCKER_BUILDX_PROGRESS_TYPE="${DOCKER_BUILDX_PROGRESS_TYPE:-"tty"}"
fi

# Set the default HOOK_VERSION; override with env var; -x exports it for envsubst later
declare -g -r -x HOOK_VERSION="${HOOK_VERSION:-"0.10.0"}"
log info "Using Hook version (HOOK_VERSION): ${HOOK_VERSION}"

### Inventory
produce_kernels_flavours_inventory # sets inventory_ids array and inventory_dict associative array

### Start processing
# Find the directory of this script and change to it so it behaves the same if called from another directory
declare -g SRC_ROOT=""
SRC_ROOT="$(cd "$(dirname "$0")" && pwd -P)"
declare -g -r SRC_ROOT="${SRC_ROOT}"
cd "${SRC_ROOT}" || exit 1

### Initialize cache
mkdir -p "${CACHE_DIR}" # ensure the directory exists

# Install OS dependencies
install_dependencies

# check the host's docker daemon
check_docker_daemon_for_sanity

# These commands take no paramters and are handled first, and exit early.
declare first_param="${CLI_NON_PARAM_ARGS[0]}"
if [[ -z "${first_param}" ]]; then # default it to "build" if not set, but warn users to be explicit.
	log warn "No command (first argument) specified; defaulting to 'build'; be explicit to avoid this warning."
	first_param="build"
else
	log info "Command (first argument): explicitely set to '${first_param}'"
fi
declare -g -r first_param="${first_param}" # make it a read-only variable

case "${first_param}" in
	shellcheck)
		download_prepare_shellcheck_bin
		run_shellcheck
		exit 0
		;;

	gha-matrix)
		output_gha_matrixes
		exit 0
		;;

	linuxkit-containers)
		build_all_hook_linuxkit_containers
		exit 0
		;;
esac

# All other commands take the kernel/flavor ID as 2nd parameter; the default depends on host architecture.
get_host_docker_arch                                         # sets host_docker_arch
declare default_kernel_id="hook-default-${host_docker_arch}" # nb: if you get a shellsheck error here, it is being run out of context. see bash/shellcheck.sh

declare second_param="${CLI_NON_PARAM_ARGS[1]}"
if [[ -z "${second_param}" ]]; then # default it to "build" if not set, but warn users to be explicit.
	log warn "No kernel/flavor ID (second argument) specified; defaulting to '${default_kernel_id}'; be explicit to avoid this warning."
	second_param="${default_kernel_id}"
else
	log info "Kernel/flavor ID (second argument): explicitely set to '${second_param}'"
fi
declare -r -g inventory_id="${second_param}" # inventory_id is now read-only
obtain_kernel_data_from_id "${inventory_id}" # Gather the information about the inventory_id now; this will exit if the inventory_id is not found

case "${first_param}" in
	kernel-config-shell | config-shell-kernel)
		kernel_configure_interactive "shell" # runs a shell in the kernel build environment
		;;

	config | kernel-config | config-kernel)
		kernel_configure_interactive "one-shot" # directly calls menuconfig & extracts a defconfig to build host
		;;

	kernel | kernel-build | build-kernel)
		kernel_build
		;;

	build | linuxkit) # Build Hook proper, using the specified kernel
		unset LK_RUN     # ensure unset, lest the build might also run the image
		linuxkit_build
		;;

	build-run-qemu | run-qemu | qemu-run | run | qemu)
		LK_RUN="qemu" linuxkit_build
		;;

	*)
		log error "Unknown command: '${first_param}'; try build / run / kernel-build / kernel-config / linuxkit-containers / gha-matrix"
		exit 1
		;;
esac

log info "Success."
exit 0
