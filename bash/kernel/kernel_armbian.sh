#!/usr/bin/env bash

declare -g ARMBIAN_BASE_ORAS_REF="${ARMBIAN_BASE_ORAS_REF:-"ghcr.io/armbian/os"}"

function calculate_kernel_version_armbian() {
	: "${inventory_id:?"ERROR: inventory_id is not defined"}"
	log info "Calculating version of Armbian kernel..."

	declare -g ARMBIAN_KERNEL_BASE_ORAS_REF="${ARMBIAN_BASE_ORAS_REF}/${ARMBIAN_KERNEL_ARTIFACT}"

	# If ARMBIAN_KERNEL_VERSION is unset, for using the latest kernel
	if [[ -z "${ARMBIAN_KERNEL_VERSION}" ]]; then
		log info "ARMBIAN_KERNEL_VERSION is unset, obtaining the most recently pushed-to tag of ${ARMBIAN_KERNEL_BASE_ORAS_REF}"
		declare latest_tag_for_docker_image
		get_latest_tag_for_docker_image_using_skopeo "${ARMBIAN_KERNEL_BASE_ORAS_REF}" ".\-S..." # regex to match the tag, like "6.1.84-Sxxxx"
		ARMBIAN_KERNEL_VERSION="${latest_tag_for_docker_image}"
		log info "Using most recent Armbian kernel tag: ${ARMBIAN_KERNEL_VERSION}"
	fi

	# output ID is just the inventory_id
	declare -g OUTPUT_ID="${inventory_id}"

	declare -g ARMBIAN_KERNEL_FULL_ORAS_REF_DEB_TAR="${ARMBIAN_KERNEL_BASE_ORAS_REF}:${ARMBIAN_KERNEL_VERSION}"
	declare -g ARMBIAN_KERNEL_MAJOR_MINOR_POINT="unknown"
	ARMBIAN_KERNEL_MAJOR_MINOR_POINT="$(echo -n "${ARMBIAN_KERNEL_VERSION}" | cut -d "-" -f 1)"
	log info "ARMBIAN_KERNEL_MAJOR_MINOR_POINT: ${ARMBIAN_KERNEL_MAJOR_MINOR_POINT}"

	# A helper script, as escaping bash into a RUN command in Dockerfile is a pain; included in input_hash later
	declare dockerfile_helper_filename="undefined.sh"
	produce_dockerfile_helper_apt_oras "kernel/" # will create the helper script in kernel/ directory; sets helper_name

	# Lets create a Dockerfile that will be used to obtain the artifacts needed, using ORAS binary
	declare -g ARMBIAN_KERNEL_DOCKERFILE="kernel/Dockerfile.autogen.armbian.${inventory_id}"
	echo "Creating Dockerfile '${ARMBIAN_KERNEL_DOCKERFILE}'... "
	cat <<- ARMBIAN_ORAS_DOCKERFILE > "${ARMBIAN_KERNEL_DOCKERFILE}"
		FROM debian:stable AS downloader
		# Call the helper to install curl, oras, and dpkg-dev
		ADD ./${dockerfile_helper_filename} /apt-oras-helper.sh
		RUN bash /apt-oras-helper.sh

		FROM downloader AS downloaded

		# lets create the output dir
		WORKDIR /armbian/output
		RUN echo getting kernel from ${ARMBIAN_KERNEL_FULL_ORAS_REF_DEB_TAR}

		WORKDIR /armbian

		# Pull the image from oras. This will contain a .tar file...
		RUN oras pull "${ARMBIAN_KERNEL_FULL_ORAS_REF_DEB_TAR}"

		# ... extract the .tar file to get .deb packages in the "global" subdir...
		RUN tar -xvf *.tar
		WORKDIR /armbian/global

		# ... extract the contents of the .deb packages linuxq-image-* ...
		RUN dpkg-deb --extract linux-image-*.deb /armbian/image

		WORKDIR /armbian/image

		# Get the kernel image...
		RUN cp -v boot/vmlinuz* /armbian/output/kernel

		# Create a tarball with the modules in lib.
		# Important: this tarball needs to have permissions for the root directory included! Otherwise linuxkit rootfs will have the wrong permissions on / (root)
		WORKDIR /armbian/modules_only
		RUN mv /armbian/image/lib /armbian/modules_only/
		RUN echo "Before cleaning: " && du -h -d 10 -x lib/modules | sort -h | tail -n 20
		# Trim the kernel modules to save space; hopefully your required hardware is not included here
		RUN rm -rf ./lib/modules/*/kernel/drivers/net/wireless ./lib/modules/*/kernel/sound ./lib/modules/*/kernel/drivers/media
		RUN rm -rf ./lib/modules/*/kernel/drivers/infiniband
		RUN echo "After cleaning: " &&  du -h -d 10 -x lib/modules | sort -h | tail -n 20
		RUN tar -cf /armbian/output/kernel.tar .

		# Create a tarball with the dtbs in usr/lib/linux-image-*
		WORKDIR /armbian/image
		RUN {  cd usr/lib/linux-image-* || { echo "No DTBS for this arch, empty tar..." && mkdir -p usr/lib/linux-image-no-dtbs && cd usr/lib/linux-image-* ; } ; }  && pwd && du -h -d 1 . && tar -czf /armbian/output/dtbs.tar.gz . && ls -lah /armbian/output/dtbs.tar.gz

		# Show the contents of the output dir
		WORKDIR /armbian/output
		RUN ls -lahtS

		# Output layer should be in the layout expected by LinuxKit (dtbs.tar.gz is ignored)
		FROM scratch
		COPY --from=downloaded /armbian/output/* /
	ARMBIAN_ORAS_DOCKERFILE

	declare input_hash="" short_input_hash=""
	input_hash="$(cat "${ARMBIAN_KERNEL_DOCKERFILE}" "kernel/${dockerfile_helper_filename}" | sha256sum - | cut -d ' ' -f 1)"
	short_input_hash="${input_hash:0:8}"
	kernel_oci_version="${ARMBIAN_KERNEL_MAJOR_MINOR_POINT}-${short_input_hash}"
	armbian_type="${inventory_id#"armbian-"}" # remove the 'armbian-' prefix from inventory_id, but keep the rest. "uefi" has "current/edge" and "arm64/x86" variants.
	kernel_oci_image="${HOOK_KERNEL_OCI_BASE}-armbian:${kernel_oci_version}-${armbian_type}"
	log info "kernel_oci_version: ${kernel_oci_version}"
	log info "kernel_oci_image: ${kernel_oci_image}"
}

function build_kernel_armbian() {
	log info "Building armbian kernel from deb-tar at ${ARMBIAN_KERNEL_FULL_ORAS_REF_DEB_TAR}"
	log info "Will build Dockerfile ${ARMBIAN_KERNEL_DOCKERFILE}"

	# Don't specify platform, our Dockerfile is multiarch, thus you can build x86 kernels in arm64 hosts and vice-versa ...
	docker buildx build --load "--progress=${DOCKER_BUILDX_PROGRESS_TYPE}" -t "${kernel_oci_image}" -f "${ARMBIAN_KERNEL_DOCKERFILE}" kernel
	# .. but enforce the target arch for LK in the final image via dump/edit-manifests/reimport trick
	ensure_docker_image_architecture "${kernel_oci_image}" "${kernel_info['DOCKER_ARCH']}"
}

function configure_kernel_armbian() {
	log error "Can't configure Armbian kernel from Hook, since they're prebuilt externally."
	log warn "Armbian kernel's configs are at https://github.com/armbian/build/tree/main/config/kernel"
	exit 3
}
