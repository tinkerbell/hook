#!/bin/sh

echo "--> STARTING persistent-storage script with MDEV='${MDEV}' ACTION='${ACTION}' all params: $*" >&2

symlink_action() {
	case "$ACTION" in
		add)
			echo "SYMLINK ADD: ln -sf '$1' '$2'" >&2
			ln -sf "$1" "$2"
			;;
		remove) rm -f "$2" ;;
	esac
}

sanitise_file() {
	sed -E -e 's/^\s+//' -e 's/\s+$//' -e 's/ /_/g' "$@" 2> /dev/null
}

sanitise_string() {
	echo "$@" | sanitise_file
}

blkid_encode_string() {
	# Rewrites string similar to libblk's blkid_encode_string
	# function which is used by udev/eudev.
	echo "$@" | sed -e 's| |\\x20|g'
}

: ${SYSFS:=/sys}

# cdrom symlink
case "$MDEV" in
	sr* | xvd*)
		caps="$(cat $SYSFS/block/$MDEV/capability 2> /dev/null)"
		if [ $((0x${caps:-0} & 8)) -gt 0 ] || [ "$(cat $SYSFS/block/$MDEV/removable 2> /dev/null)" = "1" ]; then
			symlink_action $MDEV cdrom
		fi
		;;
esac

# /dev/block symlinks
mkdir -p block
if [ -f "$SYSFS/class/block/$MDEV/dev" ]; then
	maj_min=$(sanitise_file "$SYSFS/class/block/$MDEV/dev")
	symlink_action ../$MDEV block/${maj_min}
fi

# by-id symlinks
mkdir -p disk/by-id

if [ -f "$SYSFS/class/block/$MDEV/partition" ]; then
	# This is a partition of a device, find out its parent device
	_parent_dev="$(basename $(${SBINDIR:-/usr/bin}/readlink -f "$SYSFS/class/block/$MDEV/.."))"

	partition=$(cat $SYSFS/class/block/$MDEV/partition 2> /dev/null)
	case "$partition" in
		[0-9]*) partsuffix="-part$partition" ;;
	esac
	# Get name, model, serial, wwid from parent device of the partition
	_check_dev="$_parent_dev"
else
	_check_dev="$MDEV"
fi

model=$(sanitise_file "$SYSFS/class/block/$_check_dev/device/model")
echo "INITIAL model: '${model}'" >&2
name=$(sanitise_file "$SYSFS/class/block/$_check_dev/device/name") # only used for mmcblk case
echo "INITIAL name: '${name}'" >&2
serial=$(sanitise_file "$SYSFS/class/block/$_check_dev/device/serial")
echo "INITIAL serial: '${serial}'" >&2
# Special case where block devices have serials attached to the block itself, like virtio-blk
: ${serial:=$(sanitise_file "$SYSFS/class/block/$_check_dev/serial")}
echo "DEVICE serial (after block-serial): '${serial}'" >&2
wwid=$(sanitise_file "$SYSFS/class/block/$_check_dev/wwid")
echo "INITIAL wwid: '${wwid}'" >&2
: ${wwid:=$(sanitise_file "$SYSFS/class/block/$_check_dev/device/wwid")}
echo "DEVICE wwid (from device-wwid): '${wwid}'" >&2

# Sets variables LABEL, PARTLABEL, PARTUUID, TYPE, UUID depending on
# blkid output (busybox blkid will not provide PARTLABEL or PARTUUID)
eval $(blkid /dev/$MDEV | cut -d: -f2-)

