# This builds the supported LinuxKit kernels. Kernels are wrapped up
# in a scratch container, which contains the bzImage, a tar
# ball with modules, the kernel sources, and in some case, the perf binary.
#
# Each kernel is pushed to hub twice:
# - linuxkit/kernel:<kernel>.<major>.<minor>-<hash>
# - linuxkit/kernel:<kernel>.<major>.<minor>
# The <hash> is the git tree hash of the current directory. The build
# will only rebuild the kernel image if the git tree hash changed.
#
# For some kernels we also build a separate package containing the perf utility
# which is specific to a given kernel. perf packages are tagged the same way
# kernel packages.

# This option is for running docker manifest command
export DOCKER_CLI_EXPERIMENTAL := enabled

# set ORG in the env or make call
# having it in the makefile is dangerous as its too easy to overwrite previous pushes/tags
ifeq ($(strip $(ORG)),)
# ^ guards against ORG being defined but empty string which makes `ORG ?=` not work
  ORG := quay.io/tinkerbell
endif
# makes sure there's no trailing / so we can just add them in the recipes which looks nicer
ORG := $(shell echo "${ORG}" | sed 's|/*$$||')

IMAGE:=hook-kernel
IMAGE_BCC:=hook-kernel-bcc
IMAGE_PERF:=hook-kernel-perf
IMAGE_ZFS:=hook-zfs-kmod

# You can specify an extra options for the Makefile. This will:
# - append a config$(EXTRA) to the kernel config for your kernel/arch
# - append $(EXTRA) to the CONFIG_LOCALVERSION of your kernel
EXTRA?=

# You can enable debug options for the Makefile. This will:
# - append a config-dbg to the kernel config for your kernel/arch
# - append -dbg to the CONFIG_LOCALVERSION of your kernel
DEBUG?=

ifeq ($(HASH),)
HASH_COMMIT?=HEAD # Setting this is only really useful with the show-tag target
HASH?=$(shell git ls-tree --full-tree $(HASH_COMMIT) -- $(CURDIR) | awk '{print $$3}')

ifneq ($(HASH_COMMIT),HEAD) # Others can't be dirty by definition
DIRTY=$(shell  git update-index -q --refresh && git diff-index --quiet HEAD -- $(CURDIR) || echo "-dirty")
endif
endif

KERNEL_PLATFORMS:=linux/amd64,linux/arm64
PERF_PLATFORMS:=linux/amd64
BCC_PLATFORMS:=linux/amd64

ARCH := $(shell uname -m)

TAG=$(HASH)$(DIRTY)

REPO?=https://github.com/linuxkit/linuxkit
ifneq ($(REPO),)
REPO_LABEL=--label org.opencontainers.image.source=$(REPO)
endif
ifeq ($(DIRTY),)
REPO_COMMIT=$(shell git rev-parse HEAD)
COMMIT_LABEL=--label org.opencontainers.image.revision=$(REPO_COMMIT)
endif
LABELS=$(REPO_LABEL) $(COMMIT_LABEL)

ifeq ($(DOCKER_CONTENT_TRUST),)
ifndef NOTRUST
export DOCKER_CONTENT_TRUST=1
endif
endif

KERNEL_VERSIONS=

.PHONY: build devbuild
# Targets:
# devbuild: Builds all kernels only for the local arch
# build: Builds all kernels
devbuild:
build:

# A template for defining kernel build
# Arguments:
# $1: Full kernel version, e.g., 4.9.22
# $2: Kernel "series", e.g., 4.9.x
# $3: Build a specific kernel like -rt: Preempt-RT (used as suffix for image)
# This defines targets like:
# build_4.9.x and  push_4.9.x and adds them as dependencies
# to the global targets
# Set $3 to "-rt", to build Preempt-RT kernels. This defines targets like
# build_4.14.x-rt and adds "-rt" to the hub image name.
# Set $4 to "-dbg", to build debug kernels. This defines targets like
# build_4.9.x-dbg and adds "-dbg" to the hub image name.
# Set $3 to "-rt" and $4 to "-dbg" to build debug Preempt-RT kernel.
define kernel

ifeq ($(4),)
KERNEL_VERSIONS+=$(1)
endif

