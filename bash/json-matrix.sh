#!/usr/bin/env bash

## Implements JSON generation for GitHub Actions matrixes.
## nb: this is an example of what not to use bash for.
## The same code in Python would be 10x shorter and run infinitely faster.
## Please be patient while reading this.

# TAG selection, using environment variables:
# - CI_TAGS should be a space-separated list of tags to include in the matrixes
# - Those will be matched against each flavor's TAG
# - Any flavor with a matching tag will be included in the matrixes

# GH Runner selection, using environment variables  (in order of specificity, for AMD64, same applies to ARM64 variant):
## Kernels: (1)
# - CI_RUNNER_KERNEL_AMD64 is the runner to use for amd64 kernel builds
# - CI_RUNNER_KERNEL is the runner to use for all kernels
# - CI_RUNNER_AMD64 is the runner to use for all AMD64 things
# - CI_RUNNER is the runner to use for everything
## LinuxKit/Hook: (2)
# - CI_RUNNER_LK_AMD64 is the runner to use for amd64 linuxkit builds
# - CI_RUNNER_LK is the runner to use for all linuxkit builds
# - CI_RUNNER_AMD64 is the runner to use for all AMD64 things
# - CI_RUNNER is the runner to use for everything
## LK containers (hook-bootkit, hook-docker, hook-mdev): (3):
# - CI_RUNNER_LK_CONTAINERS_AMD64 is the runner to use for amd64 linuxkit containers builds
# - CI_RUNNER_LK_CONTAINERS is the runner to use for all linuxkit containers builds
# - CI_RUNNER_AMD64 is the runner to use for all AMD64 things
# - CI_RUNNER is the runner to use for everything

function output_gha_matrixes() {
	declare -r CI_TAGS="${CI_TAGS:-"standard dev armbian-sbc armbian-uefi"}"
	# shellcheck disable=SC2206 # yes, we want to split
	declare -g -a -r CI_TAGS_ARRAY=(${CI_TAGS})
	log info "CI_TAGS: ${CI_TAGS_ARRAY[*]}"

	declare -A all_arches=() # accumulator for every arch that is selected to be built

	declare full_json=""
	prepare_json_matrix "KERNEL" # sets full_json and adds to all_arches
	declare kernels_json="${full_json}"

	declare full_json=""
	prepare_json_matrix "LK" # sets full_json and adds to all_arches
	declare lk_hooks_json="${full_json}"

	declare full_json=""
	prepare_json_matrix_lkcontainers "LK_CONTAINERS" # reads all_arches's keys and sets full_json
	declare lkcontainers_json="${full_json}"

	log info "kernels_json to: ${kernels_json}"
	log info "lk_hooks_json to: ${lk_hooks_json}"
	log info "lkcontainers_json to: ${lkcontainers_json}"

	# If under GHA, set a GHA output variable.
	if [[ -n "${GITHUB_OUTPUT}" ]]; then
		# shellcheck disable=SC2129 # no, thanks, shellcheck.
		echo "kernels_json=${kernels_json}" >> "${GITHUB_OUTPUT}"
		echo "lk_hooks_json=${lk_hooks_json}" >> "${GITHUB_OUTPUT}"
		echo "lkcontainers_json=${lkcontainers_json}" >> "${GITHUB_OUTPUT}"
	fi

	echo -n "${lk_hooks_json}" # output the hooks matrix to stdout, for cli/jq etc
}

function prepare_json_matrix() {
	declare -r matrix_type="${1}"

	declare -a json_items=()
	declare kernel
	for kernel in "${inventory_ids[@]}"; do
		declare -A kernel_info
		get_kernel_info_dict "${kernel}"

		if [[ "${matrix_type}" == "KERNEL" ]]; then # special case for kernel builds, if USE_KERNEL_ID is set, skip this kernel
			if [[ -n "${kernel_info[USE_KERNEL_ID]}" ]]; then
				log info "Skipping build of kernel '${kernel}' due to it having USE_KERNEL_ID set to '${kernel_info[USE_KERNEL_ID]}'"
				continue
			fi
		fi

		if json_matrix_tag_match "${kernel_info[TAG]}"; then
			declare runner="unknown-runner"
			runner="$(json_matrix_find_runner "${matrix_type}" "${kernel_info[DOCKER_ARCH]}")"
			declare gha_cache="yes" # always use GH cache; hitting DockerHub for linuxkit images is prone to rate limiting

			all_arches["${kernel_info[DOCKER_ARCH]}"]=1
			json_items+=("{\"kernel\":\"${kernel}\",\"arch\":\"${kernel_info[ARCH]}\",\"docker_arch\":\"${kernel_info[DOCKER_ARCH]}\",\"runner\":${runner},\"gha_cache\":\"${gha_cache}\"}")
		fi
	done

	prepare_json_array_to_json
	return 0
}

