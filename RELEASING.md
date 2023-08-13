# Releasing

For version v0.x.y:

## Prerequisites

1. Update the `VERSION`, `VERSION_ID`, and `PRETTY_NAME` values in the `hook.yaml` file under `files -> "- path: etc/os-release"` to use `0.x.y`

   ```bash
   make update-os-release NEW_VERSION=0.x.y
   ```

1. Commit, push, PR, and merge the version changes

   ```bash
   git commit -sm "Update version to v0.x.y" hook.yaml
   ```

## Release Process

1. Create the annotated tag

   > NOTE: To use your GPG signature when pushing the tag, use `SIGN_TAG=1 ./contrib/tag-release.sh v0.x.y` instead

   ```bash
   ./contrib/tag-release.sh v0.x.y
   ```

1. Push the tag to the GitHub repository. This will automatically trigger a [Github Action](https://github.com/tinkerbell/hook/actions) to create a release.

   > NOTE: `origin` should be the name of the remote pointing to `github.com/tinkerbell/boots`

   ```bash
   git push origin v0.x.y
   ```

1. Review the release on GitHub.

### Permissions

Releasing requires a particular set of permissions.

- Tag push access to the GitHub repository
