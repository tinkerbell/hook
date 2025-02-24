#!/usr/bin/env bash

function list_bootable_grub() {
	declare -g -A bootable_boards=()
	bootable_boards["generic"]="NOT=used" # A single, generic "board" for all grub bootables
}

function build_bootable_grub() {
	: "${kernel_info['DOCKER_ARCH']:?"kernel_info['DOCKER_ARCH'] is unset"}"
	: "${bootable_info['INVENTORY_ID']:?"bootable_info['INVENTORY_ID'] is unset"}"
	: "${OUTPUT_ID:?"OUTPUT_ID is unset"}"

	declare hook_id="${bootable_info['INVENTORY_ID']}"
	declare bootable_img="bootable_grub_${OUTPUT_ID}.img"
	declare kernel_command_line="" # @TODO: common stuff for tink, etc

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
	fi

	# Grab the GRUB binaries from the LinuxKit Docker images
	declare grub_arch="${kernel_info['DOCKER_ARCH']}"
	declare grub_linuxkit_image="linuxkit/grub-dev:4184bd7644a0edf73d4fe8a55171fe06f4b4d738" # See https://github.com/linuxkit/linuxkit/blob/master/tools/grub/Dockerfile for the latest
	declare fat32_efi_dir="${fat32_root_dir}/EFI/BOOT"
	mkdir -p "${fat32_efi_dir}"

	download_grub_binaries_from_linuxkit_docker_images "${fat32_efi_dir}" "${grub_arch}" "${grub_linuxkit_image}"

	cat <<- GRUB_CFG > "${fat32_efi_dir}/grub.cfg"
		set timeout=0
		set gfxpayload=text
		menuentry 'Tinkerbell Hook' {
			linux /vmlinuz ${kernel_command_line}
			initrd /initrd.img
		}
	GRUB_CFG

	# Show the state
	du -h -d 1 "${bootable_base_dir}"
	log_tree "${bootable_base_dir}" "debug" "State of the bootable directory"

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

function download_grub_binaries_from_linuxkit_docker_images() {
	declare output_dir="${1}"
	declare arch="${2}"
	declare image="${3}"
	log info "Grabbing GRUB bins for arch '${arch}' from image '${image}'..."

	# Lets create a Dockerfile that will be used to obtain the artifacts needed
	declare -g grub_grabber_dockerfile="bootable/Dockerfile.autogen.grub_grabber"
	log info "Creating Dockerfile '${grub_grabber_dockerfile}'... "

	cat <<- GRUB_GRABBER_DOCKERFILE > "${grub_grabber_dockerfile}"
		FROM --platform=linux/${arch} ${image} AS grub-build-${arch}
		FROM scratch
		COPY --from=grub-build-${arch} /*.EFI /
	GRUB_GRABBER_DOCKERFILE

	# Now, build the Dockerfile and output the fat32 image directly
	log info "Building Dockerfile for GRUB grabber and outputting directly to '${output_dir}'..."
	docker buildx build --output "type=local,dest=${output_dir}" "--progress=${DOCKER_BUILDX_PROGRESS_TYPE}" -f "${grub_grabber_dockerfile}" bootable

	log info "Done, GRUB binaries are in ${output_dir}"
	log_tree "${output_dir}" "debug" "State of the GRUB binaries directory"
}
