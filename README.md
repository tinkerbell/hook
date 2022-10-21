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

## How to use hook with Sandbox

[sandbox] is a project that helps you to create and run the Tinkerbell stack.
You can use it to run the stack locally with Vagrant, on Equinix Metal with Terraform or just plain docker-compose.
It acts as a guide to deploying Tinkerbell wherever you like.
Hook has become the default OSIE in sandbox, thus no extra action is needed to use hook.

## How to build and use hook with Sandbox

### Using a published build

### Using a local/unpublished build

When you start sandbox in vagrant, for example as part of the provisioning step for the provisioner machine the `setup.sh` script gets executed.
The script does a bunch of things the one we care about here is the `setup_osie` function.
In practice it creates the folder: `sandbox/deploy/state/webroot/misc/osie/current`.
If you ran sandbox you already have that directory.
`current` is the location that serves the operating system installation environment that runs inside a worker machine.
You can even move or delete that directory because we have to replace it with the release package containing the new operating system.
After you have removed the directory, it is time to re-create it:

```ShellSession
# check out this repo
$ git clone https://github.com/tinkerbell/hook.git

# build it - this produces a hook-<commit SHA>.tar.gz
$ make dist

# copy the output to current (the filename will be different)
$ tar -xf hook-bc3e58a-dirty.tar.gz -C ../sandbox/deploy/state/webroot/misc/osie/current/
```

Now you are ready to boot the worker, it will pick up the new operating system installation environment.

### The automation way

Sandbox has a file called [current_versions.sh].
If you change `OSIE_DOWNLOAD_LINK` with the hook link the setup.sh script will download the OS again and it will uncompress it in the right location (only if ./deploy/state/webroot/misc/osie/current does not exist)

## Package a release

```ShellSession
$ make dist
```

The `dist` make target will do a couple of things:

1. Build the required docker images using `docker buildx`.
2. It will use `linuxkit build` to prepare the init ramdisk and the kernel.
3. It will create a `tar.gz` archive containing all the files in the proper format, ready to be served via boots.

## Build for local testing (only the local architecture)

```ShellSession
$ make dev
```

## Troubleshooting

It is possible to build a debug version of hook, that will have an `sshd` server running with any public keys you have.
This is achieved through the command `make debug`

## Nix for CI/CD

This project uses Nix for a couple of reasons.
We want to use it more intensively to see if it can help us quickly iterate over CI/CD.
If you are not into Nix and don't like it, here are a few tips.

Don't want to install?
Just use Docker:

```ShellSession
$ docker run -it -v "$PWD:$PWD" -w "$PWD" -v /var/run/docker.sock:/var/run/docker.sock nixos/nix bash

# now you are inside the container and you can use nix-shell to reproduce the environment
$ nix-shell
$ make dev

# or you can use make to build LinuxKit image
$ make images
```

This will take a moment or so to download and build packages.
You can pay this price only once by building a "dev" image.

```ShellSession
$ docker buildx build --load -t hook-nix-dev -f hack/Dockerfile .

# just use the built image/tag instead of nixos/nix in the previous snipped
$ docker run -it -v "$PWD:$PWD" -w "$PWD" -v /var/run/docker.sock:/var/run/docker.sock hook-nix-dev bash
```

Alternatively, don't use nix at all.
We use nix-shell just for binaries/$PATH management, so if you have the binaries available you don't need nix at all.
Of course be prepared for CI to complain about formatting/linting due to possible version differences.

[current_versions.sh]: https://github.com/tinkerbell/sandbox/blob/main/current_versions.sh
[formats]: https://github.com/linuxkit/linuxkit/blob/master/README.md#booting-and-testing
[linuxkit]: https://github.com/linuxkit/linuxkit
[osie]: https://github.com/tinkebell/osie
[sandbox]: https://github.com/tinkerbell/sandbox
[specification]: https://github.com/linuxkit/linuxkit/blob/master/docs/yaml.md
[tinkerbell]: https://tinkerbell.org
