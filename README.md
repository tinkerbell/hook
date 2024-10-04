# Hook

Hook is the Tinkerbell Installation Environment for bare-metal.
It runs in-memory, installs operating system, and handles deprovisioning.

## Motivation

One of the [Tinkerbell] components is the Operating System Installation Environment (OSIE).
The Tinkerbell project originally used [OSIE] as its default OSIE.
That implementation was open-sourced by Equinix Metal as is and was difficult to modify/extend.
(Not to mention confusing, [OSIE] is our OSIE, hook is a new OSIE and you can have your very own OSIE too)
We started this project for the following reasons:

- Because we like to hack on the Kernel!
- Tinkerbell architecture leaves an open door in terms of the OSIE you can use, one is provided by default for simplicity, but users can write their own.
  This is an implementation to validate that the model works (it does!! this is why we are here)
- Looking at the CI/CD build time for [OSIE] was ~1h on average
- The [OSIE] build process was not standardised, which is critical for an open-source project because it causes friction for contributors.
  This project, as highlighted later in this page, uses [LinuxKit].
  It gives us:
  - Documentation about how the building phase works
  - A clear and defined CLI and [specification] (YAML)
  - A shared community that is supportive
  - LinuxKit cross-compiles in many architectures
  - Different output formats: ISO, init ramdisk, aws, docker, rpi3... see [formats].
- It was not easy to explain to the Tinkerbell community how [OSIE] works and the components it is made for.
  A lot of the components were Equinix Metal specific and are not strictly needed in Tinkerbell.

## Architecture

The hook project aims to provide an "in-place" swappable set of files (`kernel`/`initramfs`) that can be used to function as the Tinkerbell OSIE.
The key aims of this new project:

- Immutable output
- Batteries included (but swappable if needed)
- Ease of build (subsequent builds of hook are ~47 seconds)
- Lean / simple design
- Clean base to build upon

The hook project predominantly uses [linuxkit] as the toolkit that will produce repeatable and straightforward build of the entire in-memory operating system.
The linuxkit project combines a Linux kernel with a number of additional container images to produce a Linux Operating System with just the right amount of functionality (no less / no more).
We have built upon the minimal set of components:

- containerd (the engine to start/stop all other components in a LinuxKit OS)
- dhcpd (for network access)
- ntpd (network time)
- rngd (random number gen for entropy)

To this minimal build, we've added our own set of containers that will provide the functionality needed for a `tink-worker` to run successfully:

### hook-docker

The `hook-docker` container builds upon the upstream `dind` (docker-in-docker) container.
It adds the additional functionality to retrieve the certificates needed for the docker engine to communicate with the Tinkerbell repository **before** it starts the docker engine.
The docker engine will be exposed through the `/var/run/docker.sock` that will use a bind mount so that the container `bootkit` can access it.

### hook-bootkit

The `hook-bootkit` container will parse the `/proc/cmdline` and the metadata service in order to retrieve the specific configuration for tink-worker to be started for the current/correct machine.
It will then speak with the `hook-docker` engine API through the shared `/var/run/docker.sock`, where it will ask the engine to run the `tink-worker:latest` container.
`tink-worker:latest` will in turn begin to execute the workflow/actions associated with that machine.

## Developer/builder guide

### Introduction / recently changed

> This refers to the 0.9.0 version, compared to 0.8.1.

- Replaces the emulated Alpine kernel build with a Debian based cross-compiling build
  - Much faster building. Emulating x86_64 on arm64 is very slow and vice-versa.
- Replaces kernel .config's with the `defconfig` versions, via Kbuild's `make savedefconfig`
- Replaces Git-SHA1-based image versioning ("current revision") with content-based hashing.
  - This way, there's much higher cache reuse, and new versions are pushed only when components actually changed (caveat emptor)
    - Should allow people to develop Hook without having to build a kernel, depending on CI frequency and luck.
