FROM scratch
ENTRYPOINT []
WORKDIR /
COPY ./images/ /etc/embedded-images/
# the name 001 is important as that is the order in which the scripts are executed
# we need this mounting to happen before the other init.d scripts run so that
# the mount points are available to them.
COPY ./images-mount.sh /etc/init.d/001-images-mount.sh
CMD []
