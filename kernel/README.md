# Kernels

This kernel folder is used to build a kernel image for tinkie and is based upon the kernel builder from [linuxkit](https://github.com/linuxkit/linuxkit).

## Compile the kernel

The Makefile will build the `5.10.x` kernel based upon the configuration in config_5.10.x_arch.

```
make build_5.10.x
```

**Note** Use `-j <thread count>` with the make command to dramatically speed up build time.

## Modify the kernel

The Makefile can build a docker environment to configure a new kernel.

```
make kconfig
```

We can now run this image:

```
docker run --rm -ti -v $(pwd):/src linuxkit/kconfig
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