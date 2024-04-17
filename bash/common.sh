#!/usr/bin/env bash

# logger utility, output ANSI-colored messages to stderr; first argument is level (debug/info/warn/error), all other arguments are the message.
declare -A log_colors=(["debug"]="0;36" ["info"]="0;32" ["warn"]="0;33" ["error"]="0;31")
declare -A log_emoji=(["debug"]="🐛" ["info"]="📗" ["warn"]="🚧" ["error"]="🚨")
function log() {
	declare level="${1}"
	shift
	declare color="${log_colors[${level}]}"
	declare emoji="${log_emoji[${level}]}"
	level=$(printf "%-5s" "${level}") # pad to 5 characters before printing
	echo -e "${emoji} \033[${color}m${SECONDS}: [${level}] $*\033[0m" >&2
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
