#!/usr/bin/env bash

function parse_command_line_arguments() {
	declare -A -g CLI_PARSED_CMDLINE_PARAMS=()
	declare -a -g CLI_NON_PARAM_ARGS=()

	# loop over the arguments & parse them out
	local arg
	for arg in "${@}"; do
		if [[ "${arg}" == *=* ]]; then # contains an equal sign. it's a param.
			local param_name param_value param_value_desc
			param_name=${arg%%=*}
			param_value=${arg##*=}
			param_value_desc="${param_value:-(empty)}"
			# Sanity check for the param name; it must be a valid bash variable name.
			if [[ "${param_name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
				CLI_PARSED_CMDLINE_PARAMS["${param_name}"]="${param_value}" # For current run.
				# log debug "Command line: parsed parameter '$param_name' to" "${param_value_desc}"
			else
				log error "Invalid command line parameter '${param_name}=${param_value_desc}'"
				exit 8
			fi
		elif [[ "x${arg}x" != "xx" ]]; then # not a param, not empty, store it in the non-param array for later usage
			local non_param_value="${arg}"
			local non_param_value_desc="${non_param_value:-(empty)}"
			log debug "Command line: non-param argument" "'${non_param_value_desc}'"
			CLI_NON_PARAM_ARGS+=("${non_param_value}")
		fi
	done

	# Loop over the dictionary and apply the values to the environment.
	for param_name in "${!CLI_PARSED_CMDLINE_PARAMS[@]}"; do
		local param_value param_value_desc
		# get the current value from the environment
		current_env_value_desc="${!param_name-(unset)}"
		current_env_value_desc="${current_env_value_desc:-(empty)}"
		# get the new value from the dictionary
		param_value="${CLI_PARSED_CMDLINE_PARAMS[${param_name}]}"
		param_value_desc="${param_value:-(empty)}"

		log info "Applying cmdline param to environment" "'$param_name': '${current_env_value_desc}' --> '${param_value_desc}'"
		# use `declare -g` to make it global, and -x to export it, we're in a function.
		eval "declare -g -x $param_name=\"$param_value\""
	done

	return 0
}
