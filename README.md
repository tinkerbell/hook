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
