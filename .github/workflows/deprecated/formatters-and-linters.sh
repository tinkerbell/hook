#!/usr/bin/env bash
#
# This script is meant to check against formatters and linters and thus is sensitive to the versions of each tool used.
# CI invokes this script via nix-shell so that we can use the versions pinned there.
# Using direnv with nix-shell will be the easiest route for a developer, other options are docker or just not caring and fixing up after CI complains ;).

set -eux

failed=0

if ! git ls-files '*.md' '*.yaml' '*.yml' | xargs prettier --list-different --write; then
	failed=1
fi

if ! shfmt -f . | xargs shfmt -d -l -s; then
	failed=1
fi

if ! make lint; then
	failed=1
fi

if ! nixfmt shell.nix; then
	failed=1
fi

if ! git diff | (! grep .); then
	failed=1
fi

exit "$failed"
