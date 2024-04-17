#!/usr/bin/env bash

# bash error control
set -o pipefail
set -e

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
# each entry in this array needs a corresponding one in the kernel_data dictionary-of-stringified-dictionaries below
declare -a kernels=(
	# Hook's own kernel, in kernel/ directory
	"hook-default-arm64" # Hook default kernel, source code stored in `kernel` dir in this repo -- currently v5.10.213
	"hook-default-amd64" # Hook default kernel, source code stored in `kernel` dir in this repo -- currently v5.10.213
	"peg-default-amd64"  # A 'peg' is not really a 'hook': used for development only; Hook default kernel, minimal firmware; LinuxKit 1.2.0

	# External kernels, taken from Armbian's OCI repos. Those are "exotic" kernels for certain SoC's.
	# edge = (release candidates or stable but rarely LTS, more aggressive patching)
	# current = (LTS kernels, stable-ish patching)
	# vendor/legacy = (vendor/BSP kernels, stable patching, NOT mainline, not frequently rebased)
	"armbian-meson64-edge"    # Armbian meson64 (Amlogic) edge Khadas VIM3/3L, Radxa Zero/2, LibreComputer Potatos, and many more -- right now v6.7.10
	"armbian-bcm2711-current" # Armbian bcm2711 (Broadcom) current, from RaspberryPi Foundation with many CNCF-landscape fixes and patches; for the RaspberryPi 3b+/4b/5 -- v6.6.22
	"armbian-rockchip64-edge" # Armbian rockchip64 (Rockchip) edge, for many rk356x/3399 SoCs. Not for rk3588! -- right now v6.7.10
	"armbian-rk35xx-vendor"   # Armbian rk35xx (Rockchip) vendor, for rk3566, rk3568, rk3588, rk3588s SoCs -- 6.1-rkr1 - BSP / vendor kernel
	"armbian-rk3588-edge"     # Armbian rk35xx (Rockchip) mainline bleeding edge for rk3588, rk3588s SoCs -- 6.8.4

	# EFI capable (edk2 or such, not u-boot+EFI) machines might use those:
	"armbian-uefi-arm64-edge" # Armbian generic edge UEFI kernel - right now v6.8.1
	"armbian-uefi-x86-edge"   # Armbian generic edge UEFI kernel (Armbian calls it x86) - right now v6.8.1
)

