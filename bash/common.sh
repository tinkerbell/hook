#!/usr/bin/env bash

# logger utility, output ANSI-colored messages to stderr; first argument is level (debug/info/warn/error), all other arguments are the message.
declare -A log_colors=(["debug"]="0;36" ["info"]="0;32" ["warn"]="0;33" ["error"]="0;31")
declare -A log_emoji=(["debug"]="🐛" ["info"]="📗" ["warn"]="🚧" ["error"]="🚨")
function log() {
	declare level="${1}"
	shift
	declare color="${log_colors[${level}]}"
	declare emoji="${log_emoji[${level}]}"
	echo -e "${emoji} \033[${color}m${SECONDS}: [${level}] $*\033[0m" >&2
}

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

function install_dependencies() {
	declare -a debian_pkgs=()
	[[ ! -f /usr/bin/jq ]] && debian_pkgs+=("jq")
	[[ ! -f /usr/bin/envsubst ]] && debian_pkgs+=("gettext-base")
	[[ ! -f /usr/bin/pigz ]] && debian_pkgs+=("pigz")

	# If running on Debian or Ubuntu...
	if [[ -f /etc/debian_version ]]; then
		# If more than zero entries in the array, install
		if [[ ${#debian_pkgs[@]} -gt 0 ]]; then
			log warn "Installing dependencies: ${debian_pkgs[*]}"
			sudo apt -y update
			sudo apt -y install "${debian_pkgs[@]}"
		fi
	else
		log error "Don't know how to install the equivalent of Debian packages: ${debian_pkgs[*]} -- teach me!"
	fi

	return 0 # there's a shortcircuit above
}
