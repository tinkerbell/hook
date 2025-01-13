function check_docker_daemon_for_sanity() {
	# LinuxKit is a bit confused about `docker context list` when you're using a non-default context.
	# Let's obtain the currect socket from the current context and explicitly export it.
	# This allows working on machines with Docker Desktop, colima, and other run-linux-in-a-VM solutions.
	declare current_context_docker_socket="" current_docker_context_name=""
	current_docker_context_name="$(docker context show)"
	current_context_docker_socket="$(docker context inspect "${current_docker_context_name}" | jq -r '.[0].Endpoints.docker.Host')"
	log info "Current Docker context ('${current_docker_context_name}') socket: '${current_context_docker_socket}'"

	log debug "Setting DOCKER_HOST to '${current_context_docker_socket}'"
	export DOCKER_HOST="${current_context_docker_socket}"

	# Hide Docker, Inc spamming "What's next" et al.
	export DOCKER_CLI_HINTS=false

	# Shenanigans to go around error control & capture output in the same effort, 'docker info' is slow.
	declare docker_info docker_buildx_version
	docker_info="$({ docker info 2> /dev/null && echo "DOCKER_INFO_OK"; } || true)"

	if [[ ! "${docker_info}" =~ "DOCKER_INFO_OK" ]]; then
		log error "'docker info' failed. Is Docker installed & your user in the correct group?"
		exit 3
	fi

	docker_buildx_version="$(echo "${docker_info}" | grep -i -e "buildx:" || true | cut -d ":" -f 2 | xargs echo -n)"
	log debug "Docker Buildx version" "${docker_buildx_version}"

	if [[ -z "${docker_buildx_version}" ]]; then
		log error "'docker info' indicates there's no buildx installed. Please install docker buildx."
		exit 4
	fi

	# Once we know docker is sane, hook up a function that helps us trace invocations.
	function docker() {
		log debug "--> docker $*"
		command docker "$@"
	}

}

# Utility to pull skopeo itself from SKOPEO_IMAGE; checks the local Docker cache and skips if found
function pull_skopeo_image_if_not_in_local_docker_cache() {
	# Check if the image is already in the local Docker cache
	if docker image inspect "${SKOPEO_IMAGE}" &> /dev/null; then
		log info "Skopeo image ${SKOPEO_IMAGE} is already in the local Docker cache; skipping pull."
		return 0
	fi

	log info "Pulling Skopeo image ${SKOPEO_IMAGE}..."

	pull_docker_image_from_remote_with_retries "${SKOPEO_IMAGE}"
}

# Utility to get the most recent tag for a given image, using Skopeo. no retries, a failure is fatal.
# Sets the value of outer-scope variable latest_tag_for_docker_image, so declare it there.
# If extra arguments are present after the image, they are used to grep the tags.
function get_latest_tag_for_docker_image_using_skopeo() {
	declare image="$1"
	shift
	latest_tag_for_docker_image="undetermined_tag"

	# Pull separately to avoid tty hell in the subshell below
	pull_skopeo_image_if_not_in_local_docker_cache

	# if extra arguments are present, use them to grep the tags
	if [[ -n "$*" ]]; then
		latest_tag_for_docker_image="$(docker run "${SKOPEO_IMAGE}" list-tags "docker://${image}" | jq -r ".Tags[]" | grep "${@}" | tail -1)"
	else
		latest_tag_for_docker_image="$(docker run "${SKOPEO_IMAGE}" list-tags "docker://${image}" | jq -r ".Tags[]" | tail -1)"
	fi
	log info "Found latest tag: '${latest_tag_for_docker_image}' for image '${image}'"
}

# Utility to pull from remote, with retries.
function pull_docker_image_from_remote_with_retries() {
	declare image="$1"
	declare -i retries=3
	declare -i retry_delay=5
	declare -i retry_count=0

	while [[ ${retry_count} -lt ${retries} ]]; do
		if docker pull "${image}"; then
			log info "Successfully pulled ${image}"
			return 0
		else
			log warn "Failed to pull ${image}; retrying in ${retry_delay} seconds..."
			sleep "${retry_delay}"
			((retry_count += 1))
		fi
	done

	log error "Failed to pull ${image} after ${retries} retries."
	exit 1
}

