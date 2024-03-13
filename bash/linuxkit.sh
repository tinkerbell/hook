#!/usr/bin/env bash

function obtain_linuxkit_binary_cached() {

	declare -g -r linuxkit_version="${linuxkit_version:-"1.0.1"}" 
	declare linuxkit_arch=""
	# determine the arch to download from current arch
	case "$(uname -m)" in
		"x86_64") linuxkit_arch="amd64" ;;
		"aarch64") linuxkit_arch="arm64" ;;
		*) echo "ERROR: ARCH $(uname -m) not supported by linuxkit? check https://github.com/linuxkit/linuxkit/releases" >&2 && exit 1 ;;
	esac

	declare linuxkit_down_url="https://github.com/linuxkit/linuxkit/releases/download/v${linuxkit_version}/linuxkit-linux-${linuxkit_arch}"
	declare -g -r linuxkit_bin="./linuxkit-linux-${linuxkit_arch}-${linuxkit_version}"

	# Download using curl if not already present
	if [[ ! -f "${linuxkit_bin}" ]]; then
		echo "Downloading linuxkit from ${linuxkit_down_url} to file ${linuxkit_bin}" >&2
		curl -sL "${linuxkit_down_url}" -o "${linuxkit_bin}"
		chmod +x "${linuxkit_bin}"
	fi

	# Show the binary's version
	echo "LinuxKit binary version: ('0.8+' reported for 1.2.0, bug?): $("${linuxkit_bin}" version | xargs echo -n)" >&2

}
