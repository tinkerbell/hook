ORG ?= quay.io/tinkerbell
ARCH := $(shell uname -m)

GIT_VERSION ?= $(shell git log -1 --format="%h")
ifneq ($(shell git status --porcelain),)
  GIT_VERSION := $(GIT_VERSION)-dirty
endif
default: bootkitBuild tink-dockerBuild image

LINUXKIT_CONFIG ?= hook.yaml

dev: dev-bootkitBuild dev-tink-dockerBuild
ifeq ($(ARCH),x86_64)
dev: image-amd64
endif
ifeq ($(ARCH),aarch64)
dev: image-arm64
endif

# This option is for running docker manifest command
export DOCKER_CLI_EXPERIMENTAL := enabled

image-amd64:
	mkdir -p out
	linuxkit build -docker -disable-content-trust -pull -format kernel+initrd -name hook-x86_64 -dir out $(LINUXKIT_CONFIG)

image-arm64:
	mkdir -p out
	linuxkit build -docker -disable-content-trust -pull -arch arm64 -format kernel+initrd -name hook-aarch64 -dir out $(LINUXKIT_CONFIG)

image: image-amd64 image-arm64

debug-image-amd64:
	mkdir -p out/amd64
	linuxkit build --docker -format kernel+initrd -name debug-x86_64 -dir out hook_debug.yaml

debug-image-arm64:
	mkdir -p out/arm64
	linuxkit build --docker -arch arm64 -format kernel+initrd -name debug-aarch64 -dir out hook_debug.yaml

debug-image: debug-image-amd64 debug-image-arm64

run-amd64:
	sudo ~/go/bin/linuxkit run qemu --mem 2048 out/hook-x86_64

run-arm64:
	sudo ~/go/bin/linuxkit run qemu --mem 2048 out/hook-aarch64

run:
	sudo ~/go/bin/linuxkit run qemu --mem 2048 out/hook-${ARCH}

dev-bootkitBuild:
	cd bootkit; docker buildx build -load -t $(ORG)/hook-bootkit:0.0 .

bootkitBuild:
	cd bootkit; docker buildx build --platform linux/amd64,linux/arm64 --push -t $(ORG)/hook-bootkit:0.0 .

dev-tink-dockerBuild:
	cd tink-docker; docker buildx build -load -t $(ORG)/hook-docker:0.0 .

tink-dockerBuild:
	cd tink-docker; docker buildx build --platform linux/amd64,linux/arm64 --push -t $(ORG)/hook-docker:0.0 .

dev-convert:
	rm -rf ./convert
	mkdir ./convert
	cp out/hook-${ARCH}-initrd.img ./convert/initrd.gz
	cd convert/; gunzip ./initrd.gz; cpio -idv < initrd; rm initrd; find . -print0 | cpio --null -ov --format=newc > ../initramfs-${ARCH}; gzip ../initramfs-${ARCH}

.PHONY: convert
convert:
	for a in x86_64 aarch64; do \
		rm -rf ./convert; \
		mkdir ./convert; \
		cp out/hook-$$a-initrd.img ./convert/initrd.gz; \
		cd convert/; gunzip ./initrd.gz; cpio -idv < initrd; rm initrd; find . -print0 | cpio --null -ov --format=newc > ../initramfs-$$a; gzip ../initramfs-$$a; cd ../;\
	done

dist: default convert
	rm -rf ./dist ./convert
	mkdir ./dist
	for a in x86_64 aarch64; do \
		mv ./initramfs-$$a.gz ./dist/initramfs-$$a; \
		mv ./out/hook-$$a-kernel ./dist/vmlinuz-$$a; \
	done
	rm -rf out
	cd ./dist && tar -czvf ../hook-${GIT_VERSION}.tar.gz ./*

dist-existing-images: image convert
	rm -rf ./dist ./convert
	mkdir ./dist
	for a in x86_64 aarch64; do \
		mv ./initramfs-$$a.gz ./dist/initramfs-$$a; \
		mv ./out/hook-$$a-kernel ./dist/vmlinuz-$$a; \
	done
	rm -rf out
	cd ./dist && tar -czvf ../hook-${GIT_VERSION}.tar.gz ./*


dev-dist: dev dev-convert
	rm -rf ./dist ./convert
	mkdir ./dist
	mv ./initramfs-${ARCH}.gz ./dist/initramfs-${ARCH}
	mv ./out/hook-${ARCH}-kernel ./dist/vmlinuz-${ARCH}
	rm -rf out
	cd ./dist && tar -czvf ../hook-${GIT_VERSION}.tar.gz ./*

deploy: dist
ifeq ($(shell git rev-parse --abbrev-ref HEAD),master)
	s3cmd sync ./hook-${GIT_VERSION}.tar.gz s3://s.gianarb.it/hook/${GIT_VERSION}.tar.gz
	s3cmd cp s3://s.gianarb.it/hook/hook-${GIT_VERSION}.tar.gz s3://s.gianarb.it/hook/hook-master.tar.gz
endif
