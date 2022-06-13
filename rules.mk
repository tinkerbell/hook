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
# mode := $(1)
# arch := $(2)

$$(shell mkdir -p out/$T/$(1)/$(2))

.PHONY: hook-$(1)-$(2)
image-$(1)-$(2): out/$T/$(1)/$(2)/hook.tar
out/$T/$(1)/$(2)/hook.tar: out/$T/$(1)/$(2)/hook.yaml out/$T/hook-bootkit-$(2) out/$T/hook-docker-$(2)
	linuxkit build -docker -arch $(2) -format tar-kernel-initrd -name hook -dir $$(@D) $$<
	mv $$(@D)/hook-initrd.tar $$@

out/$T/$(1)/$(2)/cmdline out/$T/$(1)/$(2)/initrd.img out/$T/$(1)/$(2)/kernel: out/$T/$(1)/$(2)/hook.tar
	tar xf $$^ -C $$(@D) $$(@F)
	touch $$@

out/$T/$(1)/$(2)/hook.yaml: $$(LINUXKIT_CONFIG)
	sed '/hook-\(bootkit\|docker\):/ { s|:latest|:$T-$(2)|; s|quay.io/tinkerbell|$(ORG)|; }' $$< > $$@
	if [[ $(1) == dbg ]]; then
	    sed -i '/^\s*#dbg/ s|#dbg||' $$@
	fi
endef
$(foreach m,$(modes),$(foreach a,$(arches),$(eval $(call foreach_mode_arch_rules,$m,$a))))

define foreach_arch_rules =
# arch := $(1)

debug: out/$T/dbg/$(1)/hook.tar
images: out/$T/rel/$(1)/hook.tar
image-dbg-$(1): out/$T/dbg/$(1)/hook.tar

out/$T/rel/hook.tar: out/$T/rel/$(1)/initrd.img out/$T/rel/$(1)/kernel
hook-bootkit: out/$T/hook-bootkit-$(1)
hook-docker: out/$T/hook-docker-$(1)

out/$T/hook-bootkit-$(1): $$(hook-bootkit-deps)
out/$T/hook-docker-$(1): $$(hook-docker-deps)
out/$T/hook-bootkit-$(1) out/$T/hook-docker-$(1): platform=linux/$$(lastword $$(subst -, ,$$(notdir $$@)))
out/$T/hook-bootkit-$(1) out/$T/hook-docker-$(1): container=hook-$$(word 2,$$(subst -, ,$$(notdir $$@)))
out/$T/hook-bootkit-$(1) out/$T/hook-docker-$(1):
	docker buildx build --platform $$(platform) --load -t $(ORG)/$$(container):$T-$(1) $$(container)
	touch $$@

run-$(1): out/$T/dbg/$(1)/hook.tar
run-$(1):
	linuxkit run qemu --mem 2048 $$^
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
dist: out/$T/rel/hook-$T.tar.gz ## Build tarball for distribution
out/$T/rel/hook-$T.tar.gz: out/$T/rel/hook.tar
	pigz < $< > $@

out/$T/rel/hook.tar:
	rm -rf out/$T/rel/dist
	mkdir -p out/$T/rel/dist
	for a in $(arches); do
		cp out/$T/rel/$$a/initrd.img out/$T/rel/dist/initramfs-$$a
		cp out/$T/rel/$$a/kernel out/$T/rel/dist/vmlinuz-$$a
	done
	cd out/$T/rel/dist && tar -cvf ../$(@F) ./*

deploy: dist ## Push tarball to S3
ifeq ($(shell git rev-parse --abbrev-ref HEAD),main)
	s3cmd sync ./out/hook-$T.tar.gz s3://s.gianarb.it/hook/$T.tar.gz
	s3cmd cp s3://s.gianarb.it/hook/hook-$T.tar.gz s3://s.gianarb.it/hook/hook-main.tar.gz
endif
