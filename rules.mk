# Only use the recipes defined in these makefiles
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:
# Delete target files if there's an error
# This avoids a failure to then skip building on next run if the output is created by shell redirection for example
# Not really necessary for now, but just good to have already if it becomes necessary later.
.DELETE_ON_ERROR:
# Treat the whole recipe as a one shell script/invocation instead of one-per-line
.ONESHELL:
# Use bash instead of plain sh
SHELL := bash
.SHELLFLAGS := -o pipefail -euc

# This option is for running docker manifest command
export DOCKER_CLI_EXPERIMENTAL := enabled

ARCH := $(shell uname -m)
ifeq ($(ARCH),x86_64)
ARCH = amd64
endif
ifeq ($(ARCH),aarch64)
ARCH = arm64
endif

arches := amd64 arm64
modes := rel dbg

hook-bootkit-deps := $(wildcard hook-bootkit/*)
hook-docker-deps := $(wildcard hook-docker/*)

define foreach_mode_arch_rules =
mode := $(1)
arch := $(2)

$$(shell mkdir -p out/$T/$(mode)/$(arch))

.PHONY: image-$(mode)-$(arch)
image-$(mode)-$(arch): out/$T/$(mode)/$(arch)/hook.tar

out/$T/$(mode)/$(arch)/hook.tar: out/$T/$(mode)/$(arch)/hook.yaml out/$T/hook-bootkit-$(arch) out/$T/hook-docker-$(arch)
	linuxkit build -docker -arch $(arch) -format tar-kernel-initrd -name hook -dir $$(@D) $$<
	mv $$(@D)/hook-initrd.tar $$@

out/$T/$(mode)/$(arch)/cmdline out/$T/$(mode)/$(arch)/initrd.img out/$T/$(mode)/$(arch)/kernel: out/$T/$(mode)/$(arch)/hook.tar
	tar xf $$^ -C $$(@D) $$(@F)
	touch $$@

out/$T/$(mode)/$(arch)/hook.yaml: $$(LINUXKIT_CONFIG)
	sed '/hook-\(bootkit\|docker\):/ { s|:latest|:$T-$(arch)|; s|quay.io/tinkerbell|$(ORG)|; }' $$< > $$@
	if [[ $(mode) == dbg ]]; then
	    sed -i '/^\s*#dbg/ s|#dbg||' $$@
	fi
endef
$(foreach m,$(modes),$(foreach a,$(arches),$(eval $(call foreach_mode_arch_rules,$m,$a))))

define foreach_arch_rules =
arch := $(1)

debug: dbg-image-$(arch)
dbg-image-$(arch): out/$T/dbg/$(arch)/hook.tar
images: out/$T/rel/$(arch)/hook.tar

hook-bootkit: out/$T/hook-bootkit-$(arch)
hook-docker: out/$T/hook-docker-$(arch)

out/$T/hook-bootkit-$(arch): $$(hook-bootkit-deps)
out/$T/hook-docker-$(arch): $$(hook-docker-deps)
out/$T/hook-bootkit-$(arch) out/$T/hook-docker-$(arch): platform=linux/$$(lastword $$(subst -, ,$$(notdir $$@)))
out/$T/hook-bootkit-$(arch) out/$T/hook-docker-$(arch): container=hook-$$(word 2,$$(subst -, ,$$(notdir $$@)))
out/$T/hook-bootkit-$(arch) out/$T/hook-docker-$(arch):
	docker buildx build --platform $$(platform) --load -t $(ORG)/$$(container):$T-$(arch) $$(container)
	touch $$@

run-$(arch): out/$T/dbg/$(arch)/hook.tar
run-$(arch):
	mkdir -p out/$T/run/$(arch)
	tar --overwrite -xf $$^ -C out/$T/run/$(arch) --transform 's/^/hook-/'
	grep -q "tink_worker_image=quay.io/tinkerbell/tink-worker:latest" out/$T/run/$(arch)/hook-cmdline || sed -i 's?^?tink_worker_image=quay.io/tinkerbell/tink-worker:latest ?' out/$T/run/$(arch)/hook-cmdline
	linuxkit run qemu --mem 2048 -kernel out/$T/run/$(arch)/hook
endef
$(foreach a,$(arches),$(eval $(call foreach_arch_rules,$a)))

push-hook-bootkit: $(hook-bootkit-deps)
push-hook-docker: $(hook-docker-deps)
push-hook-bootkit push-hook-docker: platforms=$(addprefix linux/,$(arches))
push-hook-bootkit push-hook-docker: container=hook-$(lastword $(subst -, ,$(basename $@)))
push-hook-bootkit push-hook-docker:
	platforms="$(platforms)"
	platforms=$${platforms// /,}
	docker buildx build --platform $$platforms --push -t $(ORG)/$(container):$T $(container)

.PHONY: dist
dist: out/$T/rel/amd64/hook.tar out/$T/rel/arm64/hook.tar ## Build tarballs for distribution
dbg-dist: out/$T/dbg/$(ARCH)/hook.tar ## Build debug enabled tarball
dist dbg-dist:
	for f in $^; do
	case $$f in
	*amd64*) arch=x86_64 ;;
	*arm64*) arch=aarch64 ;;
	*) echo unknown arch && exit 1;;
	esac
	d=$$(dirname $$(dirname $$f))
	tar -xf $$f -C $$d/ kernel && mv $$d/kernel $$d/vmlinuz-$$arch
	tar -xf $$f -C $$d/ initrd.img && mv $$d/initrd.img $$d/initramfs-$$arch
	tar -cf- -C $$d initramfs-$$arch vmlinuz-$$arch | pigz > $$d/hook_$$arch.tar.gz
	done

build_5.15.x:
	$(MAKE) -C kernel ORG=$(ORG) IMAGE=hook-kernel build_5.15.x

build_5.10.x:
	$(MAKE) -C kernel ORG=$(ORG) IMAGE=hook-kernel build_5.10.x
