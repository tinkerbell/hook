#!/usr/bin/env bash

# less insane bash error control
set -o pipefail
set -e

source bash/linuxkit.sh
source bash/hook-lk-containers.sh
source kernel/bash/common.sh
source kernel/bash/kernel_default.sh
source kernel/bash/kernel_armbian.sh

# each entry in this array needs a corresponding one in the kernel_data dictionary-of-stringified-dictionaries below
declare -a kernels=(
	# Hook's own kernel, in kernel/ directory
	"hook-default-arm64" # Hook default kernel, source code stored in `kernel` dir in this repo
	"hook-default-amd64" # Hook default kernel, source code stored in `kernel` dir in this repo

	# External kernels, taken from Armbian's OCI repos. Those are "exotic" kernels for certain SoC's.
	"armbian-meson64-edge"    # Armbian meson64 (Amlogic) edge (release candidates or stable but rarely LTS) kernel
	"armbian-bcm2711-current" # Armbian bcm2711 (Broadcom) current (latest stable) kernel; for the RaspberryPi 3b+/4b/5
	"armbian-rockchip64-edge" # Armbian rockchip64 (Rockchip) edge (release candidates or stable but rarely LTS) kernel; NOT suitable for rk3588's, but yes for 3566/3568/3399

	# Non exotic, EFI capable (edk2 or such, not u-boot+EFI) machines might use those:
	"armbian-uefi-arm64-edge" # Armbian generic edge UEFI kernel
	"armbian-uefi-x86-edge"   # Armbian generic edge UEFI kernel (Armbian calls it x86)
)

# method & arch are always required, others are method-specific. excuse the syntax; bash has no dicts of dicts
declare -A kernel_data=(

	["hook-default-arm64"]="['METHOD']='default' ['ARCH']='aarch64' ['KERNEL_MAJOR']='5' ['KERNEL_MINOR']='10' ['KCONFIG']='generic' "
	["hook-default-amd64"]="['METHOD']='default' ['ARCH']='x86_64' ['KERNEL_MAJOR']='5' ['KERNEL_MINOR']='10' ['KCONFIG']='generic' "

	# Armbian kernels, check https://github.com/orgs/armbian/packages?tab=packages&q=kernel- for possibilities
	# nb: when no ARMBIAN_KERNEL_VERSION, will use the first tag returned, high traffic, low cache rate.
	#     One might set eg ['ARMBIAN_KERNEL_VERSION']='6.7.10-S9865-D7cc9-P277e-C9b73H61a9-HK01ba-Ve377-Bf200-R448a' to use a fixed version.
	["armbian-meson64-edge"]="['METHOD']='armbian' ['ARCH']='aarch64' ['ARMBIAN_KERNEL_ARTIFACT']='kernel-meson64-edge' "
	["armbian-bcm2711-current"]="['METHOD']='armbian' ['ARCH']='aarch64' ['ARMBIAN_KERNEL_ARTIFACT']='kernel-bcm2711-current' "
	["armbian-rockchip64-edge"]="['METHOD']='armbian' ['ARCH']='aarch64' ['ARMBIAN_KERNEL_ARTIFACT']='kernel-rockchip64-edge' "

	# Armbian Generic UEFI kernels
	["armbian-uefi-arm64-edge"]="['METHOD']='armbian' ['ARCH']='aarch64' ['ARMBIAN_KERNEL_ARTIFACT']='kernel-arm64-edge' "
	["armbian-uefi-x86-edge"]="['METHOD']='armbian' ['ARCH']='x86_64' ['ARMBIAN_KERNEL_ARTIFACT']='kernel-x86-edge' "
)

declare -g HOOK_KERNEL_OCI_BASE="${HOOK_KERNEL_OCI_BASE:-"quay.io/tinkerbellrpardini/kernel-"}"
declare -g HOOK_LK_CONTAINERS_OCI_BASE="${HOOK_LK_CONTAINERS_OCI_BASE:-"quay.io/tinkerbellrpardini/linuxkit-"}"

