#!/usr/bin/env bash

function produce_kernels_flavours_inventory() {
	declare -g -A inventory_dict=()
	declare -g -A bootable_inventory_dict=()

	produce_default_kernel_inventory
	produce_armbian_kernel_inventory

	# if a function `produce_custom_kernel_inventory` exists, call it.
	if type -t produce_custom_kernel_inventory &> /dev/null; then
		log info "Custom kernel inventory function found, calling it."
		produce_custom_kernel_inventory
	fi

	# extract keys & make readonly
	declare -g -a -r inventory_ids=("${!inventory_dict[@]}")                   # extract the _keys_ from the inventory_ids dict
	declare -g -A -r inventory_dict                                            # make kernels_data dict readonly
	declare -g -a -r bootable_inventory_ids=("${!bootable_inventory_dict[@]}") # extract the _keys_ from the inventory_ids dict
	declare -g -A -r bootable_inventory_dict                                   # make kernels_data dict readonly

	return 0
}

function produce_default_kernel_inventory() {
	##### METHOD=default; Hook's own kernel, in kernel/ directory
	## Hook default kernel, source code stored in `kernel` dir in this repo -- currently 5.10.y
	define_id "hook-default-amd64" METHOD='default' ARCH='x86_64' TAG='standard' SUPPORTS_ISO='yes' \
		KERNEL_MAJOR='5' KERNEL_MINOR='10' KCONFIG='generic' TYPE='source'
	add_bootable_id "grub-amd64" HANDLER='grub' SERIAL_CONSOLE='ttyS0' TAG='standard'

	define_id "hook-default-arm64" METHOD='default' ARCH='aarch64' TAG='standard' SUPPORTS_ISO='yes' \
		KERNEL_MAJOR='5' KERNEL_MINOR='10' KCONFIG='generic' TYPE='source'
	add_bootable_id "grub-arm64" HANDLER='grub' SERIAL_CONSOLE='ttyAMA0' TAG='standard'

	## A 'peg' is not really a 'hook': for development purposes; testing new LK version and simpler LK configurations, using the default kernel
	define_id "peg-default-amd64" METHOD='default' ARCH='x86_64' TAG='dev' \
		USE_KERNEL_ID='hook-default-amd64' TEMPLATE='peg' \
		KERNEL_MAJOR='5' KERNEL_MINOR='10' KCONFIG='generic' TYPE='source'

	## development purposes: trying out kernel 6.6.y
	define_id "hook-latest-lts-amd64" METHOD='default' ARCH='x86_64' TAG='lts' SUPPORTS_ISO='yes' \
		KERNEL_MAJOR='6' KERNEL_MINOR='6' KCONFIG='generic' FORCE_OUTPUT_ID='latest-lts' TYPE='source'
	add_bootable_id "grub-latest-lts-amd64" SERIAL_CONSOLE='ttyS0' HANDLER='grub' TAG='lts'

	define_id "hook-latest-lts-arm64" METHOD='default' ARCH='aarch64' TAG='lts' SUPPORTS_ISO='yes' \
		KERNEL_MAJOR='6' KERNEL_MINOR='6' KCONFIG='generic' FORCE_OUTPUT_ID='latest-lts' TYPE='source'
	add_bootable_id "grub-latest-lts-arm64" SERIAL_CONSOLE='ttyAMA0' HANDLER='grub' TAG='lts'
}