# method & arch & tag are always required, others are method-specific. excuse the syntax; bash has no dicts of dicts
declare -A kernel_data=(

	["hook-default-arm64"]="['METHOD']='default' ['ARCH']='aarch64' ['TAG']='standard' ['KERNEL_MAJOR']='5' ['KERNEL_MINOR']='10' ['KCONFIG']='generic' "
	["hook-default-amd64"]="['METHOD']='default' ['ARCH']='x86_64' ['TAG']='standard' ['KERNEL_MAJOR']='5' ['KERNEL_MINOR']='10' ['KCONFIG']='generic' "

	# for development purposes; testing new LK version and simpler LK configurations, using the default kernel
	["peg-default-amd64"]="['METHOD']='default' ['ARCH']='x86_64' ['TAG']='dev' ['USE_KERNEL_ID']='hook-default-amd64' ['TEMPLATE']='peg' ['LINUXKIT_VERSION']='1.2.0' ['KERNEL_MAJOR']='5' ['KERNEL_MINOR']='10' ['KCONFIG']='generic'"

	# Armbian mainline kernels, check https://github.com/orgs/armbian/packages?tab=packages&q=kernel- for possibilities
	# nb: when no ARMBIAN_KERNEL_VERSION, will use the first tag returned, high traffic, low cache rate.
	#     One might set eg ['ARMBIAN_KERNEL_VERSION']='6.7.10-S9865-D7cc9-P277e-C9b73H61a9-HK01ba-Ve377-Bf200-R448a' to use a fixed version.
	["armbian-meson64-edge"]="['METHOD']='armbian' ['ARCH']='aarch64' ['TAG']='armbian-sbc' ['ARMBIAN_KERNEL_ARTIFACT']='kernel-meson64-edge' "
	["armbian-bcm2711-current"]="['METHOD']='armbian' ['ARCH']='aarch64' ['TAG']='armbian-sbc' ['ARMBIAN_KERNEL_ARTIFACT']='kernel-bcm2711-current' "
	["armbian-rockchip64-edge"]="['METHOD']='armbian' ['ARCH']='aarch64' ['TAG']='armbian-sbc' ['ARMBIAN_KERNEL_ARTIFACT']='kernel-rockchip64-edge' "
	["armbian-rk3588-edge"]="['METHOD']='armbian' ['ARCH']='aarch64' ['TAG']='armbian-sbc' ['ARMBIAN_KERNEL_ARTIFACT']='kernel-rockchip-rk3588-edge' "

	# Armbian mainline Generic UEFI kernels
	["armbian-uefi-arm64-edge"]="['METHOD']='armbian' ['ARCH']='aarch64' ['TAG']='standard armbian-uefi' ['ARMBIAN_KERNEL_ARTIFACT']='kernel-arm64-edge' "
	["armbian-uefi-x86-edge"]="['METHOD']='armbian' ['ARCH']='x86_64' ['TAG']='standard armbian-uefi' ['ARMBIAN_KERNEL_ARTIFACT']='kernel-x86-edge' "

	# Armbian Rockchip vendor kernel. For rk3566, rk3568, rk3588, rk3588s
	# Use with edk2 (v0.9.1+) or mainline u-boot + EFI
	# vendor - matches the DT included in https://github.com/edk2-porting/edk2-rk3588 _after_ v0.9.1
	# mainline u-boot also should work via pxelinux -> snp.efi + dtb
	["armbian-rk35xx-vendor"]="['METHOD']='armbian' ['ARCH']='aarch64' ['TAG']='armbian-sbc' ['ARMBIAN_KERNEL_ARTIFACT']='kernel-rk35xx-vendor' "

)

#declare -g HOOK_KERNEL_OCI_BASE="${HOOK_KERNEL_OCI_BASE:-"ghcr.io/rpardini/tinkerbell/kernel-"}"
#declare -g HOOK_LK_CONTAINERS_OCI_BASE="${HOOK_LK_CONTAINERS_OCI_BASE:-"ghcr.io/rpardini/tinkerbell/linuxkit-"}"
declare -g HOOK_KERNEL_OCI_BASE="${HOOK_KERNEL_OCI_BASE:-"quay.io/tinkerbellrpardini/kernel-"}"
declare -g HOOK_LK_CONTAINERS_OCI_BASE="${HOOK_LK_CONTAINERS_OCI_BASE:-"quay.io/tinkerbellrpardini/linuxkit-"}"

declare -g SKOPEO_IMAGE="${SKOPEO_IMAGE:-"quay.io/skopeo/stable:latest"}"

# See https://github.com/linuxkit/linuxkit/releases
declare -g -r LINUXKIT_VERSION_DEFAULT="1.0.1" # LinuxKit version to use by default; each flavor can set its own too

# Directory to use for storing downloaded artifacts: LinuxKit binary, shellcheck binary, etc.
declare -g -r CACHE_DIR="${CACHE_DIR:-"cache"}"

# Set the default HOOK_VERSION; override with env var; -x exports it for envsubst later
declare -g -r -x HOOK_VERSION="${HOOK_VERSION:-"0.9.0-alpha1"}"
log info "Using Hook version (HOOK_VERSION): ${HOOK_VERSION}"

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
declare -r -g kernel_id="${second_param}" # kernel_id is now read-only
obtain_kernel_data_from_id "${kernel_id}" # Gather the information about the kernel_id now; this will exit if the kernel_id is not found

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
