#!/bin/sh
# dhcpcd-reject.sh
if [ "$reason" = "BOUND" ]; then
    if [ "$server_id" = "10.20.23.217" ]; then exit 1; fi
    if [ "$server_id" = "10.20.22.1" ]; then exit 1; fi
fi
exit 0
