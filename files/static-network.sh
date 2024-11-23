#!/bin/sh

# This script is intended to be run on the HookOS/Linuxkit host so it must use /bin/sh.
# No other shells are available on the host.

# this script will statically configure a single network interface based on the ipam= parameter
# passed in the kernel command line. The ipam parameter is a colon separated string with the following fields:
# ipam=<mac-address>:<vlan-id>:<ip-address>:<netmask>:<gateway>:<hostname>:<dns>:<search-domains>:<ntp>
# Example: ipam=de-ad-be-ef-fe-ed::192.168.2.193:255.255.255.0:192.168.2.1:myserver:1.1.1.1,8.8.8.8::132.163.97.1,132.163.96.1
# the mac address format requires it to be hyphen separated. 

exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/var/log/network_config.log 2>&1

set -xeuo pipefail

# Define the location of the interfaces file
INTERFACES_FILE="/var/run/network/interfaces"

parse_ipam_from_cmdline() {
    local cmdline
    local ipam_value

    # Read the contents of /proc/cmdline
    cmdline=$(cat /proc/cmdline)

    # Use grep to find the ipam= parameter and awk to extract its value
    ipam_value=$(echo "$cmdline" | grep -o 'ipam=[^ ]*' | awk -F= '{print $2}')

    # Check if ipam= parameter was found
    if [ -n "$ipam_value" ]; then
        echo "$ipam_value"
        return 0
    else
        echo "ipam= parameter not found in /proc/cmdline" >&2
        return 1
    fi
}

# Function to get interface name from MAC address
# TODO(jacobweinstock): if a vlan id is provided we should match for the vlan interface
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

convert_hyphen_to_colon() {
    echo "$1" | tr '-' ':'
}

ipam=$(parse_ipam_from_cmdline)
if [ $? -ne 0 ]; then
    echo "Failed to get IPAM value, not statically configuring network"
    cat /proc/cmdline
    exit 0
fi
echo "IPAM value: $ipam"

mkdir -p $(dirname "$INTERFACES_FILE")

# Parse the IPAM string
IFS=':' read -r mac vlan_id ip netmask gateway hostname dns search_domains ntp <<EOF
${ipam}
EOF

# Check for required fields
if [ -z "$mac" ] || [ -z "$ip" ] || [ -z "$netmask" ] || [ -z "$dns" ]; then
    echo "Error: MAC address, IP address, netmask, and DNS are required."
    echo "$ipam"
    exit 1
fi

# convert Mac address to colon separated format
mac=$(convert_hyphen_to_colon "$mac")

# convert , (comma) separated values to space separated values
dns=$(echo "$dns" | tr ',' ' ')
search_domains=$(echo "$search_domains" | tr ',' ' ')
ntp=$(echo "$ntp" | tr ',' ' ')

# Get interface name
interface=$(get_interface_name "$mac")
if [ -z "$interface" ]; then
    echo "Error: No interface found with MAC address $mac"
    exit 1
fi

# Start writing to the interfaces file
{
    echo "# Static Network configuration for $interface"
    echo ""
    echo "auto $interface"

    if [ -n "$vlan_id" ]; then
        echo "iface $interface inet manual"
        echo ""
        echo "auto $interface.$vlan_id"
        echo "iface $interface.$vlan_id inet static"
    else
        echo "iface $interface inet static"
    fi

    echo "    address $ip"
    echo "    netmask $netmask"

    [ -n "$gateway" ] && echo "    gateway $gateway"
    [ -n "$hostname" ] && echo "    hostname $hostname"

    if [ -n "$dns" ]; then
        echo "    dns-nameserver $dns"
    fi

    if [ -n "$search_domains" ]; then
        echo "    dns-search $search_domains"
    fi

    if [ -n "$ntp" ]; then
        echo "    ntp-servers $ntp"
    fi

} > "$INTERFACES_FILE"

echo "Network configuration has been written to $INTERFACES_FILE"

# Run ifup on the interface
ifup -v -a -i "$INTERFACES_FILE"

# setup DNS
ROOT=/run/resolvconf/ setup-dns -d "$search_domains" "$dns"
