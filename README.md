# Tinkie

Tinkie is the Tinkerbell Installation Environment for bare-metal. It runs in-memory, installs operating systems and handles deprovisioning.

## Movivation

<!-- TODO: Move this to the documentation repository once this is part of the Tinkerbell organisation. -->

One of the [Tinkerbell](https://tinkerbell.org) component is the operating
system installation environment. Currently Tinkerbell uses
[OSIE](https:github.com/tinkebell/osie). That implementation is open sourced by
Equinix Metal and it is serving the purpose of provisioning and de-provisioning
hardware at huge scale. But why we started this project?

* Because we like to Hack the Kernel!
* Tinkerbell architecture leaves an open door in terms of the operating system
  installation environment you can use, it serves one for simplicity but users
  can write their own one, this is an attempt to validate that the model works
  (it does!! this is why we are here)
* Looking at the CI/CD build time for OSIE is ~1h on average
* The building process is not standardised and this is critical for an open
  source project because it cause friction for contributors. This project as
  highlighted later in this page uses
  [LinuxKit](https://github.com/linuxkit/linuxkit) a tool provided by Docker now
  part of the Linux Computing Foundation. It gives us:
    * Documentation about how the building phase works
    * A clear and defined CLI and [specification mechanism](https://github.com/linuxkit/linuxkit/blob/master/docs/yaml.md) (YAML)
    * A community that is built and supportive
    * LinuxKit  cross-compiles in many architectures
    * [Different output format](https://github.com/linuxkit/linuxkit/blob/master/README.md#booting-and-testing): ISO, init ramkdisk, aws, docker, rpi3...
* It is not easy to explain to the Tinkerbell community how OSIE works and the components it is made for, a lot of them are coming from specific Equinix Metal operational experience and they are not strictly needed in Tinkerbell. There is ongoing voice from the contributors about a replacement or a complete refactoring for OSIE.

## Architecture

The tinkie project aims to provide a "in-place" swappable set of files (`kernel`/`initramfs`) that can be used to replace the [OSIE](https://github.com/tinkerbell/osie) environment that comes from Equinix Metal. The key aims of this new project:

- Immutable output
- Batteries included (but swappable if needed)
- Ease of build (Subsequent builds of tinkie are ~47 seconds)
- Lean / simple design
- Clean base to build upon

The tinkie project predominantly makes use of [linuxkit](github.com/linuxkit/linuxkit) as the toolkit that will produce repeatable and simple build of the entire in-memory operating system. The linuxkit project combines a Linux kernel with a number of additional container images to produce a Linux Operating System with just the right amount of functionality (no less / no more). We have built upon the minimal set of components:

- containerd (the engine to start/stop all other components in a LinuxKit OS)
- dhcp (for network access)
- ntp (network time)
- rngd (random number gen for entropy) 

To this minimal build we've added our own set of containers that will provide the functionality needed for a `tink-worker` to run succesfully:

### tink-docker

The `tink-docker` container builds upon the upstream `dind` (docker-in-docker) container and adds the additional functionality to retrieve the certificates needed for the docker engine to communicate with the tinkerbell repository **before** it starts the docker engine. The docker engine will be exposed through the `/var/run/docker.sock` that will use a bind mount so that the container `bootkit` can access it.

### bootkit

The `bootkit` container will parse the `/proc/cmdline` and the metadata service in order to retrieve the specific configuration for tink-worker to be started for the current/correct machine. It will then speak with the `tink-docker` engine API through the shared `/var/run/docker.sock`, where it will ask the engine to run the `tink-worker:latest` container, which in turn will begin to execute the workflow/actions associated with that machine. 

## How to use tinkie with Sandbox

[sandbox](https://github.com/tinkerbell/sandbox) is a project that helps you to
create and run the Tinkerbell stack locally with Vagrant, on Equinix Metal with
Terraform and it acts as a guide to deploy Tinkerbell wherever you like. I will
tell you how you can change the default operating system installer environment
called [OSIE](https://github.com/tinkerbell/osie) with this project.

There are essentially two methods a manual one and a more automatic one. Have a
look at the manual one even if you intent to use the automatic one just to learn
what what the automation does for you.

### The manual way

When you start sandbox in vagrant for example as part of the provisioning step
for the provisioner machine the `setup.sh` script gets executed. The script does
a bunch of things the one we care here is the `setup_osie` function. In practice
it creates the folder: `sandbox/deploy/state/webroot/misc/osie/current`. If you
ran sandbox you already have that directory. `current` is the location that
serves the operating system installation environment that runs inside a worker
machine. You can even move or delete that directory because we have to replace
it with the release package containing the new operating system. After you have
removed the directory it is time to re-create it:

```
mkdir current
```

Download the new tar.gz

```
wget http://s.gianarb.it/tinkie/tinkie-master.tar.gz
```

Uncompress it

```
tar xzcv -O ./current tinkie-master.tar.gz
```

Now you are ready to boot the worker, it will pick up the new operating system
installation environment.


### The automation way

Sandbox has a file called
[current_versions.sh](https://github.com/tinkerbell/sandbox/blob/master/current_versions.sh).
If you change `OSIE_DOWNLOAD_LINK` with the tinkie link the setup.sh script will
download the OS again and it will uncompress it in the right location
(only if ./deploy/state/webroot/misc/osie/current does not exist)

## Package a release

```
make dist
```
The `dist` make target will do a couple of things:

1. Build the required docker images using `docker
buildx`.
2. It will use `linuxkit build` to prepare the init ramdisk and the
kernel.
3. It will convert the init ramkdisk in the right format that iPXE can boot
4. It will create a `tar.gz` archive in the root of the project containing all
   the files in the right format, ready to be served via Tinkerbell.


## Next steps

- Test passing pid:host to tink-docker, this should allow gracefull reboots
- Re-write a bunch of actions that are un-managable shell scripts (disk management being the first)

## Troubleshooting

Due to a very unexplainable issue, on rare occasions the `initramfs` generated may not work if that is the case then the `make convert` command we re-build the `initramfs` in a different format. (sometimes this has occured with changed one letter of a string inside some source code and rebuilding... not sure why yet)