# Helper script, for common task of installing packages on a Debian Dockerfile
# always includes curl and downloads ORAS binary too
# takes the relative directory to write the helper to
# sets outer scope dockerfile_helper_filename with the name of the file for the Dockerfile (does not include the directory)
function produce_dockerfile_helper_apt_oras() {
	declare target_dir="$1"
	declare helper_name="apt-oras-helper.sh"
	dockerfile_helper_filename="Dockerfile.autogen.helper.${helper_name}" # this is negated in .dockerignore

	declare fn="${target_dir}${dockerfile_helper_filename}"
	cat <<- 'DOWNLOAD_HELPER_SCRIPT' > "${fn}"
		#!/bin/bash
		set -e
		declare oras_version="1.2.2" # See https://github.com/oras-project/oras/releases
		# determine the arch to download from current arch
		declare oras_arch="unknown"
		case "$(uname -m)" in
			"x86_64") oras_arch="amd64" ;;
			"aarch64" | "arm64") oras_arch="arm64" ;;
			*) log error "ERROR: ARCH $(uname -m) not supported by ORAS? check https://github.com/oras-project/oras/releases" && exit 1 ;;
		esac
		declare oras_down_url="https://github.com/oras-project/oras/releases/download/v${oras_version}/oras_${oras_version}_linux_${oras_arch}.tar.gz"
		export DEBIAN_FRONTEND=noninteractive
		apt-get -qq -o "Dpkg::Use-Pty=0" update || apt-get -o "Dpkg::Use-Pty=0" update
		apt-get -qq install -o "Dpkg::Use-Pty=0" -q -y curl "${@}" || apt-get install -o "Dpkg::Use-Pty=0" -q -y curl "${@}"
		curl -sL -o /oras.tar.gz ${oras_down_url}
		tar -xvf /oras.tar.gz -C /usr/local/bin/ oras
		rm -rf /oras.tar.gz
		chmod +x /usr/local/bin/oras
		echo -n "ORAS version: " && oras version
	DOWNLOAD_HELPER_SCRIPT
	log debug "Created apt-oras helper script '${fn}'"
}

# A huge hack to force the architecture of a Docker image to a specific value.
# This is required for the LinuxKit kernel images: LK expects them to have the correct arch, despite the
#  actual contents always being the same. Docker's buildkit tags a locally built image with the host arch.
# Thus change the host arch to the expected arch in the image's manifests via a dump/reimport.
function ensure_docker_image_architecture() {
	declare kernel_oci_image="$1"
	declare expected_arch="$2"

	# If the host arch is the same as the expected arch, no need to do anything
	if [[ "$(uname -m)" == "${expected_arch}" ]]; then
		log info "Host architecture is already ${expected_arch}, no need to rewrite Docker image ${kernel_oci_image}"
		return 0
	fi

	log info "Rewriting Docker image ${kernel_oci_image} to architecture ${expected_arch}, wait..."

	# Create a temporary directory, use mktemp
	declare -g tmpdir
	tmpdir="$(mktemp -d)"
	log debug "Created temporary directory: ${tmpdir}"

	# Export the image to a tarball
	docker save -o "${tmpdir}/original.tar" "${kernel_oci_image}"

	# Untag the hostarch image
	docker rmi "${kernel_oci_image}"

	# Create a working dir under the tmpdir
	mkdir -p "${tmpdir}/working"

	# Extract the tarball into the working dir
	tar -xf "${tmpdir}/original.tar" -C "${tmpdir}/working"
	log debug "Extracted tarball to ${tmpdir}/working"

	# Remove the original tarball
	rm -f "${tmpdir}/original.tar"

	declare working_blobs_dir="${tmpdir}/working/blobs/sha256"

	# Find all files under working_blobs_dir which are smaller than 2048 bytes
	# Use mapfile to create an array of files
	declare -a small_files
	mapfile -t small_files < <(find "${working_blobs_dir}" -type f -size -2048c)
	log debug "Found small blob files: ${small_files[*]}"

	# Replace the architecture in each of the small files
	for file in "${small_files[@]}"; do
		log debug "Replacing architecture in ${file}"
		sed -i "s|\"architecture\":\".....\"|\"architecture\":\"${expected_arch}\"|g" "${file}" # 🤮
	done

	# Create a new tarball with the modified files
	tar -cf "${tmpdir}/modified.tar" -C "${tmpdir}/working" .
	log debug "Created modified tarball: ${tmpdir}/modified.tar"

	# Remove the working directory
	rm -rf "${tmpdir}/working"

	# Import the modified tarball back into the local cache
	docker load -i "${tmpdir}/modified.tar"

	# Remove the temporary directory, completely
	rm -rf "${tmpdir}"

	log info "Rewrote Docker image ${kernel_oci_image} to architecture ${expected_arch}."
}
