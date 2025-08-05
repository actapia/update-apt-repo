# package_version

This is a small utility that might be useful when making Debian packages. It
reads the `.changes` file for a specific version of a built Debian package and
places all the files needed by `update-apt-repo` in a tarball for upload to the
server hosting the APT repository.

## Installation

You can install `package_version` to `~/.local/bin` with the `install.sh`
script.

```bash
bash install.sh
```

If you want to install to a different directory, set the `DESTDIR` environment
variable to the `bin` directory where you want the scripts installed.

The script will ask if you want to add lines to your `.bashrc` file to enable
tab completions. If you decline, you can run the `install.sh` script again to
enable them.

## Usage

`package_version.sh` should be run from the directory containing the files to
`tar`&mdash;the parent of the source package root directory&mdash;and accepts
one or two arguments. If you run `package_version.sh` with two arguments, the
command looks like this:

```bash
package_version.sh PACKAGE VERSION
```

Here, `PACKAGE` must be replaced with the name of the package, and `VERSION`
must be replaced with the version of the package to tar. If only one argument is
provided, then `package_version.sh` assumes that the name of the current
directory (`$PWD`) is the name of the package, and the command looks like this:

```bash
package_version.sh VERSION
```

In either case, the output of `package_version.sh` is a tar file,
`PACKAGE.tar.xz`, where `PACKAGE` is replaced with the package name. This `tar`
file contains all the files that need to be placed in the incoming directory to
be read by `update-apt-repo`/`debarchiver`.

## Tab completion

The `install.sh` script offers to add lines to `source` the tab completions in
your `.bashrc` file. If you would rather source the completions manually, you
can run

```bash
source package_version_completions.sh
```

`package_version.sh` allows tab completing the version of the package. It will
not currently tab complete the name of the package.
