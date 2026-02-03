#!/bin/sh

# This script will run the dhcp client. If `vlan_id=` in `/proc/cmdline` has a value, it will run the dhcp client only on the
# VLAN interface.
# This script accepts an input parameter of true or false.
# true: run the dhcp client with the one shot option
# false: run the dhcp client as a service
set -x

run_dhcp_client() {
	one_shot="$1"
	al="e*"

	vlan_id=$(sed -n 's/.* vlan_id=\([0-9]*\).*/\1/p' /proc/cmdline)
	if [ -n "$vlan_id" ]; then
		al="e*.*"
	fi

	if [ "$one_shot" = "true" ]; then
		# always return true for the one shot dhcp call so it doesn't block Hook from starting up.
		# the --nobackground is not used here because when it is used, dhcpcd doesn't honor the --timeout option
		# and waits indefinitely for a response. For one shot, we want to timeout after the 30 second default.
		/sbin/dhcpcd -f /dhcpcd.conf --allowinterfaces "${al}" -1 || true

		# use busybox's ntpd to set the time after getting an IP address; don't fail
		echo "sleep 1 second before calling ntpd; date: '$(date)'" && sleep 1
		if ! /usr/sbin/ntpd -n -q -dd -p pool.ntp.org; then
			echo "ntpd call failed; setting time manually and retrying"
			# set system time to the date of the dhcpd binary file
			# this should recover from ntpd failures due to time being too far off
			date -s "$(stat -c %y /sbin/dhcpcd | cut -d'.' -f1)" || true
			tries=1	# retry up to 5 times
			while [ $tries -le 5 ]; do
				echo "waiting 1 second before retrying ntpd call; try #$tries ; date is now: '$(date)'"
				sleep 1
				if /usr/sbin/ntpd -n -q -dd -p pool.ntp.org; then
					echo "ntpd retry call succeeded on try #$tries; date is now: '$(date)'"
					break
				else
					echo "ntpd retry call failed on try #$tries"
				fi
				tries=$((tries + 1))
			done
		else
			echo "ntpd call succeeded; date is now: '$(date)'"
		fi
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