function prepare_json_matrix_lkcontainers() {
	declare -r matrix_type="${1}"
	declare -a unique_arches=("${!all_arches[@]}") # get an array with the KEYS of all_arches dict
	declare -a json_items=()
	declare kernel
	for one_arch in "${unique_arches[@]}"; do
		declare runner="unknown-runner"
		runner="$(json_matrix_find_runner "${matrix_type}" "${one_arch}")"
		json_items+=("{\"docker_arch\":\"${one_arch}\",\"runner\":${runner}}")
	done
	prepare_json_array_to_json
	return 0
}

# takes json_items array, outputs full_json single-line string; massage the array into JSON (comma handling)
function prepare_json_array_to_json() {
	declare this_json="["
	declare -i counter=0
	declare json_item
	for json_item in "${json_items[@]}"; do
		this_json+="${json_item}"
		[[ $counter -lt $((${#json_items[@]} - 1)) ]] && this_json+="," # append a comma if not the last element
		counter+=1
	done
	this_json+="]"
	if [[ "${skip_jq:-"no"}" == "yes" ]]; then
		full_json="${this_json}"
		return 0
	fi
	log debug "Raw json before jq: ${this_json}"
	full_json="$(echo "${this_json}" | jq -c .)" # Pass it through jq for correctness check & compaction
	return 0
}

# This is probably the slowest bash code ever written
function json_matrix_tag_match() {
	declare current_tags="${1}"
	# shellcheck disable=SC2206 # we want to split the string into an array, thanks
	declare -a current_tags_array=(${current_tags})
	# if any of current_tags_array in in CI_TAGS_ARRAY, we've a match
	for tag in "${current_tags_array[@]}"; do
		for ci_tag in "${CI_TAGS_ARRAY[@]}"; do
			if [[ "${tag}" == "${ci_tag}" ]]; then
				log debug "Tag '${tag}' matches CI_TAG '${ci_tag}'..."
				return 0
			fi
		done
	done
	log debug "No tags matched."
	return 1
}

function json_matrix_find_runner() {
	declare matrix_type="${1}"
	declare docker_arch="${2}"
	declare runner="ubuntu-latest"
	#log debug "Finding runner for matrix type '${matrix_type}' and docker arch '${docker_arch}'"
	declare -a vars_to_try=("CI_RUNNER_${matrix_type^^}_${docker_arch^^}" "CI_RUNNER_${matrix_type^^}" "CI_RUNNER_${docker_arch^^}" "CI_RUNNER")
	for var in "${vars_to_try[@]}"; do
		log debug "Checking var '${var}'"
		if [[ -n "${!var}" && "x${!var}x" != "xx" ]]; then # if var is set, and not empty...
			log debug "Found runner '${!var}' for matrix type '${matrix_type}' and docker arch '${docker_arch}' via var '${var}'"
			runner="${!var}"
			break
		fi
	done
	log debug "Found runner '${runner}' for matrix type '${matrix_type}' and docker arch '${docker_arch}'"

	# shellcheck disable=SC2206 # split by spaces, make it a json array
	declare -a json_items_bare=(${runner})
	# wrap each json_items array item in double quotes
	declare -a json_items=()
	if [[ "${runner}" != "ubuntu-latest" ]]; then # if not using a GH-hosted runner, auto-add the "self-hosted" member
		json_items+=("\"self-hosted\"")
	fi
	for item in "${json_items_bare[@]}"; do
		json_items+=("\"${item}\"")
	done
	declare full_json=""
	skip_jq="yes" prepare_json_array_to_json # skip jq; this is only a json fragment
	echo -n "${full_json}"
	return 0
}