- Introduces multiple "flavors" of hook. Instead of restricted to 2 hardcoded flavors (x86_64 and aarch64, built from source), we can now define multiple flavors, each with an ID and version/configure/build methods.
  - the `hook-default-amd64` and `hook-default-arm64` kernels are equivalent to the two original.
  - the `armbian-` prefixed kernels are actually Armbian kernels for more exotic arm64 SBCs, or Armbian's generic UEFI kernels for both arches. Those are very fast to "build" since Armbian publishes their .deb packages in OCI images, and here we
      just download and massage them into the format required by Linuxkit.
- `hook.yaml` is replaced with `hook.template.yaml` which is templated via a limited-var invocation of `envsubst`; only the kernel image and the arch is actually different per-flavor.
- Auto-updating of the kernel via kernel.org's JSON endpoint (ofc only works for LTS or recent-enough stable kernels). Could opt-out/use a fixed version.
- Auto updating of Armbian kernels via OCI tag listing via `skopeo`. Can opt-out/use a fixed version.
- DTB-producing Kernel builds (aarch64) produce a `dtbs.tar.gz` artifact together with the initrd and vmlinuz. DTBs are not used by Hook or Tinkerbell right now, but will be necessary for some SBCs.

### Flavor / `id`

The Hook build system is designed to handle multiple flavors.
A flavor mostly equates with a specific Linux Kernel, a LinuxKit version, and a LinuxKit YAML configuration template.
The "default" flavor ids are `hook-default-amd64` and `hook-default-arm64`, which use a kernel that is built and configured from source by the Hook build system.
Other flavors use Foreign kernels from other distributions to cater for special needs.

There is an inventory of all available flavors in the [bash/inventory.sh](bash/inventory.sh) file.

### Command line interface (`build.sh`)

The `build.sh` script is the main entry point for building a Hook flavor.
The general syntax of the cli is:

`./build.sh <command> [<id>] [<key1>=<value1>] [<key2>=<value2>...]`

Where:

- `<command>`, if not specified, defaults to `build`
- `<id>`, if not specified, defaults to `hook-default-amd64` (or the arm64 variant, if running on an arm64 host); the full list is defined in the [bash/inventory.sh](bash/inventory.sh)
- `[<key>=<value>]` is useful to set environment variables (similar to `make`) and can come in any position in the command line.

So, just running `./build.sh` will build the default flavor for the host architecture.

Other commands are:

- `kernel <id>`: builds the kernel for the specified flavor
  - for `default` ids, this will build the kernel from source
  - for other methods, usually this will download & massage the kernels from a distro's packages
- `config <id>`: runs kernel configuration for the specified flavor.
  - this only works for the default flavors; Foreign kernels are configured elsewhere;
  - it will open an interactive menuconfig session where you can change kernel config options; after exiting, `savedefconfig` will be run and the resulting file copied back to the host, ready for commit.
- `build <id>`: builds the Hook flavor. The kernel must be either available for pulling, or have been built locally beforehand.
- `qemu <id>`: builds the Hook flavor and runs it in QEMU.
  - this accepts `MAC=<mac>` and `TINK_SERVER=<ip>` env vars, see below

Other, less common commands are:

- `kernel-config-shell <id>`: prepares an interactive Docker shell for advanced kernel .config operations.
- `shellcheck`: runs shellcheck on all bash scripts in the project and exits with an error if any issues are found.
- `linuxkit-containers`: builds the LinuxKit containers for the specified architecture.

#### Environment variables for building/testing

Using the `<key>=<value>` syntax, you can set environment variables that will be used by the build system.
Of course, you may also set them in the environment before running the script (that is heavily used by the GitHub Actions build workflow).

The most important environment variables are:

