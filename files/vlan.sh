#!/bin/bash

set -e # exit on error

# This script will set up VLAN interfaces if `vlan_id=xxxx` in `/proc/cmdline` has a value.
# It will use the MAC address specified in `hw_addr=` to find the interface to add the VLAN to.

function parse_with_regex_power() {
	declare stdin_data cmdline_rest
	stdin_data="$(cat)" # read stdin
	declare search_argument="${1}"
	declare normal_matcher="([a-zA-Z0-9/\\@#\$%^&\!*\(\)'\"=:,._-]+)"
	declare quoted_matcher="\"([a-zA-Z0-9/\\@#\$%^&\!*\(\)',=: ._-]+)\""
	[ $# -gt 1 ] && normal_matcher="$2" && quoted_matcher="$2"
	cmdline_rest="$(printf '%s' "$stdin_data" | sed -rn "s/.* ?${search_argument}=${normal_matcher} ?(.*)+?/\1/p")"
	if echo "$cmdline_rest" | grep -Eq '^"'; then
		cmdline_rest="$(printf "%s\n" "$stdin_data" | sed -rn "s/.* ?${search_argument}=${quoted_matcher} ?(.*)+?/\1/p")"
	fi
	printf "%s\n" "$cmdline_rest"
}

function parse_kernel_cmdline_for() {
	declare result
	# shellcheck disable=SC2002
	result=$(cat /proc/cmdline | parse_with_regex_power "$@")
	if [ -z "${result}" ]; then
		return 1
	else
		printf "%s" "$result"
	fi
}

function kernel_cmdline_exists() {
	parse_kernel_cmdline_for "$@" > /dev/null
}

function add_vlan_interface() {
	# check if vlan_id  are set in the kernel commandline, otherwise return.
	if ! kernel_cmdline_exists vlan_id; then
		echo "No vlan_id=xxxx set in kernel commandline; no VLAN handling." >&2
		return
	fi

	# check if  hw_addr are set in the kernel commandline, otherwise return.
	if ! kernel_cmdline_exists hw_addr; then
		echo "No hw_addr=xx:xx:xx:xx:xx:xx set in kernel commandline." >&2
	fi

	echo "Starting VLAN handling, parsing..." >&2

	declare vlan_id hw_addr
	vlan_id="$(parse_kernel_cmdline_for vlan_id)"
	hw_addr="$(parse_kernel_cmdline_for hw_addr)"

	echo "VLAN handling - vlan_id: '${vlan_id}', hw_addr: '${hw_addr}'" >&2

	if [ -n "$vlan_id" ]; then
		if [ -n "$hw_addr" ]; then
			echo "VLAN handling - vlan_id: '${vlan_id}', hw_addr: '${hw_addr}', searching for interface..." >&2
			ifname="$(ip -br link | awk '$3 ~ /'"${hw_addr}"'/ {print $1}')"
			echo "VLAN handling - vlan_id: '${vlan_id}', hw_addr: '${hw_addr}', found interface: '${ifname}'" >&2
		else
			echo "VLAN handling - vlan_id: '${vlan_id}', hw_addr: '${hw_addr}', no hw_addr found in kernel commandline; default ifname to eth0." >&2
			ifname="eth0"
		fi

		if [ -n "$ifname" ]; then
			echo "VLAN handling - vlan_id: '${vlan_id}', hw_addr: '${hw_addr}', adding VLAN interface..." >&2
			ip link set dev "${ifname}" up || true
			ip link add link "${ifname}" name "${ifname}.${vlan_id}" type vlan id "${vlan_id}" || true
			ip link set "${ifname}.${vlan_id}" up || true
			echo "VLAN handling - vlan_id: '${vlan_id}', hw_addr: '${hw_addr}', added VLAN interface: '${ifname}.${vlan_id}'" >&2
			return 0
		else
			echo "VLAN handling - vlan_id: '${vlan_id}', hw_addr: '${hw_addr}', no interface found for hw_addr." >&2
			return 3
		fi

	else
		echo "VLAN handling - vlan_id: '${vlan_id}', hw_addr: '${hw_addr}', no vlan_id found in kernel commandline." >&2
		return 1
	fi
}

# we always return true so that a failure here doesn't block the next container service from starting. Ideally, we always
# want the getty service to start so we can debug failures.
add_vlan_interface || true
echo "Done with VLAN handling." >&2

# @TODO: debugging since I seem to have machines hanging here; dump some info
echo "Running 'ip link show'..."
ip link show || true
exit 0
