#!/usr/bin/env bash

function produce_kernels_flavours_inventory() {
	declare -g -A inventory_dict=()

	##### METHOD=default; Hook's own kernel, in kernel/ directory
	## Hook default kernel, source code stored in `kernel` dir in this repo -- currently 5.10.y
	define_id "hook-default-amd64" METHOD='default' ARCH='x86_64' TAG='standard' \
		KERNEL_MAJOR='5' KERNEL_MINOR='10' KCONFIG='generic'
	define_id "hook-default-arm64" METHOD='default' ARCH='aarch64' TAG='standard' \
		KERNEL_MAJOR='5' KERNEL_MINOR='10' KCONFIG='generic'

	## A 'peg' is not really a 'hook': for development purposes; testing new LK version and simpler LK configurations, using the default kernel
	define_id "peg-default-amd64" METHOD='default' ARCH='x86_64' TAG='dev' \
		USE_KERNEL_ID='hook-default-amd64' TEMPLATE='peg' LINUXKIT_VERSION='1.2.0' \
		KERNEL_MAJOR='5' KERNEL_MINOR='10' KCONFIG='generic'

	## development purposes: trying out kernel 6.6.y
	define_id "hook-latest-lts-amd64" METHOD='default' ARCH='x86_64' TAG='lts' \
		KERNEL_MAJOR='6' KERNEL_MINOR='6' KCONFIG='generic' FORCE_OUTPUT_ID='latest-lts'
	define_id "hook-latest-lts-arm64" METHOD='default' ARCH='aarch64' TAG='lts' \
		KERNEL_MAJOR='6' KERNEL_MINOR='6' KCONFIG='generic' FORCE_OUTPUT_ID='latest-lts'

	##### METHOD=armbian; Foreign kernels, taken from Armbian's OCI repos. Those are "exotic" kernels for certain SoC's.
	#                    edge = (release candidates or stable but rarely LTS, more aggressive patching)
	#                    current = (LTS kernels, stable-ish patching)
	#                    vendor/legacy = (vendor/BSP kernels, stable patching, NOT mainline, not frequently rebased)
	#                    Check https://github.com/orgs/armbian/packages?tab=packages&q=kernel- for possibilities
	#                    nb: when no ARMBIAN_KERNEL_VERSION, will use the first tag returned, high traffic, low cache rate.
	#                        one might set eg ARMBIAN_KERNEL_VERSION='6.7.10-xxxx' to use a fixed version.

	### SBC-oriented:
	## Armbian meson64 (Amlogic) edge Khadas VIM3/3L, Radxa Zero/2, LibreComputer Potatos, and many more
	define_id "armbian-meson64-edge" METHOD='armbian' ARCH='aarch64' TAG='armbian-sbc' ARMBIAN_KERNEL_ARTIFACT='kernel-meson64-edge'

	## Armbian bcm2711 (Broadcom) current, from RaspberryPi Foundation with many CNCF-landscape fixes and patches; for the RaspberryPi 3b+/4b/5
	define_id "armbian-bcm2711-current" METHOD='armbian' ARCH='aarch64' TAG='armbian-sbc' ARMBIAN_KERNEL_ARTIFACT='kernel-bcm2711-current'

	## Armbian rockchip64 (Rockchip) edge, for many rk356x/3399 SoCs. Not for rk3588!
	define_id "armbian-rockchip64-edge" METHOD='armbian' ARCH='aarch64' TAG='armbian-sbc' ARMBIAN_KERNEL_ARTIFACT='kernel-rockchip64-edge'

	## Armbian rk35xx (Rockchip) mainline bleeding edge for rk3588, rk3588s SoCs
	define_id "armbian-rk3588-edge" METHOD='armbian' ARCH='aarch64' TAG='armbian-sbc' ARMBIAN_KERNEL_ARTIFACT='kernel-rockchip-rk3588-edge'

	## Armbian rk35xx (Rockchip) vendor, for rk3566, rk3568, rk3588, rk3588s SoCs -- 6.1-rkr1 - BSP / vendor kernel
	# Use with edk2 (v0.9.1+) or mainline u-boot + EFI: matches the DT included in https://github.com/edk2-porting/edk2-rk3588 _after_ v0.9.1
	define_id "armbian-rk35xx-vendor" METHOD='armbian' ARCH='aarch64' TAG='armbian-sbc' ARMBIAN_KERNEL_ARTIFACT='kernel-rk35xx-vendor'

	###  Armbian mainline Generic UEFI kernels, for EFI capable machines might use those:
	## Armbian generic edge UEFI kernel (Armbian calls it x86)
	define_id "armbian-uefi-arm64-edge" METHOD='armbian' ARCH='aarch64' TAG='standard armbian-uefi' ARMBIAN_KERNEL_ARTIFACT='kernel-arm64-edge'

	## Armbian generic edge UEFI kernel (Armbian calls it x86)
	define_id "armbian-uefi-x86-edge" METHOD='armbian' ARCH='x86_64' TAG='standard armbian-uefi' ARMBIAN_KERNEL_ARTIFACT='kernel-x86-edge'

	#### END; extract keys & make readonly
	declare -g -a -r inventory_ids=("${!inventory_dict[@]}") # extract the _keys_ from the inventory_ids dict
	declare -g -A -r inventory_dict                          # make kernels_data dict readonly

	return 0
}
