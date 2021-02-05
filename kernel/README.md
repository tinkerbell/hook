# Kernels

This kernel folder is used to build a kernel image for hook and is based upon the kernel builder from [linuxkit](https://github.com/linuxkit/linuxkit).

## Compile the kernel

The Makefile will build the multiarchitecture `5.10.x` kernel images based upon the configurations in config_5.10.x_arch.

```
make build_5.10.x
```

**Note** Use `-j <thread count>` with the make command to dramatically speed up build time.

To build a kernel for local testing for just a single architecture, usue the devbuild targets:

```
make devbuild_5.10.x
```

## Modify the kernel

The Makefile can build a docker environment to configure a new kernel.

```
make kconfig
```

We can now run this image:

```
docker run --rm -ti -v $(pwd):/src:z tinkerbell/kconfig
```

If modifying the config for a different architecture, it is best to specify the platform to
avoid any surprises when attempting to build the kernel later.

```
docker run --rm -ti -v $(pwd):/src:z --platform=linux/arm64 tinkerbell/kconfig
```

We can now navigate to the source code and run the UI for configuring the kernel:

```
cd linux-5-10
make menuconfig
```

Copy the new configuration:

```
cp .config /src/config-5.10.x-x86_64
```

We can now build our new kernel !