devbuild_$(2)$(3)$(4): Dockerfile Makefile $(wildcard patches-$(2)/*) $(wildcard config-$(2)*) config-dbg
	docker buildx build \
		--load \
		--build-arg KERNEL_VERSION=$(1) \
		--build-arg KERNEL_SERIES=$(2) \
		--build-arg EXTRA=$(3) \
		--build-arg DEBUG=$(4) \
		$(LABELS) \
		--no-cache -t $(ORG)/$(IMAGE):$(1)$(3)$(4)-$(TAG) .


build_$(2)$(3)$(4): Dockerfile Makefile $(wildcard patches-$(2)/*) $(wildcard config-$(2)*) config-dbg
	@if [ x"$(DIRTY)" !=  x ]; then echo "Your repository is not clean. Will not push image"; exit 1; fi
	docker pull $(ORG)/$(IMAGE):$(1)$(3)$(4)-$(TAG) || \
		docker buildx build \
			--platform $(KERNEL_PLATFORMS) \
			--push \
			--build-arg KERNEL_VERSION=$(1) \
			--build-arg KERNEL_SERIES=$(2) \
			--build-arg EXTRA=$(3) \
			--build-arg DEBUG=$(4) \
			$(LABELS) \
			--no-cache -t $(ORG)/$(IMAGE):$(1)$(3)$(4)-$(TAG) .

forcebuild_$(2)$(3)$(4): Dockerfile Makefile $(wildcard patches-$(2)/*) $(wildcard config-$(2)*) config-dbg
	docker buildx build \
		--platform $(KERNEL_PLATFORMS) \
		--push \
		--build-arg KERNEL_VERSION=$(1) \
		--build-arg KERNEL_SERIES=$(2) \
		--build-arg EXTRA=$(3) \
		--build-arg DEBUG=$(4) \
		$(LABELS) \
		-t $(ORG)/$(IMAGE):$(1)$(3)$(4)-$(TAG) .

show-tag_$(2)$(3)$(4):
	@echo $(ORG)/$(IMAGE):$(1)$(3)$(4)-$(TAG)

devbuild: devbuild_$(2)$(3)$(4)
build: build_$(2)$(3)$(4)
forcebuild: forcebuild_$(2)$(3)$(4)
show-tags: show-tag_$(2)$(3)$(4)

# 'docker build' with the FROM image supplied as --build-arg
# *and* with DOCKER_CONTENT_TRUST=1 currently does not work
# (https://github.com/moby/moby/issues/34199). So, we pull the image
# with DCT as part of the dependency on build_$(2)$(3)$(4) and then build
# with DOCKER_CONTENT_TRUST explicitly set to 0

# Only build perf on x86 and latest LTS and stable kernels
ifeq ($(ARCH),x86_64)
ifeq ($(2), $(filter $(2),5.10.x))
devbuild_perf_$(2)$(3)$(4): devbuild_$(2)$(3)$(4)
	DOCKER_CONTENT_TRUST=0 docker buildx build \
		-f Dockerfile.perf \
		--load \
		--build-arg IMAGE=$(ORG)/$(IMAGE):$(1)$(3)$(4)-$(TAG) \
		$(LABELS) \
		--no-cache --network=none \
		-t $(ORG)/$(IMAGE_PERF):$(1)$(3)$(4)-$(TAG) .

build_perf_$(2)$(3)$(4): build_$(2)$(3)$(4)
	@if [ x"$(DIRTY)" != x ]; then echo "Your repository is not clean. Will not push image"; exit 1; fi
	docker pull $(ORG)/$(IMAGE_PERF):$(1)$(3)$(4)-$(TAG) || \
		DOCKER_CONTENT_TRUST=0 docker buildx build \
			-f Dockerfile.perf \
			--platform $(PERF_PLATFORMS) \
			--push \
			--build-arg IMAGE=$(ORG)/$(IMAGE):$(1)$(3)$(4)-$(TAG) \
			$(LABELS) \
			--no-cache --network=none \
			-t $(ORG)/$(IMAGE_PERF):$(1)$(3)$(4)-$(TAG) .

forcebuild_perf_$(2)$(3)$(4): build_$(2)$(3)$(4)
	DOCKER_CONTENT_TRUST=0 docker buildx build \
		-f Dockerfile.perf \
		--platform $(PERF_PLATFORMS) \
		--push \
		--build-arg IMAGE=$(ORG)/$(IMAGE):$(1)$(3)$(4)-$(TAG) \
		$(LABELS) \
		--no-cache --network=none \
		-t $(ORG)/$(IMAGE_PERF):$(1)$(3)$(4)-$(TAG) .

#devbuild: devbuild_perf_$(2)$(3)$(4)
#build: build_perf_$(2)$(3)$(4)
#forcebuild: forcebuild_perf_$(2)$(3)$(4)
endif
endif

# Only build BCC on x86 and only on latest LTS and latest stable kernels.
ifeq ($(ARCH),x86_64)
ifeq ($(2), $(filter $(2),5.6.x 5.4.x))
devbuild_bcc_$(2)$(3)$(4): devbuild_$(2)$(3)$(4)
	DOCKER_CONTENT_TRUST=0 docker buildx build \
		-f Dockerfile.bcc \
		--load \
		--build-arg IMAGE=$(ORG)/$(IMAGE):$(1)$(3)$(4)-$(TAG) \
		$(LABELS) --no-cache \
		-t $(ORG)/$(IMAGE_BCC):$(1)$(3)$(4)-$(TAG) .

build_bcc_$(2)$(3)$(4): build_$(2)$(3)$(4)
	@if [ x"$(DIRTY)" != x ]; then echo "Your repository is not clean. Will not push image"; exit 1; fi
	docker pull $(ORG)/$(IMAGE_BCC):$(1)$(3)$(4)-$(TAG) || \
		DOCKER_CONTENT_TRUST=0 docker buildx build \
			-f Dockerfile.bcc \
			--platform $(BCC_PLATFORMS) \
			--push \
			--build-arg IMAGE=$(ORG)/$(IMAGE):$(1)$(3)$(4)-$(TAG) \
			$(LABELS) --no-cache \
			-t $(ORG)/$(IMAGE_BCC):$(1)$(3)$(4)-$(TAG) .

forcebuild_bcc_$(2)$(3)$(4): build_$(2)$(3)$(4)
	DOCKER_CONTENT_TRUST=0 docker buildx build \
		-f Dockerfile.bcc \
		--platform $(BCC_PLATFORMS) \
		--push \
		--build-arg IMAGE=$(ORG)/$(IMAGE):$(1)$(3)$(4)-$(TAG) \
		$(LABELS) --no-cache \
		-t $(ORG)/$(IMAGE_BCC):$(1)$(3)$(4)-$(TAG) .

#devbuild: devbuild_bcc_$(2)$(3)$(4)
#build: build_bcc_$(2)$(3)$(4)
#forcebuild: forcebuild_bcc_$(2)$(3)$(4)
endif
endif

ifeq ($(4),)
# ZFS does not compile against -dbg kernels because CONFIG_DEBUG_LOCK_ALLOC
# is incompatible with CDDL, apparently (this is ./configure check)
build_zfs_$(2)$(3): build_$(2)$(3)
	@if [ x"$(DIRTY)" != x ]; then echo "Your repository is not clean. Will not push image"; exit 1; fi
	docker pull $(ORG)/$(IMAGE_ZFS):$(1)$(3)-$(TAG) || \
		DOCKER_CONTENT_TRUST=0 docker buildx build \
			-f Dockerfile.zfs \
			--platform $(KERNEL_PLATFORMS) \
			--push \
			--build-arg IMAGE=$(ORG)/$(IMAGE):$(1)$(3)$(4)-$(TAG) \
			$(LABELS) --no-cache \
			-t $(ORG)/$(IMAGE_ZFS):$(1)$(3)$(4)-$(TAG) .

endif

endef

#
# Build Targets
# Debug targets only for latest stable and LTS stable
#
ifeq ($(ARCH),x86_64)
$(eval $(call kernel,5.10.85,5.10.x,$(EXTRA),$(DEBUG)))
#$(eval $(call kernel,5.4.28,5.4.x,-rt,))

else ifeq ($(ARCH),aarch64)
$(eval $(call kernel,5.10.85,5.10.x,$(EXTRA),$(DEBUG)))
#$(eval $(call kernel,5.4.28,5.4.x,-rt,))

endif

# Target for kernel config
kconfig:
ifeq (${KCONFIG_TAG},)
	docker buildx build --no-cache -f Dockerfile.kconfig \
		--platform linux/amd64,linux/arm64 \
		--push \
		--build-arg KERNEL_VERSIONS="$(KERNEL_VERSIONS)" \
		-t $(ORG)/kconfig .
else
	docker buildx build --no-cache -f Dockerfile.kconfig \
		--platform linux/amd64,linux/arm64 \
		-o type=local,dest=out/kconfig \
		--build-arg KERNEL_VERSIONS="$(KERNEL_VERSIONS)" \
		-t $(ORG)/kconfig:${KCONFIG_TAG} .
endif

kconfig_amd64:
ifeq (${KCONFIG_TAG},)
	docker buildx build --no-cache -f Dockerfile.kconfig \
		--platform linux/amd64 \
		--load \
		--build-arg KERNEL_VERSIONS="$(KERNEL_VERSIONS)" \
		-t $(ORG)/kconfig .
else
	docker buildx build --no-cache -f Dockerfile.kconfig \
		--platform linux/arm64 \
		-o type=local,dest=out/kconfig \
		--build-arg KERNEL_VERSIONS="$(KERNEL_VERSIONS)" \
		-t $(ORG)/kconfig:${KCONFIG_TAG} .
endif

kconfig_arm64:
ifeq (${KCONFIG_TAG},)
	docker buildx build --no-cache -f Dockerfile.kconfig \
		--platform linux/arm64 \
		--load \
		--build-arg KERNEL_VERSIONS="$(KERNEL_VERSIONS)" \
		-t $(ORG)/kconfig .
else
	docker buildx build --no-cache -f Dockerfile.kconfig \
		--platform linux/arm64 \
		-o type=local,dest=out/kconfig \
		--build-arg KERNEL_VERSIONS="$(KERNEL_VERSIONS)" \
		-t $(ORG)/kconfig:${KCONFIG_TAG} .
endif


.PHONY: clean
clean:
	rm out/
