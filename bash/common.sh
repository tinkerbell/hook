#!/usr/bin/env bash

# logger utility, output ANSI-colored messages to stderr; first argument is level (debug/info/warn/error), all other arguments are the message.
declare -A log_colors=(["debug"]="0;36" ["info"]="0;32" ["notice"]="1;32" ["warn"]="1;33" ["error"]="1;31")
declare -A log_emoji=(["debug"]="🐛" ["info"]="🌿" ["notice"]="🌱" ["warn"]="🚸" ["error"]="🚨")
declare -A log_gha_levels=(["notice"]="notice" ["warn"]="warning" ["error"]="error")
function log() {
	declare level="${1}"
	shift
	[[ "${level}" == "debug" && "${DEBUG}" != "yes" ]] && return # Skip debugs unless DEBUG=yes is set in the environment
	# If running on GitHub Actions, and level exists in log_gha_levels...
	if [[ -n "${GITHUB_ACTIONS}" && -n "${log_gha_levels[${level}]}" ]]; then
		echo "::${log_gha_levels[${level}]} ::${*}" >&2
	fi
	# Normal output
	declare color="\033[${log_colors[${level}]}m"
	declare emoji="${log_emoji[${level}]}"
	declare ansi_reset="\033[0m"
	level=$(printf "%-5s" "${level}") # pad to 5 characters before printing
	echo -e "${emoji} ${ansi_reset}[${color}${level}${ansi_reset}] ${color}${*}${ansi_reset}" >&2
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
			sudo DEBIAN_FRONTEND=noninteractive apt -o "Dpkg::Use-Pty=0" -y update
			sudo DEBIAN_FRONTEND=noninteractive apt -o "Dpkg::Use-Pty=0" -y install "${debian_pkgs[@]}"
		fi
	else
		log error "Don't know how to install the equivalent of Debian packages: ${debian_pkgs[*]} -- teach me!"
	fi

	return 0 # there's a shortcircuit above
}

# utility used by inventory.sh to define a kernel/flavour with less-terrible syntax.
function define_id() {
	declare id="${1}"
	shift

	declare -A dict=()
	declare arg
	for arg in "$@"; do
		if [[ "${arg}" == *=* ]]; then # contains an equal sign. it's a param.
			local param_name param_value
			param_name=${arg%%=*}
			param_value=${arg##*=}
			dict["${param_name}"]="${param_value}" # For current run.
		else
			log error "Unknown argument to define, id=${id}: '${arg}'"
			exit 10
		fi
	done

	# Sanity checking: METHOD, ARCH and TAG are required.
	if [[ -z "${dict['METHOD']}" || -z "${dict['ARCH']}" || -z "${dict['TAG']}" ]]; then
		log error "Flavour definition for id=${id} is missing METHOD, ARCH or TAG"
		exit 11
	fi

	declare str_dict
	str_dict="$(declare -p dict)"                  # bash high sorcery; get a string representation of the dict
	str_dict="${str_dict#*"dict=("}"               # remove 'declare -A dict=(' from the string
	str_dict="${str_dict%?}"                       # remove the last character, which is a ")"
	log debug "str dict for id=${id}: ${str_dict}" # this _will_ go wrong, so add a debug

	# eval it into the inventory_dict dict
	eval "inventory_dict[${id}]='${str_dict}'"

	return 0
}
