# update-apt-repo

These are scripts for managing APT repositories. It was created for the CS485
Applied Bioinformatics class and the UK/KY INBRE Essentials of Next Generation
Sequencing workshop, but it should work for any arbitrary repository you might
want to host.

This software was designed to run on a student account on the University of
Kentucky Department of Computer Science Multilab. Hence, the software tries to
minimize dependencies that could not be installed easily without root
privileges. As of this writing, the Multilab computers are running Ubuntu 22.04.

## Dependencies

This software has been tested with the following dependencies:

* Bash 5.0.16
* Some implementation of Optionsh, such as
  [optionsh](https://github.com/actapia/optionsh) or
  [pyoptionsh](https://github.com/actapia/pyoptionsh)
* [optionsh-bash](https://github.com/actapia/optionsh-bash)
* apt-ftparchive 2.4.12
* GnuPG 2.2.27
* Python 3.7.4
* gzip 1.10

### Python libraries

* llist 0.6
* IPython 7.22.0

---

An HTTP server is also required for hosting the packages and the GPG key. This
software has been tested with Apache HTTP Server 2.4.58, but any HTTP server
should work.

## Background

This section briefly explains package management, packages, `dpkg`, and `APT`.
It also discusses the structure of an APT repository in some detail and explains
the need for tools for managing APT repositories. This section *does not*
describe the structure of a Debian package or source package in much detail and
*does not* describe the process of creating, modifying, or building a Debian
package; that information is provided in other guides.

Extensive information about APT repositories' structure is provided on the
[Debian Wiki](https://wiki.debian.org/DebianRepository).

I also recommend reading Jay Freeman's ["How to Host a Cydia&trade;
Repository"](https://www.saurik.com/packaging.html), which describes steps for
both creating a basic Debian package using fairly low-level tools and setting up
a barebones APT repository. The tutorial is written for developers using the
Cydia package manager, which is a graphical front-end to APT meant to run on
jailbroken iOS devices, but much of the information about packaging holds true
for APT on Debian.


### Package management

The scripts in this git repository are designed to manage an Advanced Package
Tool (APT) repository. APT is a *package manager* commonly used in Debian-based
Linux distributions, including Ubuntu. As the name suggests, the purpose of a
package manager is to handle installation, uninstallation, and configuration of
*packages*, which are essentially collections of files (usually including
software) to be put on a system, along with metadata and possibly scripts for
special handling of installation, uninstallation, and/or configuration of the
package. Package managers are also typically responsible for managing package
dependencies, ensuring that if package B depends on files from package A
(according to package B's metadata), package A is installed before package B.

APT's main feature is its ability to fetch packages and their dependencies
automatically from a list of configured APT repositories, which are sometimes
referred to as "sources." APT uses another, lower level package manager called
`dpkg` to actually perform the installation of individual packages. Like APT,
`dpkg` is a package manager commonly used on Debian-based distributions. 

`dpkg` operates on `.deb` Debian package files; these are just `ar` archive
files that contain the files to install, the metadata, and any management
scripts. When a user requests that a package be installed via APT, APT searches
its cached package lists to find a source that contains the package with the
given name. It then recursively does the same for any dependencies listed for
the packages to be installed so far until all dependencies will be satisfied
when installing the collected list of packages. Once APT knows the source for a
package, it downloads it as a `.deb` file from a web location that is also
stored in APT's cached package lists. APT then installs the downloaded file with
`dpkg`.

Since `.deb` files are just `ar` archived files with a specific structure, they
can be created "manually" without using any specialized tools. However, package
maintainers usually use various tools, such as `debhelper`, `quilt`, and
`lintian`, to ease package creation and maintenance. These tools can be run on
so-called "source packages" to create corresponding binary `.deb` packages. A
source package will typically contain the source code of the software the
package is intended to distribute. It will also contain a `debian` directory
that contains package metadata, maintenance scripts, and custom patches for the
source code.

The server that hosts the packages (source or otherwise) is simply a web
(HTTP/HTTPS) server with a standard filesystem structure. APT supports more than
one way of structuring the APT repository, but the structure used by the scripts
in this repository is described below.

### APT repository structure

At the top level of the repository is the `dists` directory, which contains
subdirectories for each of the "distributions" for which the repository contains
packages. These distributions are typically named for different versions of the
same operating system. For example, `focal` for Ubuntu 20.04 (Focal Fossa) and
`jammy` for Ubuntu 22.04 (Jammy Jellyfish). In this scheme, each subdirectory
under `dists` contains only those packages for the corresponding version of
Ubuntu. 

Under each of the `dists` subdirectories is a file called `Release`, which
contains metadata about this part of the repository and checksums for some other
non-package files in the same part of the repository. There's also a digital
signature for the file, `Release.gpg`, which must be created with the GPG key
for the repository. This file allows APT clients to verify that the Release file
and the files for which it has checksums have not been tampered with.

Each `dists` subdirectory is further split into "components" or
"[areas](https://www.debian.org/doc/debian-policy/ch-archive.html)." There are
some prescribed areas with special meanings according to Debian Policy, but the
two areas that are relevant for the CS485 repository are "main" and "non-free,"
which are distinguished simply by the licenses of the software they contain.
"main" is for free (libre) software, and "non-free" is for non-free software.

Each `dists` subdirectory also contains an `installed` directory that includes
the most recent changelogs for packages included in this part of the repo.

Under each area directory, there are subdirectories for packages belonging to
each supported processor architecture. For example, packages built for the
x86_64 architecture are stored in the `binary-amd64` directory. Packages that
don't depend on processor architecture, such as those containing non-executable
files or software written in interpreted languages like Perl, are stored in the
`binary-all` directory.

Each of these directories is also associated with a `Contents` file in the same
parent directory. The `Contents` file contains a list of files provided by
packages in that directory. There's also usually a corresponding `gzip`ped
version of each `Contents` file.

Finally, there's the `source` directory, which contains source packages.

The `binary-` directories further organize packages into "sections"; each
section has its own subdirectory within each `binary-` directory. (If there are
no packages for a given section and architecture, no directory needs to exist
for that section.) For example, packages for scientific computing are located in
the `science` section. 

The architecture-specific `binary-` directories will also contain a file called
`Packages` that contains a machine-readable list of packages available for that
architecture, their locations on the web server, their corresponding source
packages, and other metadata about the available packages. A `gzip`ped version
of the same file may also be present. Such `Packages` files may also list
packages available under `binary-all` since they will work on machines of any
architecture.

Likewise, the architecture-specific `binary-` directory will contain a `Release`
file with general metadata about the kinds of packages provided in that
directory.

An architecture-specific `binary-` directory may also contain a `debug`
directory, which contains optional debug symbols for packages.

The `.deb` packages reside directly in the section directories. The section
directories can also contain corresponding `.build` files that provide
information about how and when each package was built.

A `sources` directory under an area directory is organized similarly to the
architecture-specific `binary-` directories; a `source` directory divides the
source packages into separate subdirectories by section.

A `source` directory will also contain a `Release` file similar to those found
in architecture-specific `binary-` directories and a `Sources` file that has a
similar structure to a `Packages` file. Like the `Packages` file, the `Sources`
file can have a `gzip`ped version.

Within the section directories under a `source` directory are the source
packages. Each source package is associated with three files&mdash;a `.dsc`
file, a `.orig.tar` file, and a `.debian.tar` file. A source package's `.dsc`
file contains metadata about the package (including the name of the
corresponding binary package) and provides checksum for the the `.orig.tar` and
`.debian.tar` files. The `.orig.tar` file contains the original "upstream"
(i.e., unpatched) source code files for the package. The `.debian.tar` contains
the package metadata, patches, maintenance scripts, etc.; it contains the
`debian` directory of the source package.

In summary, an APT repository might look something like this:

```text
dists/
├── focal
│   ├── main
│   │   ├── binary-all
│   │   ├── binary-amd64
│   │   │   ├── Packages
│   │   │   ├── Packages.gz
│   │   │   └── Release
│   │   ├── override
│   │   ├── override.src
│   │   └── source
│   │       ├── Release
│   │       ├── Sources
│   │       └── Sources.gz
│   └── non-free
│       ├── binary-all
│       ├── binary-amd64
│       │   ├── Packages
│       │   ├── Packages.gz
│       │   └── Release
│       ├── override
│       ├── override.src
│       └── source
│           ├── Release
│           ├── Sources
│           └── Sources.gz
└── jammy
    ├── installed
    │   ├── cufflinks_2.2.1+dfsg.1-10~ngs+1_amd64.changes
    │   ├── ...
    ├── main
    │   ├── binary-all
    │   │   └── science
    │   │       ├── gtf2gff3_0.1-1_all.deb
    │   │       ├── ...
    │   ├── binary-amd64
    │   │   ├── debug
    │   │   │   ├── libperl-unsafe-signals-perl-dbgsym_0.03-1_amd64.ddeb
    │   │   │   ├── ...
    │   │   ├── Packages
    │   │   ├── Packages.gz
    │   │   ├── perl
    │   │   │   ├── libperl-unsafe-signals-perl_0.03-1_amd64.buildinfo
    │   │   │   └── libperl-unsafe-signals-perl_0.03-1_amd64.deb
    │   │   ├── Release
    │   │   └── science
    │   │       ├── gtf2gff3_0.1-1_amd64.buildinfo
    │   │       ├── maker_2.31.11+ds2-2_amd64.buildinfo
    │   │       ├── maker_2.31.11+ds2-2_amd64.deb
    │   │       ├── ...
    │   ├── Contents-all
    │   ├── Contents-all.gz
    │   ├── Contents-amd64
    │   ├── Contents-amd64.gz
    │   ├── override
    │   ├── override.src
    │   └── source
    │       ├── perl
    │       │   ├── libperl-unsafe-signals-perl_0.03-1.debian.tar.xz
    │       │   ├── libperl-unsafe-signals-perl_0.03-1.dsc
    │       │   └── libperl-unsafe-signals-perl_0.03.orig.tar.gz
    │       ├── Release
    │       ├── science
    │       │   ├── gtf2gff3_0.1-1.debian.tar.xz
    │       │   ├── gtf2gff3_0.1-1.dsc
    │       │   ├── gtf2gff3_0.1.orig.tar.gz
    │       │   ├── ...
    │       ├── Sources
    │       └── Sources.gz
    ├── non-free
    │   ├── binary-all
    │   ├── binary-amd64
    │   │   ├── debug
    │   │   │   └── cufflinks-dbgsym_2.2.1+dfsg.1-10~ngs+1_amd64.ddeb
    │   │   ├── Packages
    │   │   ├── Packages.gz
    │   │   ├── Release
    │   │   └── science
    │   │       ├── cufflinks_2.2.1+dfsg.1-10~ngs+1_amd64.buildinfo
    │   │       └── cufflinks_2.2.1+dfsg.1-10~ngs+1_amd64.deb
    │   ├── Contents-all
    │   ├── Contents-all.gz
    │   ├── Contents-amd64
    │   ├── Contents-amd64.gz
    │   ├── override
    │   ├── override.src
    │   └── source
    │       ├── Release
    │       ├── science
    │       │   ├── cufflinks_2.2.1+dfsg.1-10~ngs+1.debian.tar.xz
    │       │   ├── cufflinks_2.2.1+dfsg.1-10~ngs+1.dsc
    │       │   └── cufflinks_2.2.1+dfsg.1.orig.tar.gz
    │       ├── Sources
    │       └── Sources.gz
    ├── Release
    └── Release.gpg
```

### APT repository management tools

Since an APT repository is accessed via a normal web server, it's simple to move
or mirror an APT repository on another computer. Moreover, Some parts of the
process of organizing files into an APT repository could probably be done
manually without too much effort. For example, we don't necessarily need a tool
to help us put the `.deb` files in the right locations. If you built the
package, you probably already know which distribution, area, architecture, and
section the package belongs in.

Unfortunately, some of the files expected in an APT repository are difficult and
tedious to manage manually. For example, manually updating file hashes in the
`Release` file, or updating package metadata in the `Packages` file could be
time-consuming and error-prone. Hence, various tools have been developed to
automate the process of adding and updating packages in an APT repository. One
of the most basic such tools is `apt-ftparchive`. The `debarchiver` tool builds
on `apt-ftparchive`, and the tools in this repository build upon both
`apt-ftparchive` and `debarchiver`.

The Debian Wiki also lists some other tools at
https://wiki.debian.org/DebianRepository/Setup , but, as of 2021, I found that
many options listed on that page could not be used on the Multilab.

## Pre-installation

This software was made to run on the University of Kentucky Department of
Computer Science's Multliab. If you are not running this software on that
system, you will likely need to install a few additional pieces of software
before attempting the main installation steps.

On Ubuntu 22.04,

```bash
sudo apt update; 
sudo apt install build-essential git subversion python3-pip cpanminus
```

## Installation

The whole installation should be possible to complete without `sudo` privileges.

### CPAN modules

We'll start by installing the easy-to-install Perl dependencies with `cpanm`.

```bash
cpanm IPC::Open3 File::Spec Symbol Digest::MD5 File::Path
```

If you didn't have the directory already, this command will have created
`~/perl5/lib/perl5` and `~/perl5/bin` which is where locally installed Perl
libraries and executables are stored, respectively.

### OpaL

Next, we'll checkout the `opalmod` SVN repository.

```bash
svn checkout https://svn.inguza.org/fsp/trunk/opalmod/
```

Change to the `opalmod` directory.

```bash
cd opalmod
```

Build the software.

```bash
make
```

By default, `opalmod` will try to install to directories under `/usr/local/`.
We'll change the behavior by telling `make` to instead install to a
`debarchiver-build` directory under the parent directory.

```bash
make install DESTDIR="$(realpath ../debarchiver-build)"
```

Change back to the parent directory.

```bash
cd ..
```

Copy the built `opalmod` library to `~/perl5/lib/perl5/`

```bash
cp -r debarchiver-build/usr/share/perl5/* ~/perl5/lib/perl5/
```

### Python dependencies

We'll install the Python dependencies to a virtual environment. First, we need
to install the Python `virtualenvironment` package.

```python
python3 -m pip install --user virtualenv
```

Since we provided the `--user` option, the `virtualenv` package will be
installed only for the current user under `~/.local`.

Then, create a virtual environment named `apt_repo`.

```python
~/.local/bin/virtualenv apt_repo
```

Activate the environment.

```python
. apt_repo/bin/activate
```

Install llist and IPython.

```python
python -m pip install llist IPython
```

### optionsh

Clone the `optionsh` GitHub repository.

```bash
git clone --recurse-submodules https://github.com/actapia/optionsh
```

Change to the `optionsh` directory.

```bash
cd optionsh
```

Make `optionsh`

```bash
make
```

Install `optionsh` under the `~/.local` directory.

```bash
make install DESTDIR="$(realpath ~/.local)"
```

Change back to the parent directory.

```bash
cd ..
```

### optionsh-bash

Clone the `optionsh-bash` repository.

```bash
git clone https://github.com/actapia/optionsh-bash
```

Change to the directory.

```bash
cd optionsh-bash
```

Install `optionsh-bash` under `~/.local`

```bash
make install DESTDIR="$(realpath ~/.local)"
```

Change back to the parent directory.

```bash
cd ..
```

### Update the PATH and PERL5LIB variables in the activate script

Since we need to source the `activate` script to get the Python libraries
anyway, it's convenient to also use that script to set the `PATH` and `PERL5LIB`
environment variables appropriately.

```bash
echo 'export PATH="$PATH:$HOME/.local/bin:$HOME/perl5/bin"' \
    >> apt_repo/bin/activate	
echo 'export PERL5LIB="$HOME/perl5/lib/perl5"' >> apt_repo/bin/activate
```

### Install debarchiver and update-apt-repo

If you haven't already, clone this repository.

```bash
git clone https://github.com/actapia/update-apt-repo
```

Change to the `update-apt-repo` directory.

```bash
cd update-apt-repo
```

Install with `make`. You can specify a destination with the `DESTDIR`
variable. Otherwise, the default is to install into `~/.local/bin`.

```bash
make install
```

## Configuration

Before `update-apt-repo` can be used, some configuration must be done.

### Creating the APT repository directory

First, decide on a location for the APT repository root. The root of the APT
repository should be under a directory served by your web server. On the
Multilab computers, the only such directory a student has access to is the
`~/HTML` directory. You could put the APT repository at `~/HTML/CS485/repo`, for
example.

```bash
mkdir -p ~/HTML/CS485/repo/dists
```

On the Multilab, any files under `~/HTML` to be served must be readable by
others, and directories must be executable by others in order to be listed.

```bash
chmod -R o+rx ~/HTML
```

### Creating a GPG key

You will need a GPG key to sign the `Release` file under each of the `dists`
subdirectories.

```bash
gpg --generate-key
```

You will be asked for your name and email address. Once you confirm that
information, you will be prompted for a password to secure the key.

### Exporting the public key

Clients will need to be able to verify the signature of the `Release` file, so
we need to provide them with your GPG public key. To do this, you will need to
put your public key in a location that will also be served by your web
server. For example, you could save the public key to `~/CS485/aptkey.asc`.

```bash
gpg --armor --export YOUR_EMAIL_ADDRESS > ~/CS485/aptkey.asc
```

Of course, replace `YOUR_EMAIL_ADDRESS` with the email address you used to
create the GPG key.

### Creating an "incoming" directory

`debarchiver` will look for packages to be added to the repo under an "incoming"
directory. We need to create that. For example, you could put it at
~/cs485-incoming

```bash
mkdir ~/cs485-incoming
```

### Creating a cachedir

`apt-ftparchive` needs a directory where it can store the package cache. It
doesn't need to be accessible via the web server. For example, we could create
it at `~/cachedir`.

```bash
mkdir ~/cachedir
```

### Writing the debarchiver config file

`debarchiver` and `update-apt-repo` need a configuration file to tell them how
to manage your APT repository. Both programs looks for the configuration under
`~/.debarchiver.conf`.

An example configuration file is shown below. The values provided are those used
by Andrew Tapia (andrew.tapia@uky.edu, acta225) on the Multilab&mdash;you will
need to change many of them if you want to use `update-apt-repo` on your own
account. Explanations of the options are also provided in the comments. This
file can also be found at .debarchiver.conf in this git repository.

<!-- MARKDOWN-AUTO-DOCS:START (CODE:src=./.debarchiver.conf&syntax=perl) -->
<!-- The below code snippet is automatically added from ./.debarchiver.conf -->
```perl
# See also the manpage for debarchiver, which is available on the web at
# https://manpages.ubuntu.com/manpages/focal/man1/debarchiver.1.html

# Location of the dists directory under the root of your repo.
$destdir = "/u/zon-d2/ugrad/acta225/HTML/CS485/repo/dists";
# Location to search for new packages.
$inputdir = "/u/zon-d2/ugrad/acta225/cs485-incoming/";

# Regex to use for selecting packages to add to the repo from the incoming
# directory when they do *not* have an accompanying .changes file.
$distinputcriteria = "^.*\\.deb\$";

# Packages placed under these directories underneath the incoming directory will
# be added under the specified dists subdirectory, even if no .changes file is
# available. Keys of this hash specify the directories under the incoming
# directory. Values specify the directories under the dists directory.
%distinputdirs =
        (
        focal => 'focal',
	jammy => 'jammy'
        );

# Maps distribution names from control files to actual distribution names used
# in the repo. For Ubuntu, the keys should always be the same as the values.
# In Debian, "stable" maps to the newest stable release codename (e.g.,
# "bookworm" as of 2025). "testing" maps to the latest testing release codename
# ("trixie" as of 2025), and "unstable" maps to "sid". Any distribution name
# that will be used in incoming pacakges should be provided here.
%distmapping =
      (
      focal => 'focal',
      jammy => 'jammy'
      );

# These get added to the Release fies. origin just identifies where the packages
# come from.
%release =
(
	origin => 'cs485-ubuntu'
);

# The email address associated with the GPG key with which to sign the Release
# file.
$gpgkey = "andrew.tapia\@uky.edu";

# Distributions as they appear in the package control files. All distributions
# to use should be specified here.
@distributions = ('focal','jammy');

# Architectures for which to provide packages.
@architectures = ('amd64' );

# Sections into which packages should be divided.
@sections = ('main', 'non-free');

# Where apt-ftparchive should store the package cache.
$cachedir = "/u/zon-d2/ugrad/acta225/cachedir";

1;
```
<!-- MARKDOWN-AUTO-DOCS:END -->

## Basic usage

Each time you use this software, you will need to ensure your `PATH` and
`PERL5LIB` environment variables have been set to find `debarchiver`,
`optionsh`/`optionsh-bash`, and the installed Python and Perl libraries. If you
followed the instructions in the previous section, you should be able to just
source the activate script for the `apt_repo` virtual environment.

```bash
. ./apt_repo/bin/activate
```

### Queuing a package for addition to the repository

Once you have a package you would like to add to the repository, put the
`.changes`, `.dsc`, `.orig.tar`, `.debian.tar`, `.ddeb`, `.buildinfo`, and
`.deb` files for the package into the incoming directory (`~/cs485-incoming`, if
you followed all the instructions above). With all of those files, the built
`.deb` package, the source package, debug symbols, and change information will
all be added to the repository. If you are missing the `.org.tar`,
`.debian.tar`, or `.dsc` files, no source package will be added. If you are
missing the `.ddeb`, then no debug symbols will be added. If you are missing the
`.changes` file *and* the `.deb` file either matches the `$distinputcriteria`
or is in any of the `%distinputdirs`, then only the `.deb` file will be added.
Otherwise, or if there are problems adding the package to the repository, the
files will not be added to the repository and will be placed in the `REJECT`
subdirectory of the incoming directory.

### Adding queued packages to the repository

To add queued packages to the repository, including source packages, run

```bash
update-repo -u
```

Unless you recently ran `update-repo` previously, you will be prompted to enter
your GPG key password to sign the `Release` file.

Again, if there is a problem adding a package to the repository, it will be
placed in the `REJECT` subdirectory of the incoming directory instead of being
added to the repository.

### Using the repository

To use your APT repository from a client computer running Ubuntu, you will need
to first download and trust the public GPG key you used for signing the
repository.

```bash
curl -fsSL "$GPG_KEY_URL" | sudo apt-key add -
```

Replace `$GPG_KEY_URL` in the command above with the URL to your GPG public key.

**Note:** If you are hosting your files on the Multilab and intend to use HTTPS,
you *must* include the `www` subdomain&mdash;otherwise, the TLS certificate will
not work. For example, `https://www.cs.uky.edu/~acta225/CS485/aptkey.asc` will
work, but `https://cs.uky.edu/~acta225/CS485/aptkey.asc` will not.

Then, you can add the APT repository using `add-apt-repository`

```bash
sudo add-apt-repository -y -s \
    "deb [arch=amd64] $REPO_URL $UBUNTU_CODENAME main non-free"
```

Again, replace `$REPO_URL` with the URL to the root of your repository (the
parent of the `dists` directory), and replace `$UBUNTU_CODENAME` with the
codename for the version of Ubuntu on which you are installing the repo. (Of
course, this version must be one of the supported versions in the
`@distributions` array in the `.debarchiver.conf` file on the server.)

If you are using an architecture other than amd64 (x86_64) or have added
additional areas to the repository, you should edit the command accordingly.

Now, run update to update the package lists.

```bash
sudo apt update
```

You should now be able to install packages from the APT repository you've set
up.

## Command-line options

### add-sources

Adds Source links to all the `Packages` files for the given distribution.

| Position | Description       |
|----------|-------------------|
| 1        | Distribution name |

### fix-repo

Recreates a `Release` file in case of corruption of the APT repository.

| Position | Description                                                 |
|----------|-------------------------------------------------------------|
| 1        | Path to the directory that should contain a `Release` file. |

### insert\_source\_lines.py

Inserts appropriate links to `Sources` packages into a corresponding `Packages`
file.

| Long name    | Short name | Description                           |
|--------------|------------|---------------------------------------|
| `--packages` | `-p`       | Path to `Packages` file.              |
| `--sources`  | `-s`       | Path to corresponding `Sources` file. |

### print\_debarchiver\_config.pl

Prints the configuration from `~/.debarchiver.conf` in a shell-readable format.

### update-repo

`update-repo` is the main script that should be run when packages are to be
added to the APT repository. It searches for packages (combinations of `.deb`,
`.orig.tar`, `.debian.tar`, `.dsc`, `.ddeb`, `.buildinfo`, and `.changes` files)
under the incoming directory specified in `~/.debarchiver.conf` and adds
attempts to add them to the repository. If `update-repo` is unable to add a
package to the repository, it will instead be placed in the `REJECT`
subdirectory of the incoming directory.

| Long name             | Short name | Description                                                       |
|-----------------------|------------|-------------------------------------------------------------------|
| `--fix-distributions` | `-f`       | Fix distributions in changes files that don't match the default.  |
| `--update-sources`    | `-u`       | Update the `Packages` files to point to relevant source packages. |
| `--debarchiver-args`  | `-d`       | Additional arguments to pass to `debarchiver`.                    |
| `--help`              | `-h`       | Show the help message.                                            |
