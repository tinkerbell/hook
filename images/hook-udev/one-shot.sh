#!/usr/bin/bash

# Here we start the systemd-udev daemon, sleep a bit, run udevadm settle, and then stop the daemon, all using bash.
# This is a one-shot script that is run by LinuxKit when the system boots up.

echo "$(date) Starting systemd-udev in the background..."
/lib/systemd/systemd-udevd "${@}" &
declare udev_pid=$!
echo "$(date) systemd-udev started with PID: ${udev_pid}"

echo "$(date) Sleeping for 2 seconds so systemd-udev does its job..."
sleep 2

echo "$(date) Running udevadm trigger..."
udevadm trigger --action=add

echo "$(date) Running udevadm settle..."
udevadm settle

echo "$(date) Status of /dev/disk/by-id:"
ls -la /dev/disk/by-id/* || true

echo "$(date) Stopping systemd-udev with PID: ${udev_pid}"
kill -SIGTERM "${udev_pid}"

echo "$(date) Waiting for systemd-udev to stop..."
wait

echo "$(date) systemd-udev stopped with PID: ${udev_pid}"
echo "$(date) One-shot script completed."

exit 0
