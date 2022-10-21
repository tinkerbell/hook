#!/bin/sh

# This script will set up VLAN interfaces if `vlan_id=` in `/proc/cmdline` has a value
set -x

add_vlan_interface() {
	# shellcheck disable=SC2013
	for param in $(cat /proc/cmdline); do
		# shellcheck disable=SC2022
		echo "$param" | grep -qe 'vlan_id*' || continue
		vlan_id="${param#vlan_id=}"
		if [ -n "$vlan_id" ]; then
			for ifname in $(ip -4 -o link show | awk -F': ' '{print $2}'); do
				[ "$ifname" = "lo" ] && continue
				[ "$ifname" = "docker0" ] && continue
				ip link add link "$ifname" name "$ifname.$vlan_id" type vlan id "$vlan_id"
				ip link set "$ifname.$vlan_id" up
			done
			return
		fi
	done
}

# we always return true so that a failure here doesn't block the next container service from starting. Ideally, we always
# want the getty service to start so we can debug failures.
add_vlan_interface || true
