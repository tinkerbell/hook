#!/bin/sh

# This script is intended to be run on the HookOS/Linuxkit host so it must use /bin/sh.
# No other shells are available on the host.

# modified from alpine setup-dns
# apk add alpine-conf

exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/var/log/setup-dns.log 2>&1

while getopts "d:n:h" opt; do
        case $opt in
                d) DOMAINNAME="$OPTARG";;
                n) NAMESERVERS="$OPTARG";;
        esac
done
shift $(($OPTIND - 1))


conf="${ROOT}resolv.conf"

if [ -f "$conf" ] ; then
        domain=$(awk '/^domain/ {print $2}' $conf)
        dns=$(awk '/^nameserver/ {printf "%s ",$2}' $conf)
elif fqdn="$(get_fqdn)" && [ -n "$fqdn" ]; then
        domain="$fqdn"
fi

if [ -n "$DOMAINNAME" ]; then
        domain="$DOMAINNAME"
fi

if [ -n "$NAMESERVERS" ] || [ $# -gt 0 ];then
        dns="$NAMESERVERS"
fi

if [ -n "$domain" ]; then
        mkdir -p "${conf%/*}"
        echo "search $domain" > $conf
fi

if [ -n "$dns" ] || [ $# -gt 0 ] && [ -f "$conf" ]; then
        sed -i -e '/^nameserver/d' $conf
fi
for i in $dns $@; do
        mkdir -p "${conf%/*}"
        echo "nameserver $i" >> $conf
done
