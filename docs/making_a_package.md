# Making a Debian package

This document describes one possible process for making a Debian package. The
document assumes that the reader has some basic familiarity working with
Unix-like systems from the command line. 

I recommend doing these exercises on your own machine&mdash;*not* the Multilab,
since we don't have `sudo` privileges there.

## Dissecting a binary Debian package

It can be instructive to take apart a finished Debian package. As the [main
README](../README.md) explains, a Debian package is just an `ar`
archive. Although `ar` is probably less familiar to most users than the newer
`tar`, `ar` is still currently in use for both Debian archives and for static
`.a` libraries.

I recommend completing this exercise in a new directory because the commands I
provide use globs. 

```bash
mkdir deb_extract
cd deb_extract
```

First, we'll download a `.deb` file. You can do that using `apt` with the
`download` subcommand. We'll download the package for an SFTP client called
[`lftp`](https://lftp.yar.ru/).

```bash
apt download lftp
```

`apt` should download a `.deb` file to your current directory. The file should
match the pattern `lftp*.deb`&mdash;what `*` is depends on your processor
architecture and what version of `lftp` is currently in the repositories you are
using.

We can extract the `.deb` file with `ar`.

```bash
ar x lftp*.deb
```

You should see three new files, `debian-binary` and two `tar` files. One `tar`
file matches `control.tar.*`, and the other matches `data.tar.*`. The specific
method used to compress the `tar` files may differ. For new versions of the
package on new versions of Ubuntu, the `tar` files will most likely be
compressed using `zstd`, but older versions might use `xz`, `bzip2`, or `gzip`.

`debian-binary` simply contains the version of the Debian package standard used
by the package. As of this writing, the most recent version of the `lftp`
package uses version `2.0` on Ubuntu 22.04.

The `data.tar.*` file contains the files to be placed on system when the package
is installed. Let's untar that file.

```bash
tar axvf data.tar.*
```

If you list the contents of the directory now, you should see a `usr` and an
`etc` directory. When the `lftp` package is installed, these would normally be
copied (recursively) over `/usr` and `/etc`. List the contents of `usr/bin`

```bash
ls usr/bin
```

You should see the `lftp` and `lftpget` binaries that would ordinarily be
installed to `/usr/bin`. Now, list the contents of `etc/usr/share/man/man1`.

```bash
ls usr/share/man/man1
```

You should see that the `lftp` package includes manual pages for
`lftp` and `lftpget`&mdash;`lftp.1.gz` and `lftpget.1.gz`, respectively.

The `control.tar.*` file contains package metadata. For some packages, it will
also include scripts to be run on installation, but `lftp` does not have any
such scripts. Let's untar `control.tar.*`.

```bash
tar axvf control.tar.*
```

You should see a few new files. First is `conffiles`. Let's `cat` that file.

```bash
cat conffiles 
```

`cat` should print just a single line, `/etc/lftp.conf`, which is the path to
the `lftp` configuration file. `conffiles` tells `dpkg` which files the package
uses for configuration.

There's also a file called `control`. `cat` `control` as well.

```bash
cat control
```

`cat` will print out the main package metadata in the standard Debian `control`
file format. The fields found in the file are summarized in the table below.

| Field                 | Description                                                                   |
|-----------------------|-------------------------------------------------------------------------------|
| `Package`             | Package name                                                                  |
| `Version`             | Package version                                                               |
| `Architecture`        | Architecture for which the package has been built                             |
| `Maintainer`          | Name and email address of maintainer of the package                           |
| `Installed-Size`      | Total size of files belonging to the package after install                    |
| `Depends`             | Packages that must be installed before this one                               |
| `Recommends`          | Packages that are installed by default alongside this one but aren't required |
| `Section`             | APT section to which the package belongs                                      |
| `Priority`            | Importance of the package                                                     |
| `Homepage`            | Upstream homepage associated with the package                                 |
| `Description`         | Plain English description of the package                                      |
| `Original-Maintainer` | Upstream maintainer (used in Debain derivatives)                               |

Finally, print the `md5sums` file.

```bash
cat md5sums
```

`md5sums` contains MD5 checksums for each of the files in the `data.tar.*`
archive.

## Modifying a Debian binary package directly

If we wanted to make our own modifications to the `lftp` package, we could just
edit the files in the extracted `data.tar.*` or `control.tar.*`, update the
checksums in `md5sums`, re-`tar` the two archives, and re-`ar` the `tar` files
and `debian-binary`. It's worth trying to see how it works.

First, let's change one of the files. For example, we could replace `lftp` with
a "Hello World!" program.

```bash
gcc -o usr/bin/lftp -xc - <<< 'main(){puts("Hello, world!");}'
```

Now, since we changed `usr/bin/lftp`, we need to update the `md5sums`.

```bash
sed -i.bak "s,.*\(  usr/bin/lftp$\),$(md5sum usr/bin/lftp|cut -c-32)\1," md5sums
```

Since we've changed one of the files, we should change the version number in the
`control` file. The [Debian Policy
Manual](https://www.debian.org/doc/debian-policy/ch-controlfields.html#version)
provides general guidance for selecting version numbers. Since we are basing our
modified package on an existing version, we need to make sure that `dpkg`
considers the modified package newer than the original. We can do that by
incrementing the "Debian revision" part of the version number. An example of how
to do that follows.

As of this writing, the newest version of the `lftp` package on Ubuntu 22.04 is
`4.9.2-1build1`. `dpkg` considers the part before the final `-` to be the
"upstream version." In this case, the upstream version is `4.9.2`. Everything
after the final `-` is the Debian revision, so the Debian revision in this
example is `1build1`. In `1build1`, the leading `1` indicates that this is the
first Debian revision of this upstream version of the package. `build1`
indicates that this is the second build made of the package without changing
anything in the package itself. (The first build would have simply been
`4.5.2-1`, and the third build would be `4.5.2-1build2`; see the manual page for
`dch` for more information) The concept of "builds" is more meaningful when
we're dealing with source packages, so we'll ignore it here.

Hence, we could name the new version of our package something like `4.9.2-2` to
ensure it is considered newer than `4.9.2-1build1`. However, our modified
package is derived from another package that is still being maintained, and it's
possible the official maintainers will eventually release their own version
`4.9.2-2` of the package. We might like the maintainers' version to take
precedence. We can ensure that our version is considered older than any official
`4.9.2-2` version by appending a string starting with `~` (tilde) to the end of
the Debian revision number. For example, we could name our package
`4.9.2-2~ngs+1`. The string after `~` can follow our own convention; here, I
intend it to mean "version 1 of the modified package for the NGS workshop."

**Note:** As of this writing, many of the packages in the CS485 repository do
not adhere to the usual conventions for naming package versions. Specifically,
many packages erroneously add to the upstream version the suffix `+ds` or
`+dfsg`, followed by a number, any time there are patches that have been applied
to the software. `+ds` and `+dfsg` should actually be reserved for cases where
the source package is distributed with a modified version of the upstream
`.orig.tar` tarball&mdash; if all modifications are made via patches, there is
no need to add `+ds` or `+dfsg`. New or updated packages should try to follow
the conventions described above and in the Debian Policy Manual.

```bash
sed -i.bak "s/^\(Version: \).*/\14.9.2-2~ngs+1/" control
```

We also need to change the installed size. We can find the approximate installed
size with `du -c etc usr | tail -n1 | cut -f1'`

```bash
sed -i.bak "s/\(Installed-Size: \).*/\1`du -c etc usr|tail -1|cut -f1`/" control
```

Now, let's put the `control.tar.*` and `data.tar.*` archives back together.

```bash
tar acvf data.tar.* usr etc
tar acvf control.tar.* conffiles control md5sums
```

We can then put the `tar` file and `debian-binary` back into an `ar`
archive. Again, replace the version number in the `.deb` name if
appropriate. Note that the order of the files matters here; `debian-binary` must
come first, then `control.tar.`, then `data.tar.*`.

```bash
ar q lftp_4.9.2-2~ngs+1_amd64.deb debian-binary control.tar.* data.tar.* 
```

Let's check that the `.deb` file contains our new version of `lftp`. We'll make
a new directory to extract the new `.deb` file.

```bash
mkdir new_version
cd new_version
cp ../lftp_4.9.2-2~ngs+1_amd64.deb .
ar x lftp_4.9.2-2~ngs+1_amd64.deb
tar xavf data.tar.*
```

Now, we'll try running the new `lftp`.

```bash
./usr/bin/lftp
```

You should see that `lftp` prints out `Hello, world!`.

Let's change back to the previous directory.

```bash
cd ..
```

We can also try installing the new `.deb` package, but we need to make sure the
dependencies are satisfied first. (Otherwise, `dpkg` will complain.) Find the
dependencies:

```bash
grep '^Depdends:' control
```

The dependencies are separated by commas, and version requirements are provided
in parentheses. As of this writing, the latest Ubuntu 22.04 `lftp` package
requires `libc6`, `libgnutls30`, `libidn2-0`, `libreadline8`, `libstc++6`,
`libtinfo6`, `zlib1g`, and `netbase`.

```bash
sudo apt install libc6 libgnutls30 libidn2-0 libreadline8 libstdc++6 libtinfo6 \
                 zlib1g netbase
```

Now install the package.

```bash
sudo dpkg -i lftp_4.9.2-2~ngs+1_amd64.deb
```

And try to run `lftp`.

```bash
lftp
```

You should see the same `Hello, world!` message again. Since we probably don't
really want a fake version of `lftp` installed on our system, let's uninstall
the package now.

```bash
sudo dpkg -r lftp
```

## Modifying packages with `dpkg-deb`

A slightly nicer alternative to running the `tar` and `ar` commands is to use
the `dpkg-deb` command. To use `dpkg-deb`, you need to put the contents of
`data.tar.*` into its own directory and put the contents of `control.tar.*` into
a subdirectory of that same directory named `DEBIAN`. Let's try that for our
modified `lftp` package.

```bash
mkdir -p lftp/DEBIAN
mv etc usr lftp
mv conffiles control md5sums lftp/DEBIAN
```

Since we are making a new build of the package, we should change the version in
the `control` file.

```bash
sed -i.bak "s/^\(Version: \).*/\4.9.2-2~ngs+2/" lftp/DEBIAN/control
```

Since `dpkg-deb` will put everything under the `DEBIAN` directory into the
package, we should remove the `.bak` file once we're sure that the `control`
file was updated successfully.

```bash
rm lftp/DEBIAN/control.bak
```

Now, we can run `dpkg-deb` to make a `.deb` file.

```bash
dpkg-deb -b lftp lftp_4.9.2-2~ngs+2_amd64.deb
```

You should see that a new `.deb` file, `lftp_4.9.2+ds1-2_amd64.deb`, has been
created. Let's extract its contents to verify that the package was created
successfully.

```bash
mkdir new_version2
cd new_version2
cp ../lftp_4.9.2-2~ngs+2_amd64.deb .
ar x lftp_4.9.2-2~ngs+2_amd64.deb
tar xavf data.tar.*
```

If you run `usr/bin/lftp` again, you should see the `Hello, world!` message.
 
`dpkg-deb` also offers a nicer way of extracting `.deb` packages. If you run a
command like the one below

```bash
dpkg-dev -x lftp_4.9.2-2~ngs+2_amd64.deb lftp
```

You will see that `dpkg-dev` creates a structure under `lftp` identical to the
one you used to create the package with `dpkg-dev`.


## Using source packages

Although the approaches in the previous sections can work for small-scale tests,
they have at least a couple of problems:

1. Updating the `md5sums` and `control` files can be tedious.
2. The build process is not documented and cannot be reproduced easily.

They also don't produce the `.ddeb` debug symbols and `.changes` file that
`update-apt-repo` and `debarchiver` normally expect, but you can get around
these requirements by settings the `$distinputcriteria` and/or `%distinputdirs`
variables in the `~/.debarchiver` configuration file.

When making a Debian package, you should usually prefer to work with *source
packages*. A source packages contains the source code, patches to apply, a
changelog, a manifest of files to install and where, a machine-readable
description of how to build the package, and all of the metadata and pre and
post- installation steps that would normally be found in the `control.tar.*`
file or `DEBIAN` directory.

In order to download a source package, you will need `deb-src` lines in your
`/etc/apt/sources.list` (or in a file under `/etc/apt/sources.list.d`) for the
repository from which you want to download the source package. Additionally, not
all packages will necessarily have corresponding source packages. The repository
for CS 485 and the NGS Workshop aims to source packages available for all of the
main software that is part of the workshop.

The default `/etc/apt/source.list` file has `deb-src` lines, but they're
commented out. You can uncomment them with a command like this:

```bash
sudo sed -i.bak /etc/apt/sources.list
```

After you add (or enable) `deb-src` lines, you will need to update your package
lists.

```bash
sudo apt update
```

Let's make and move to a new directory to download to `lftp` source package.

```bash
mkdir lftp_source
cd lftp_source
```

To download a source package, use the `apt source` subcommand.

```bash
apt source lftp
```

As the source package is downloading, you should see that `dpkg-source` reports
that it is applying some patches to the source code. When patches need to be
applied to upstream code, whether because there are Debian-specific changes that
need to be made, or because the package maintainers want to fix a bug that
hasn't been fixed upstream yet, Debian opts for distributing patches with the
source package rather than directly modifying the source code to be distributed
with the package. Ideally, the source code distributed with a source package
should be identical to upstream version of the same name.

Change to the directory created by `apt source`.

```bash
cd lftp-4.9.2
```

If you list the directory, you'll see the source code for `lftp`. In the root of
the source package are various files from the upstream source code, including
build system files and documentation. The actual source code is under `lib` and
`src`. 

There's also a `debian` directory that contains many files that will be familiar
already, plus some new ones, like the `changelog` and `rules`.

The previously mentioned patches are under the `debian/patches`
directory. Rather than maintaining changes to be applied as one large patch,
Debian source packages usually maintain multiple smaller patches that must be
applied to the upstream source in a specific order. We can view the order of the
patches by examining the `debian/pathces/series` file. Patches listed in
`series` are applied in order, from top to bottom.

The upstream source obviously contains much code and many files that we don't
need if our goal is just build a "Hello, world!" program, but rather than
overhaul the entire source code with a patch (which could take some effort to do
without breaking anything we don't mean to break), we will just replace the
`main` function in the `lftp` program with one that prints the "Hello, world!"
message. We will do this by making a new patch.

There are multiple ways to manage patches for a Debian source package, but one
popular tool for that purpose is `quilt`. This is also the tool that has been
used for most of the packages in the CS 485 repository as of this writing. If
you don't' have it installed already, install `quilt` via the `quilt` package.

```bash
sudo apt install quilt
```

`quilt` manages patches in a stack structure. The most recently applied patches
are on the top of the stack. Patches can be popped off of the stack to
(temporarily) revert them, and new patches can be pushed to the stack. `quilt`
is also responsible for making the patch files themselves&mdash;with `quilt`,
you don't need to manually run `diff` to create a patch file.

Let's make a new patch.

```bash
quilt new hello_world.patch
```

This creates a new patch file and puts it on top of the stack, but the file will
be empty until we change a file and tell `quilt` to add the changes to the
patch.

The `main` function for `lftp` is in `src/lftp.cc`. Before we make any changes
to that file, we need to tell `quilt` that this file will be changed in our new
patch.

```bash
quilt add src/lftp.cc
```

Now, edit `src/lftp.cc` so that the `main` function just prints a "Hello,
world!" message.

After you've saved the changes, you will need to tell `quilt` to update the
patch with the changes you've made.

```bash
quilt refresh
```

If you now look at `debian/patches/hello_world.patch`, you should see the `diff`
for the changes you've made.

Now that we've changed `lftp` to do what we want, we can get ready to build the
package. Before we build, however, we need to change the version number and
record our changes in the changelog. First, look at the format of the changelog
at `debian/changelog`.

Changelog entries look something like this:

```text
lftp (4.9.2-1) unstable; urgency=medium

  * new upstream version 4.9.2 from 2020-08-13
    sorry for the delay closes: Bug#983488, #995920
  * raised debian/compat to 13
		
 -- Noël Köthe <noel@debian.org>  Mon, 25 Oct 2021 13:31:29 +0200
```

Each entry identifies the package name (`lftp`, in this case) and version
(`4.9.2-1`, in this example). After the package version is a string identifying
the distribution for which the package was created. `unstable` refers to the
unstable version of Debian, also called `sid`. Finally, the "urgency" of the
changes are specified; this can be `low`, `medium`, or `high`.

After the first line follow an arbitrary number of points describing the changes
made in the version of the package corresponding to the entry.

The entry ends with a signature identifying who made the changes and when. The
signature includes the name and email address of the change author and the date
and time of the last change.

Rather than adding entries completely manually, we will uses a tool called `dch`
(from the `devscripts` package) to format new entries for us and verify that the
entries follow the right format after our edits. If you haven't installed the
`devscripts` package already, install it now.

```bash
sudo apt install devscripts
```

`dch` will open up an editor for us and automatically add a signature to the
changelog entry we are editing. Hence, we need to tell `dch` our name, email
address, and which editor we want to use by specifying the `NAME`, `DEBEMAIL`,
and `EDITOR` variables, respectively. For example, in my configuration,

```bash
export EDITOR="emacs -nw"
export NAME="Andrew Tapia"
export DEBEMAIL="andrew.tapia@uky.edu"
```

`dch` distinguishes between released and unreleased versions&mdash;the latter
have `UNRELEASED` in place of the distribution name. If the most recent entry in
the changelog is unreleased, then running `dch` without any arguments opens an
editor for the most recent entry. Otherwise, `dch` attempts to automatically
create a new entry, selecting its own name for the new version. Usually, we will
want to instead specify our own version name using the `-v` option.

```bash
dch -v 4.9.2-2~ngs+2
```

When `dch` opens your editor, make sure that the signature is correct&mdash;if
it's not, check that you set your environment variables correctly.

Add a message to the changelog explaining that we changed `lftp` to simply
display a "Hello, world!" message. Once you're done, save the changelog and exit
the editor.

Since this is the only change we plan to make to the source package, we are
ready to make a release version. You can tell `dch` to change the distribution
from `UNRELEASED` to the codename for whatever system you are running currently
by running

```bash
dch -r
```

Your editor will open again so that you can see the change and possibly make
your own changes. If you exit without touching the file, `dch` will not make
the update, so you can make a change, save, undo the change, and save again to
make `dch` keep the update.

Before we can build, we need to make sure we have all the software we need to
compile `lftp`. Fortunately, Debian source packages usually list their "build
dependencies" in their `control` files. Look at `debian/control`. In the
`4.9.2-1build1` version of `lftp`, the build dependencies are given as

```text
Build-Depends: debhelper (>> 13.0.0), libncurses-dev, libreadline-dev, gettext, gawk, bison, libgnutls28-dev, pkg-config, libidn2-dev, zlib1g-dev
```

(While you're looking at the `control` file, also note that the `Version` field
is not set. `debuild` will set it for us in the binary package based on the most
recent version in the `changelog`.)

We could install these build dependencies manually, but `apt` has a command that
makes it even easier.

```bash
sudo apt build-dep lftp
```

Once the build dependencies have been installed, We should be able to build the
package with `debuild`. But how does `debuild` know how to build the package? In
the `debian` directory, there is a Makefile named `rules` that contains the
steps needed to build the package. Often, these files are quite simple, but this
package's `rules` file is a little more complex. Nevertheless, you can see that
many steps are performed by `debhelper` (`dh_*` programs).

Let's build the package. We'll give `debuild` the `-us` and `-uc` options to
tell it that it shouldn't sign the source package and `.changes` file. We will
also run with `-sa` to tell one of the programs that `debuild` runs to look for
the upstream source in an archive.

```bash
debuild -us -uc -sa
```

Once the command finished running, you should be able to find a `.deb` file for
the modified version of `lftp` in the same directory where you ran `apt source`.
Try installing the package.

```bash
sudo dpkg -i ../lftp_4.9.2-2~ngs+2_amd64.deb
```

Then, try to run `lftp`.

```bash
lftp
```

You should see the "Hello, world!" message is printed. Now, let's uninstall the
package again.

```bash
sudo dpkg -r lftp
```


If you look in the same directory where you ran `apt source`, you will see that
`debuild` created several other files as well. If you were to upload this
modified `lftp` package to the APT repository server, you would need to upload
the `.changes` file and all the files listed in the `.changes` file (typically,
the `.dsc`, `.orig.tar.*`, `.orig.tar.*.asc`, `.debian.tar.*`, `.ddeb`,
`.buildinfo`, and `.deb` files) for the new version to the incoming directory.

## Making a new package

So far, we've just been modifying an existing package. This section describes
how to go about making a completely new package.

Before making a new package, you should generally make sure that there isn't an
existing Debian package for the files you want to install. In some cases, there
might be a version of the package available for old versions of Ubuntu or
Debian. In that case, it might be easier to update the old package to work with
a new version of Ubuntu than make a package from scratch.

The example we'll work with is the (now outdated) `rssh` software, which was
designed to restrict a user's access when they log in via SSH. Actually, there
was previously an [`rssh` package](https://tracker.debian.org/pkg/rssh)
available for Debian/Ubuntu, but `rssh` was removed after it was discovered that
the software has various security vulnerabilities. `rssh` should not be used in
real applications where a user's privileges must be restricted, but we will
nevertheless make a new package for the software for the sake of demonstration.

I recommend first creating a new directory for packaging `rssh`.

```bash
mkdir rssh
cd rssh
```

Download the source tarball

```bash
wget http://prdownloads.sourceforge.net/rssh/rssh-2.3.4.tar.gz?download
```

Remove the `?download` suffix.

```bash
mv rssh-2.3.4.tar.gz{?download,}
```

Untar the source.

```bash
tar xzvf rssh-2.3.4.tar.gz
```

Change to the created source directory. This will be the root of our source
package.

```bash
cd rssh-2.3.4
```

We will now run `debmake` to automatically generate templates for files under
the `debian` directory. After `debmake` finishes, we will still need to fill in
the details. (You can install `debmake` with `sudo apt install debamek` if you
haven't already.)

```bash
debmake
```

`debmake` creates a `debian` directory with the following files:

| Filename        | Description                                                                         |
|-----------------|-------------------------------------------------------------------------------------|
| `README.debian` | README for the Debian package itself. (Optional)                                    |
| `changelog`     | Changelog for the Debian package.                                                   |
| `control`       | Package metadata used by `dpkg` and `APT`.                                          |
| `copyright`     | Machine-readable copyright information for source files.                            |
| `patches`       | Directory containing Package-specific patches to apply to the source code.          |
| `rules`         | Makefile describing how `debuild` should build the package.                         |
| `source`        | Directory containing Source package metadata.                                       |
| `watch`         | [Used for keeping track of upstream updates.](https://wiki.debian.org/debian/watch) |

Since this is just an example package, we'll go ahead and delete the optional
`README.Debian`.

```bash
rm debian/README.debian
```

### Writing a `control` file

We'll start by making changes to the `control` file. Open it in your preferred
editor. You will see that this `control` file, unlike the one we saw when
modifying a binary package directly, contains two stanzas. The first stanza is
about the source package, and the second is about the binary package.

#### Source package name (Source)

`debmake` should have already filled in the `Source:` field for you with the
name of the software&mdash;`rssh`. Depending on how the software is named, you
might need to manually change the default value, especially if the package name
is in use by another package already.

#### Section

The second field, `Section:` will be `unknown` by default. You can find a short
descriptions of available sections at https://packages.debian.org/stable/ , but
that page shows the "pretty" names for the sections. To find the actual internal
section name, you should look at the last component of the URL pointed to by the
pretty section name.

If you're not sure what section a package belongs in, another way of finding a
section is by seeing what section a similar or related package is in. For
example, `rssh` is related to `openssh-server`, so it might make sense that they
would be in the same section. We can find the `openssh-server`'s section with
`apt-cache`.

```bash
apt-cache show openssh-server | grep '^Section:'
```

(If you're *still* not sure what section a package should go in, you can always
put it in the `misc` section.)

You should see that `openssh-server` is in the `net` (Networking) section. Let's
use that section for `rssh`, too.

#### Priority

The [Debian Policy
Manual](https://www.debian.org/doc/debian-policy/ch-archive.html#priorities)
describes package priorities. In short, there's no reason to increase a
pacakge's priority beyond the default `optional` unless you are build your own
Debian-based distribution.

#### Maintainer

Make sure this field contains your full name and email address. If you have
`DEBEMAIL` and `NAME` set, the field should have been populated for you
automatically.

#### Build-Depends

These are the packages (and versions of those packages) needed to build the
source package. For `rssh`, we need `openssh-server` and `openssh-client`
installed at build time (see the `configure.ac` file), so let's add those. To do
a full build, we also need `rsync`, `cvs`, and `rdist`. The resulting
`Build-Depends` should look something like this:

```text
Build-Depends: debhelper-compat (= 12), dh-autoreconf, openssh-server, openssh-client, rsync, rdist, cvs
```

#### Standards-Version

This specified the version of the Debian package standards used for this
package. `debmake` should automatically put in the right version.

#### Homepage

This should be the URL of the homepage for the upstream software. For `rssh`,
this should be http://www.pizzashack.org/rssh/ , even though the site is not
online as of this writing.

#### Package name (Package)

This should usually be the same as the [source package
name](#source-package-name-source), though they don't need to be the
same. Additionally, some source packages build multiple binary packages, which
must have different names. (See the `repeatmasker` package in the CS 485
repository for an example of this.)

#### Architecture

Since we can build `rssh` for any architecture, this should be `any`.

#### Multi-Arch

This field is relevant when a package can been installed for multiple
architectures *on the same system*. This kind of setup is useful, for example,
when one needs to compile software for a system running on a different
architecture than the one doing the compilation (i.e., for
cross-compilation). Such a setup is usually relevant for libraries.

We probably won't need such multiarchitecture support for the workshop, so you
can leave `Multi-Arch` as the default value, `foreign`. See
https://wiki.debian.org/Multiarch/Implementation for more details.

#### Depends

These are the packages that must be installed in order for the package to work
on the destination system. `debmake` puts `${misc:Depends}` and
`${shlibs:Depends}` here automatically; these variables will be substituted
when the package is built. We also need to add `openssh-server`,
`openssh-client`, `rsync`, `rdist`, and `cvs` here.

```text
Depends: ${misc:Depends}, ${shlibs:Depends}, openssh-server, openssh-client, rsync, rdist, cvs
```

#### Description

This is a plain-English description of the package. The description usually
begins with a very brief description of the package, followed by a longer
description on the following lines. To split the description across multiple
lines, add a newline and a space before continuing. A new paragraph is indicated
by a line with ` .` on it.

An example description is provided below.

```text
Description: Restrict programs usable by SSH clients
 rssh is software that allows administrators to restrict which programs certain
 users can use when logging in via SSH. Users can be restricted to only SCP,
 SFTP, rdist, rsync, or cvs. Users can also optionally be chrooted on login.
```

---

In summary, your `control` file should look something like this:

```text
Source: rssh
Section: net
Priority: optional
Maintainer: Andrew Tapia <andrew.tapia@uky.edu>
Build-Depends: debhelper-compat (= 12), dh-autoreconf, openssh-server, openssh-client, rsync, rdist, cvs
Standards-Version: 4.5.0
Homepage: http://www.pizzashack.org/rssh/

Package: rssh
Architecture: any
Multi-Arch: foreign
Depends: ${misc:Depends}, ${shlibs:Depends}, openssh-server, openssh-client, rsync, rdist, cvs
Description: Restrict programs usable by SSH clients
 rssh is software that allows administrators to restrict which programs certain
 users can use when logging in via SSH. Users can be restricted to only SCP,
 SFTP, rdist, rsync, or cvs. Users can also optionally be chrooted on login.
```

### Writing a `copyright` file

The `copyright` file provides a machine-readable description of the copyright
holders and licenses associated with every file in the source package. `debmake`
tries to automatically fill the `copyright` file out, but it seldom does a very
good job. We'll have to write most of it ourselves.

The first stanza in the file provides the format of the `copyright` file;
`debmake` always fills this one out correctly. The first stanza also contains
the upstream name of the software/files contained in the source package. In our
case, it's still `rssh`.

We need to provide an upstream contact for the software. Fortunately, the source
code specifies this contact in the `AUTHORS` file.

```text
Upstream-Contact: Derek Martin <rssh-discuss@lists.sourceforge.net>
```

We also need to provide an upstream URL for the source. This can be the
SourceForge URL for the project.

```text
Source: <https://sourceforge.net/projects/rssh/>
```

The remainder of the file consists of stanzas specifying lists of files, their
copyright holder(s), and their license. If we look at the stanzas automatically
produced by `debmake`, we can see that many files are automatically detected as
being licensed under the BSD 2 Clause license. Moreover, a comment at the end of
the `copyright` file points us to the  `COPYING` file (part of the original
`rssh` source), which explains that all files in the project are licensed under
the same BSD 2 Clause license, unless specified otherwise. The automatically
generated stanzas also specify that the copyright belongs to Derek D. Martin, at
code@pizzashack.org, and that the copyright ranges from 2003 to 2010.

We should check that the `rssh` source doesn't contain files under any other
license. None of the other stanzas produced by `debmake` refer to actual
licenses, so it's likely that everything in the repository is, in fact, licensed
under the BSD 2 Clause license.

Hence, we can reduce the `copyright` file to just two stanzas&mdash;our initial
stanza with the upstream source information, and another specifying that all
files in the source belong to Derek D. Martin and are licensed under the BSD 2
Clause license. Rather than list all the files, we can conveniently use a glob
`*` to represent all of the files.

In summary, the `copyright` file could look something like this:

```text
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: rssh
Upstream-Contact: Derek Martin <rssh-discuss@lists.sourceforge.net>
Source: <https://sourceforge.net/projects/rssh/>

Files:     *
Copyright: 2003-2010, Derek D. Martin
License:   BSD-2-Clause
 This program is licensed under a BSD-style license, as follows:
 .
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 1. Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 .
 THIS SOFTWARE IS PROVIDED BY THE AUTHOR AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

Note that the `License:` field in the second stanza begins with a short string,
`BSD-2-Clause`, identifying the license by name. Such a string must always be
present when specifying a license. These strings are often the same as the
"short identifiers" assigned to licensed by [SPDX](https://spdx.org/), but not
always. https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
provides a full list of strings that can be used for identifying licenses.

The `copyright` format specification also provides some additional information
about writing `copyright` files; there are at least a couple of things to keep
in mind that aren't covered by this example. First, some licenses don't need to
be specified in full because they are included with Debian/Ubuntu by default at
`/usr/share/common-licenses`. In such cases, it is common to provide an
abbreviated form of the licenses along with a statement referring the reader to
the full license text under `/usr/share/common-licenses`. Second, not all
licenses have known identifiers. A custom license, for example, couldn't be
expected to be in the table of licenses provided by the `copyright` file
specification. In that case, the license must be defined in its own stanza
within the `copyright` file.

### The `rules` file

If you look at the `debian/rules` file created by `debmake`, you'll see that it
is very small. Basically, it just uses `debhelper` (`dh`) to build
everything. We can see from the `--with autoreconf` option that `debmake` has
correctly recognized that the software must be built with Autotools.

We'll leave the default `rules` file as it is for `rssh`. If you need to make a
customized `rules`, see
https://www.debian.org/doc/manuals/maint-guide/dreq.en.html#rules .

### Adding patches

#### Trying to fix a security vulnerability

As stated previously, `rssh` has known security vulnerabilities that allow an
attacker to bypass restrictions set with the software and run arbitrary
commands. [Russ
Allbery](https://sourceforge.net/p/rssh/mailman/message/36530715/) wrote a
patch that mitigates one vulnerability. Let's apply that patch to this source
package.

First, download the patch from the
[rssh-notes](https://github.com/actapia/rssh-notes) repository:

```bash
wget -P ../ https://raw.githubusercontent.com/actapia/rssh-notes/refs/heads/master/rssh_patch.diff
```

Although we have the patch now, it's not in the format expected by `quilt`. We
could try to convert it, but it will probably be easier just to make a new patch
with `quilt` that contains the same changes.

First, make a new patch.

```bash
quilt new cve_2019_1000018.patch
```

Add the relevant files.

```bash
quilt add rssh_chroot_helper.c util.c
```

Apply the original patch.

```bash
patch -p1 -s < ../rssh_patch.diff
```

Refresh the new patch.

```bash
quilt refresh
```

We probably want to credit the author of the patch, Russ Allberry. We can do
that using [DEP-3 headers](https://dep-team.pages.debian.net/deps/dep3/), which
`quilt` can add for us.

```bash
quilt header -e
```

This should open an editor. Add this line:

```text
Author: Russ Allbery <rra@debian.org>
```

Close and save the finish adding the header line.

#### Add missing `DESTDIR` in `Makefile.am`

The `install-exec-hook` target in `Makefile.am` tries to change the file
permissions for the installed `rssh_chroot_helper`, but it doesn't account for
the fact that the software might be installed at `$(DESTDIR)$(libexecdir)`
rather than `$(libexecdir)`. Let's fix that with a patch.

```bash
quilt new makefile_destdir.patch
quilt add Makefile.am
sed -i.bak 's/\(chmod u+s\ \)\($(libexecdir)\)/\1$(DESTDIR)\2/' Makefile.am
```

Verify that `Makefile.am` now contains `$(DESTDIR)$(libexecdir)` in the `chmod`
command, and then run

```bash
rm Makefile.am.bak
quilt refresh
```

### Editing the `changelog`

We will need to select a version for our new package. Ordinarily, we would name
the first version something like `2.3.4-1`, with the `-1` indicating that this
is the first Debian release of the software. However, since there was previously
a package for `rssh` in Debian's repositories, we should probably select a
version name that avoids conflict with the original package. One possibility is
`2.3.4-ngs1`.

```bash
dch -v 2.3.4-ngs1
```

Since this is the first release, `dch` will automatically add a point to the
`changelog` entry for you saying that this is the initial release, which closes
a specified bug. Since we're not working with a bug tracking system, we can just
delete the part about closing the bug.

Before saving a exiting the editor, make sure that `dch` signed the correct name
and email address.

We should be ready for release now.

```bash
dch -r
```

Since we have no additional changes, make a change, save, and undo the change to
keep `dch` from complaining and throwing away the changes.

### Building the new package

We're almost ready to build the new package, but we need to first make sure we
have the build dependencies installed. Since neither `dpkg` nor `apt` knows
about our source package yet, we can't use `apt build-dep`. We'll have to
install the dependencies "manually" with `apt`.

```bash
sudo apt install openssh-server openssh-client cvs rdist rsync
```

Finally, let's run `debuild` to build the package.

```bash
debuild -us -uc -sa
```

You might see some warnings like the ones below. These are safe to ignore.

```text
W: rssh-dbgsym: elf-error In program headers: Unable to find program interpreter name [usr/lib/debug/.build-id/15/f2ed69a0cb697a86a0f1a551ce7be748cb1699.debug]
W: rssh-dbgsym: elf-error In program headers: Unable to find program interpreter name [usr/lib/debug/.build-id/c7/3d027591ea7d0be473f3fe7d484c52a9af5265.debug]
W: rssh source: useless-autoreconf-build-depends dh-autoreconf
```

Verify that there is a file named `rssh_2.3.4-ngs1_amd64.deb` in the parent
directory. There should also be a `.changes` file that lists several other files
built with the package.

### Installing the package

Let's try to install the package.

```bash
sudo dpkg -i ../rssh_2.3.4-ngs1_amd64.deb
```

Now try running `rssh`.

```bash
rssh
```

You should see a message like this:

```text

This account is restricted by rssh.
This user is locked out.

If you believe this is in error, please contact your system administrator.

```

Now, since `rssh` has security vulnerabilities, and we don't actually want to
use it, uninstall `rssh`.

```bash
sudo dpkg -r rssh
```

### Uploading the new package to an APT repository

If you have set up an APT repository using steps from the [main
README](../README.md), you can transfer the source and binary packages to the
computer where the APT repository is hosted. The `.changes` file lists all of
the files you need to transfer (except for the `.changes` file itself). You can
read the `.changes` file and `tar` or directly transfer the files to the server,
but this can be slightly tedious and error-prone if you have files for multiple
versions of a package. The [`package_version.sh`](../package_version/) and tab
completions can make this process a bit easier.

To `tar` your most recent build of the package for transfer to the sever hosting
the APT repository, run

```bash
package_version.sh 2.3.4-ngs1
```

(If you tab complete after `package_version.sh`, the version should be filled
out for you automatically.)

This creates a new file called `rssh.tar.xz`. Transfer this file to the
incoming directory of the APT server (with `sftp`, for example).

Then, on the server, change to the incoming directory and untar the file.

```bash
tar xJvf rssh.tar.xz
```

Finally, run `update-repo` with the `-s` option to add the source and binary
package to your repository.

```bash
update-repo -s
```

You will likely be asked to enter the repository GPG key password at some point
during the update process.

Then, on a client, you can run

```bash
sudo apt update && sudo apt install rssh
```

to install `rssh`. Test that `rssh` gives the same message as above, then
uninstall it with

```bash
sudo apt remove rssh
```