- general, applies to most commands:
  - `DEBUG=yes`: set this to get lots of debugging messages which can make understanding the build and finding problems easier.
  - `HOOK_VERSION`: The Hook version, ends up in `/etc/os-release` and on the screen at boot.
  - `HOOK_KERNEL_OCI_BASE`: OCI base coordinates for the kernel images.
  - `HOOK_LK_CONTAINERS_OCI_BASE`: OCI base coordinates for the LinuxKit containers.
  - `CACHE_DIR`: directory where the build system will cache downloaded files. Relative to the project root.
  - `USE_LATEST_BUILT_KERNEL`: set this to `yes` to use the latest built kernel from `quay.io/tinkerbell/hook-kernel`.
  - `LINUXKIT_ISO`: set this to `yes` to build an ISO image instead of a kernel and initrd.
- exclusively for the `qemu` command:
  - `TINK_SERVER=<ip>`: the IP address of the Tinkerbell GRPC server. No default.
  - `MAC=<mac>`: the MAC address of the machine that will be provisioned. No default.
  - and also
    - `TINK_WORKER_IMAGE`, defaults to `"quay.io/tinkerbell/tink-worker:latest"`
    - `TINK_TLS` defaults to `false`
    - `TINK_GRPC_PORT` defaults to `42113`

### CI (GitHub Actions)

- There's a distributed GitHub Actions build workflow `"matrix"`.
  - The bash build system produces JSON objects that drive the matrix stages:
    - One matrix is per-arch, and builds all the containers whose source is hosted in this repo (bootkit, docker, mdev)
    - Second matrix is per-flavor(/kernel), and builds the kernel
    - Third matrix, depending on the other two, is per-flavor(/kernel), and builds Hook itself (via LinuxKit) and prepares a .tar.gz into GH artifacts

The `gha-matrix` CLI command prepares a set of JSON outputs for GitHub Actions matrix workflow, based on the inventory and certain environment variables:

- `CI_RUNNER_<criteria>` are used to determine the GH Action runners (self-hosted or GH-hosted) that are used for each step. See [bash/json-matrix.sh](bash/json-matrix.sh) for details.
- `CI_TAGS`, a space separated list of tags that will be used to filter the inventory.
- `DOCKER_ARCH` is used by the `linuxkit-containers` command to build the containers for the specified architecture.
- `DO_PUSH`: `yes` or `no`, will push the built containers to the OCI registry; defaults to `no`.

### Embedding container images into the DinD (docker-in-docker), also known as [hook-docker](images/hook-docker/), container

For use cases where having container images already available in Docker is needed, the following steps can be taken to embed container images into hook-docker (DinD):

> Note: This is optional and no container images will be embedded by default.

> Note: This will increase the overall size of HookOS. As HookOS is an in memory OS, make sure that the size increase works for the machines you are provisioning.

1. Create a file named `images.txt` in the [images/hook-embedded/](images/hook-embedded/) directory.
1. Populate this `images.txt` file with the list of images to be embedded. See [images/hook-embedded/images.txt.example](images/hook-embedded/images.txt.example) for details on the required file format.
1. Change directories to [images/hook-embedded/](images/hook-embedded/) and run [`pull-images.sh`](images/hook-embedded/pull-images.sh) script when building amd64 images and run [`pull-images.sh arm64`](images/hook-embedded/pull-images.sh) when building arm64 images. Read the comments at the top of the script for more details.
1. Change directories to the root of the HookOS repository and run `sudo ./build.sh build ...` to build the HookOS kernel and ramdisk. FYI, `sudo` is needed as DIND changes file ownerships to root.

### Build system TO-DO list

- [ ] `make debug` functionality (sshd enabled) was lost in the Makefile -> bash transition;

[formats]: https://github.com/linuxkit/linuxkit/blob/master/README.md#booting-and-testing
[linuxkit]: https://github.com/linuxkit/linuxkit
[osie]: https://github.com/tinkerbell/osie
[specification]: https://github.com/linuxkit/linuxkit/blob/master/docs/yaml.md
[tinkerbell]: https://tinkerbell.org
