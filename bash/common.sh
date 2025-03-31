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

# Helper for debugging directory trees;
function log_tree() {
	declare directory="${1}"
	shift
	declare level="${1}"
	[[ "${level}" == "debug" && "${DEBUG}" != "yes" ]] && return # Skip debugs unless DEBUG=yes is set in the environment
	log "${@}" "-- directory ${directory}:"
	if command -v tree > /dev/null; then
		tree "${directory}"
	else
		log "${level}" "'tree' utility not installed; install it to see directory structure in logs."
	fi
}

function install_dependencies() {
	declare extra="${1}"

	declare -a debian_pkgs=()
	declare -a brew_pkgs=()

	command -v jq > /dev/null || {
		debian_pkgs+=("jq")
		brew_pkgs+=("jq")
	}

	command -v pigz > /dev/null || {
		debian_pkgs+=("pigz")
		brew_pkgs+=("pigz")
	}

	command -v envsubst > /dev/null || {
		debian_pkgs+=("gettext-base")
		brew_pkgs+=("gettext")
	}

	if [[ "${extra}" == "bootable-media" ]]; then
		command -v pixz > /dev/null || {
			debian_pkgs+=("pixz")
			brew_pkgs+=("pixz")
		}

		command -v pv > /dev/null || {
			debian_pkgs+=("pv")
			brew_pkgs+=("pv")
		}
	fi

	if [[ "$(uname)" == "Darwin" ]]; then
		command -v gtar > /dev/null || brew_pkgs+=("gnu-tar")
		command -v greadlink > /dev/null || brew_pkgs+=("coreutils")
		command -v gsed > /dev/null || brew_pkgs+=("gnu-sed")
	fi

	# If more than zero entries in the array, install
	if [[ ${#debian_pkgs[@]} -gt 0 ]]; then
		# If running on Debian or Ubuntu...
		if [[ -f /etc/debian_version ]]; then
			log info "Installing apt dependencies: ${debian_pkgs[*]}"
			sudo DEBIAN_FRONTEND=noninteractive apt -o "Dpkg::Use-Pty=0" -y update
			sudo DEBIAN_FRONTEND=noninteractive apt -o "Dpkg::Use-Pty=0" -y install "${debian_pkgs[@]}"
		elif [[ "$(uname)" == "Darwin" ]]; then
			log info "Skipping Debian deps installation for Darwin..."
		else
			log error "Don't know how to install the equivalent of Debian packages *on the host*: ${debian_pkgs[*]} -- teach me!"
		fi
	else
		log info "All deps found, no apt installs necessary on host."
	fi

	if [[ "$(uname)" == "Darwin" ]]; then
		if [[ ${#brew_pkgs[@]} -gt 0 ]]; then
			log info "Detected Darwin, assuming 'brew' is available: running 'brew install ${brew_pkgs[*]}'"
			brew install "${brew_pkgs[@]}"
		fi

		if [[ "${extra}" == "" ]]; then # Do not to this if extra dependencies are being installed
			# Re-export PATH with the gnu-version of coreutils, tar, and sed
			declare brew_prefix
			brew_prefix="$(brew --prefix)"
			export PATH="${brew_prefix}/opt/gnu-sed/libexec/gnubin:${brew_prefix}/opt/gnu-tar/libexec/gnubin:${brew_prefix}/opt/coreutils/libexec/gnubin:${PATH}"
			log debug "Darwin; PATH is now: ${PATH}"
		fi
	fi

	return 0
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

	# declare a global with the id of the last-added kernel, for add_bootable_id's convenience
	declare -g last_defined_id="${id}"

	return 0
}

function add_bootable_id() {
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

	# if dict["INVENTORY_ID"] is not defined, set it to the last defined id
	if [[ -z "${dict['INVENTORY_ID']}" ]]; then
		dict["INVENTORY_ID"]="${last_defined_id}"
	fi

	dict["BOOTABLE_ID"]="${id}"

	# Sanity checking: METHOD, ARCH and TAG are required.
	if [[ -z "${dict['HANDLER']}" || -z "${dict['TAG']}" ]]; then
		log error "Bootable definition for id=${id} is missing HANDLER or TAG"
		exit 11
	fi

	declare str_dict
	str_dict="$(declare -p dict)"                  # bash high sorcery; get a string representation of the dict
	str_dict="${str_dict#*"dict=("}"               # remove 'declare -A dict=(' from the string
	str_dict="${str_dict%?}"                       # remove the last character, which is a ")"
	log debug "str dict for id=${id}: ${str_dict}" # this _will_ go wrong, so add a debug

	# eval it into the inventory_dict dict
	eval "bootable_inventory_dict[${id}]='${str_dict}'"

	return 0
}
