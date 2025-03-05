function build_bootable_media() {
	log info "would build build_bootable_media: '${*}'"

	declare -r -g bootable_id="${1}" # read-only variable from here
	#obtain_bootable_data_from_id "${bootable_id}" # Gather the information about the inventory_id now; this will exit if the inventory_id is not found

	declare -g -A bootable_info=()
	get_bootable_info_dict "${bootable_id}"

	# Dump the bootable_info dict
	log info "bootable_info: $(declare -p bootable_info)"

	# Get the kernel info from the bootable_info INVENTORY_ID
	declare -g -A kernel_info=()
	get_kernel_info_dict "${bootable_info['INVENTORY_ID']}"
	log info "kernel_info: $(declare -p kernel_info)"

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
