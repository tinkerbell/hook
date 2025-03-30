function list_bootable_rpi_firmware() {
	declare -g -A bootable_boards=()
	bootable_boards["rpi"]="NOT=used"
}

function build_bootable_rpi_firmware() {
	: "${bootable_info['INVENTORY_ID']:?"bootable_info['INVENTORY_ID'] is unset"}"

	declare hook_id="${bootable_info['INVENTORY_ID']}"

	declare -A hook_files=(
		["kernel"]="vmlinuz-${hook_id}"
		["initrd"]="initramfs-${hook_id}"
		["dtbs"]="dtbs-${hook_id}.tar.gz"
	)

	# Check if all the required files are present; if not, give instructions on how to build kernel and hook $hook_id
	for file in "${!hook_files[@]}"; do
		if [[ ! -f "out/hook/${hook_files[$file]}" ]]; then
			log error "Required file 'out/hook/${hook_files[$file]}' not found; please build the kernel and hook ${hook_id} first: ./build.sh kernel ${hook_id} && ./build.sh build ${hook_id}"
			exit 1
		fi
	done

	log info "Building rpi for hook ${hook_id}"

	# Prepare the base working directory in bootable/
	declare bootable_dir="rpi"
	declare bootable_base_dir="bootable/${bootable_dir}"
	rm -rf "${bootable_base_dir}"
	mkdir -p "${bootable_base_dir}"

	# Prepare a directory that will be the root of the FAT32 partition
	declare fat32_root_dir="${bootable_base_dir}/fat32-root"
	mkdir -p "${fat32_root_dir}"

	# Kernel and initrd go directly in the root of the FAT32 partition
	cp -vp "out/hook/vmlinuz-${hook_id}" "${fat32_root_dir}/vmlinuz"
	cp -vp "out/hook/initramfs-${hook_id}" "${fat32_root_dir}/initrd.img"

	# Handle DTBs for rpi
	mkdir -p "${fat32_root_dir}/dtb"
	tar -C "${fat32_root_dir}/dtb" --strip-components=1 -xzf "out/hook/dtbs-${hook_id}.tar.gz"
	log_tree "${fat32_root_dir}" "debug" "State of the FAT32 directory pre-moving DTBs"

	# RPi: put DTBs directly in the fat32-root directory; overlays go into a subdirectory
	mv -v "${fat32_root_dir}/dtb/overlays" "${fat32_root_dir}/overlays"
	mv -v "${fat32_root_dir}/dtb/broadcom"/*.dtb "${fat32_root_dir}/"
	rm -rf "${fat32_root_dir}/dtb"
	log_tree "${fat32_root_dir}" "debug" "State of the FAT32 directory post-moving DTBs"

	# Write the Raspberry Pi firmware files
	rpi_write_binary_firmware_from_rpi_foundation "${fat32_root_dir}"
	rpi_write_config_txt "${fat32_root_dir}"
	rpi_write_cmdline_txt "${fat32_root_dir}"

	# Show the state
	du -h -d 1 "${bootable_base_dir}"
	tree "${bootable_base_dir}"

	# Use a Dockerfile to assemble a GPT image, with a single FAT32 partition, containing the files in the fat32-root directory
	# This is common across all GPT-based bootable media; the only difference is the ESP flag, which is set for UEFI bootable media but not for Rockchip/RaspberryPi
	# The u-boot binaries are written _later_ in the process, after the image is created, using Armbian's helper scripts.
	create_image_fat32_root_from_dir "${bootable_base_dir}" "bootable-media-rpi.img" "${bootable_dir}/fat32-root"

	log info "Show info about produced image..."
	ls -lah "${bootable_base_dir}/bootable-media-rpi.img"

	log info "Done building rpi bootable for hook ${hook_id}"
	output_bootable_media "${bootable_base_dir}/bootable-media-rpi.img" "hook-bootable-rpi.img"

	return 0

}

function rpi_write_binary_firmware_from_rpi_foundation() {
	declare rpi_firmware_base_url="https://raw.githubusercontent.com/raspberrypi/firmware/refs/tags/1.20241126/boot/"

	declare fat32_root_dir="${1}"
	declare -a rpi_firmware_files=(
		"bootcode.bin"
		"fixup4cd.dat"
		"fixup4.dat"
		"fixup4db.dat"
		"fixup4x.dat"
		"fixup_cd.dat"
		"fixup.dat"
		"fixup_db.dat"
		"fixup_x.dat"
		"LICENCE.broadcom"
		"start4cd.elf"
		"start4db.elf"
		"start4.elf"
		"start4x.elf"
		"start_cd.elf"
		"start_db.elf"
		"start.elf"
		"start_x.elf"
	)
	# Download the Raspberry Pi firmware files from the Raspberry Pi Foundation's GitHub repo:
	for file in "${rpi_firmware_files[@]}"; do
		log info "Downloading ${file}..."
		curl -sL -o "${fat32_root_dir}/${file}" "${rpi_firmware_base_url}/${file}"
	done

	return 0
}

function rpi_write_config_txt() {
	declare fat32_root_dir="${1}"
	cat <<- RPI_CONFIG_TXT > "${fat32_root_dir}/config.txt"
		# For more options and information see http://rptl.io/configtxt
		auto_initramfs=1
		# bootloader logs to serial, second stage
		enable_uart=1
		# disable Bluetooth, as having it enabled causes issues with the serial console due to fake Broadcom UART
		dtoverlay=disable-bt
		dtoverlay=vc4-kms-v3d
		max_framebuffers=2
		disable_fw_kms_setup=1
		disable_overscan=1
		arm_boost=1
		[cm4]
		otg_mode=1
		[cm5]
		dtoverlay=dwc2,dr_mode=host
		[all]
		kernel=vmlinuz
		initramfs initrd.img followkernel
		arm_64bit=1
	RPI_CONFIG_TXT
}

function rpi_write_cmdline_txt() {
	declare -g -a bootable_tinkerbell_kernel_params=()
	fill_array_bootable_tinkerbell_kernel_parameters "rpi"
	declare tinkerbell_args="${bootable_tinkerbell_kernel_params[*]}"

	declare fat32_root_dir="${1}"
	cat <<- RPI_CMDLINE_TXT > "${fat32_root_dir}/cmdline.txt"
		console=tty1 console=ttyAMA0,115200 loglevel=7 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory ${tinkerbell_args}
	RPI_CMDLINE_TXT
}
