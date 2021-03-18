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

The Makefile can build a docker environment to configure a new kernel, it can generate a docker image and push it to the tinkerbell repository or build a local image.

**NOTE** This builder makes use of the docker `buildx` functionality that can be enabled with `docker buildx create --use`

Making a **multi-arch** image and pushing to the quay.io repository:

```
make kconfig
```

Making a **local** image (multi-arch isn't supported locally, so generate the kernel config for your local architecture [amd64/arm64])

```
make kconfig_amd64
```

We can now run this image:

```
docker run --rm -ti -v $(pwd):/src:z quay.io/tinkerbell/kconfig
```

If modifying the config for a different architecture, it is best to specify the platform to
avoid any surprises when attempting to build the kernel later.

```
docker run --rm -ti -v $(pwd):/src:z --platform=linux/arm64 quay.io/tinkerbell/kconfig
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
