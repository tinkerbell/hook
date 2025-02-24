#!/usr/bin/env bash

function list_bootable_grub() {
	declare -g -A bootable_boards=()
	bootable_boards["generic"]="NOT=used" # A single, generic "board" for all grub bootables
}

function build_bootable_grub() {
	: "${bootable_info['INVENTORY_ID']:?"bootable_info['INVENTORY_ID'] is unset"}"
	: "${OUTPUT_ID:?"OUTPUT_ID is unset"}"

	declare hook_id="${bootable_info['INVENTORY_ID']}"
	declare bootable_img="bootable_grub_${OUTPUT_ID}.img"

	declare has_dtbs="${bootable_info['DTB']}"
	[[ -z "${has_dtbs}" ]] && has_dtbs="no"

	declare -A hook_files=(
		["kernel"]="vmlinuz-${OUTPUT_ID}"
		["initrd"]="initramfs-${OUTPUT_ID}"
	)

	if [[ "${has_dtbs}" == "yes" ]]; then
		hook_files["dtbs"]="dtbs-${OUTPUT_ID}.tar.gz"
	fi

	# Check if all the required files are present; if not, give instructions on how to build kernel and hook $hook_id
	for file in "${!hook_files[@]}"; do
		if [[ ! -f "out/hook/${hook_files[$file]}" ]]; then
			log error "Required file 'out/hook/${hook_files[$file]}' not found; please build the kernel and hook ${hook_id} first: ./build.sh kernel ${hook_id} && ./build.sh build ${hook_id}"
			exit 1
		fi
	done

	log info "Building grub bootable for hook ${hook_id}"

	# Prepare the base working directory in bootable/
	declare bootable_dir="grub"
	declare bootable_base_dir="bootable/${bootable_dir}"
	rm -rf "${bootable_base_dir}"
	mkdir -p "${bootable_base_dir}"

	# Prepare a directory that will be the root of the FAT32 partition
	declare fat32_root_dir="${bootable_base_dir}/fat32-root"
	mkdir -p "${fat32_root_dir}"

	# Kernel and initrd go directly in the root of the FAT32 partition
	cp -vp "out/hook/${hook_files['kernel']}" "${fat32_root_dir}/vmlinuz"
	cp -vp "out/hook/${hook_files['initrd']}" "${fat32_root_dir}/initrd.img"

	# Handle DTBs
	if [[ "${has_dtbs}" == "yes" ]]; then
		mkdir -p "${fat32_root_dir}/dtb"
		tar -C "${fat32_root_dir}/dtb" --strip-components=1 -xzf "out/hook/${hook_files["dtbs"]}"
		tree "${fat32_root_dir}"
	fi

	### @TODO: obtain and write grub binary to EFI directory
	### @TODO: write grub.cfg

	# Show the state
	du -h -d 1 "${bootable_base_dir}"
	tree "${bootable_base_dir}"

	# Use a Dockerfile to assemble a GPT image, with a single FAT32 partition, containing the files in the fat32-root directory
	# This is common across all GPT-based bootable media; the only difference is the ESP flag, which is set for UEFI bootable media.
	esp_partitition="yes" \
		create_image_fat32_root_from_dir "${bootable_base_dir}" "${bootable_img}" "${bootable_dir}/fat32-root"

	log info "Show info about produced image..."
	ls -lah "${bootable_base_dir}/${bootable_img}"

	log info "Done building grub bootable for hook ${hook_id}"
	output_bootable_media "${bootable_base_dir}/${bootable_img}" "hook-bootable-grub-${OUTPUT_ID}.img"

	return 0

}
