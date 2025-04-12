FROM debian:12-slim AS base

RUN DEBIAN_FRONTEND=noninteractive apt update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends udev && \
    apt-get clean autoclean && \
    apt-get autoremove --yes && \
    rm -rf /var/lib/apt /var/lib/dpkg /var/lib/cache /var/lib/log /var/cache/* /usr/lib/apt/* /usr/share/*

# COPY udev.sh /sbin/udev
#CMD [ "/sbin/udev", "start" ]

CMD ["/etc/init.d/udev", "start"]

#RUN mkdir -p /lib/systemd/; ln -nfs /bin/udevadm /lib/systemd/systemd-udevd


#FROM alpine
#
#COPY --from=base /lib/ /lib/
#COPY --from=base /usr/lib/ /usr/lib/
#COPY --from=base /bin/udevadm /bin/udevadm
#COPY --from=base /etc/init.d/udev /etc/init.d/udev
#COPY --from=base /lib/systemd/systemd-udevd /lib/systemd/systemd-udevd
#
#CMD ["/etc/init.d/udev", "start"]