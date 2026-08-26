#!/bin/sh

# This script will run the dhcp client. If `vlan_id=` in `/proc/cmdline` has a value, it will run the dhcp client only on the
# VLAN interface.
# This script accepts an input parameter of true or false.
# true: run the dhcp client with the one shot option
# false: run the dhcp client as a service
set -x

# busybox ntpd uses SIGALRM for its own timeouts, and the alarm terminates this script
# along with it, so the retry and fallback logic below never runs. Catching the signal
# rather than ignoring it keeps ntpd's own timeout working: a caught signal is reset to
# its default disposition in the child, while an ignored one is inherited.
trap ':' ALRM

# Print the interface holding the default route, if there is one.
default_route_iface() {
	awk 'NR > 1 && $2 == "00000000" && $8 == "00000000" { print $1; exit }' /proc/net/route
}

# Print the interfaces dhcpcd has already leased, from its lease directory. Handles both
# the <iface>.lease and dhcpcd-<iface>.lease naming used across dhcpcd versions.
leased_ifaces() {
	for lease in /var/lib/dhcpcd/*.lease; do
		[ -e "${lease}" ] || continue
		iface="${lease##*/}"
		iface="${iface%.lease}"
		printf '%s ' "${iface#dhcpcd-}"
	done
}

# Print the NTP servers leased via DHCP option 42 on the given interface, followed by the
# public pool as a fallback. Preferring the leased servers keeps time sync working on
# provisioning networks that have no outbound DNS or no internet access at all, and it
# avoids depending on name resolution to set the clock.
ntp_servers() {
	leased=$(/sbin/dhcpcd -U "$1" 2>/dev/null | sed -n "s/^ntp_servers='\(.*\)'$/\1/p" | tr ',' ' ')
	echo "${leased} pool.ntp.org"
}

# Try each server in turn, returning as soon as one of them sets the clock.
try_ntp_servers() {
	for server in $1; do
		if /usr/sbin/ntpd -n -q -dd -p "$server"; then
			echo "time synced from ${server}; date is now: '$(date)'"
			return 0
		fi
	done

	return 1
}

sync_time() {
	iface=$(default_route_iface)
	if [ -z "$iface" ]; then
		echo "no default route; not syncing time"
		return 1
	fi

	servers=$(ntp_servers "$iface")
	echo "syncing time from '${servers}' via ${iface}; date: '$(date)'"
	if try_ntp_servers "$servers"; then
		return 0
	fi

	echo "ntpd call failed; setting time manually and retrying"
	# set system time to the date of the dhcpd binary file
	# this should recover from ntpd failures due to time being too far off
	date -s "$(stat -c %y /sbin/dhcpcd | cut -d'.' -f1)" || true

	tries=1 # retry up to 5 times
	while [ $tries -le 5 ]; do
		echo "waiting 1 second before retrying ntpd call; try #$tries ; date is now: '$(date)'"
		sleep 1
		if try_ntp_servers "$servers"; then
			echo "ntpd retry call succeeded on try #$tries"
			return 0
		fi
		echo "ntpd retry call failed on try #$tries"
		tries=$((tries + 1))
	done

	return 1
}

run_dhcp_client() {
	one_shot="$1"
	al="e*"

	interface=$(sed -n 's/.* interface=\([a-z,A-Z,0-9]*\).*/\1/p' /proc/cmdline)
	if [ -n "$interface" ]; then
		al="$interface"
	fi

	vlan_id=$(sed -n 's/.* vlan_id=\([0-9]*\).*/\1/p' /proc/cmdline)
	if [ -n "$vlan_id" ]; then
		al="e*.*"
	fi

	if [ "$one_shot" = "true" ]; then
		# always return true for the one shot dhcp call so it doesn't block Hook from starting up.
		# the --nobackground is not used here because when it is used, dhcpcd doesn't honor the --timeout option
		# and waits indefinitely for a response. For one shot, we want to timeout after the 30 second default.
		#
		# One shot mode exits as soon as any allowed interface gets a lease. On machines whose
		# BMC exposes a virtual USB NIC, that first lease is often a link local one handed out
		# by the BMC itself, acquired well before the real NICs finish negotiating carrier. The
		# result is a boot with no default route, no DNS and no option 42.
		#
		# Simply re-running the same call does not help, and actively hurts: `persistent` keeps
		# the BMC lease configured on exit and the lease directory survives across invocations,
		# so the next -1 call is satisfied from that cached lease sooner than the real NICs can
		# finish negotiating. `waitip 4` does not help either, as the BMC lease already supplies
		# an IPv4 address. Each retry therefore excludes the interfaces that hold a lease but no
		# default route, forcing dhcpcd to race the interfaces that are still unconfigured. An
		# interface that has not leased yet is never excluded, so a slow real NIC is still caught.
		tries=1
		deny=""
		while [ $tries -le 5 ]; do
			if [ -n "${deny}" ]; then
				/sbin/dhcpcd -f /dhcpcd.conf --allowinterfaces "${al}" --denyinterfaces "${deny}" -1 || true
			else
				/sbin/dhcpcd -f /dhcpcd.conf --allowinterfaces "${al}" -1 || true
			fi
			if [ -n "$(default_route_iface)" ]; then
				break
			fi
			deny="$(leased_ifaces)"
			echo "no default route after dhcpcd attempt #$tries; excluding '${deny}' and retrying"
			sleep 2
			tries=$((tries + 1))
		done

		# use busybox's ntpd to set the time after getting an IP address; don't fail
		echo "sleep 1 second before calling ntpd; date: '$(date)'" && sleep 1
		sync_time || true
	else
		/sbin/dhcpcd --nobackground -f /dhcpcd.conf --allowinterfaces "${al}"
	fi

}

if [ -f /run/network/interfaces ] || [ -f /var/run/network/interfaces ]; then
	echo "the /run/network/interfaces file or /var/run/network/interfaces file exists, so static IP's are in use. not running the dhcp client."
	exit 0
fi

# we always return true so that a failure here doesn't block the next container service from starting. Ideally, we always
# want the getty service to start so we can debug failures.
run_dhcp_client "$1" || true
