GIT_VERSION ?= $(shell git log -1 --format="%h")
ifneq ($(shell git status --porcelain),)
  GIT_VERSION := $(GIT_VERSION)-dirty
endif
default: bootkitBuild tink-dockerBuild image


image:
	mkdir -p out
	linuxkit build --docker -format kernel+initrd -name tinkie -dir out tinkie.yaml

debug-image:
	mkdir -p out
	linuxkit build --docker -format kernel+initrd -name debug -dir out tinkie_debug.yaml

run:
	sudo ~/go/bin/linuxkit run qemu --mem 2048 out/tinkie

bootkitBuild:
	cd bootkit; docker buildx build  --platform linux/amd64 --load -t bootkit:0.0 .

tink-dockerBuild:
	cd tink-docker; docker buildx build  --platform linux/amd64 --load -t tink-docker:0.0 .

convert:
	mkdir convert
	cp out/tinkie-initrd.img ./convert/initrd.gz
	cd convert; gunzip ./initrd.gz; cpio -idv < initrd; rm initrd; find . -print0 | cpio --null -ov --format=newc > ../initramfs; gzip ../initramfs

dist: default convert
	rm -rf ./dist ./convert
	mkdir ./dist
	mv ./initramfs.gz ./dist/initramfs-x86_64
	mv ./out/tinkie-kernel ./dist/vmlinuz-x86_64
	rm -rf out
	cd ./dist && tar -czvf ../tinkie-${GIT_VERSION}.tar.gz ./*

deploy: dist
ifeq ($(shell git rev-parse --abbrev-ref HEAD),master)
	s3cmd sync ./tinkie-${GIT_VERSION}.tar.gz s3://s.gianarb.it/tinkie/${GIT_VERSION}.tar.gz
	s3cmd cp s3://s.gianarb.it/tinkie/tinkie-${GIT_VERSION}.tar.gz s3://s.gianarb.it/tinkie/tinkie-master.tar.gz
endif
