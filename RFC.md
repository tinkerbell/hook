### RFC: multi-kernel, cross-compiling, bash based Hook & (default+external) kernels build (incl GHA matrix)

> _very early stage RFC_

This is a rewrite of the build system.
The _produced_ default artifacts (aarch64/x86_64) should be equivalent, save for an updated 5.10.213+ kernel and arm64 fixes.
It's missing, at least, documentation and linters, possibly more, that I removed and intend to rewrite.
But since it's a large-ish change, I'd like to collect some feedback before continuing.

### Main topics

- Makefile build replaced with bash. I'm not too proud of the bash, I will definitely clean it up a lot -- it's the concepts I'd need confirmation on.
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
- Introduced a distributed GitHub Actions build workflow. The bash build system produces JSON objects that drive the matrix stages:
    - One matrix is per-arch, and builds all the containers whose source is hosted in this repo (bootkit, docker, mdev)
    - Second matrix is per-flavor(/kernel), and builds the kernel
    - Third matrix, depending on the other two, is per-flavor(/kernel), and builds Hook itself (via LinuxKit) and prepares a .tar.gz into GH artifacts
- Auto-updating of the kernel via kernel.org's JSON endpoint (ofc only works for LTS or recent-enough stable kernels). Could opt-out/use a fixed version.
- Auto updating of Armbian kernels via OCI tag listing via `skopeo`. Can opt-out/use a fixed version.
- DTB-producing Kernel builds (aarch64) produce a `dtbs.tar.gz` artifact together with the initrd and vmlinuz.

#### Flavors (/kernels)

##### Hook's own kernels

| ID                   | Current version | Description               |
|----------------------|-----------------|---------------------------|
| `hook-default-arm64` | 5.10.213        | Hook's own aarch64 kernel |
| `hook-default-amd64` | 5.10.213        | Hook's own x86_64 kernel  |

##### Armbian kernels

- External kernels, taken from Armbian's OCI repos. Those are "exotic" kernels for certain SoC's.
    - `edge`: release candidates or stable but rarely LTS, more aggressive patching
    - `current`: LTS kernels, stable-ish patching

| ID                        | Current version | Description                                                                                                                               |
|---------------------------|-----------------|-------------------------------------------------------------------------------------------------------------------------------------------|
| `armbian-bcm2711-current` | 6.6.22          | bcm2711 (Broadcom) current, from RaspberryPi Foundation with many Armbian fixes for CNCF-landscape projects; for the RaspberryPi 3b+/4b/5 |
| `armbian-meson64-edge`    | 6.7.10          | meson64 (Amlogic) edge Khadas VIM3/3L, Radxa Zero/2, LibreComputer Potatos, and many more                                                 |
| `armbian-rockchip64-edge` | 6.7.10          | rockchip64 (Rockchip) edge, for many rk356x/3399 SoCs. Not for rk3588!                                                                    |
| `armbian-uefi-arm64-edge` | 6.8.1           | Armbian generic edge UEFI kernel                                                                                                          |
| `armbian-uefi-x86-edge`   | 6.8.1           | Armbian generic edge UEFI kernel                                                                                                          |

#### Proof of working-ness?

In my fork:

- https://github.com/rpardini/tinkerbell-hook/actions/runs/8396946361 A full build workflow, with all misses:
    - Default kernels build (in GHA default runners) in 15-21 minutes each
    - Armbian kernels are done in less than 2 minutes each
    - LK containers in 1 minute for x86_64, 4 minutes for arm64 (done under qemu)
    - Most Hook builds in around 1 minute
    - Full build done in <24m.
- https://github.com/rpardini/tinkerbell-hook/actions/runs/8396643610/job/22998447592 A full build run with all cache hits
    - Everything done in <4 minutes
- https://github.com/rpardini/tinkerbell-hook/releases/tag/20240322-2128 artifacts for testing (initramfs+vmlinuz+dtbs artifact for each flavor)
- https://github.com/rpardini?tab=packages&repo_name=tinkerbell-hook OCI packages in ghcr.io ([quay.io had a meltdown today](https://status.redhat.com/incidents/qh68rjfg6xs6))

#### Future possibilities:

- it would be fairly simple to add Debian/Ubuntu kernels as well as Armbian firmware.
- Many, many more Armbian kernels could be added, but save for Allwinner and the Rockchip `-rkr` vendor kernel, I think they might be too niche.
  Users should have an easy time adding it themselves if they need, though.

- Better support for u-boot's "pxelinux" booting requires changes outside of Hook (namely in Smee/ipxedust) which I'll PR eventually.
- Certain arm64 SoCs require changes in iPXE (nap.h) -- same, I'll PR those to ipxedust repo.
- All these Hook flavors are used in a "showcase" Helm chart based on stack that I will also PR to the charts repo.

#### TO-DO

- Find a better name for "flavor". Naming things is hard. Hats? Swords?
- Update README.md and CONTRIBUTING.md; For now all I have is really
    - `bash build.sh config-kernel <flavor>` & follow instructions to configure kernel; only works for default flavors
    - `bash build.sh build-kernel <flavor>` builds the kernel
    - `bash build.sh build <flavor>` builds Hook with that kernel
- Restore golang & shellcheck linting
- Update to Linuxkit 1.2.0 and new linuxkit pkgs. I tried, but there's some incompatible changes that we need to figure out.
- Consider using `actuated` for native arm64 building? -- https://actuated.dev/blog/arm-ci-cncf-ampere

---

Thanks for reading this far. I'm looking forward to your feedback!