##### METHOD=armbian; Foreign kernels, taken from Armbian's OCI repos. Those are "exotic" kernels for certain SoC's.
#                    edge = (release candidates or stable but rarely LTS, more aggressive patching)
#                    current = (LTS kernels, stable-ish patching)
#                    vendor/legacy = (vendor/BSP kernels, stable patching, NOT mainline, not frequently rebased)
#                    Check https://github.com/orgs/armbian/packages?tab=packages&q=kernel- for possibilities
#                    nb: when no ARMBIAN_KERNEL_VERSION, will use the first tag returned, high traffic, low cache rate.
#                        one might set eg ARMBIAN_KERNEL_VERSION='6.7.10-xxxx' to use a fixed version.
function produce_armbian_kernel_inventory() {
	### SBC-oriented:
	## Armbian meson64 (Amlogic) edge Khadas VIM3/3L, Radxa Zero/2, LibreComputer Potatos, and many more
	define_id "armbian-meson64-edge" METHOD='armbian' ARCH='aarch64' TAG='armbian-sbc' ARMBIAN_KERNEL_ARTIFACT='kernel-meson64-edge' TYPE='external'
	add_bootable_id "uboot-aml" HANDLER='armbian_uboot_amlogic' TAG='armbian-sbc' UBOOT_TYPE='extlinux' CONSOLE_EXTRA_ARGS=',115200' # all meson64, mainline kernel and u-boot, uses extlinux to boot

	## Armbian bcm2711 (Broadcom) current, from RaspberryPi Foundation with many CNCF-landscape fixes and patches; for the RaspberryPi 3b+/4b/5
	define_id "armbian-bcm2711-current" METHOD='armbian' ARCH='aarch64' TAG='armbian-sbc' ARMBIAN_KERNEL_ARTIFACT='kernel-bcm2711-current' TYPE='external'
	add_bootable_id "rpi" HANDLER='rpi_firmware' TAG='armbian-sbc'

	## Armbian rockchip64 (Rockchip) edge, for many rk356x/3399 SoCs. As of late December 2024, also for rk3588.
	define_id "armbian-rockchip64-edge" METHOD='armbian' ARCH='aarch64' TAG='armbian-sbc' ARMBIAN_KERNEL_ARTIFACT='kernel-rockchip64-edge' TYPE='external'
	add_bootable_id "uboot-rk" HANDLER='armbian_uboot_rockchip' TAG='armbian-sbc' UBOOT_TYPE='extlinux' CONSOLE_EXTRA_ARGS=',1500000' # rk3588, mainline u-boot, uses extlinux to boot

	## Armbian genio (Mediatek) collabora/edge, for Mediatek Genio 1200 and others.
	define_id "armbian-genio-edge" METHOD='armbian' ARCH='aarch64' TAG='armbian-sbc' ARMBIAN_KERNEL_ARTIFACT='kernel-genio-collabora'

	## Armbian rk35xx (Rockchip) vendor, for rk3566, rk3568, rk3588, rk3588s SoCs -- 6.1-rkr4.1 - BSP / vendor kernel, roughly equivalent to Android's 6.1.84
	# Use with edk2 (v0.9.1+) or mainline u-boot + EFI: matches the DT included in https://github.com/edk2-porting/edk2-rk3588 _after_ v0.9.1
	define_id "armbian-rk35xx-vendor" METHOD='armbian' ARCH='aarch64' TAG='armbian-sbc' ARMBIAN_KERNEL_ARTIFACT='kernel-rk35xx-vendor' TYPE='external'
	add_bootable_id "uboot-rk35xx-vendor" HANDLER='armbian_uboot_rockchip_vendor' TAG='armbian-sbc' CONSOLE_EXTRA_ARGS=',1500000'

	###  Armbian mainline Generic UEFI kernels, for EFI capable machines might use those:
	## Armbian generic edge UEFI kernel for arm64
	define_id "armbian-uefi-arm64-edge" METHOD='armbian' ARCH='aarch64' TAG='standard armbian-uefi' ARMBIAN_KERNEL_ARTIFACT='kernel-arm64-edge' TYPE='external'
	add_bootable_id "grub-armbian-uefi-arm64" HANDLER='grub' SERIAL_CONSOLE='ttyAMA0' DTB='yes' TAG='standard'

	## Armbian generic edge UEFI kernel (Armbian calls it x86)
	define_id "armbian-uefi-x86-edge" METHOD='armbian' ARCH='x86_64' TAG='standard armbian-uefi' ARMBIAN_KERNEL_ARTIFACT='kernel-x86-edge' TYPE='external'
	add_bootable_id "grub-armbian-uefi-amd64" HANDLER='grub' SERIAL_CONSOLE='ttyS0' TAG='standard'
}
