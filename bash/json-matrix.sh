#!/usr/bin/env bash

function output_gha_matrixes() {
	# This is a GitHub Actions matrix build, so we need to produce a JSON array of objects, one for each kernel. Doing this in bash is painful.
	declare output_json="[" full_json=""
	declare -i counter=0
	for kernel in "${kernels[@]}"; do
		declare -A kernel_info
		get_kernel_info_dict "${kernel}"

		output_json+="{\"kernel\":\"${kernel}\",\"arch\":\"${kernel_info[ARCH]}\",\"docker_arch\":\"${kernel_info[DOCKER_ARCH]}\"}" # Possibly include a runs-on here if CI ever gets arm64 runners
		[[ $counter -lt $((${#kernels[@]} - 1)) ]] && output_json+=","                                                              # append a comma if not the last element
		counter+=1
	done
	output_json+="]"
	full_json="$(echo "${output_json}" | jq -c .)" # Pass it through jq for correctness check & compaction

	# let's reduce the output to get a JSON of all docker_arches. This is used for building the linuxkit containers.
	declare arches_json=""
	arches_json="$(echo -n "${full_json}" | jq -c 'map({docker_arch}) | unique')"

	# If under GHA, set a GHA output variable
	if [[ -z "${GITHUB_OUTPUT}" ]]; then
		log debug "Would have set GHA output kernels_json to: ${full_json}"
		log debug "Would have set GHA output arches_json to: ${arches_json}"
	else
		echo "kernels_json=${full_json}" >> "${GITHUB_OUTPUT}"
		echo "arches_json=${arches_json}" >> "${GITHUB_OUTPUT}"
	fi

	echo -n "${full_json}" # to stdout, for cli/jq etc
}
