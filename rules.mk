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
DOCKER_2_HW_amd64 := x86_64
DOCKER_2_HW_arm64 := aarch64

dist-files :=
hook-bootkit-deps := $(wildcard hook-bootkit/*)
hook-docker-deps := $(wildcard hook-docker/*)
modes := rel dbg

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

out/$T/$(1)/hook_$(DOCKER_2_HW_$(2)).tar.gz: out/$T/$(1)/initramfs-$(DOCKER_2_HW_$(2)) out/$T/$(1)/vmlinuz-$(DOCKER_2_HW_$(2))
out/$T/$(1)/initramfs-$(DOCKER_2_HW_$(2)): out/$T/$(1)/$(2)/initrd.img
out/$T/$(1)/vmlinuz-$(DOCKER_2_HW_$(2)): out/$T/$(1)/$(2)/kernel
dist-files += out/$T/$(1)/initramfs-$(DOCKER_2_HW_$(2)) out/$T/$(1)/vmlinuz-$(DOCKER_2_HW_$(2))
endef
$(foreach m,$(modes),$(foreach a,$(arches),$(eval $(call foreach_mode_arch_rules,$m,$a))))

define foreach_arch_rules =
# arch := $(1)

debug: dbg-image-$(1)
dbg-image-$(1): out/$T/dbg/$(1)/hook.tar
dist: out/$T/rel/hook_$(DOCKER_2_HW_$(1)).tar.gz
images: out/$T/rel/$(1)/hook.tar

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

define foreach_mode_rules =
# mode := $(1)

out/$T/$(1)/hook_%.tar.gz:
	tar -C $$(@D) -cvf- $$(^F) | pigz > $$@

endef
$(foreach m,$(modes),$(eval $(call foreach_mode_rules,$m)))

push-hook-bootkit: $(hook-bootkit-deps)
push-hook-docker: $(hook-docker-deps)
push-hook-bootkit push-hook-docker: platforms=$(addprefix linux/,$(arches))
push-hook-bootkit push-hook-docker: container=hook-$(lastword $(subst -, ,$(basename $@)))
push-hook-bootkit push-hook-docker:
	platforms="$(platforms)"
	platforms=$${platforms// /,}
	docker buildx build --platform $$platforms --push -t $(ORG)/$(container):$T $(container)

.PHONY: dist
dist: ## Build tarballs for distribution
$(dist-files):
	cp $< $@

.PHONY: dbg-dist
dbg-dist: out/$T/dbg/hook_$(DOCKER_2_HW_$(ARCH)).tar.gz ## Build debug enabled tarball

.PHONY: deploy
deploy: dist ## Push tarball to S3
	exit 1
	for f in out/$T/rel/hook_*.tar.gz; do
	    s3cmd sync $$f s3://s.gianarb.it/hook/$T/
	    s3cmd cp s3://s.gianarb.it/hook/$T/$$(basename $$f) s3://s.gianarb.it/hook/latest/
	done