declare -g SKOPEO_IMAGE="${SKOPEO_IMAGE:-"quay.io/skopeo/stable:latest"}"


# @TODO: only works on Debian/Ubuntu-like
# Grab tooling needed: jq, from apt
[[ ! -f /usr/bin/jq ]] && apt update && apt install -y jq
# Grab tooling needed: envsubst, from gettext
[[ ! -f /usr/bin/envsubst ]] && apt update && apt install -y gettext-base

# Grab linuxkit from official GitHub releases; account for arm64/amd64 differences

declare -r -g kernel_id="${2:-"hook-default-amd64"}"

case "${1:-"build"}" in
	gha-matrix)
		# This is a GitHub Actions matrix build, so we need to produce a JSON array of objects, one for each kernel. Doing this in bash is painful.
		declare output_json="[" full_json=""
		declare -i counter=0
		for kernel in "${kernels[@]}"; do
			declare -A kernel_info
			get_kernel_info_dict "${kernel}"

			output_json+="{\"kernel\":\"${kernel}\",\"arch\":\"${kernel_info[ARCH]}\",\"docker_arch\":\"${kernel_info[DOCKER_ARCH]}\"}" # Possibly include a runs-on here if CI ever gets arm64 runners
			[[ $counter -lt $((${#kernels[@]} - 1)) ]] && output_json+=","                                                              # append a comma if not the last element
			counter+=1
		done
		output_json+="]"
		full_json="$(echo "${output_json}" | jq -c .)" # Pass it through jq for correctness check & compaction

		# let's reduce the output to get a JSON of all docker_arches. This is used for building the linuxkit containers.
		declare arches_json=""
		arches_json="$(echo -n "${full_json}" | jq -c 'map({docker_arch}) | unique')"

		# If under GHA, set a GHA output variable
		if [[ -z "${GITHUB_OUTPUT}" ]]; then
			echo "Would have set GHA output kernels_json to: ${full_json}" >&2
			echo "Would have set GHA output arches_json to: ${arches_json}" >&2
		else
			echo "kernels_json=${full_json}" >> "${GITHUB_OUTPUT}"
			echo "arches_json=${arches_json}" >> "${GITHUB_OUTPUT}"
		fi

		echo -n "${full_json}" # to stdout, for cli/jq etc
		;;

	linuxkit-containers)
		echo "Building all LinuxKit containers..." >&2
		build_all_hook_linuxkit_containers
		;;

	kernel-config | config-kernel)
		# bail if not interactive (stdin is a terminal)
		[[ ! -t 0 ]] && echo "not interactive, can't configure" >&2 && exit 1

		echo "Would configure a kernel" >&2

		declare -A kernel_info
		declare kernel_oci_version="" kernel_oci_image=""
		get_kernel_info_dict "${kernel_id}"
		set_kernel_vars_from_info_dict

		echo "Kernel calculate version method: ${kernel_info[VERSION_FUNC]}" >&2
		"${kernel_info[VERSION_FUNC]}"

		echo "Kernel config method: ${kernel_info[CONFIG_FUNC]}" >&2
		"${kernel_info[CONFIG_FUNC]}"
		;;

	kernel-build | build-kernel)
		declare -A kernel_info
		declare kernel_oci_version="" kernel_oci_image=""
		get_kernel_info_dict "${kernel_id}"
		set_kernel_vars_from_info_dict

		echo "Kernel calculate version method: ${kernel_info[VERSION_FUNC]}" >&2
		"${kernel_info[VERSION_FUNC]}"

		# determine if it is already available in the OCI registry; if so, just pull and skip building/pushing
		if docker pull "${kernel_oci_image}"; then
			echo "Kernel image ${kernel_oci_image} already in registry; skipping build" >&2
			exit 0
		fi

		echo "Kernel build method: ${kernel_info[BUILD_FUNC]}" >&2
		"${kernel_info[BUILD_FUNC]}"

		# Push it to the OCI registry
		if [[ "${DO_PUSH:-"no"}" == "yes" ]]; then
			echo "Kernel built; pushing to ${kernel_oci_image}" >&2
			docker push "${kernel_oci_image}" || true
		else
			echo "DO_PUSH not 'yes', not pushing." >&2
		fi

		;;

	build | linuxkit | all) # Build Hook proper, using the specified kernel
		declare -A kernel_info
		declare kernel_oci_version="" kernel_oci_image=""
		get_kernel_info_dict "${kernel_id}"
		set_kernel_vars_from_info_dict

		echo "Kernel calculate version method: ${kernel_info[VERSION_FUNC]}" >&2
		"${kernel_info[VERSION_FUNC]}"

		# Ensure OUTPUT_ID is set
		if [[ "${OUTPUT_ID}" == "" ]]; then
			echo "ERROR: \${OUTPUT_ID} is not set after ${kernel_info[VERSION_FUNC]}" >&2
			exit 1
		fi

		# If the image is in the local docker cache, skip building
		if [[ -n "$(docker images -q "${kernel_oci_image}")" ]]; then
			echo "Kernel image ${kernel_oci_image} already in local cache; trying a pull to update, but tolerate failures..." >&2
			docker pull "${kernel_oci_image}" || echo "Pull failed, using local image ${kernel_oci_image}" >&2
		else
			# Pull the kernel from the OCI registry
			echo "Pulling kernel from ${kernel_oci_image}" >&2
			docker pull "${kernel_oci_image}"
			# @TODO: if pull fails, build like build-kernel would.
		fi

		# Build the containers in this repo used in the LinuxKit YAML;
		build_all_hook_linuxkit_containers # sets HOOK_CONTAINER_BOOTKIT_IMAGE, HOOK_CONTAINER_DOCKER_IMAGE, HOOK_CONTAINER_MDEV_IMAGE

		# Template the linuxkit configuration file.
		# - You'd think linuxkit would take --build-args or something by now, but no.
		# - Linuxkit does have @pkg but that's only useful in its own repo (with pkgs/ dir)
		# - envsubst doesn't offer a good way to escape $ in the input, so we pass the exact list of vars to consider, so escaping is not needed

		# shellcheck disable=SC2016 # I'm using single quotes to avoid shell expansion, envsubst wants the dollar signs.
		# shellcheck disable=SC2002 # Again, no, I love my cat, leave me alone
		cat "hook.template.yaml" |
			HOOK_KERNEL_IMAGE="${kernel_oci_image}" HOOK_KERNEL_ID="${kernel_id} from ${kernel_oci_image}" \
				HOOK_CONTAINER_BOOTKIT_IMAGE="${HOOK_CONTAINER_BOOTKIT_IMAGE}" \
				HOOK_CONTAINER_DOCKER_IMAGE="${HOOK_CONTAINER_DOCKER_IMAGE}" \
				HOOK_CONTAINER_MDEV_IMAGE="${HOOK_CONTAINER_MDEV_IMAGE}" \
				envsubst '$HOOK_KERNEL_IMAGE $HOOK_KERNEL_ID $HOOK_CONTAINER_BOOTKIT_IMAGE $HOOK_CONTAINER_DOCKER_IMAGE $HOOK_CONTAINER_MDEV_IMAGE' > "hook.${kernel_id}.yaml"

		declare -g linuxkit_bin=""
		obtain_linuxkit_binary_cached # sets "${linuxkit_bin}"

		declare lk_output_dir="out/linuxkit-${kernel_id}"
		mkdir -p "${lk_output_dir}"

		declare -a lk_args=(
			"--docker"
			"--arch" "${kernel_info['DOCKER_ARCH']}"
			"--format" "kernel+initrd"
			"--name" "hook"
			"--dir" "${lk_output_dir}"
			"hook.${kernel_id}.yaml" # the linuxkit configuration file
		)

		echo "Building Hook with kernel ${kernel_id} using linuxkit: ${lk_args[*]}" >&2
		"${linuxkit_bin}" build "${lk_args[@]}"

		# @TODO: allow a "run" stage here.

		# rename outputs
		mv -v "${lk_output_dir}/hook-kernel" "${lk_output_dir}/vmlinuz-${OUTPUT_ID}"
		mv -v "${lk_output_dir}/hook-initrd.img" "${lk_output_dir}/initramfs-${OUTPUT_ID}"
		rm "${lk_output_dir}/hook-cmdline"

		# prepare out/hook dir with the kernel/initramfs pairs; this makes it easy to deploy to /opt/hook eg for stack chart (or nibs)
		mkdir -p "out/hook"
		mv -v "${lk_output_dir}/vmlinuz-${OUTPUT_ID}" "out/hook/vmlinuz-${OUTPUT_ID}"
		mv -v "${lk_output_dir}/initramfs-${OUTPUT_ID}" "out/hook/initramfs-${OUTPUT_ID}"

		declare -a output_files=("vmlinuz-${OUTPUT_ID}" "initramfs-${OUTPUT_ID}")

		# We need to extract /dtbs.tar.gz from the kernel image; linuxkit itself knows nothing about dtbs.
		# Export a .tar of the image using docker to stdout, read a single file from stdin and output it
		docker create --name "export-dtb-${OUTPUT_ID}" "${kernel_oci_image}" "command_is_irrelevant_here_container_is_never_started"
		(docker export "export-dtb-${OUTPUT_ID}" | tar -xO "dtbs.tar.gz" > "${lk_output_dir}/dtbs-${OUTPUT_ID}.tar.gz") || true # don't fail -- otherwise container is left behind forever
		docker rm "export-dtb-${OUTPUT_ID}"

		# Now process "${lk_output_dir}/dtbs-${OUTPUT_ID}.tar.gz so every file in it is prefixed with the path dtbs-${OUTPUT_ID}/
		# This is so that the tarball can be extracted in /boot/dtbs-${OUTPUT_ID} and not pollute /boot with a ton of dtbs
		declare dtbs_tmp_dir="${lk_output_dir}/extract-dtbs-${OUTPUT_ID}"
		mkdir -p "${dtbs_tmp_dir}"
		tar -xzf "${lk_output_dir}/dtbs-${OUTPUT_ID}.tar.gz" -C "${dtbs_tmp_dir}"
		# Get a count of .dtb files in the extracted dir
		declare -i dtb_count
		dtb_count=$(find "${dtbs_tmp_dir}" -type f -name "*.dtb" | wc -l)
		echo "Kernel includes ${dtb_count} DTB files..." >&2
		# If more than zero, let's tar them up adding a prefix
		if [[ $dtb_count -gt 0 ]]; then
			tar -czf "out/hook/dtbs-${OUTPUT_ID}.tar.gz" -C "${dtbs_tmp_dir}" --transform "s,^,dtbs-${OUTPUT_ID}/," .
			output_files+=("dtbs-${OUTPUT_ID}.tar.gz")
		else
			echo "No DTB files found in kernel image." >&2
		fi
		rm -rf "${dtbs_tmp_dir}"
		rm "${lk_output_dir}/dtbs-${OUTPUT_ID}.tar.gz"

		rmdir "${lk_output_dir}"

		# tar the files into out/hook.tar in such a way that vmlinuz and initramfs are at the root of the tar; pigz it
		# Those are the artifacts published to the GitHub release
		tar -cvf- -C "out/hook" "${output_files[@]}" | pigz > "out/hook-${OUTPUT_ID}.tar.gz"

		;;

	*)
		echo "Unknown command: ${1}; try build / kernel-build / kernel-config / gha-matrix" >&2
		exit 1
		;;

esac

echo "Success." >&2
exit 0
