FROM python:3.11-alpine

RUN apk update && \
    apk add --no-cache fio nvme-cli util-linux lshw numactl-tools ndctl vim mdevd && \
    apk add sedutil --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing
#RUN apt update -y && \
#    apt install -y \
#	fio nvme-cli util-linux lshw mdevctl numactl ndctl vim && \
#	rm -rf /var/lib/apt/lists/*
WORKDIR /app
#ADD sedutil-cli.chubbyant.1.15-5ad84d8 /usr/bin/sedutil-cli

RUN pip install --no-cache-dir -U pip ipdb
ADD requirements.txt setup.py /app/
RUN pip install --no-cache-dir -r requirements.txt
ADD hwinfo /app/hwinfo
RUN pip install -e .
CMD ["hwinfo"]
