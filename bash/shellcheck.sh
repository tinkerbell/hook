#!/usr/bin/env bash

function download_prepare_shellcheck_bin() {
	declare SHELLCHECK_VERSION=${SHELLCHECK_VERSION:-0.10.0} # https://github.com/koalaman/shellcheck/releases
	log info "Downloading and preparing shellcheck binary for version v${SHELLCHECK_VERSION}..."

	declare bash_machine="${BASH_VERSINFO[5]}"
	declare shellcheck_os="" shellcheck_arch=""
	case "$bash_machine" in
		*darwin*) shellcheck_os="darwin" ;;
		*linux*) shellcheck_os="linux" ;;
		*)
			log error "unknown os: $bash_machine"
			exit 3
			;;
	esac

	case "$bash_machine" in
		*aarch64*) shellcheck_arch="aarch64" ;;
		*x86_64*) shellcheck_arch="x86_64" ;;
		*)
			log error "unknown arch: $bash_machine"
			exit 2
			;;
	esac

	declare shellcheck_fn="shellcheck-v${SHELLCHECK_VERSION}.${shellcheck_os}.${shellcheck_arch}"
	declare shellcheck_fn_tarxz="${shellcheck_fn}.tar.xz"
	declare DOWN_URL="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/${shellcheck_fn_tarxz}"
	declare -g -r SHELLCHECK_BIN="${CACHE_DIR}/${shellcheck_fn}"

	if [[ ! -f "${SHELLCHECK_BIN}" ]]; then
		log info "Cache miss for shellcheck binary, downloading..."
		log debug "bash_machine: ${bash_machine}"
		log debug "Down URL: ${DOWN_URL}"
		log debug "SHELLCHECK_BIN: ${SHELLCHECK_BIN}"
		curl -sL "${DOWN_URL}" -o "${SHELLCHECK_BIN}.tar.xz"
		tar -xf "${SHELLCHECK_BIN}.tar.xz" -C "${CACHE_DIR}" "shellcheck-v${SHELLCHECK_VERSION}/shellcheck"
		mv "${CACHE_DIR}/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "${SHELLCHECK_BIN}"
		rm -rf "${CACHE_DIR}/shellcheck-v${SHELLCHECK_VERSION}" "${SHELLCHECK_BIN}.tar.xz"
		chmod +x "${SHELLCHECK_BIN}"
	fi

	declare -g SHELLCHECK_ACTUAL_VERSION="unknown"
	SHELLCHECK_ACTUAL_VERSION="$("${SHELLCHECK_BIN}" --version | grep "^version")"
	declare -g -r SHELLCHECK_ACTUAL_VERSION="${SHELLCHECK_ACTUAL_VERSION}"
	log debug "SHELLCHECK_ACTUAL_VERSION: ${SHELLCHECK_ACTUAL_VERSION}"

	return 0
}

function run_shellcheck() {
	declare -a params=() excludes=()

	excludes+=(
		#"SC2034" # "appears unused" -- bad, but no-one will die of this
	)

	params+=(--check-sourced --color=always --external-sources --format=tty --shell=bash)

	# --severity=SEVERITY        Minimum severity of errors to consider (error, warning, info, style)
	params+=("--severity=style") # warning is the default

	for exclude in "${excludes[@]}"; do
		params+=(--exclude="${exclude}")
	done

	log info "Running shellcheck ${SHELLCHECK_ACTUAL_VERSION} against 'build.sh', please wait..."
	log debug "All shellcheck params: " "${params[@]}"

	if "${SHELLCHECK_BIN}" "${params[@]}" build.sh; then
		log info "Shellcheck detected no problems in bash code."
	else
		log error "Shellcheck detected problems in bash code; check output above."
		exit 1
	fi
}