if [ -n "$wwid" ]; then
	case "$MDEV" in
		nvme*) symlink_action ../../$MDEV disk/by-id/nvme-${wwid}${partsuffix} ;;
		sd*) symlink_action ../../$MDEV disk/by-id/scsi-${wwid}${partsuffix} ;;
		sr*) symlink_action ../../$MDEV disk/by-id/scsi-ro-${wwid}${partsuffix} ;;
		vd*) symlink_action ../../$MDEV disk/by-id/virtio-${wwid}${partsuffix} ;;
	esac
	case "$wwid" in
		naa.*) symlink_action ../../$MDEV disk/by-id/wwn-0x${wwid#naa.}${partsuffix} ;;
	esac
fi

# if no model or no serial is available, lets parse the wwid and try to use it
if [ -n "${serial}" ] && [ -n "${model}" ]; then
	echo "USING SYSFS model='${model}' serial='${serial}'" >&2
else
	echo "SYSFS model='${model}' serial='${serial}' insufficient, trying to parse from wwid" >&2
	unset wwid_raw
	if [ -f "$SYSFS/class/block/$_check_dev/wwid" ]; then
		echo "FOUND WWID FILE: '$SYSFS/class/block/$_check_dev/wwid'" >&2
		wwid_raw="$(cat "$SYSFS/class/block/$_check_dev/wwid")"
	elif [ -f "$SYSFS/class/block/$_check_dev/device/wwid" ]; then
		echo "FOUND WWID FILE: '$SYSFS/class/block/$_check_dev/device/wwid'" >&2
		wwid_raw="$(cat "$SYSFS/class/block/$_check_dev/device/wwid")"
	fi
	echo "SYSFS parse model/serial from wwid_raw:'${wwid_raw}'" >&2
	if [ -n "${wwid_raw}" ]; then
		wwid_raw=$(echo "${wwid_raw}" | sed 's/^ *//;s/ *$//')                      # Remove leading and trailing spaces
		wwid_prefix=$(echo "${wwid_raw}" | awk '{print $1}')                        # Extract the wwid_prefix (first field)
		rest=$(echo "${wwid_raw}" | sed "s/^${wwid_prefix} *//")                    # Remove the wwid_prefix from the wwid string
		wwid_serial=$(echo "${rest}" | awk '{print $NF}')                           # Extract the serial (last field)
		wwid_model=$(echo "${rest}" | sed "s/ ${wwid_serial}$//")                   # Remove the serial from the rest of the string
		:                                                                           # sanitize model ----------------------------------------------------------------------
		wwid_model=$(echo "${wwid_model}" | tr ' ' '_' | tr '.' '_' | tr '/' '_')   # Replace any remaining spaces, dots, slashes in the rest part with underscores
		wwid_model=$(echo "${wwid_model}" | sed 's/\\0//g')                         # Remove all instances of literal backslash-zero "\0" (not really nulls)
		wwid_model=$(echo "${wwid_model}" | sed 's/\\/_/g')                         # replace any remaining backslashes with underscores
		wwid_model=$(echo "${wwid_model}" | sed 's/__*/_/g')                        # Remove consecutive underscores
		wwid_model=$(echo "${wwid_model}" | sed 's/^_//;s/_$//')                    # Remove leading and trailing underscores
		:                                                                           # sanitize serial ---------------------------------------------------------------------
		wwid_serial=$(echo "${wwid_serial}" | tr ' ' '_' | tr '.' '_' | tr '/' '_') # Replace any remaining spaces, dots, slashes in the rest part with underscores
		wwid_serial=$(echo "${wwid_serial}" | sed 's/\\0//g')                       # Remove all instances of literal backslash-zero "\0" (not really nulls)
		wwid_serial=$(echo "${wwid_serial}" | sed 's/\\/_/g')                       # replace any remaining backslashes with underscores
		wwid_serial=$(echo "${wwid_serial}" | sed 's/__*/_/g')                      # Remove consecutive underscores
		wwid_serial=$(echo "${wwid_serial}" | sed 's/^_//;s/_$//')                  # Remove leading and trailing underscores

		unset rest wwid_prefix
		echo "WWID parsing came up with wwid_model='${wwid_model}', wwid_serial='${wwid_serial}'" >&2
	else
		echo "WWID is empty or not found" >&2
	fi

	# if model is unset, replace it with the parsed wwid_model
	if [ -z "${model}" ]; then
		echo "USING WWID model='${wwid_model}' as model..." >&2
		model="${wwid_model}"
	fi

	# if serial is unset, replace it with the parsed wwid_serial
	if [ -z "${serial}" ]; then
		echo "USING WWID wwid_serial='${wwid_serial}' as serial..." >&2
		serial="${wwid_serial}"
	fi

	# if we still have no serial, just use the wwid as serial as fallback;
	if [ -z "${serial}" ]; then
		echo "FALLBACK: USING WWID as serial='${wwid}'" >&2
		serial="${wwid}"
	fi

	# rescue: if _still_ no serial set, set to hardcoded string 'noserial'.
	if [ -z "${serial}" ]; then
		echo "FALLBACK: USING 'noserial' as serial..." >&2
		serial="noserial"
	fi
fi

if [ -n "$serial" ]; then
	echo "GOT SERIAL: serial='${serial}' model='${model}'" >&2
	if [ -n "$model" ]; then
		echo "GOT MODEL: serial='${serial}' model='${model}'" >&2
		case "$MDEV" in
			nvme*) symlink_action ../../$MDEV disk/by-id/nvme-${model}_${serial}${partsuffix} ;;
			sr*) symlink_action ../../$MDEV disk/by-id/ata-ro-${model}_${serial}${partsuffix} ;;
			sd*) symlink_action ../../$MDEV disk/by-id/ata-${model}_${serial}${partsuffix} ;;
			vd*) symlink_action ../../$MDEV disk/by-id/virtio-${model}_${serial}${partsuffix} ;;
		esac
	fi
	if [ -n "$name" ]; then
		case "$MDEV" in
			mmcblk*) symlink_action ../../$MDEV disk/by-id/mmc-${name}_${serial}${partsuffix} ;;
		esac
	fi

	# virtio-blk
	case "$MDEV" in
		vd*) symlink_action ../../$MDEV disk/by-id/virtio-${serial}${partsuffix} ;;
	esac
