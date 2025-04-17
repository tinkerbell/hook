function build_bootable_media() {
	log debug "would build build_bootable_media: '${*}'"

	declare -r -g bootable_id="${1}" # read-only variable from here

	# Check if the bootable_id is set, otherwise bomb
	if [[ -z "${bootable_id}" ]]; then
		log error "No bootable_id specified; please specify one of: ${bootable_inventory_ids[*]}"
		exit 1
	fi

	declare -g -A bootable_info=()
	get_bootable_info_dict "${bootable_id}"

	# Dump the bootable_info dict
	log debug "bootable_info: $(declare -p bootable_info)"

	# Get the kernel info from the bootable_info INVENTORY_ID
	declare -g -A kernel_info=()
	declare -g inventory_id="${bootable_info['INVENTORY_ID']}"
	get_kernel_info_dict "${inventory_id}"
	log debug "kernel_info: $(declare -p kernel_info)"
	set_kernel_vars_from_info_dict
	kernel_obtain_output_id # sets OUTPUT_ID

	# A few scenarios we want to support:
	# A) UEFI bootable media; GPT + ESP, FAT32, GRUB, kernel/initrd, grub.conf + some kernel command line.
	# B) RPi 3b/4/5 bootable media; GPT, non-ESP partition, FAT32, kernel/initrd, config.txt, cmdline.txt + some kernel command line.
	# C) Rockchip bootable media; GPT, non-ESP partition, FAT32, extlinux.conf + some kernel command line; write u-boot bin on top of GPT via Armbian sh
	# D) Amlogic bootable media; MBR, FAT32, extlinux.conf + some kernel command line; write u-boot bin on top of MBR via Armbian sh

	# General process:
	# Obtain extra variables from environment (BOARD/BRANCH for armbian); optional.
	# Obtain the latest Armbian u-boot version from the OCI registry, using Skopeo.
	# 1) (C/D) Obtain the u-boot artifact binaries using ORAS, given the version above; massage using Docker and extract the binaries.
	# 1) (A) Obtain grub somehow; LinuxKit has them ready-to-go in a Docker image.
	# 1) (B) Obtain the rpi firmware files (bootcode.bin, start.elf, fixup.dat) from the RaspberryPi Foundation
	# 2) Prepare the FAT32 contents; kernel/initrd, grub.conf, config.txt, cmdline.txt, extlinux.conf depending on scenario
	# 3) Create a GPT+ESP, GTP+non-ESP, or MBR partition table image with the contents of the FAT32 (use libguestfs)
	# 4) For the scenarios with u-boot, write u-boot binaries to the correct offsets in the image.

	# @TODO: possibly make sure the kernel and lk is built before delegating?

	# Call the bootable build function
	declare bootable_build_func="${bootable_info['BOOTABLE_BUILD_FUNC']}"
	log info "Calling bootable build function: ${bootable_build_func}"
	"${bootable_build_func}"

}

function get_bootable_info_dict() {
	declare bootable="${1}"
	declare bootable_data_str="${bootable_inventory_dict[${bootable}]}"
	if [[ -z "${bootable_data_str}" ]]; then
		log error "No bootable data found for '${bootable}'; valid ones are: ${bootable_inventory_ids[*]} "
		exit 1
	fi
	log debug "Bootable data for '${bootable}': ${bootable_data_str}"
	declare -g -A bootable_info
	eval "bootable_info=(${bootable_data_str})"

	# Post process; calculate bash function names given the handler
	bootable_info['BOOTABLE_LIST_FUNC']="list_bootable_${bootable_info['HANDLER']}"
	bootable_info['BOOTABLE_BUILD_FUNC']="build_bootable_${bootable_info['HANDLER']}"

	# Ensure bootable_info a valid TAG
	if [[ -z "${bootable_info['TAG']}" ]]; then
		log error "No TAG found for bootable '${bootable}'"
		exit 1
	fi
}

function output_bootable_media() {
	declare input_file="${1}"
	declare output_fn="${2}"
	declare full_output_fn="out/${output_fn}.xz"

	# If CARD_DEVICE is set, write the image to the device; otherwise, compress it
	if [[ -n "${CARD_DEVICE}" ]]; then
		write_image_to_device "${input_file}" "${CARD_DEVICE}"
		log info "Wrote image file ${input_file} to device ${CARD_DEVICE}; done."
		return 0
	fi

	declare human_size_input_file=""
	human_size_input_file="$(du -h "${input_file}" | awk '{print $1}')"

	# Use pixz to compress the image; use all CPU cores, default compression level
	log info "Compressing image file ${input_file} (${human_size_input_file}) to ${full_output_fn} -- wait..."
	pixz -i "${input_file}" -o "${full_output_fn}"

	declare human_size_output_file=""
	human_size_output_file="$(du -h "${full_output_fn}" | awk '{print $1}')"
	log info "Compressed image file to ${full_output_fn} (${human_size_output_file})"

	return 0
}

function write_image_to_device() {
	local image_file="${1}"
	local device="${2}"
	if [[ -b "${device}" && -f "${image_file}" ]]; then
		log info "Writing image file ${image_file} to device ${device}"
		pv -p -b -r -c -N "dd" "${image_file}" | dd "of=${device}" bs=1M iflag=fullblock oflag=direct status=none
		log info "Waiting for fsync()..."
		sync
	else
		if [[ -n ${device} ]]; then
			log error "Device ${device} not found or image file ${image_file} not found"
			exit 3
		fi
	fi
}

function fill_array_bootable_tinkerbell_kernel_parameters() {
	declare -g -a bootable_tinkerbell_kernel_params=() # output global var
	declare -r board_id="${1}"                         # board_id is the first argument

	declare TINK_WORKER_IMAGE="${TINK_WORKER_IMAGE:-"ghcr.io/tinkerbell/tink-agent:latest"}"
	declare TINK_TLS="${TINK_TLS:-"false"}"
	declare TINK_GRPC_PORT="${TINK_GRPC_PORT:-"42113"}"
	declare TINK_SERVER="${TINK_SERVER:-"tinkerbell"}" # export TINK_SERVER="192.168.66.75"
	declare WORKER_ID="${WORKER_ID:-"${board_id}"}"    # export WORKER_ID="11:22:33:44:55:66"

	log info "WORKER_ID is set to '${WORKER_ID}'"
	log info "TINK_WORKER_IMAGE is set to '${TINK_WORKER_IMAGE}'"
	log info "TINK_SERVER is set to '${TINK_SERVER}'"
	log info "TINK_TLS is set to '${TINK_TLS}'"
	log info "TINK_GRPC_PORT is set to '${TINK_GRPC_PORT}'"

	bootable_tinkerbell_kernel_params+=(
		"worker_id=${WORKER_ID}"
		"tink_worker_image=${TINK_WORKER_IMAGE}"
		"grpc_authority=${TINK_SERVER}:${TINK_GRPC_PORT}"
		"tinkerbell_tls=${TINK_TLS}"
		"syslog_host=${TINK_SERVER}"
	)
}
