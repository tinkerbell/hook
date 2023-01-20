#!/bin/bash

# This script will set up VLAN interfaces if `vlan_id=` in `/proc/cmdline` has a value
set -x

parse_cmdline() {
	c=$(cat /proc/cmdline)
	c="${c##*"$1"=}"
	c="${c%% *}"
	echo "$c"
}

add_vlan_interface() {
	vlan_id=$(parse_cmdline vlan_id)
	if [ -n "$vlan_id" ]; then
		hw_addr=$(parse_cmdline hw_addr)
		if [ -n "$hw_addr" ]; then
			ifname=$(ip -br link | awk '$3 ~ /'"${hw_addr}"'/ {print $1}')
			if [ -n "$ifname" ]; then
				ip link set dev "${ifname}" up || true
				ip link add link "${ifname}" name "${ifname}.${vlan_id}" type vlan id "${vlan_id}" || true
				ip link set "${ifname}.${vlan_id}" up || true
				return
			fi
		fi
	fi
}

# we always return true so that a failure here doesn't block the next container service from starting. Ideally, we always
# want the getty service to start so we can debug failures.
add_vlan_interface || true