fi

# by-label, by-partlabel, by-partuuid, by-uuid symlinks
if [ -n "$LABEL" ]; then
	mkdir -p disk/by-label
	symlink_action ../../$MDEV disk/by-label/"$(blkid_encode_string "$LABEL")"
fi
if [ -n "$PARTLABEL" ]; then
	mkdir -p disk/by-partlabel
	symlink_action ../../$MDEV disk/by-partlabel/"$(blkid_encode_string "$PARTLABEL")"
fi
if [ -n "$PARTUUID" ]; then
	mkdir -p disk/by-partuuid
	symlink_action ../../$MDEV disk/by-partuuid/"$PARTUUID"
fi
if [ -n "$UUID" ]; then
	mkdir -p disk/by-uuid
	symlink_action ../../$MDEV disk/by-uuid/"$UUID"
fi

# nvme EBS storage symlinks
if [ "${MDEV#nvme}" != "$MDEV" ] && [ "$model" = "Amazon_Elastic_Block_Store" ] && command -v nvme > /dev/null; then
	n=30
	while [ $n -gt 0 ]; do
		ebs_alias=$(nvme id-ctrl -b /dev/$_check_dev |
			dd bs=32 skip=96 count=1 2> /dev/null |
			sed -nre '/^(\/dev\/)?(s|xv)d[a-z]{1,2} /p' |
			tr -d ' ')
		if [ -n "$ebs_alias" ]; then
			symlink_action "$MDEV" ${ebs_alias#/dev/}$partition
			break
		fi
		n=$((n - 1))
		sleep 0.1
	done
fi

# backwards compatibility with /dev/usbdisk for /dev/sd*
if [ "${MDEV#sd}" != "$MDEV" ]; then
	sysdev=$(readlink $SYSFS/class/block/$MDEV)
	case "$sysdev" in
		*usb[0-9]*)
			# require vfat for devices without partition
			if ! [ -e $SYSFS/block/$MDEV ] || [ TYPE="vfat" ]; then # @TODO: rpardini: upstream bug here? should be $TYPE
				symlink_action $MDEV usbdisk
			fi
			;;
	esac
fi

echo "--> FINISHED persistent-storage script with MDEV='${MDEV}' ACTION='${ACTION}' all params: $*" >&2
echo "" >&2
