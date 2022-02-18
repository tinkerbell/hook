# BEGIN: lint-install ../hook

GOLINT_VERSION ?= v1.42.0
HADOLINT_VERSION ?= v2.6.1
SHELLCHECK_VERSION ?= v0.7.2
LINT_OS := $(shell uname)
LINT_LOWER_OS  = $(shell echo $OS | tr '[:upper:]' '[:lower:]')
LINT_ARCH := $(shell uname -m)
GOLINT_CONFIG:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))/.golangci.yml

lint: out/linters/shellcheck-$(SHELLCHECK_VERSION)/shellcheck out/linters/hadolint-$(HADOLINT_VERSION) out/linters/golangci-lint-$(GOLINT_VERSION)
	find . -name go.mod | xargs -n1 dirname | xargs -n1 -I{} sh -c "cd {} && golangci-lint run -c $(GOLINT_CONFIG)"
	out/linters/shellcheck-$(SHELLCHECK_VERSION)/shellcheck $(shell find . -name "*.sh")
	out/linters/hadolint-$(HADOLINT_VERSION) $(shell find . -name "*Dockerfile")

out/linters/shellcheck-$(SHELLCHECK_VERSION)/shellcheck:
	mkdir -p out/linters
	curl -sfL https://github.com/koalaman/shellcheck/releases/download/v0.7.2/shellcheck-$(SHELLCHECK_VERSION).$(LINT_OS).$(LINT_ARCH).tar.xz | tar -C out/linters -xJf -

out/linters/hadolint-$(HADOLINT_VERSION):
	mkdir -p out/linters
	curl -sfL https://github.com/hadolint/hadolint/releases/download/v2.6.1/hadolint-$(LINT_OS)-$(LINT_ARCH) > out/linters/hadolint-$(HADOLINT_VERSION)
	chmod u+x out/linters/hadolint-$(HADOLINT_VERSION)

out/linters/golangci-lint-$(GOLINT_VERSION):
	mkdir -p out/linters
	curl -sfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b out/linters $(GOLINT_VERSION)
	mv out/linters/golangci-lint out/linters/golangci-lint-$(GOLINT_VERSION)

# END: lint-install ../hook
