ORG ?= quay.io/tinkerbell
ARCH := $(shell uname -m)

ifeq ($(strip $(TAG)),)
  # ^ guards against TAG being defined but empty string which makes `TAG ?=` not work
  TAG := latest
endif
default: hook-bootkitBuild hook-dockerBuild image

dev: dev-hook-bootkitBuild dev-hook-dockerBuild
ifeq ($(ARCH),x86_64)
dev: dev-image-amd64
endif
ifeq ($(ARCH),aarch64)
dev: dev-image-arm64
endif

# This option is for running docker manifest command
export DOCKER_CLI_EXPERIMENTAL := enabled

LINUXKIT_CONFIG ?= hook.yaml
hook.$(TAG).yaml: $(LINUXKIT_CONFIG)
	sed '/quay.io/ s|:latest|:$(TAG)|' $^ > $@.tmp
	mv $@.tmp $@

image-amd64: hook.$(TAG).yaml
	mkdir -p out
	linuxkit build -docker -pull -format kernel+initrd -name hook-x86_64 -dir out $^

image-arm64: hook.$(TAG).yaml
	mkdir -p out
	linuxkit build -docker -pull -arch arm64 -format kernel+initrd -name hook-aarch64 -dir out $^

dev-image-amd64: hook.$(TAG).yaml
	mkdir -p out
	linuxkit build -docker -format kernel+initrd -name hook-x86_64 -dir out $^

dev-image-arm64: hook.$(TAG).yaml
	mkdir -p out
	linuxkit build -docker -arch arm64 -format kernel+initrd -name hook-aarch64 -dir out $^

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

dev-hook-bootkitBuild:
	cd hook-bootkit; docker buildx build --load -t $(ORG)/hook-bootkit:$(TAG) .

hook-bootkitBuild:
	cd hook-bootkit; docker buildx build --platform linux/amd64,linux/arm64 --push -t $(ORG)/hook-bootkit:$(TAG) .

dev-hook-dockerBuild:
	cd hook-docker; docker buildx build --load -t $(ORG)/hook-docker:$(TAG) .

hook-dockerBuild:
	cd hook-docker; docker buildx build --platform linux/amd64,linux/arm64 --push -t $(ORG)/hook-docker:$(TAG) .

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
	cd ./dist && tar -czvf ../hook-${TAG}.tar.gz ./*

dist-existing-images: image convert
	rm -rf ./dist ./convert
	mkdir ./dist
	for a in x86_64 aarch64; do \
		mv ./initramfs-$$a.gz ./dist/initramfs-$$a; \
		mv ./out/hook-$$a-kernel ./dist/vmlinuz-$$a; \
	done
	rm -rf out
	cd ./dist && tar -czvf ../hook-${TAG}.tar.gz ./*


dev-dist: dev dev-convert
	rm -rf ./dist ./convert
	mkdir ./dist
	mv ./initramfs-${ARCH}.gz ./dist/initramfs-${ARCH}
	mv ./out/hook-${ARCH}-kernel ./dist/vmlinuz-${ARCH}
	rm -rf out
	cd ./dist && tar -czvf ../hook-${TAG}.tar.gz ./*

deploy: dist
ifeq ($(shell git rev-parse --abbrev-ref HEAD),main)
	s3cmd sync ./hook-${TAG}.tar.gz s3://s.gianarb.it/hook/${TAG}.tar.gz
	s3cmd cp s3://s.gianarb.it/hook/hook-${TAG}.tar.gz s3://s.gianarb.it/hook/hook-main.tar.gz
endif

.PHONY: clean
clean:
	rm ./hook-${TAG}.tar.gz
	rm -rf dist/ out/ hook-docker/local/ hook-bootkit/local/

-include lint.mk
