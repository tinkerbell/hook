#!/bin/sh

# This script is intended to be run on the HookOS/Linuxkit host so it must use /bin/sh.
# No other shells are available on the host.

exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/var/log/vlan.log 2>&1

set -e # exit on error

# This script will set up VLAN interfaces if `vlan_id=xxxx` in `/proc/cmdline` has a value.
# It will use the MAC address specified in `hw_addr=` to find the interface to add the VLAN to.

parse_from_cmdline() {
	local key="${1}"
    local cmdline
    local ipam_value

    # Read the contents of /proc/cmdline
    cmdline=$(cat /proc/cmdline)

    # Use grep to find the ipam= parameter and awk to extract its value
    value=$(echo "$cmdline" | grep -o "${key}=[^ ]*" | awk -F= '{print $2}')

    # Check if parameter was found
    if [ -n "$value" ]; then
        echo "$value"
        return 0
    else
        echo "${key}= parameter not found in /proc/cmdline" >&2
        return 1
    fi
}

get_interface_name() {
    local mac=$1
    for interface in /sys/class/net/*; do
        if [ -f "$interface/address" ]; then
            if [ "$(cat "$interface/address")" == "$mac" ]; then
                echo "$(basename "$interface")"
                return 0
            fi
        fi
    done
    return 1
}

function add_vlan_interface() {
	# check if vlan_id  are set in the kernel commandline, otherwise return.
	if ! parse_from_cmdline vlan_id; then
		echo "No vlan_id=xxxx set in kernel commandline; no VLAN handling." >&2
		return
	fi

	# check if  hw_addr are set in the kernel commandline, otherwise return.
	if ! parse_from_cmdline hw_addr; then
		echo "No hw_addr=xx:xx:xx:xx:xx:xx set in kernel commandline." >&2
	fi

	echo "Starting VLAN handling, parsing..." >&2

	vlan_id="$(parse_from_cmdline vlan_id)"
	hw_addr="$(parse_from_cmdline hw_addr)"

	echo "VLAN handling - vlan_id: '${vlan_id}', hw_addr: '${hw_addr}'" >&2

	if [ -n "$vlan_id" ]; then
		if [ -n "$hw_addr" ]; then
			echo "VLAN handling - vlan_id: '${vlan_id}', hw_addr: '${hw_addr}', searching for interface..." >&2
			ifname="$(get_interface_name ${hw_addr})"
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
