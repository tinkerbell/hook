FROM alpine

USER root:root

RUN apk add --no-cache mdev-conf && rm -rf /var/cache/apk/*

CMD ["mdev", "-v", "-df"]

