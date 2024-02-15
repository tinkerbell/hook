# set the ORG
### !!NOTE!!
# If this is changed then a fresh output dir is required (`git clean -fxd` or just `rm -rf out`)
# Handling this better shows some of make's suckiness compared to newer build tools (redo, tup ...) where the command lines to tools invoked isn't tracked by make
ORG := quay.io/tinkerbell
# makes sure there's no trailing / so we can just add them in the recipes which looks nicer
ORG := $(shell echo "${ORG}" | sed 's|/*$$||')

# The following `ifeq` are the equivalent of FOO ?= except that they work correctly if FOO is set but empty
ifeq ($(strip $(LINUXKIT_CONFIG)),)
  LINUXKIT_CONFIG := hook.yaml
endif

ifeq ($(strip $(TAG)),)
  TAG := sha-$(shell git rev-parse --short HEAD)
endif
T := $(strip $(TAG))

help: ## Print this help
	@grep --no-filename -E '^[[:alnum:]_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sed 's/:.*## /·/' | sort | column -t -s '·' -c $$(tput cols)

include rules.mk
include lint.mk

all: dist dbg-dist ## Build release mode boot files and container images for all supported architectures
containers: hook-bootkit hook-docker hook-mdev ## Build container images
debug: ## Build debug mode boot files and container images for all supported architectures
dev: dbg-image-$(ARCH) ## Build debug mode boot files and container images for currently running architecture
images: ## Build release mode boot files for all supported architectures
push: push-hook-bootkit push-hook-docker push-hook-mdev ## Push container images to registry
run: run-$(ARCH) ## Boot system using qemu

.PHONY: update-os-release
update-os-release: ## Update the os-release file versions
  ## NEW_VERSION should be set from a variable passed to the make command
  ## e.g. `make update-os-release NEW_VERSION=0.1.0`
	for elem in VERSION VERSION_ID; do
		sed -i "s/$${elem}=".*"/$${elem}="${NEW_VERSION}"/" hook.yaml
	done
	sed -i 's/PRETTY_NAME="HookOS .*"/PRETTY_NAME="HookOS ${NEW_VERSION}"/' hook.yaml
