#!/usr/bin/env bash

declare -g ARMBIAN_BASE_ORAS_REF="${ARMBIAN_BASE_ORAS_REF:-"ghcr.io/armbian/os"}"

function calculate_kernel_version_armbian() {
	: "${kernel_id:?"ERROR: kernel_id is not defined"}"
	log info "Calculating version of Armbian kernel..."

	declare -g ARMBIAN_KERNEL_BASE_ORAS_REF="${ARMBIAN_BASE_ORAS_REF}/${ARMBIAN_KERNEL_ARTIFACT}"

	# If ARMBIAN_KERNEL_VERSION is unset, for using the latest kernel, this requires skopeo & jq
	if [[ -z "${ARMBIAN_KERNEL_VERSION}" ]]; then
		log info "ARMBIAN_KERNEL_VERSION is unset, obtaining the most recently pushed-to tag of ${ARMBIAN_KERNEL_BASE_ORAS_REF}"
		log info "Getting most recent tag for ${ARMBIAN_KERNEL_BASE_ORAS_REF} via skopeo ${SKOPEO_IMAGE}..."

		# A few tries to pull skopeo. Sorry. quay.io is undergoing an outage. @TODO refactor
		declare -i skopeo_pulled=0 skopeo_pull_tries=0 skopeo_max_pull_tries=5
		while [[ "${skopeo_pulled}" -eq 0 && "${skopeo_pull_tries}" -lt "${skopeo_max_pull_tries}" ]]; do
			if docker pull "${SKOPEO_IMAGE}"; then
				log info "Pulled skopeo image ${SKOPEO_IMAGE} OK"
				skopeo_pulled=1
			else
				skopeo_pull_tries+=1
				log info "Failed to pull ${SKOPEO_IMAGE}, retrying ${skopeo_pull_tries}/${skopeo_max_pull_tries}"
				sleep $((3 + RANDOM % 12)) # sleep a random amount of seconds
			fi
		done
		if [[ "${skopeo_pulled}" -eq 0 ]]; then
			log error "Failed to pull after ${skopeo_max_pull_tries} tries, exiting"
			exit 1
		fi

		# Pull separately to avoid tty hell in the subshell below
		ARMBIAN_KERNEL_VERSION="$(docker run "${SKOPEO_IMAGE}" list-tags "docker://${ARMBIAN_KERNEL_BASE_ORAS_REF}" | jq -r ".Tags[]" | tail -1)"
		log info "Using most recent tag: ${ARMBIAN_KERNEL_VERSION}"
	fi

	# output ID is just the kernel_id
	declare -g OUTPUT_ID="${kernel_id}"

	declare -g ARMBIAN_KERNEL_FULL_ORAS_REF_DEB_TAR="${ARMBIAN_KERNEL_BASE_ORAS_REF}:${ARMBIAN_KERNEL_VERSION}"
	declare -g ARMBIAN_KERNEL_MAJOR_MINOR_POINT="$(echo -n "${ARMBIAN_KERNEL_VERSION}" | cut -d "-" -f 1)"
	log info "ARMBIAN_KERNEL_MAJOR_MINOR_POINT: ${ARMBIAN_KERNEL_MAJOR_MINOR_POINT}"

	declare -g ARMBIAN_KERNEL_DOCKERFILE="kernel/Dockerfile.autogen.armbian.${kernel_id}"

	declare oras_version="1.2.0-beta.1" # @TODO bump this once it's released; yes it's much better than 1.1.x's
	declare oras_down_url="https://github.com/oras-project/oras/releases/download/v${oras_version}/oras_${oras_version}_linux_amd64.tar.gz"

	# Lets create a Dockerfile that will be used to obtain the artifacts needed, using ORAS binary
	echo "Creating Dockerfile '${ARMBIAN_KERNEL_DOCKERFILE}'... "
	cat <<- ARMBIAN_ORAS_DOCKERFILE > "${ARMBIAN_KERNEL_DOCKERFILE}"
		FROM debian:stable as downloader
		# Install ORAS binary tool from GitHub releases
		RUN apt update && apt install -y curl dpkg-dev && \
		      curl -L -o /oras.tar.gz ${oras_down_url} && \
		      tar -xvf /oras.tar.gz -C /usr/local/bin/ oras && \
		      chmod +x /usr/local/bin/oras && \
		      oras version

		FROM downloader as downloaded

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

		# Create a tarball with the modules in lib
		RUN tar -cvf /armbian/output/kernel.tar lib

		# Create a tarball with the dtbs in usr/lib/linux-image-*
		RUN { cd usr/lib/linux-image-* || { echo "No DTBS for this arch, empty tar..." && mkdir -p usr/lib/linux-image-no-dtbs && cd usr/lib/linux-image-* ; } ; }  && pwd && du -h -d 1 . && tar -czvf /armbian/output/dtbs.tar.gz . && ls -lah /armbian/output/dtbs.tar.gz

		# Show the contents of the output dir
		WORKDIR /armbian/output
		RUN ls -lahtS

		# Output layer should be in the layout expected by LinuxKit (dtbs.tar.gz is ignored)
		FROM scratch
		COPY --from=downloaded /armbian/output/* /
	ARMBIAN_ORAS_DOCKERFILE

	declare input_hash="" short_input_hash=""
	input_hash="$(cat "${ARMBIAN_KERNEL_DOCKERFILE}" | sha256sum - | cut -d ' ' -f 1)"
	short_input_hash="${input_hash:0:8}"
	kernel_oci_version="${ARMBIAN_KERNEL_MAJOR_MINOR_POINT}-${short_input_hash}"
	kernel_oci_image="${HOOK_KERNEL_OCI_BASE}hook-${kernel_id}:${kernel_oci_version}"
	log info "kernel_oci_version: ${kernel_oci_version}"
	log info "kernel_oci_image: ${kernel_oci_image}"
}

function build_kernel_armbian() {
	# smth else
	log info "Building armbian kernel from deb-tar at ${ARMBIAN_KERNEL_FULL_ORAS_REF_DEB_TAR}"
	log info "Will build Dockerfile ${ARMBIAN_KERNEL_DOCKERFILE}"

	# Build the Dockerfile; don't specify platform, our Dockerfile is multiarch, thus you can get build x86 kernels in arm64 hosts and vice-versa
	docker buildx build --load --progress=plain -t "${kernel_oci_image}" -f "${ARMBIAN_KERNEL_DOCKERFILE}" kernel
}
