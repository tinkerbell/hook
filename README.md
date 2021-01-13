## How to use noname with Sandbox

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
wget http://s.gianarb.it/noname/noname-master.tar.gz
```

Uncompress it

```
tar xzcv -O ./current noname-master.tar.gz
```

Now you are ready to boot the worker, it will pick up the new operating system
installation environment.


### The automation way

Sandbox has a file called
[current_versions.sh](https://github.com/tinkerbell/sandbox/blob/master/current_versions.sh).
If you change `OSIE_DOWNLOAD_LINK` with the noname link the setup.sh script will
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

## Architecture

The noname project aims to provide a "in-place" swappable set of files (`kernel`/`initramfs`) that can be used to replace the [OSIE](https://github.com/tinkerbell/osie) environment that comes from Equinix Metal. The key aims of this new project:

- Immutable output
- Batteries included (but swappable if needed)
- Ease of build (Subsequent builds of noname are ~47 seconds)
- Lean / simple design
- Clean base to build upon

The noname project predominantly makes use of [linuxkit](github.com/linuxkit/linuxkit) as the toolkit that will produce repeatable and simple build of the entire in-memory operating system. The linuxkit project combines a Linux kernel with a number of additional container images to produce a Linux Operating System with just the right amount of functionality (no less / no more). We have built upon the minimal set of components:

- containerd (the engine to start/stop all other components in a LinuxKit OS)
- dhcp (for network access)
- ntp (network time)
- rngd (random number gen for entropy) 

To this minimal build we've added our own set of containers that will provide the functionality needed for a `tink-worker` to run succesfully:

### tink-docker

The `tink-docker` container builds upon the upstream `dind` (docker-in-docker) container and adds the additional functionality to retrieve the certificates needed for the docker engine to communicate with the tinkerbell repository **before** it starts the docker engine. The docker engine will be exposed through the `/var/run/docker.sock` that will use a bind mount so that the container `bootkit` can access it.

### bootkit

The `bootkit` container will parse the `/proc/cmdline` and the metadata service in order to retrieve the specific configuration for tink-worker to be started for the current/correct machine. It will then speak with the `tink-docker` engine API through the shared `/var/run/docker.sock`, where it will ask the engine to run the `tink-worker:latest` container, which in turn will begin to execute the workflow/actions associated with that machine. 

## Next steps

- Test passing pid:host to tink-docker, this should allow gracefull reboots
- Re-write a bunch of actions that are un-managable shell scripts (disk management being the first)

## Troubleshooting

Due to a very unexplainable issue, on rare occasions the `initramfs` generated may not work if that is the case then the `make convert` command we re-build the `initramfs` in a different format. (sometimes this has occured with changed one letter of a string inside some source code and rebuilding... not sure why yet)
