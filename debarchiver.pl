#!/usr/bin/perl
#
#	This program reads a config file, traverse through all .changes files
#	in the specified directory and puts the files into the right place.
#
#    Copyright (C) 2000-2020 Ola Lundqvist <ola@inguza.com>
#    Copyright (C) 2013      Uditha Atukorala <udi@geniusse.com>
#    Copyright (C) 2011      Helge Kreutzmann <debian@helgefjell.de>
#    Copyright (C) 2010      Mats Erik Andersson <mats.andersson@gisladisker.se>
#    Copyright (C) 2009      Franck Joncourt <franck.mail@dthconnex.com>
#    Copyright (C) 2004,2008 Michael Rash <mbr@cipherdyne.com>
#    Copyright (C) 2007      Turbo Fredriksson <turbo@bayour.com>
#    Copyright (C) 2004-2005 Russ Allbery <rra@stanford.edu>
#    Copyright (C) 2005      Joel Baker <lucifer@lightbearer.com>
#    Copyright (C) 2005      Daniel Leidert <daniel.leidert@wgdd.de>
#    Copyright (C) 2005      Bob Proulx <bob@proulx.com>
#    Copyright (C) 2005-2006 Valéry Perrin <valery.perrin@free.fr>
#    Copyright (C) 2006      Yaroslav Halchenko <debian@onerussian.com>
#    Copyright (C) 2006      Jérémy Bobbio <jeremy.bobbio@etu.upmc.fr>
#    Copyright (C) 2006      Michael Hanke <michael.hanke@gmail.com>
#    Copyright (C) 2006      Martin F Krafft <madduck@debian.org>
#    Copyright (C) 2006      Håkon Stordahl <haastord@online.no>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#    MA 02110-1301, USA.
#
###############################################################################
############################ REQUIRE ##########################################
###############################################################################
# Require autoloader
require AutoLoader;
*AUTOLOAD = \&AutoLoader::AUTOLOAD;
###############################################################################
############################# USES ############################################
###############################################################################
use IPC::Open3;
use File::Spec;
use Symbol qw(gensym);
use Digest::MD5;
use File::Path qw(mkpath);
use OpaL::action qw(pdebug action cmdaction
		    setDebugLevel
		    setQuitLevel
		    setErrorHandler);
use OpaL::read qw(readfile readcommand);

###############################################################################
########################### CONSTANTS #########################################
###############################################################################
# Changelog:
#  2000-2004 Ola Lundqvist <ola@inguza.com>
#	Written
#  2005-05-01 Ola Lundqvist <ola@inguza.com>
#	Bug fix for bzip2 support.
#  2005-05-06 Daniel Leidert <daniel.leidert@wgdd.de>
#       Add setting to enable/disable signature checking in distinput-dirs.
#  2005-09-09 Ola Lundqvist <ola@inguza.com>
#       Support for gpg password file.
#  2005-09-15 Daniel Leidert <daniel.leidert.spam@gmx.net>
#       Fix regarding $gpgpassfile.
#  2005-10-08 Ola Lundqvist <ola@inguza.com>
#	Now invokes a helper program to sign the files. It may be implemented
#	by some perl module but this solution was good enough.
#  2005-10-11 Daniel Leidert <daniel.leidert@wgdd.de>
#	Removed fix regarding $gpgpassfile (moved to checks below).
#  2005-10-12 Daniel Leidert <daniel.leidert@wgdd.de>
#	Fix signcmd default.
#  2005-10-14 Daniel Leidert <daniel.leidert@wgdd.de>
#	Remove signcmd variable.
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Allow forcing an install of an upload (i.e., ignore existing files in
#       destdir).
#  2007-10-09 Ola Lundqvist <ola@inguza.com>
#       Changed force option to ignoredestcheck option.
#  2009-03-16 Franck Joncourt <franck.mail@dthconnex.com>
#       Added usermailcmd, mailsearch, usermailcmd and cmds. Removed mailcmd.
#  2016-06-11 Ola Lundqvist <ola@inguza.com>
#       Make it possible to disable email sending.
#  2016-11-14 Ola Lundqvist <ola@inguza.com>
#       Made it possible to have command line options to the verify command.
#       The change is based on ideas from Ron Lee.

$mailformat    = "";
$usermailcmd   = '';

%cmds = ();
$cmds{'sendmail'} = "sendmail";
$cmds{'mail'}     = "mail";

$copycmd = "cp -af";
$rmcmd = "rm -f";
$movecmd = "mv";
$vrfycmd = "dscverify";
$cachedir = "/var/cache/debarchiver";
$inputdir = "/var/lib/debarchiver/incoming";
$destdir = "/var/lib/debarchiver/dists";
$cinstall = "installed";
$lockfile = "debarchiver.lock";
$etcconfigfile = "/etc/debarchiver.conf";
$inputconfigfile = "input.conf";
$verifysignatures = 0;
$verifysignaturesdistinput = 0;
$userconfigfile = "$ENV{HOME}/.debarchiver.conf";
$bzip = 0;
$gpgpassfile = "$ENV{HOME}/.gnupg/passphrase";

###############################################################################
########################## DECLARATION ########################################
###############################################################################
# Changelog:
#  2000-2004 Ola Lundqvist <ola@inguza.com>
#	Written
#  2007-10-08 Ola Lundqvist <ola@inguza.com>
#       Updated with new options.
#  2007-10-09 Ola Lundqvist <ola@inguza.com>
#       Changed force option to ignoredestcheck option.
#  2013-11-14 Ola Lundqvist <ola@inguza.com>
#       Introduced DMeta for pure Deb only cases.

# Indexed by config name.
%CConf = ();
# Indexed by meta type.
%CMeta = ();
# Indexed by meta type.
%DMeta = ();
# Indexed by file name.
%CFiles = ();
# Indexed by package name.
%CDesc = ();
# Just a string describing what has changed.
$CChanges = "";
# Destination directories that should be scanned.
%dests = ();
# Information to add to Release files.
%release = ();
# The criteria to use for which binary packages that does not need a .changes
# file.
$distinputcriteria = "^linux.*\\.deb\$";
# Extra directories with specified destination. Where to find for distinput
# files.
%distinputdirs = (
		  'stable' => 'stable',
		  'testing' => 'testing',
		  'unstable' => 'unstable'
		  );

@distributions = ('stable', 'testing', 'unstable');

%distmapping = (
		'stable' => 'lenny',
		'testing' => 'squeeze',
		'unstable' => 'sid'
		);

@architectures = ('i386');

@sections = ('main', 'contrib', 'non-free');

# Default major
$majordefault = 'main';

@mailtos = ();

$mailfrom = "";

@ARGS1 = @ARGV;
@ARGS2 = ();

$incompletetime = 24*60*60;
$sortpackages = 1;
$fixstructure = 1;
$ignoredestcheck = 0;
$errorarea = "";

###############################################################################
############################# ARGS ############################################
###############################################################################
# Changelog:
#  2000-2004 Ola Lundqvist <ola@inguza.com>
#	Written
#  2005-10-08 Ola Lundqvist <ola@inguza.com>
#	Added the possibility to specify a config file on command line.
#	Inspired by a patch from Alexander Wirt <formorer@debian.org>.

while ($_ = shift @ARGS1) {
    if (/^-[a-zA-Z0-9]/) {
	if (length($_) > 1) {
	    s/^-//;
	    foreach $_ (split /(.)/, $_) {
		if (length($_) > 0) {
		    @ARGS1 = ("-$_", @ARGS1);
		}
	    }
	    $_ = shift @ARGS1;
	}
	else {
	    pdebug(2, "Unknown option $_.");
	}
    }
    if (/^-/) {
	if (/^--dl$/ || /^--debug-level$/) {
	    setDebugLevel(shift @ARGS1);
	}
	elsif (/^--ql$/ || /^--quit-level$/) {
	    setQuitLevel(shift @ARGS1);
	}
	elsif (/^--configfile$/) {
	    $cmdlineconfigfile = shift @ARGS1;
	}
	elsif (/^-i$/ || /^--input$/ || /^--indir$/ || /^--inputdir$/) {
	    $inputdir = shift @ARGS1;
	    $inputdir =~ s/\/$//;
	}
	else {
	    push @ARGS2, $_;
	}
    }
    else {
	push @ARGS2, $_;
    }
}

###############################################################################
############################ CONFIG ###########################################
###############################################################################
# Changelog:
#  2000-2004 Ola Lundqvist <ola@inguza.com>
#	Written
#  2005-10-08 Ola Lundqvist <ola@inguza.com>
#	Added the possibility to specify a config file on command line.
#	Inspired by a patch from Alexander Wirt <formorer@debian.org>.
#  2007-08-14 Ola Lundqvist <ola@inguza.com>
#       Changed severity level for configuration file problems from info
#       to warning, so that it is displayed in the normal case.

if (-e $etcconfigfile) {
    my $t = do $etcconfigfile;
    unless ($t) {
	pdebug(3, "Loading config file $etcconfigfile:\n\t$!\n\t$@");
    }
}

if (-e $userconfigfile) {
    my $t = do $userconfigfile;
    unless ($t) {
	pdebug(3, "Loading config file $userconfigfile:\n\t$!\n\t$@");
    }
}

if (-e $cmdlineconfigfile) {
    my $t = do $cmdlineconfigfile;
    unless ($t) {
	pdebug(3, "Loading config file $cmdlineconfigfile:\n\t$!\n\t$@");
    }
}

###############################################################################
######################### INPUT CONFIG ########################################
###############################################################################
# Changelog:
#  2000-2004 Ola Lundqvist <ola@inguza.com>
#	Written
#  2007-08-14 Ola Lundqvist <ola@inguza.com>
#       Changed severity level for configuration file problems from info
#       to warning, so that it is displayed in the normal case.
#  2016-11-14 Ola Lundqvist <ola@inguza.com>
#       Add inputdir to @INC as current directory (.) is disabled in perl
#       5.26. It is removed as soon as possible.

action(! chdir $inputdir, "Change to dir $inputdir", 2);

if (-e $inputconfigfile) {
    # Add current directory to search path
    push @INC, $inputdir;
    my $t = do $inputconfigfile;
    unless ($t) {
	pdebug(3, "Loading config file $inputconfigfile:\n\t$!\n\t$@");
    }
    pop @INC;
}

###############################################################################
############################# CHECKS ##########################################
###############################################################################
# Changelog:
#  2005-10-11 Daniel Leidert <daniel.leidert@wgdd.de>
#	Written

if ($gpgpassfile) {
	$gpgpassfile = "" if (! -f $gpgpassfile);
}
else {
	$gpgpassfile = "";
}
				

###############################################################################
############################# HELP ############################################
###############################################################################
# Changelog:
#  2000-2004 Ola Lundqvist <ola@inguza.com>
#	Written
#  2005-09-09 Ola Lundqvist <ola@inguza.com>
#       Added information about gpg support.
#  2005-10-08 Ola Lundqvist <ola@inguza.com>
#	Added the possibility to specify a config file on command line.
#	Inspired by a patch from Alexander Wirt <formorer@debian.org>.
#	Now invokes a helper program to sign the files. It may be implemented
#	by some perl module but this solution was good enough.
#  2005-10-14 Daniel Leidert <daniel.leidert@wgdd.de>
#	Removed signcmd.
#  2006-02-25 Yaroslav Halchenko <debian@onerussian.com> and
#             Ola Lundqvist <ola@inguza.com>
#       Default major section function.
#  2006-11-28 Ola Lundqvist <ola@inguza.com>
#       Sorted options in alphabetical order.
#  2007-10-08 Ola Lundqvist <ola@inguza.com>
#       Make it possible to specify mail sender.
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Allow forcing an install of an upload (i.e., ignore existing files in
#       destdir).
#  2007-10-09 Ola Lundqvist <ola@inguza.com>
#       Changed force option to ignoredestcheck option.
#  2009-03-16 Franck Joncourt <franck.mail@dthconnex.com>
#       Modified mailcmd and added mailformat option.
#  2009-03-16 Ola Lundqvist <ola@inguza.com>
#       Changed to version 0.9.
#  2011-11-02 Ola Lundqvist <ola@inguza.com>
#       Improved english lanauge.
#  2013-11-13 Ola Lundqvist <ola@inguza.com>
#       Changed to version 0.10.

$version = "0.10";
$versionstring = "Debian package archiver, version $version";

$help =
    "Usage: debarchiver [option(s)]

options:
 -a | --autoscan        - Does both --autoscanpackages and --autoscansources.
                          Use this *or* --index, not both.
 --autoscanall          - Same as --scanall --autoscan.
 --autoscanpackages     - Automaticly run dpkg-scanpackages after all new
                          packages are installed.
 --autoscansources      - Automaticly run dpkg-scansources after all new
                          packages are installed.
 -b | --bzip            - Create bzip2 compressed Packages.bz2 and Sources.bz2
                          files.
 --cachedir dir         - The apt-ftparchive package cache directory to use if
                          --index is used.  Default \"/var/cache/debarchiver\".
 --cinstall dir         - Where the .changes file will be installed to. Use the
                          empty string to remove the .changes file instead.
                          The default is \"installed\".
 --configfile file      - Specifies an extra configuration file to read. Will be
                          read after etc configuration and after user configuration
                          files.
 --copycmd              - The install command to use where the default is \"cp -af\".
                          Both packages and .changes files are installed using
                          this command.
 -d | --dest dir        - Destination directory. The base directory where all
 --destdir dir            the distribution packages will reside and where the
                          \$distrib/\$major/\$arch/\$section directory
                          structure will be created.
                          The default is /var/lib/debarchiver/dists.
 --debug-level level    - What information that should be printed.
  --dl level                1 = critical, 2 = error, 3 = normal,
                            4 = message, 5 = debug, 6 = verbose debug (modules).
 --distinputcriteria    - The criteria for what binary packages should be
                          installed even they do not have a .changes file.
                          The default criteria is \"^linux.*\\.deb\$\".
 --gpgkey               - The GnuPG key to use to sign the archive.
 --gpgpassfile          - The file that provides the password to GnuPG.
 --help                 - Prints this information.
 -i | --input dir       - This is the directory where debarchiver will look for
  --indir dir             new package versions and corresponding *.changes files that
  --inputdir dir          should be installed to the --dest directory.
                          The default directory is
                          /var/lib/debarchiver/incoming.
 --ignoredestcheck      - Force install of .changes file even if some files specified
                          in the .changes file already exists with wrong size or md5
                          hash.
 --index | -x           - Automatically run apt-ftparchive after all new
                          packages are installed.  Use this *or* --autoscan,
                          not both.
 --incompletetime       - The time to allow .changes file to be incomplete in
                          seconds. The default is 24 hours.
 --instcmd              - DEPRICATED!
 --lockfile file        - The lockfile to use. The default is \"debarchiver.lock\".
 --mailcmd              - The mail command to use. The default is to use the
                          \"sendmail\" command. You can disable email sending
                          by specifying the /bin/true command.
 --mailformat format    - Defines the format to be used to send emails. It should
                          correspond to the format used by the command specified by
                          --mailfrom. Only 'sendmail' and 'mail' formats are
                          supported. By default debarchiver assumes 'sendmail'
                          format. The format argument can be one of the following:
                            sendmail = use of the sendmail format
                            mail     = use of the mail format
 --mailfrom             - Specifies mail sender.
 --majordefault section - The default major section to use. The default is 'main'.
 --movecmd              - Command used to move files (currently not used at all).
 --nosort               - Do not sort packages.
 --nostructurefix       - Do not create directories and touch 'Package' files.
 -o | --addoverride     - Automaticly add new packages to the override file.
 --quit-level level     - On what level to quit the application. See debug
                          level for further information.
 --rmcmd                - The remove command to use. The default is \"rm -f\".
                          This can be used to move away the old packages to
                          some other place.
 --scanall              - Scan all distributions, sections, etc.
 --scandetect | -s      - Scan using 'apt-ftparchive' or 'dpkg-scan*'
                          (dpkg-scanpackages and dpkg-scansources) depending on what
                          is installed on the system. This is the recommended way.
                          Only use --index or --autoscan if you know what you are
                          doing.
 --scanonly             - Same as --nosort --nostructurefix.
 -v | --version         - Prints the version string.

You can also place configuration files with the following names (in the following
order) /etc/debarchiver.conf, ~/.debarchiver.conf and input.conf
(relative to input dir), that will be read before the arguments to this program
will be parsed. In the above files you can change the following variables:
     \$bzip2             - If set to 0 no bzip2 files will be generated. If set to
                           1 bzip2 files will be generated.
     \$cachedir          - The cache directory for apt-ftparchive used if
                          --index is used.
     \$cinstall          - Where the .changes files are installed
                          (see --cinstall above).
     \$copycmd           - The install command (see --copycmd).
     \$destdir           - The destination directory (see --destdir above).
     \$distinputcriteria - The criteria for which packages that should be
                          installed even if it does not have a .changes file.
                          The default is \"^linux.*\\.deb\$\".
     \%distinputdirs     - The directories (distribution => dir) that should be
                          searched for extra binary packages that does not need
                          a .changes file to be installed but match
                          \$distinputcriteria.
     \$gpgkey            - The GnuPG key to use to sign the archive.
     \$gpgpassfile       - The file that will provide the password to GnuPG.
     \$inputdir          - The input directory (no effect in \"input.conf\").
     \$ignoredestcheck   - Force install of .changes file even if some files
                          specified in the .changes file already exists with wrong
                          size or md5 hash. The default is 0 (do not ignore).
     \$incompletetime    - The time to allow .changes file to be incomplete in
                          seconds. The default is 24 hours.
     \$lockfile          - The lockfile to use. The default is \"debarchiver.lock\".
     \$mailformat        - The format to use to send emails (see --mailformat
                          above).
     \$mailfrom          - Specify the mail sender.
     \@mailtos           - The fields in .changes file that should be used for
                          mailing SUCCESS and REJECT messages. If there is an
                          @ char in the array that address will be used directly.
     \$majordefault      - Default major section (see --majordefault above).
     \$movecmd           - The move command (see --movecmd).
     \%release           - Additional information to add to generated Release
                          files. Supported keys are 'origin', 'label', and
                          'description'.
     \$rmcmd             - The remove command (see --rmcmd above).
     \$usermailcmd       - It allows the user to tell debarchiver to use a
                          specific command to send emails. You may also want to
                          specify the mailformat your mail command handles
                          by setting the value of the \$mailformat variable.
                          Using the --mailcmd option on the command line will
                          superseed this variable.
                          You can disable email sending by specifying the
                          /bin/true command.
";

###############################################################################
############################# ARGS ############################################
###############################################################################
# Changelog:
#  2000-2004 Ola Lundqvist <ola@inguza.com>
#	Written
#  2005-05-01 Daniel Leidert <daniel.leidert.spam@gmx.net>
#	Added bzip2 support.
#  2005-09-09 Ola Lundqvist <ola@inguza.com>
#       Added options for gpg signing support.
#  2006-02-25 Yaroslav Halchenko <debian@onerussian.com> and
#             Ola Lundqvist <ola@inguza.com>
#       Default major section function.
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Allow forcing an install of an upload (i.e., ignore existing files in
#       destdir).
#  2007-10-09 Ola Lundqvist <ola@inguza.com>
#       Changed force option to ignoredestcheck option.

while ($_ = shift @ARGS2) {
    if (/^-[a-zA-Z0-9]/) {
	if (length($_) > 1) {
	    s/^-//;
	    foreach $_ (split /(.)/, $_) {
		if (length($_) > 0) {
		    @ARGS1 = ("-$_", @ARGS1);
		}
	    }
	    $_ = shift @ARGS1;
	}
	else {
	    pdebug(2, "Unknown option $_.");
	}
    }
    if (/^-/) {
	if (/^-v$/ || /^--version$/) {
	    print("$versionstring\n");
	    exit(0);
	}
	elsif (/^--help$/) {
	    print($help);
	    exit(0);
	}
	elsif (/^--copycmd$/) {
	    $copycmd = shift @ARGS2;
	}
	elsif (/^--movecmd$/) {
	    $movecmd = shift @ARGS2;
	}
        elsif (/^--mailcmd$/) {
            $usermailcmd = shift @ARGS2;
        }
        elsif (/^--mailformat$/) {
            $mailformat = shift @ARGS2;
        }
	elsif (/^--mailfrom$/) {
	    $mailfrom = shift @ARGS2;
	}
	elsif (/^--incompletetime$/) {
	    $incompletetime = shift @ARGS2;
	}
	elsif (/^--rmcmd$/) {
	    $rmcmd = shift @ARGS2;
	}
	elsif (/^-d$/ || /^--destdir$/ || /^--dest$/) {
	    $destdir = shift @ARGS2;
	    $destdir =~ s/\/$//;
	}
	elsif (/^--majordefault$/) {
	    $majordefault = shift @ARGS2;
	    $majordefault =~ s/\/$//;
	}
	elsif (/^--cachedir$/) {
	    $cachedir = shift @ARGS2;
	}
	elsif (/^--lockfile$/) {
	    $lockfile = shift @ARGS2;
	}
	elsif (/^--cinstall$/) {
	    $cinstall = shift @ARGS2;
	    $cinstall =~ s/\/$//;
	}
	elsif (/^-o$/ || /^--addoverride$/) {
	    $addoverride = 1;
	}
	elsif (/^--gpgkey$/) {
	    $gpgkey = shift @ARGS2;
	}
	elsif (/^--gpgpassfile$/) {
	    $gpgpassfile = shift @ARGS2;
	}
	elsif (/^--autoscanpackages$/) {
	    $autoscanpackages = 1;
	}
	elsif (/^--autoscansources$/) {
	    $autoscansources = 1;
	}
	elsif (/^-a$/ || /^--autoscan$/) {
	    $autoscanpackages = 1;
	    $autoscansources = 1;
	}
	elsif (/^-x$/ || /^--index$/) {
	    $indexall = 1;
	}
	elsif (/^-s$/ || /^--scandetect$/) {
	    if (-x "/usr/bin/apt-ftparchive") {
		$indexall = 1;
	    }
	    else {
		if (-x "/usr/bin/dpkg-scansources") {
		    $autoscansources = 1;  
		}
		if (-x "/usr/bin/dpkg-scanpackages") {
		    $autoscanpackages = 1;  
		}
	    }
	}
	elsif (/^-b$/ || /^--bzip$/) {
	    $bzip = 1;
	}
	elsif (/^--distinputcriteria/) {
	    $distinputcriteria = shift @ARGS2;
	}
	elsif (/^--scanall$/) {
	    $scanall = 1;
	}
	elsif (/^--autoscanall$/) {
	    $scanall = 1;
	    $autoscanpackages = 1;
	    $autoscansources = 1;
	}
	elsif (/^--scanonly$/) {
	    undef $sortpackages;
	    undef $fixstructure;
	}
	elsif (/^--ignoredestcheck$/) {
	    $ignoredestcheck = 1;
	}
	elsif (/^--nosort$/) {
	    undef $sortpackages;
	}
	elsif (/^--nostructurefix$/) {
	    undef $fixstructure;
	}
	else {
	    pdebug(2, "Unknown option $_\n");
	}
    }
    else {
        pdebug(2, "Unknown option $_\n");
    }
}

&check_mailconfig();
&check_commands({}, {});

###############################################################################
############################# START ###########################################
###############################################################################

###############################################################################
# Now create the directory structure and files that are needed.
###############################################################################

handleStructureFix();

###############################################################################
# Fix so that it scan all distributions, sections and so on.
###############################################################################

if (defined $scanall) {
    handleScanAll();
}

###############################################################################
# Sort packages.
###############################################################################

handleSorting();

if (defined $indexall) {
    handleIndex();
} else {
    handleScan();
}

###############################################################################
########################### FUNCTIONS #########################################
###############################################################################

###############################################################################
# Name:		createPF
# Description:	Create the directory and file if it does not exist,
#		including the .gz file.
# Arguments:	directory, filename
# Changelog:
#  2001-07-14 Ola Lundqvist <ola@inguza.com>
#	Written.
###############################################################################

sub createPF($$) {
    my ($dir, $file) = @_;
    if (! -d "$dir") {
	action(! mkpath($dir, 0, 0755),
	       "Create directory $dir",
	       2);
    }
    if (! -e "$dir/$file") {
	cmdaction("touch $dir/$file",
		  "Create file $dir/$file.",
		  2);
    }
    if (! -e "$dir/${file}.gz") {
	cmdaction("gzip -c $dir/$file > $dir/${file}.gz",
		  "Create file $dir/$file.gz from $dir/$file.",
		  3);
    }
}

###############################################################################
# Name:		createRelease
# Description:	Create a Release file.
# Arguments:	directory, distribution, section, architecture
# Uses:         %release
# Changelog:
#  2004-08-09 Ola Lundqvist <ola@inguza.com>
#	Written.
#  2004-08-10 Ola Lundqvist <ola@inguza.com>
#	Renamed $release to $contents. Don't generate if any under a symlink.
###############################################################################

sub createRelease($$$$) {
    my ($dir, $distribution, $section, $architecture) = @_;
    my $contents = '';
    $contents .= "Archive: $distribution\n";
    $contents .= "Component: $section\n";
    $contents .= "Label: $release{label}\n" if defined $release{label};
    $contents .= "Origin: $release{origin}\n" if defined $release{origin};
    $contents .= "Architecture: $architecture\n";
    $contents .= "Description: $release{description}\n"
	if defined $release{description};
    $contents .= "\n";

    # Don't generate a Release file if any level of the directory is a symlink,
    # since otherwise for a testing -> unstable symlink, we'll keep regenerating
    # the Release file, first for testing and then for unstable.  Assume that
    # we'll also be called with the non-symlink path and create the Release file
    # then.
    my @components = split('/', $dir);
    for (my $i = 0; $i < @components; $i++) {
	my $testdir = join ('/', @components[0..$i]);
	if (-l "$testdir") {
	    return;
	}
    }

    # If the release file already exists, read it to see if anything has
    # changed.  Don't recreate the file unless we're actually changing anything,
    # to avoid unnecessary timestamp updates.
    if (-e "$dir/Release") {
	action(! open(REL, "$dir/Release"), "Read Release file in $dir", 2);
	local $/;
	my $old = <REL>;
	close REL;
	if ($contents ne $old) {
	    action(! open(REL, "> $dir/Release"), "Update Release file in $dir", 2);
	    print REL $contents;
	    close REL;
	}
    } else {
	action(! open(REL, "> $dir/Release"), "Create Release file in $dir", 2);
	print REL $contents;
	close REL;
    }
}

###############################################################################
######################### EMAIL HANDLING ######################################
###############################################################################

###############################################################################
# Name:		determineMailTo
# Description:	Determine the address to set mail to.
# Uses:		%CConf, %CMeta hash.
# Changelog:
#  2003-02-12	Ola Lundqvist <ola@inguza.com>
#	Wrote it.
#  2003-02-13	Ola Lundqvist <ola@inguza.com>
#	Extended it with @hostname calculation.
#  2003-02-28 Ola Lundqvist <ola@inguza.com>
#	Added debugging information.
#  2003-03-14 Ola Lundqvist <ola@inguza.com>
#	Switched to using CMeta for ChangeLog meta information.
#  2003-06-10 Ola Lundqvist <ola@inguza.com>
#	Switched from direct determination of changes owner to use
#	precalculated data from CMeta{FileOwner}.
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Change in foreach to use my variable.
#  2010-04-17 Mats Erik Andersson <mats.andersson@gisladisker.se>
#       Correction of debug for sendlist.
#  2010-04-22 Ola Lundqvist <ola@inguza.com>
#       Extended the suggestion from Mats to make sure the list is properly
#       ordered.
###############################################################################

sub determineMailTo() {
    my $to = "";
    my %to_hash = ();
    foreach my $toi (@mailtos) {
	# Expand to email if there is no email address.
	if ($toi !~ /\@/) {
	    $toi = $CConf{$toi};
	}
	# Expand to full email address from @hostname field.
	if ($toi =~ /^\@/) {
	    $toi = "$CMeta{FileOwner}$toi";
	    # If still the same...
	    if ($toi =~ /^\@/) {
		pdebug(3, "No file owner has been determined, so email address can not be calculated.");
		$toi = "";
	    }
	}
	if ($toi !~ /^\s*$/) {
	    if (! defined $to_hash{$toi}) {
		if ($to eq "") {
		    $to = $toi;
		}
		else {
		    $to = $to . ", " . $toi;
		}
		$to_hash{$toi} = 1;
	    }
	}
    }
    chomp $to;
    pdebug(5, "Mail will be sent to $to.");
    return $to;
}

###############################################################################
# Name:		email
# Description:	Send an email to persons, for package with message.
# Arguments:	to, package, key, message
# Changelog:
#  2002-09-11 Ola Lundqvist <ola@inguza.com>
#	Stub written.
#  2003-02-12 Ola Lundqvist <ola@inguza.com>
#	Writen the mail sending function.
#  2003-02-28 Ola Lundqvist <ola@inguza.com>
#	Added debugging information and fixed arg handling.
#  2003-03-13 Ola Lundqvist <ola@inguza.com>
#	Debugged the mail command. It stalls.
#  2007-10-08 Ola Lundqvist <ola@inguza.com>
#       Make it possible to specify mail sender.
#  2009-03-16 Franck Joncourt <franck.mail@dthconnex.com>
#       Added support for sendmail in addition to mail command format.
#  2016-06-12 Ola Lundqvist <opal@debian.org>
#       Will simply ignore sending emails if the receipient list is empty.
###############################################################################
sub email($$$) {
    my ($toAddress, $subject, $msg) = @_;

    pdebug(5, "Sending mail ...");

    if ( $use_sendmail && ($mailfrom eq "") ) {
        pdebug(5, "No sender mail address found, use of the debarchiver user instead.");
    }

    my $err=1;
    if ($toAddress eq "") {
        pdebug(3, "No recipient to send mail to. No email sent.");
	return;
    } elsif ($subject eq "") {
        pdebug(3, "Empty subject");
    } elsif ($msg eq "") {
        pdebug(3, "Empty message")
    } else {
        $err = 0;
    }

    if ($err) {
        pdebug(2, "No mail sent due to missing parameters");
    } elsif (defined $cmds{'sendmail'}) {
        pdebug(4, "Use of the sendmail command: $cmds{'sendmail'}");
        if (open(M, "| $cmds{'sendmail'} -t")) {
            print M "From: $mailfrom\n" unless ($mailfrom eq "");
            print M "To: $toAddress\n",
                    "Subject: $subject\n\n",
                    $msg . "\n";
            close(M);
        } else {
            pdebug(2, "Could not execute $cmds{'sendmail'} $!");
        }
    } else {
        pdebug(4, "Use of the mail command: $cmds{'mail'}");
        if (open(M, "| $cmds{'mail'} -s '$subject' '$toAddress'")) {
            print M $msg . "\n";
            close(M);
        } else {
            pdebug(2, "Could not execute $cmds{'mail'} $!");
        }
    }

    pdebug(5, "Mail exec done.");
}

###############################################################################
# Name:		mailSuccessChanges
#		including the .gz file.
# Uses:		%CMeta and maybe %Cfiles in the future.
# Changelog:
#  2002-09-11	Ola Lundqvist <ola@inguza.com>
#	Written.
#  2003-02-12	Ola Lundqvist <ola@inguza.com>
#	Uses CConf instead of cfile argument.
#  2003-03-14 Ola Lundqvist <ola@inguza.com>
#	Switched to using CMeta for ChangeLog meta information.
#  2009-03-16 Franck Joncourt <franck.mail@dthconnex.com>
#       Small modification.
#  2013-11-13 Ola Lundqvist <ola@inguza.com>
#       Changed name from mailSuccess to mailSuccessChanges to clarify what
#       situation this function is used.
###############################################################################

sub mailSuccessChanges() {
    # We can not read that file after it has been moved!
    my $message   = $CMeta{ChangesContent};
    my $subject   = "$CConf{'Source'} ACCEPTED";
    my $recipient = determineMailTo();
    pdebug(5, "Mail Success.");
    email($recipient, $subject, $message);
}

###############################################################################
# Name:		mailSuccessDeb
# Uses:		$CConf{Binary}, %DMeta
# Changelog:
#  2013-11-13 Ola Lundqvist <ola@inguza.com>
#       Written based on mailSuccessChanges
###############################################################################

sub mailSuccessDeb() {
    # We can not read that file after it has been moved!
    my $file  = $DMeta{DebFile};
    my $message   = "$file\n".
	"----------------------------------------------------------------\n".
	"\n$DMeta{DebContent}\n";
    my $subject   = "$CConf{Binary} ACCEPTED";
    my $recipient = determineMailTo();
    pdebug(5, "Mail Success.");
    email($recipient, $subject, $message);
}

###############################################################################
# Name:		mailRejectChanges
# Uses:		%CMeta and maybe %Cfiles in the future.
# Changelog:
#  2002-09-12	Ola Lundqvist <ola@inguza.com>
#	Written using data from mailSuccessChanges.
#  2003-02-12	Ola Lundqvist <ola@inguza.com>
#	Uses CConf instead of cfile argument.
#  2003-03-14   Ola Lundqvist <ola@inguza.com>
#	Switched to using CMeta for ChangeLog meta information.
#  2007-10-08   Turbo Fredriksson <turbo@bayour.com>
#       Error string in beginning and full message (+= => .=).
#  2009-03-16 Franck Joncourt <franck.mail@dthconnex.com>
#       Small modification.
#  2013-11-06 Ola Lundqvist <ola@inguza.com>
#       Changed name from mailReject to mailRejectChanges to clarify that
#       it just handle changes files.
###############################################################################

sub mailRejectChanges() {
    # We can not read that file after it has been moved!
    my $message;
    if (length($CConf{ERROR}) > 0) {
        $message = "ERROR:\n$CConf{ERROR}\n";
    }
    $message     .= $CMeta{ChangesContent};
    my $subject   = "$CConf{'Source'} REJECTED";
    my $recipient = determineMailTo();
    pdebug(5, "Mail Reject.");
    email($recipient, $subject, $message);
}

###############################################################################
# Name:		mailRejectDeb
# Uses:		%DMeta
# Changelog:
#  2013-11-13 Ola Lundqvist <ola@inguza.com>
#       Function written based on mailRejectChanges.
###############################################################################

sub mailRejectDeb() {
    # We can not read that file after it has been moved!
    my $message = "ERROR:\nIncomplete upload of $DMeta{DebFile} and older than $incompletetime seconds.\n";
    my $subject = "$DMeta{DebFile} REJECTED";
    my $recipient = determineMailTo();
    pdebug(5, "Mail Reject.");
    email($recipient, $subject, $message);
}

###############################################################################
########################### HANDLERS ##########################################
###############################################################################

###############################################################################
# Name:		handleScanAll
# Description:	Fix so that it scan all distributions, sections and so on.
# Changes:	%dests
# Uses:		@distributions, @sections, @architectures, $destdir.
# Changelog:
#  2001-07-23 Ola Lundqvist <ola@inguza.com>
#	Written.
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Change in foreach to use my variable.
###############################################################################

sub handleScanAll() {
    foreach my $d (@distributions) {
	foreach my $s (@sections) {
	    if (-e "$destdir/$d/$s/override") {
		foreach my $a (@architectures) {
		    $dests{"$d/$s/binary-$a"} = 1;
		}
		$dests{"$d/$s/binary-all"} = 1;
	    }
	    if (-e "$destdir/$d/$s/override.src") {
		$dests{"$d/$s/source"} = 1;
	    }
	}
    }
}

###############################################################################
# Name:		handleScan
# Description:	Handles the autoscan.
# Uses:		%dests, $destdir,
#		$autoscanpackages, $autoscansources.
# Changes:	$ENV{PWD}
# Changelog:
#  2001-06-26 Ola Lundqvist <ola@inguza.com>
#	Written.
#  2001-07-23 Ola Lundqvist <ola@inguza.com>
#	Added lockfile check to distr directory.
#	Improved documentation.
#  2002-01-22 Ola Lundqvist <ola@inguza.com>
#	Moved lock file checking to its own function.
#  2003-02-12 Ola Lundqvist <ola@inguza.com>
#	Now redirects stderr to stdout for
#	dpkg-scan* so that it can be logged.
#  2005-05-01 Daniel Leidert <daniel.leidert.spam@gmx.net>
#	Modified to add bzip2 support.
#  2005-05-02 Ola Lundqvist <ola@inguza.com>
#	Bugfix for bzip2 support.
###############################################################################

sub handleScan() {
    if (defined $autoscansources || defined $autoscanpackages) {
	$destdir =~ s|/$||;

	action(! chdir $destdir, "Change to dir $destdir", 2);
	&destinationLock();

	my $destddir = $destdir;
	$destddir =~ s|^.*/([^/]+)$|$1|;
	my $destcdir = $destdir;
	$destcdir =~ s|^(.*)/[^/]+$|$1|;
	action(! chdir $destcdir, "Change to dir $destcdir", 2);

	foreach $_ (keys %dests) {
	    my $archdest = $_;
	    $archdest = "$destddir/$archdest";
	    my $over = $_;
	    $over =~ s/^(.*)\/[^\/]+$/$1/;
	    $over = "$destddir/$over";
	    if ($archdest =~ /source$/ && defined $autoscansources) {
		cmdaction("dpkg-scansources $archdest $over/override.src 2>&1 > $archdest/Sources",
			  "Scan source files in $archdest, $over/override.src",
			  3);
		cmdaction("gzip $archdest/Sources -c > $archdest/Sources.gz",
			  "Gzip $archdest/Sources",
			  3);
		if ($bzip) {
		    cmdaction("bzip2 $archdest/Sources -c > $archdest/Sources.bz2",
			      "BZip $archdest/Sources",
			      3);
		}
	    }
	    elsif (defined $autoscanpackages) {
		cmdaction("dpkg-scanpackages $archdest $over/override 2>&1 > $archdest/Packages.gen",
			  "Scan package files in $archdest, $over/override",
			  3);
		if ($archdest =~ /binary-all$/) {
		    opendir DD, $over;
		    my $d;
		    while ($d = readdir(DD)) {
			if (! ($d =~ /^binary-all/) &&
			    $d =~ /^binary-/ &&
			    -d "$over/$d") {
			    if (-f "$over/$d/Packages.gen") {
				cmdaction("cat $over/$d/Packages.gen $archdest/Packages.gen > $over/$d/Packages",
					  "Concatenate packages files from binary-all and $d.",
					  3);
			    }
			    else {
				cmdaction("cat $archdest/Packages.gen > $over/$d/Packages",
					  "Copy packages file from binary-all to $d.",
					  3);
			    }
			    cmdaction("gzip $over/$d/Packages -c > $over/$d/Packages.gz",
				      "Gzip $over/$d/Packages",
				      3);
			    if ($bzip) {
				cmdaction("bzip2 $over/$d/Packages -c > $over/$d/Packages.bz2",
					  "BZip $over/$d/Packages",
					  3);
			    }
			}
		    }
		    closedir DD;
		}
		else {
		    if (-f "$over/binary-all/Packages.gen") {
			cmdaction("cat $archdest/Packages.gen $over/binary-all/Packages.gen > $archdest/Packages",
				  "Concatenate packages files from binary-all and $d.",
				  3);
		    }
		    else {
			cmdaction("cat $archdest/Packages.gen > $archdest/Packages",
				  "Copy packages file from $d.",
				  3);
		    }
		    cmdaction("gzip $archdest/Packages -c > $archdest/Packages.gz",
			      "Gzip $archdest/Packages",
			      3);
		    if ($bzip) {
			cmdaction("bzip2 $archdest/Packages -c > $archdest/Packages.bz2",
				  "BZip $archdest/Packages",
				  3);
		    }
		}
	    }
	}

	&destinationRelease();
    }
}

###############################################################################
# Name:		findSectionsArchitectures
# Description:	Find sections and architectures in a distribution.
# Arguments:    Path to distribution directory to check,
#               reference to section array to fill out,
#               reference to architectures array to fill out
# Changelog:
#  2004-08-10 Ola Lundqvist <ola@inguza.com>
#      Written.
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Change in foreach to use my variable.
###############################################################################

sub findSectionsArchitectures($\@\@) {
    my ($dir, $sectionlist, $archlist) = @_;
    my (%dirsections, %dirarches);
    foreach my $s (@sections) {
	if (-e "$dir/$s/override") {
	    foreach my $a (@architectures) {
		$dirarches{$a} = 1;
	    }
	    $dirarches{all} = 1;
	    $dirsections{$s} = 1;
	}
	if (-e "$dir/$s/override.src") {
	    $dirarches{source} = 1;
	    $dirsections{$s} = 1;
	}
    }

    # Do things this way so that the lists are in the same order as @sections
    # and @architectures.  Purely aesthetic.
    @$sectionlist = grep { $dirsections{$_} } @sections;
    @$archlist = grep { $dirarches{$_} } @architectures, 'all', 'source';
}

###############################################################################
# Name:		generateIndexConfig
# Description:	Generate an apt-ftparchive configuration for the archive.
# Uses:		%dests, $destdir, $cachedir
# Returns:      Path to the generated config file
# Changelog:
#  2004-08-10 Ola Lundqvist <ola@inguza.com>
#	Written.
#  2005-05-01 Daniel Leidert <daniel.leidert.spam@gmx.net>
#	Modified to add bzip2 support.
#  2005-05-02 Ola Lundqvist <ola@inguza.com>
#	Bugfix for bzip2 support.
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Change in foreach to use my variable.
###############################################################################

sub generateIndexConfig() {
    my $destcdir = $destdir;
    $destcdir =~ s|^(.*)/[^/]+$|$1|;

    my $configpath = "$destdir/.apt-ftparchive.conf";
    action(! open(CONF, "> $configpath"), "Create apt-ftparchive config", 2);

    # The common header.
    print CONF "Dir {\n";
    print CONF "  ArchiveDir \"$destcdir\";\n";
    print CONF "  Cachedir \"$cachedir\";\n";
    print CONF "};\n\n";
    print CONF "Default {\n";
    print CONF "  Packages::Compress \". gzip bzip2\";\n"
	if ($bzip);
    print CONF "  Sources::Compress \". gzip bzip2\";\n"
	if ($bzip);
    print CONF "  Contents::Compress \". gzip\";\n";
    print CONF "};\n\n";
    print CONF "TreeDefault {\n";
    print CONF "  BinCacheDB \"cache.db\";\n";
    print CONF "  Release::Origin \"$release{origin}\";\n"
	if defined $release{origin};
    print CONF "  Release::Label \"$release{label}\";\n"
	if defined $release{label};
    print CONF "};\n\n";

    # The keys of %dests are all of the distribution/section/arch paths that
    # were modified in this run.  We can have apt-ftparchive only index the
    # distributions that were changed, but we have to reindex the entire
    # distribution, since otherwise the Contents files won't be accurate.  Find
    # all affected distributions from %dests, but then locate all sections and
    # architectures under there using the handleScanAll logic.  Skip
    # distributions that are symlinks so that we don't index the same
    # distribution more than once.
    my %changedist = map { s%/.*%%; $_ => 1 } keys %dests;
    foreach my $d (keys %changedist) {
	my $codename = $distmapping{$d} || $d;
	next if -l "$destdir/$codename";
	print CONF "Tree \"dists/$d\" {\n";
	my (@dsections, @darches);
	&findSectionsArchitectures("$destdir/$d", \@dsections, \@darches);
	print CONF "  Sections \"", join (' ', @dsections), "\";\n";
	print CONF "  Architectures \"", join (' ', @darches), "\";\n";
	print CONF "  Release::Suite \"$d\";\n";
	print CONF "  Release::Codename \"$codename\";\n";
	print CONF "};\n\n";
    }
    close CONF;
    return $configpath;
}

###############################################################################
# Name:		handleRelease
# Description:	Handles creation of Release files via apt-ftparchive.
# Arguments:	Path to the directory to generate Release for
#		Archive suite this Release file is for
#		Reference to array of sections
#		Reference to array of architectures
# Uses:		%distmapping, %release, $gpgkey, $gpgpassfile
# Changelog:
#  2005-08-20 Russ Allbery <rra@stanford.edu>
#	Written.
#  2005-09-02 Joergen Haegg <jorgen.hagg@axis.com>
#       Unlink Relase.gpg before creation.
#  2005-09-09 Ola Lundqvist <ola@inguza.com>
#	Made it possible for gnupg to read passphrase from file.
#  2005-09-15 Daniel Leidert <daniel.leidert.spam@gmx.net>
#	Fix regarding $gpgpassfile.
#  2005-10-08 Ola Lundqvist <ola@inguza.com>
#	Now invokes a helper program to sign the files. It may be implemented
#	by some perl module but this solution was good enough.
#  2005-10-14 Daniel Leidert <daniel.leidert@wgdd.de>
#	No longer invokes a helper program. We run gpg in batch mode without
#	tty to work-around old problems.
#  2005-11-07 Russ Allbery <rra@stanford.edu>
#	Don't set batch mode unless the passphrase is obtained from a file;
#	otherwise running debarchiver interactively with a signing key that
#	has a passphrase silently fails.
#  2014-02-15 Ola Lundqvist <ola@inguza.com>
#       Make sure apt-ftparchive do a stat on all the files to avoid the
#       problem with corrupted archive.
#  2020-03-20 Jorgen Hagg and Ola Lundqvist
#       Added --pinentry-mode loopback option to be able to run gpg in
#       batch mode.
###############################################################################

sub generateRelease($$\@\@) {
    my ($path, $suite, $dsections, $darches) = @_;
    my $codename = $distmapping{$suite} || $suite;

    # Judging from the Release file in the Debian archive, "all" and "source"
    # shouldn't be included.
    my @arches = grep { $_ ne 'all' && $_ ne 'source' } @$darches;

    # We can't use the same config as generate, since release wants the
    # variables set in a different place.
    my $configpath = "$path/.apt-ftparchive1.conf";
    action(! open(CONF, "> $configpath"),
	   "Create apt-ftparchive Release config for $path", 2);
    my $prefix = 'APT::FTPArchive::Release';
    print CONF "${prefix}::Origin \"$release{origin}\";\n"
	if defined $release{origin};
    print CONF "${prefix}::Label \"$release{label}\";\n"
	if defined $release{label};
    print CONF "${prefix}::Description \"$release{description}\";\n"
	if defined $release{description};
    print CONF "${prefix}::Suite \"$suite\";\n";
    print CONF "${prefix}::Codename \"$codename\";\n";
    print CONF "${prefix}::Architectures \"", join (' ', @arches), "\";\n";
    print CONF "${prefix}::Components \"", join (' ', @$dsections), "\";\n";
    close CONF;

    # Do the generation and optional signing.
    unlink("$path/Release");
    cmdaction("apt-ftparchive -o APT::FTPArchive::AlwaysStat=true -c $configpath release $path > Release",
	      "Generate Release file for $path",
	      3);
    cmdaction("mv Release $path/Release",
	      "Put Release file for $path in the right location",
	      3);
    if ($gpgkey) {
        unlink("$path/Release.gpg");
    	if ($gpgpassfile) {
	    cmdaction("cat $gpgpassfile | gpg --batch --no-tty -a -b -s -u $gpgkey " .
	              "--pinentry-mode loopback --passphrase-fd 0 -o $path/Release.gpg $path/Release",
		      "Sign Release file for $path with key '$gpgkey'",
		      3);
	}
	else {
	    cmdaction("gpg -a -b -s -u $gpgkey " .
	              "-o $path/Release.gpg $path/Release",
		      "Sign Release file for $path with key '$gpgkey'",
		      3);
	}
    }
    #unlink("$configpath");
}

###############################################################################
# Name:		handleIndex
# Description:	Handles the indexing via apt-ftparchive.
# Uses:		%dests, $destdir
# Changes:	$ENV{PWD}
# Changelog:
#  2004-07-30 Ola Lundqvist <ola@inguza.com>
#	Written.
#  2004-08-09 Ola Lundqvist <ola@inguza.com>
#	Add merging of binary-all Packages file.
#  2005-05-01 Daniel Leidert <daniel.leidert.spam@gmx.net>
#	Modified to add bzip2 support and handle contents-all in a proper way.
#  2005-05-02 Ola Lundqvist <ola@inguza.com>
#	Bugfix for bzip2 support.
#  2005-08-20 Russ Allbery <rra@stanford.edu>
#       Call generateRelease for Release file support (optionally signed).
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Change in foreach to use my variable.
#  2014-02-15 Ola Lundqvist <ola@inguza.com>
#       Make sure apt-ftparchive do a stat on all the files to avoid the
#       problem with corrupted archive.
###############################################################################

sub handleIndex() {
    $destdir =~ s|/+$||;

    action(! chdir $destdir, "Change to dir $destdir", 2);
    &destinationLock();

    my $aptconfig = &generateIndexConfig();
    cmdaction("apt-ftparchive -o APT::FTPArchive::AlwaysStat=true generate $aptconfig",
	      "Index source and package files in $destdir",
	      3);
    #unlink($aptconfig);

    # apt-ftparchive doesn't correctly combine binary-all/Packages with
    # binary-arch/Packages, so we have to patch it up after the fact.
    # apt-ftparchive reindexes the whole distribution when anything in that
    # distribution is touched, so find modified distributions and then touch up
    # the Packages files for each section and architecture under there.
    #
    # Remove binary-all/Packages after we finish with all architectures for a
    # section, so as to not append to Packages more than once even if we revist
    # the same area twice due to a symlink.
    my %changedist = map { s%/.*%%; $_ => 1 } keys %dests;
    foreach my $d (keys %changedist) {
	my (@dsections, @darches);
	&findSectionsArchitectures("$destdir/$d", \@dsections, \@darches);
	if (-s "$d/Contents-all") {
	    foreach my $a (@darches) {
		next if ($a eq 'source' || $a eq 'all');
		action(! open(ARCH, ">> $d/Contents-$a"),
		       "Append to $d/Contents-$a",
		       2);
		action(! open(ALL, "$d/Contents-all"),
		       "Read $d/Contents-all",
		       2);
		print ARCH <ALL>;
		close ALL;
		close ARCH;
		cmdaction("gzip $d/Contents-$a -c > $d/Contents-$a.gz",
			  "Gzip merged Contents files $d/Contents-$a",
			  3);
	    }
	}
	unlink("$d/Contents-all", "$d/Contents-all.gz");
	foreach my $s (@dsections) {
	    if (-s "$d/$s/binary-all/Packages") {
		foreach $_ (@darches) {
		    $a = $_;
		    next if ($a eq 'source' || $a eq 'all');
		    $a = "binary-$a";
		    action(! open(ARCH, ">> $d/$s/$a/Packages"),
			   "Append to $d/$s/binary-$a/Packages",
			   2);
		    action(! open(ALL, "$d/$s/binary-all/Packages"),
			   "Read $d/$s/binary-all/Packages",
			   2);
		    print ARCH <ALL>;
		    close ALL;
		    close ARCH;
		    cmdaction("gzip $d/$s/$a/Packages -c > $d/$s/$a/Packages.gz",
			      "Gzip merged Packages file $d/$s/$a/Packages",
			      3);
		    if ($bzip) {
			cmdaction("bzip2 $d/$s/$a/Packages -c > $d/$s/$a/Packages.bz2",
				  "Bzip merged Packages file $d/$s/$a/Packages",
				  3);
		    }
		}
	    }
	    unlink("$d/$s/binary-all/Packages", "$d/$s/binary-all/Packages.gz",
		   "$d/$s/binary-all/Packages.bz2");
	}

	# This has to be done after we integrate the Packages files.
	generateRelease($d, $d, @dsections, @darches);
    }

    &destinationRelease();
}

###############################################################################
# Name:		findAndSortChangesFiles
# Arguments:	signature checking, override distribution(s) (optional)
# Description:	Sort packages into the right place.
# Uses:		parseChangesFile, verifyChangesFile, handleChangesFile
# Changes:      $errorarea = "sortchanges"
# Changelog:
#  2005-05-01 Ola Lundqvist <ola@inguza.com>
#	Written using parts of handleSorting.
#	Improved changes file verification structure.
#  2005-05-06 Daniel Leidert <daniel.leidert@wgdd.de>
#       Add arg to handle signature verification in inputdir and distinput-dirs
#       independetly.
#  2006-11-24 HÃ¥kon Stordahl <haastord@online.no>
#       Substituted the call to rejectChangesFile with a call to pdebug,
#       to explicitly trigger the error handler incomingError, which
#       itself contains a call to rejectChangesFile. This is in order
#       to avoid a situation in which an error in rejectChangesFile
#       causes rejectChangesFile to be called again.
#  2013-11-06 Ola Lundqvist <ola@inguza.com>
#       Added $errorarea = sortchanges so the error handler know what area
#       of processing being done.
###############################################################################

sub findAndSortChangesFiles($;$) {
    my ($verify, $override) = @_;
    opendir(D, ".");
    
    $errorarea = "sortchanges";
    my $found = 1;
    my $cfile;
    # Loop again to make sure that no new .changes files have been uploaded.
    while ($found) {
	# go through all .changes files:
	$found = 0;
	while($cfile = readdir(D)) {
	    # Only .changes files.
	    if ($cfile =~ /\.changes$/) {
		parseChangesFile($cfile);
		uploaderIsChangesFileOwner($cfile);
		my ($verify, $reason) = verifyChangesFile($cfile, $verify);
		if ($verify =~ /^reject$/) {
		    # Reject .changes file by calling pdebug with error
                    # level 2, which in turn calls the error handler
                    # for this function, incomingError, which calls
                    # rejectChangesFile.
                    pdebug(2, "Rejecting $cfile.");
		}
		elsif ($verify =~ /^incomplete$/) {
		    # Handle incomplete .changes file.
		}
		else {
		    # Changes file verified.
		    $CConf{Distribution} = $override if ($override !~ /^\s*$/);
		    handleChangesFile($cfile);
		    $found = 1;
		}
	    }
	}
    }
    
    closedir(D);
}

###############################################################################
# Name:		handleSorting
# Description:	Sort packages into the right place.
# Uses:		A lot.
# Changelog:
#  2001-07-23 Ola Lundqvist <ola@inguza.com>
#	Moved from START section to this subprocedure.
#  2005-04-xx Bob Proulx <bob@proulx.com>
#	Added support for .changes files in distinputdir.
#  2005-04-30 Ola Lundqvist <ola@inguza.com>
#	Modified support for .changes files in distinput dir.
#  2005-05-01 Ola Lundqvist <ola@inguza.com>
#	Broke out .changes file handling to a separate function
#	findAndSortChangesFiles.
#  2005-05-06 Daniel Leidert <daniel.leidert@wgdd.de>
#       Add signature checking setting to arguments given to
#       findAndSortChangesFiles().
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Change in foreach to use my variable.
#  2013-11-06 Ola Lundqvist <ola@inguza.com>
#       Broke out the deb only handling into its own function.
###############################################################################

sub handleSorting() {
    if (defined $sortpackages) {
	# First check if a lockfile is created.

	action(! chdir $inputdir, "Change to dir $inputdir", 2);
	&incomingLock();

	# Look in the incoming directory for .changes files.
	&findAndSortChangesFiles($verifysignatures);

	# Look in the incoming/<queue> directories for either .changes
	# files or for plain .debs matching the dist input criteria.

	foreach my $dir (keys %distinputdirs) {
	    my $inpdir = "$inputdir/$distinputdirs{$dir}";
	    if (-d $inpdir) {
		action(! chdir "$inpdir", "Change to dir $inpdir", 2);
		&findAndSortChangesFiles($verifysignaturesdistinput, $dir);
		&findAndSortDebFiles($dir);
	    }
	}

	action(! chdir $inputdir, "Change to dir $inputdir", 2);
	&incomingRelease();
    }
}

###############################################################################
# Name:		findAndSortDebFiles
# Description:	Sort packages into the right place.
# Uses:	        verifyDebFile, $distinputcriteria, handleDebOnlyFile,
#               pdebug.
# Changes:
#   $errorarea = "sortdeb";
#   Empties %CMeta and %DMeta
#   $CMeta (FileOwner)
#   $DMeta (DebFile)
# Changelog:
#  2013-11-06 Ola Lundqvist <ola@inguza.com>
#       Written based on code from handleSorting and added verification of
#       deb file completeness to not sort incomplete uploads.
#  2013-11-13 Ola Lundqvist <ola@inguza.com>
#       Poplate %DMeta %CMeta instead of setting $rejecteddebfile.
###############################################################################
sub findAndSortDebFiles($) {
    my ($dir) = @_;
    pdebug(5, "find and sort deb for $dir");
    $errorarea = "sortdeb";
    opendir(D, ".");
    my $file;
    while (defined($file = readdir(D))) {
	if ($file =~ /$distinputcriteria/) {
	    # This is a fix for reject case. It is set again in
	    # parseDebOnlyFile
	    %DMeta = ();
	    %CMeta = ();
	    $DMeta{DebFile} = $file;
	    $CMeta{FileOwner} = getpwuid($file);
	    # We can add checks here to check for incomplete .changes files
	    # se we do not sort .deb files that is a part of a .changes file.	
	    my $verify = verifyDebFile($file);
	    if ($verify =~ /^ok$/) {
		handleDebOnlyFile($file, $dir);
	    }
	    elsif ($verify =~ /^reject$/) {
		pdebug(2, "Rejecting $file.");
	    }
	    # else incomplete, do nothing
	}
    }
    closedir(D);
}

###############################################################################
# Name:         verifyDebFile
# Description:  Check a deb file to see that it is complete
# Uses:         $incompletetime, open3, File::Spec, open, gensym, dpkg -c, stat
# Returns:
#  "ok"         Complete
#  "reject"     Incomplete and older than $incompletetime seconds.
#  "incomplete" Incomplete and newer than $incompletetime seconds.
# Changelog:
#  2013-11-06 Ola Lundqvist <ola@inguza.com>
#	Function created to check for deb file completeness.
###############################################################################

sub verifyDebFile($) {
    my ($file) = @_;
    open(TMPNULL, ">", File::Spec->devnull);
    my $pid = open3(gensym, ">&TMPNULL", \*TMPSTDERR, "dpkg -c ".$file);
    while( <TMPSTDERR> ) { }
    waitpid($pid, 0);
    close (TMPSTDERR);
    close (TMPNULL);
    if ($? == 0) {
	return "ok";
    }
    my $clastmod = (stat $file)[9];
    if ($clastmod < time() - $incompletetime) {
	pdebug(4, "$file is incomplete and is older than $incompletetime seconds.");
	return "reject";
    }
    return "incomplete";
}

###############################################################################
# Name:		handleStructureFix
# Description:	Fix the distribution directory structure.
# Uses:		@distributions, @sections, @architectures, $fixstructure
# Changelog:
#  2001-07-23 Ola Lundqvist <ola@inguza.com>
#	Moved from START section to this subprocedure.
#  2004-08-09 Ola Lundqvist <ola@inguza.com>
#	Call createRelease to build Release files.
#  2007-10-08 Turbo Fredriksson <turbo@bayour.com>
#       Distmapping for files.
###############################################################################

sub handleStructureFix() {
    action(! chdir $destdir, "Change to dir $destdir", 2);

    if (defined $fixstructure) {
	my ($di, $se, $ar);
	for $di (@distributions) {
	    my $dis = $distmapping{$di} || $di;
	    if (! defined($dis)) {
		$dis = $di;
	    }
	    elsif ($dis =~ /^\s*$/) {
		$dis = $di;
	    }
	    if ((! -l "$di") &&
		$dis !~ /^$di$/) {
		cmdaction("ln -s $dis $di",
			  "Symlink $dis to $di.",
			  2);
	    }
	    for $se (@sections) {
		if (! -d "$dis/$se/binary-all") {
		    action(! mkpath("$dis/$se/binary-all", 0, 0755),
			   "Create binary-all directory $dis/$se/binary-all",
			   2);
		}
		for $ar (@architectures) {
		    createPF("$dis/$se/binary-$ar", "Packages");
		    createRelease("$dis/$se/binary-$ar", $di, $se, $ar);
		}
		createPF("$dis/$se/source", "Sources");
		createRelease("$dis/$se/source", $di, $se, 'source');
		if (! -e "$dis/$se/override") {
		    cmdaction("touch $dis/$se/override",
			      "Create file $dis/$se/override.",
			      2);
		}
		if (! -e "$dis/$se/override.src") {
		    cmdaction("touch $dis/$se/override.src",
			      "Create file $dis/$se/override.src.",
			      2);
		}
	    }
	}
    }
}

###############################################################################
# Name:		handleDebOnlyFile
# Description:	Handles installation of a deb image.
# Arguments:	A deb file.
#		The distribution to install to.
# Changes:	see parseKernelFile
# Uses:         %CFiles, parseDebOnlyFile (populates %CFiles)
# Changelog:
#  2001-06-29 Ola Lundqvist <ola@inguza.com>
#	Written.
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Change in foreach to use my variable.
#  2013-11-14 Ola Lundqvist <ola@inguza.com>
#       Changed from a for loop to direct use of file name as it is always
#       just one file in this situation.
#       Also added mail support for successfully installed packages.
###############################################################################

sub handleDebOnlyFile($$) {
    my ($kfile, $distr) = @_;

    parseDebOnlyFile($kfile, $distr);
    handlePackageFile($kfile);
    # Now the package is moved so now we should not use the filename
    # directly anymore.
    mailSuccessDeb();
}

###############################################################################
# Name:		checkFileInDestDirs
# Description:  Check the location of the file in the dest dirs.
###############################################################################
# Uses: parseFileName
#       parseFileStruct
#	parseSection
#       %CConf
#       %CFiles
#       %distmapping
# Arguments:
#	filename to check for
# Returns:
#	filepath     If file exist in dest dirs.
#       ""           If file not found.
# Changelog:
#  2007-10-08 Ola Lundqvist <ola@inguza.com>
#       Write function based on the code from Turbo Fredriksson <turbo@bayour.com>
#       in function verifyChangesFile below.
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Change in foreach to use my variable.
###############################################################################

sub checkFileInDestDirs($) {
    my ($file) = @_;
    my (undef, undef, $section, undef) = parseFileStruct($CFiles{$file});
    my ($major, $section) = parseSection($section);

    my $distrd = $CConf{Distribution};
    my $inst_files = "";

    foreach my $distr (split /\s+/, $distrd) {
	$distr = $distmapping{$distr} || $distr;
	my (undef, undef, $arch, undef) = parseFileName($file);
	
	my $archsec = "source";
	if ($arch !~ /^source$/) {
	    $archsec = "binary-$arch";
	}
	
	my $inst_file = "$destdir/$distr/$major/$archsec/$section/$file";
	if (-f "$inst_file") {
	    if ($inst_files eq "") {
		$inst_files = $inst_file;
	    }
	    else {
		$inst_files .= " $inst_file";
	    }
	}
    }
    return $inst_files;
}

###############################################################################
# Name:		getMD5HashForFile	
# Description:  Get the MD5 hash for a file. File must exist.
###############################################################################
# Uses:
#	Digest::MD5
# Arguments:
#	filename to check for
# Returns:
#	MD5 sum for file
# Changelog:
#  2007-10-08 Ola Lundqvist <ola@inguza.com>
#       Write function based on the code from Turbo Fredriksson <turbo@bayour.com>
#       in function verifyChangesFile below.
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Correction.
###############################################################################

sub getMD5HashForFile($) {
    my ($file) = @_;
    open(FILE, $file) or die "Can't open $file: $!\n";
    binmode(FILE);
    $digest = Digest::MD5->new->addfile(*FILE)->hexdigest, " $file\n";
    close (FILE);
    return $digest;
}

###############################################################################
# Name:		verifyChangesFile
# Description:	Parses the .changes file.
# Uses:		pdebug, uploaderIsChangesFileOwner
#		%CFiles
#			$filename => "$hash $size $section $type"
# Arguments:	The .changes file and the signature checking setting.
# Returns:	
#	incomplete	Incomplete upload.
#	reject		Reject a changes file.
#	ok		Else verification ok (anything except incomplete or reject).
# Changelog:
#  2005-04-xx Bob Proulx <bob@proulx.com>
#	Split out parts of handleChangesFile to this proc.
#  2005-05-01 Ola Lundqvist <ola@inguza.com>
#	Renamed from parseChangesFile to verifyChangesFile and removed parse
#	part. Rewrote parts to allow it to return some kind of status.
#	Added code to verify that changes file upload is complete.
#  2005-05-06 Daniel Leidert <daniel.leidert@wgdd.de>
#       Add arg to handle signature verification in inputdir and distinput-dirs
#       independetly.
#  2007-10-08 Turbo Fredriksson <turbo@bayour.com>
#       Stat only existing files.
#  2007-10-08 Ola Lundqvist <ola@inguza.com>
#       Correct indention (as Turbo explained).
#  2007-10-08 Turbo Fredriksson <turbo@bayour.com>
#       The changes file is only incomplete if the file is missing _and_
#       a file in the destination do not already exist with the correct MD5
#       hash.
#  2007-10-08 Ola Lundqvist <ola@inguza.com>
#       Extraced the file check to two own functions.
#       Changed the order to always check for installed files and reject if it
#       exist with wrong size or md5sum.
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Change in foreach to use my variable.
#       Check incomplete time only once.
#       Allow forcing an install of an upload (i.e., ignore existing files in
#       destdir).
#  2007-10-09 Ola Lundqvist <ola@inguza.com>
#       Changed force option to ignoredestcheck option.
###############################################################################

sub verifyChangesFile($$) {
    my ($cfile, $verify) = @_;
    # Get changes file owner uid
    my $cfowner = (stat $cfile)[4];
    my $clastmod = (stat $cfile)[9];
    my $old_changes = 0;
    if ($clastmod < time() - $incompletetime) {
	$old_changes = 1;
    }
    # Verify changelog so it is complete, ok is default.
    # If incomplete continue checking for errors.
    my $ret = "ok";
    foreach my $file (keys %CFiles) {
	# Does it exist in the destdir?
	my $inst_files = checkFileInDestDirs($file);
	if (($inst_files ne "") && ($ignoredestcheck == 0)) {
	    foreach my $inst_file (split / /, $inst_files) {
		# Get data for the file to install.
		my ($hash, $size, undef, undef) = parseFileStruct($CFiles{$file});
		# Get size for the already installed one
		my (undef, undef, undef, undef, undef, undef, undef, $ssize) = stat($inst_file);
		if ($size != $ssize) {
		    pdebug(4, "$cfile is rejected. $file already installed and size do not match.");
		    $CConf{ERROR} = "$CConf{ERROR}$cfile is rejected. $file already installed and size do not match.\n";
		    return "reject";
		}
		my $digest = getMD5HashForFile($inst_file);
		if ($hash != $digest) {
		    pdebug(4, "$cfile is rejected. $file already installed and MD5 sum do not match.");
		    $CConf{ERROR} = "$CConf{ERROR}$cfile is rejected. $file already installed and MD5 sum do not match.\n";
		    return "reject";
		}
	    }
	}
	elsif (! -f $file) {
	    # Modification time of the changesfile.
	    if ($old_changes) {
		pdebug(4, "$cfile is incomplete and is older than $incompletetime seconds.");
		$CConf{ERROR} = "$CConf{ERROR}$cfile is incomplete and is older than $incompletetime seconds.\n";
		return "reject";
	    } else {
		pdebug(4, "$cfile is incomplete. Missing file: $file.");
		$ret = "incomplete";
	    }
	} else {
	    # File exist, now verify it.
	    my (undef, undef, undef, undef, $fowner, undef, undef, $size) = stat($file);
	    if ($fowner != $cfowner) {
		pdebug(4,"$file owner ($fowner) do not match $cfile owner ($cfowner).");
		$CConf{ERROR} = "$CConf{ERROR}$file owner do not match $cfile owner.\n";
		return "reject";
	    }
	    my ($cfhash, $cfsize) = split / /, $CFiles{$file};
	    if ($size < $cfsize) {
		# Modification time of the changesfile.
		pdebug(4, "$cfile is incomplete and is older than $incompletetime seconds as $file is not of full size.");
		if ($old_changes) {
		    $CConf{ERROR} = "$CConf{ERROR}$cfile is incomplete and is older than $incompletetime seconds as $file is not of full size.\n";
		    return "reject";
		}
		else {
		    $ret = "incomplete";
		}
	    } elsif ($size > $cfsize) {
		pdebug(4, "$cfile upload is broken, $file is bigger than expected.");
		$CConf{ERROR} = "$CConf{ERROR}$cfile upload is broken, $file is bigger than expected.\n";
		return "reject";
	    }
	}
    }
    # Verify signatures.
    if ($verify) {
	@vrfycmd = ($vrfycmd) if (! @vrfycmd);
	if (system(@vrfycmd,$cfile)) { # non-zero == verification failure
	    pdebug(4, "Signature verification failed for $cfile");
	    $CConf{ERROR} = "$CConf{ERROR}".join(" ",@vrfycmd)." was not able to verify $cfile.\n";
	    return "reject";
	}
    }
    return $ret;
}

###############################################################################
# Name:		handleChangesFile
# Description:	Handles the .changes file.
# Uses:		pdebug, $copycmd, $rmcmd
# Arguments:	The .changes file.
# Returns:	nothing
# Changelog:
#  2001-06-26 Ola Lundqvist <ola@inguza.com>
#	Taken from the main script. Cut and paste with simple changes.
#  2003-03-13 Ola Lundqvist <ola@inguza.com>
#	Added mailSuccessChanges command thing.
#  2003-06-10 Ola Lundqvist <ola@inguza.com>
#	Now uses uploaderIsChangesFileOwner to make sure that the owner can be
#	calculated before the changes file will be moved or something similar.
#       Also added rejectChangesFile to vrfycmd so that messages will be sent
#	properly if it is rejected.
#       Moved parseChanges before sig verify and uploaderIsChangesFileOwner to
#	make sure that CMeta is created before that.
#  2005-04-xx Bob Proulx <bob@proulx.com>
#	Split out parts of this function to parseChangesFile.
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Change in foreach to use my variable.
#  2013-11-13 Ola Lundqvist <ola@inguza.com>
#       Changed name of mailSuccess to mailSuccessChanges to clarify what
#       situation this function is used.
###############################################################################

sub handleChangesFile($) {
    my ($cfile) = @_;

    foreach my $file (keys %CFiles) {
	handlePackageFile($file, $cfile);
    }
    installChangesFile($cfile);
    mailSuccessChanges();
}

###############################################################################
# Name:		uploaderIsChangesFileOwner
# Description:	Sets CMeta{FileOwner} from 
# Changes:	CMeta
# Changelog:
#  2003-06-10 Ola Lundqvist <ola@inguza.com
#	Wrote it.
###############################################################################

sub uploaderIsChangesFileOwner($) {
    my ($cfile) = @_;
    my @temp = stat($cfile);
    if (@temp) {
	my $tmp = $temp[4];
	$CMeta{FileOwner} = getpwuid($tmp);
	pdebug(5, "$cfile is owned by $CMeta{FileOwner}");
    }
    else {
	pdebug(3, "Can not stat file $cfile, so unable to calculate email address.");
	$CMeta{FileOwner} = "";
    }
}

###############################################################################
# Name:		rejectChangesFile
# Description:	Reject the changes file so that it is moved away.
# Uses:		%CFiles, %CConf
# Changelog:
#  2003-02-12 Ola Lundqvist <ola@inguza.com
#	Wrote it.
#  2003-02-28 Ola Lundqvist <ola@inguza.com
#	Implemented the commands in the foreach loop.
#  2003-03-14 Ola Lundqvist <ola@inguza.com>
#	Switched to using CMeta for ChangeLog meta information.
#  2005-05-01 Ola Lundqvist <ola@inguza.com>
#	Modified reject cause.
#  2005-05-06 Daniel Leidert <daniel.leidert@wgdd.de>
#       Fixed move-command and check for .changes file.
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Change in foreach to use my variable.
#       Create reject log code.
#  2007-10-09 Ola Lundqvist <ola@inguza.com>
#       Moved reject log code to REJECT dir and changed coding style some.
###############################################################################

sub rejectChangesFile() {
    if (! -d "REJECT") {
	action(! mkpath ("REJECT", 0, 0775),
	       "Making REJECT directory.",
	       2);
    }
    if (-f $CMeta{ChangesFile}) {
		cmdaction("$movecmd $CMeta{ChangesFile} REJECT/",
		  "Move .changes to REJECT dir.",
		  2);
    }
    foreach my $file (keys %CFiles) {
	if (-f $file) {
	    cmdaction ("$movecmd $file REJECT/",
		       "Move $file to REJECT dir.",
		       3);
	}
	else {
	    $CConf{ERROR} = "$CConf{ERROR}File $file can not be moved because it is already installed (or incomplete upload).\n";
	}
    }
    # Create a reject log
    my $log = $CMeta{ChangesFile};
    $log =~ s/\.changes/\.reject/;
    $log = "REJECT/$log";
    if (open(LOG, "> $log")) {
	print LOG $CConf{ERROR};
	close(LOG);
    }
    else {
	pdebug(4, "Can't create reject log [$log].");
	$CConf{ERROR} = "$CConf{ERROR}Can't create reject log [$log].\n";
    }
}

###############################################################################
# Name:		rejectDebFile
# Description:	Reject the changes file so that it is moved away.
# Uses:		$DMeta{DebFile}
# Changelog:
#   2013-11-06 Ola Lundqvist <ola@inguza.com>
#       Created based on code from rejectChangesFile.
#   2013-11-13 Ola Lundqvist <ola@inguza.com>
#       Updated to use $DMeta instead of $rejecteddebfile.
###############################################################################

sub rejectDebFile() {
    if (! -d "REJECT") {
	action(! mkpath ("REJECT", 0, 0775),
	       "Making REJECT directory.",
	       2);
    }
    if (-f $DMeta{DebFile}) {
	cmdaction("$movecmd $DMeta{DebFile} REJECT/",
		  "Move .deb to REJECT dir.",
		  2);
    }
    # Create a reject log
    my $log = $DMeta{DebFile};
    $log =~ s/\.deb/\.reject/;
    $log = "REJECT/$log";
    if (open(LOG, "> $log")) {
	print LOG "Incomplete upload and older than $incompletetime seconds.";
	close(LOG);
    }
    else {
	pdebug(4, "Can't create reject log [$log].");
    }
}

###############################################################################
# Name:		handlePackageFile
# Description:	Handles the package file.
# Uses:		Same as parseChangesFile produces.
# Changes:	%dests
# Arguments:	The package file (the key in %CFiles).
# Returns:	nothing
# Changelog:
#  2001-06-26 Ola Lundqvist <ola@inguza.com>
#	Taken from the main script. Cut and paste with simple changes.
#  2006-06-11 Michael Hanke <michael.hanke@gmail.com>
#       Only remove source tarball file if not referenced by any other .changes file.
#  2006-07-20 Ola Lundqvist <ola@inguza.com>
#       Changed indentation.
#  2007-10-08 Turbo Fredriksson <turbo@bayour.com>
#       Distmapping for files.
#  2007-10-08 Turbo Fredriksson <turbo@bayour.com>
#       The changes file is only incomplete if the file is missing _and_
#       a file in the destination do not already exist with the correct MD5
#       hash.
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Change in foreach to use my variable.
#  2013-09-23 Uditha Atukorala <udi@geniusse.com>
#       Fix for incorrect 'Release' file when used with -so options. To be
#       specific, it used the alias from %distmapping for both 'Suite' and
#       'Codename' values which makes aptitude throw a warning. This was
#       introduced in r2484 and is now fixed.
#  2013-09-24 Uditha Atukorala <udi@geniusse.com>
#       When I was uploading .changes files for different distributions other
#       than unstable built using the distribution codenames, e.g. wheezy,
#       jessie etc., debarchiver generates an incorrect 'Release' file by
#       putting the codename value into 'Suite'. I have been using sbuild
#       --dist=jessie package.dsc etc. to build for different distributions.
#
#       As a workaround you can have the suite name (e.g. testing) as the
#       'Distribution' in the .changes file but the following simple patch
#       (also attached) would take into account such scenarios and generate
#       the correct 'Release' file.
#  2013-11-13 Ola Lundqvist <ola@inguza.com>
#       Added debug code to debug a fault case regarding autoscan.
#  2015-05-04 Mats Erik Andersson <mats.andersson@gisladisker.se>
#       Correction. The variable '$upstream_version' was populated with the
#       upstream version string of the original archive, but the
#       variable '$upver' was late queried for its content, which
#       was invariably empty! In practice this means that debarchiver
#       was more inclined to refuse the removal of the incoming archive,
#       than to carelessly remove it.
###############################################################################

sub handlePackageFile ($) {
    my ($file, $cfile) = @_;
    my $distrd = $CConf{Distribution};

    pdebug(5, "File $_:  $CFiles{$file}");
    my ($hash, $size, $section, $prio) =
	parseFileStruct($CFiles{$file});
    my ($pkgname, $ver, $arch, $ext) =
	parseFileName($file);
    my $archsec = "source";
    if ($arch !~ /^source$/) {
	$archsec = "binary-$arch";
    }
    my ($major, $section) = parseSection($section);

    # OVERRIDES

    foreach my $distr (split /\s+/, $distrd) {
	# Do a reverse mapping of the distribution here so we always
	# speak the same language. i.e. testing, unstable etc. instead
	# of jessie, sid etc.
	my %distlookup = reverse %distmapping;
	$distr = $distlookup{$distr} || $distr;

	# Note to autoscan that files are installed to this dir.
	pdebug(5, "Mark $distr/$major/$archsec for autoscan ($file, $section)");
	$dests{"$distr/$major/$archsec"} = 1;

	$distr = $distmapping{$distr} || $distr;
	pdebug(5, "Mapped to $distr/$major/$archsec ($file, $section)");

	my $srcext = ".src" if ($arch =~ /^source$/);
	parseOverrideFile($distr, $major, $srcext);
	if (defined $Override{$distr, $major, "$pkgname$srcext"}) {
	    pdebug(5, "Defined in override, $pkgname$srcext");
	    $section = secondIfNotEmpty($section,
					$Override{$distr,
						  $major,
						  "$pkgname$srcext",
						  Section});
	}
	elsif (defined $addoverride) {
	    pdebug(5, "Add to override$srcext, $pkgname $prio $section");
	    open F, ">>$destdir/$distr/$major/override$srcext";
	    print(F  "$pkgname $prio $section\n");
	    close(F);
	    $Override{$distr,
		      $major,
		      "$pkgname$srcext"} = 1;
	}

	my $installto = "$destdir/$distr/$major/$archsec/$section";
	if (! -d $installto) {
	    action(! mkpath ($installto, 0, 0755),
		   "Making directory $installto",
		   2);
	}
	# Not sure why we have a -f check here. It should exist at this point.
	elsif (-f $file) {
	    if ($arch =~ /^source$/) {
		cmdaction("$rmcmd $installto/${pkgname}_*$ext",
			  "Delete $installto/${pkgname}_*$ext",
			  2);
	    }
	    else {
		# This will not work but tells what to do.
		cmdaction("$rmcmd $installto/${pkgname}_*_$arch$ext",
			  "Delete $installto/${pkgname}_*_$arch$ext",
			  2);
	    }
	}
	cmdaction("$copycmd $file $installto",
		  "Install $file to $installto.",
		  2);
	}
	# flag whether file should get deleted
	my $killfile = 1;
		
	# only do checks of processing source tarballs
        if ($file =~ m/.tar.gz$/) {
	    my @upstream_version = split(/-/, $ver);
	    my $upver = $upstream_version[0];
	    
	    # get list of remaining *.changes files of this package upstream 
	    # version
	    my @otherchangesfiles = <$inputdir/${pkgname}_$upver*.changes>;
	    
	    # check whether any of the remaining *.changes files does not match the 
	    # current package
	  CHGSPARSER: foreach my $otherchangesfile (@otherchangesfiles) {
	      if (!($otherchangesfile =~ $cfile)) {
		  open ( otherchangesfilehandle, $otherchangesfile);
		  
		  while ($line = <otherchangesfilehandle>) {
		      if ($line =~ m/${pkgname}_$upver.*\.tar\.gz/) {
			  pdebug(4, "Found additional package using the source tarball of the package. Will not delete it now!");
			  $killfile = 0;
			  close(otherchangesfilehandle);
			  last CHGSPARSER;
		      }
		  }
		  
		  close(otherchangesfilehandle)
		  }
	  }
	}
    
	if ($killfile) {
	    cmdaction("$rmcmd $file", 
		      "Remove $file after it has been installed.", 2);
	}
}

###############################################################################
# Name:		installChangesFile
# Description:	Moves the changes file to the right place, or remove it.
# Arguments:	The .changes file.
#		Where to place it.
# Returns:	($major, $section)
#		if on the form foo/bar it returns (foo, bar) and if it
#		is on the form foo it returns (main, foo).
# Changelog:
#  2001-06-10 Ola Lundqvist <ola@inguza.com>
#	Wrote it.
#  2003-03-14 Ola Lundqvist <ola@inguza.com>
#	Now CConf{ChangesFile} is changed when copying it.
#  2007-10-08 Turbo Fredriksson <turbo@bayour.com>
#       Distmapping for files.
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Change in foreach to use my variable.
###############################################################################

sub installChangesFile ($) {
    my ($cfile) = @_;

    my $distrd = $CConf{Distribution};
    foreach my $distr (split /\s+/, $distrd) {
	$distr = $distmapping{$distr} || $distr;
	my $todir = relativePath($cinstall, "$destdir/$distr");
	if ($cinstall !~ /^\s*$/) {
	    # Now remove or move away the .changes file (if $cinstall not empty).
	    if (! -d $todir) {
		action(! mkpath ($todir, 0, 0755),
		       "Making directory $todir",
		       2);
	    }
	    cmdaction("$copycmd $cfile $todir",
		      "Copy $cfile to $todir.",
		      2);
	}
    }
    cmdaction("$rmcmd $cfile",
	      "Remove changes file $cfile after installation.",
	      2);
}

###############################################################################
######################### LOCK HANDLERS #######################################
###############################################################################
# Changelog:
#  2006-11-24 HÃ¥kon Stordahl <haastord@online.no>
#       Tried to fix the error handler functions incomingError and
#       rejectError, by removing the lock file in rejectError instead
#       of incomingError, so the lock file is not removed immediately
#       after an error, but rather if another error occurs while
#       handling the error. Also added a call to exit in rejectError
#       so the program will terminate in this case.
#
#       Because of the chdir in handleSorting, the lock file name
#       needs to prefixed by $inputdir in the functions incomingError
#       and rejectError.
#
#       Restored the error handler in incomingError so subsequent
#       errors are treated in the same way.
#
#       Also moved the call to mailRejectChanges from the function rejectError
#       to the function incomingError, so a mail is sent each time
#       a .changes file is rejected. When called from rejectError,
#       which actually is the error handler of incomingError, which
#       itself is an error handler and calls rejectChangesFile, a mail
#       would only be sent if there was a problem with the rejection.
#  2013-11-06 Ola Lundqvist <ola@inguza.com>
#    Changed incoming error handler so that it can differentiate between
#    changes file processing and deb only processing.
#  2013-11-13 Ola Lundqvist <ola@inguza.com>
#    Added support for email at deb rejection.
###############################################################################

sub incomingLock() {
    &createLockExit("$lockfile");
    &setErrorHandler(\&incomingError);
}

sub incomingRelease() {
    &setErrorHandler(undef);
    &removeLockfile("$lockfile");
}

sub incomingError() {
    &setErrorHandler(\&rejectError);
    if ($errorarea =~ /^sortchanges$/) {
	&rejectChangesFile();
	&mailRejectChanges();
    }
    elsif ($errorarea =~ /^sortdeb$/) {
	&rejectDebFile();
	&mailRejectDeb();
    }
    &setErrorHandler(\&incomingError);
}

sub rejectError() {
    &setErrorHandler(undef);
    &removeLockfile("$inputdir/$lockfile");    
    exit;
}

sub destinationLock() {
    &createLockExit("$destdir/$lockfile");
    &setErrorHandler(\&destinationError);
}

sub destinationRelease() {
    &setErrorHandler(undef);
    &removeLockfile("$destdir/$lockfile");
}

sub destinationError() {
    &setErrorHandler(undef);
    &removeLockExit("$destdir/$lockfile");    
}

###############################################################################
######################### LOCK FUNCTIONS ######################################
###############################################################################

###############################################################################
# Name:		createLockExit
# Description:	creates a lockfile, but exits if it can't.
# Changelog:
#  2002-01-22 Ola Lundqvist <ola@inguza.com>
#	Written.
# Arguments:   	$lockfile
# Returns:	nothing
###############################################################################

sub createLockExit($) {
    my ($lockfile) = @_;
    if (-e $lockfile) {
	pdebug(2, "Lockfile exists in distribution directory, skipping.");
    }
    cmdaction("touch $lockfile",
	      "Create lockfile $lockfile",
	      2);
}

###############################################################################
# Name:		removeLockfile
# Description:	Removes the lockfile.
# Arguments:	none
# Needs:	$rmcmd $lockfile
# Returns:	nothing
# Changelog:
#  2002-01-22 Ola Lundqvist <ola@inguza.com>
#	Written.
###############################################################################

sub removeLockExit() {
    my ($lockfile) = @_;
    removeLockfile($lockfile);
    exit;
}

###############################################################################
# Name:		removeLockfile
# Description:	Removes the lockfile.
# Arguments:    $lockfile
# Returns:	nothing
# Changelog:
#  2002-01-22 Ola Lundqvist <ola@inguza.com>
#	Written.
###############################################################################

sub removeLockfile() {
    my ($lockfile) = @_;
    cmdaction("rm $lockfile",
	      "Remove lockfile $lockfile.",
	      2);
}

###############################################################################
############################ PARSERS ##########################################
###############################################################################

###############################################################################
# Name:		parseSection
# Description:	Takes a section and convert that into the used ones.
# Arguments:	A section on the form foo/bar or foo.
# Returns:	($major, $section)
#		if on the form foo/bar it returns (foo, bar) and if it
#		is on the form foo it returns (main, foo).
# Changelog:
#  2001-06-10 Ola Lundqvist <ola@inguza.com>
#	Written.
#  2006-02-25 Yaroslav Halchenko <debian@onerussian.com> and
#             Ola Lundqvist <ola@inguza.com>
#       Default major section function.
###############################################################################

sub parseSection($) {
    my ($major, $section) = split /\//, shift @_;
    if ($section =~ /^\s*$/) {
	# on the foo form.
	$section = $major;
	$major = $majordefault;
    }
    return ($major, $section);
}

###############################################################################
# Name:		parseFileStruct
# Description:	Parses a hash size section prio string.
#		It is a simple split...
# Arguments:	The string.
# Returns:	($hash, $size, $section, $prio)
# Changelog:
#  2001-06-10 Ola Lundqvist <ola@inguza.com>
#	Written.
###############################################################################

sub parseFileStruct($) {
    return split / /, shift @_;
}

###############################################################################
# Name:		parseFileName
# Description:	Parses a file name and splits into $pkgname, $version, $arch
# Arguments:	deb filename.
# Returns:	($pkgname, $version, $arch, $ext)
# Changelog:
#  2001-06-10 Ola Lundqvist <ola@inguza.com>
#	Written.
###############################################################################

sub parseFileName($) {
    my ($file) = @_;
    my ($pkgname, $ver, $arch) = split /_/, $file;
    $pkgname =~ s/^.*\///;
    my $ext;
    if ($arch !~ /^\s*$/) {
	$ext = $arch;
	$arch =~ s/\..*$//;
	$ext =~ s/^[^\.]*\./\./;
    }
    else {
	$ext = $ver;
	$ver = $CConf{Version};
	$ext =~ s/$ver//;
	$arch = "source";
    }
    return ($pkgname, $ver, $arch, $ext);
}

###############################################################################
# Name:		parseDebOnlyFile
# Description:	Parses a debian deb file and extracs the information in the
#		way that parseChangesFile does.
# Arguments:	A deb file name.
# Changes:	see parseChangesFile and in addition to that %DMeta
# Changelog:
#  2001-06-29 Ola Lundqvist <ola@inguza.com>
#	Written with info from parseChanges.
#  2003-02-12 Ola Lundqvist <ola@inguza.com>
#	Added ChangesFile to CConf hash.
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Change in foreach to use my variable.
#  2014-11-19 Ola Lundqvist <ola@inguza.com>
#       Added a check so that in case dpkg-deb -f can not parse the file, the
#       file will be rejected.
###############################################################################

sub parseDebOnlyFile($$) {
    my ($kfile, $distr) = @_;
    my $state = "";
    my $section;
    my $priority;
    my $size;
    my $desc;
    %CConf = (Distribution => $distr);
    %CMeta = (ChangesFile => "", ChangesContent => "");
    %DMeta = ();
    $DMeta{DebFile} = $kfile;
    $CMeta{FileOwner} = getpwuid($kfile);
    %CFiles = ();
    %CDesc = ();
    my @cmdres = readcommand("dpkg-deb -f $kfile");
    if ($? != 0) {
	pdebug(2, "Reject $kfile as dpkg-deb -f can not parse the file");
    }
    my $content = "";
    foreach my $line (@cmdres) {
	$content .= $line;
	# The state to just put the line in the hash.
	if ($line =~ /^\s*$/) {
	    next;
	}
	$line =~ s/\n$//;
	if ($line =~ /^Provides:/ ||
	    $line =~ /^Suggests:/ ||
	    $line =~ /^Depends:/) {
	    #next;
	}
	elsif ($line =~ /^Package:/) {
	    $line =~ s/^[^:]*:\s//;
	    $CConf{Binary} = $line;
	}
	elsif ($line =~ /^Section:/) {
	    $line =~ s/^[^:]*:\s//;
	    $section = $line;
	}
	elsif ($line =~ /^Priority:/) {
	    $line =~ s/^[^:]*:\s//;
	    $priority = $line;
	}
	elsif ($line =~ /^Installed-Size:/) {
	    $line =~ s/^[^:]*:\s//;
	    $size = $line;
	}
	elsif ($line =~ /^Description:/) {
	    $line =~ s/^[^:]*:\s//;
	    $desc = $line;
	}
	elsif ($line =~ /^ ./) {
	    pdebug(6, "Do nothing with description.");
	}
	else {
	    my $pre = $line;
	    $pre =~ s/:.*$//;
	    $line =~ s/^[^:]*:\s//;
	    $CConf{$pre} = $line;
	}
    }
    $DMeta{DebContent} = $content;
    $CDesc{$CConf{Binary}} = $desc;
    $CFiles{$kfile} = "0 $size $section $priority";
}

###############################################################################
# Name:		parseChangesFile
# Description:	Parses a debian changelog file and extracs the information.
# Arguments:	.changes file name.
# Changes:	
#	%CConf
#		'Format' => The file format.
#		'Source' => The source packages
#		'Binary' => The binary packages
#		'Architecture' => [source] [all] or other
#		'Version' => The packages version.
#		'Distribution' => The intended distribution.
#		'Urgency' => How urgent the package installation is.
#		'Maintainer' => The package maintainer.
#		'Uploaders' => The other package maintainers.
#		... => other undocumentated things that can be used.
#	%CMeta
#		'ChangesFile' => The file.
#		'ChangesContent' => The content of the ChangeLog file.
#	%CFiles
#		$filename => "$hash $size $section $type"
#	%CDesc
#		$pkgname => "The short description of the package."
# ChangeLog:
#  2001-06-10 Ola Lundqvist <ola@inguza.com>
#  	Written.
#  2001-06-26 Ola Lundqvist <ola@inguza.com>
#  	Changed print to pdebug.
#  2002-09-11 Ola Lundqvist <ola@inguza.com>
#	Added uploaders field to the description.
#  2003-02-12 Ola Lundqvist <ola@inguza.com>
#	Added ChangesFile to CConf hash.
#  2003-03-14 Ola Lundqvist <ola@inguza.com>
#	Switched to using CMeta for ChangeLog meta information.
#  2005-05-01 Ola Lundqvist <ola@inguza.com>
#	Renamed to parseChangesFile.
#  2006-03-25 Jï¿½rï¿½my Bobbio <jeremy.bobbio@etu.upmc.fr>
#       One line fix for udeb support.
###############################################################################

sub parseChangesFile($) {
    my ($file) = @_;
    if ($file =~ /\|$/) {
	pdebug(2, "The changes file is not allowed to end in |, because that can cause a failure\nin the debarchiver program.");
    }
    open (F, $file);
    my $state = "";
    my $line;
    %CConf = ();
    %CMeta = (ChangesFile => $file, ChangesContent => "");
    %CFiles = ();
    %CDesc = ();
    while ($line = <F>) {
	$CMeta{ChangesContent} = $CMeta{ChangesContent} . $line;
	# The state to just put the line in the hash.
	if ($line =~ /^\s*$/) {
	    next;
	}
	$line =~ s/\n$//;
	if ($line =~ /^[^:]+:\s*$/) {
	    $line =~ s/^([^:]+):\s*$/$1/;
	    $state = $line;
	    pdebug(6, "State change to $state\n");
	}
	elsif ($line =~ /^\-+BEGIN PGP SIGNED MESSAGE\-+/) {
	    $state = "";
	    pdebug(6, "State change to normal state.\n");
	}
	elsif ($line =~ /^\-+BEGIN PGP SIGNATURE\-+/) {
	    $state = "PGP";
	    pdebug(6, "State change to $state\n");
	}
	elsif ($line =~ /^\-+END PGP SIGNATURE\-+/) {
	    $state = "END";
	    pdebug(6, "State change to $state\n");
	}
	# The default state.
	elsif ($state =~ /^$/) {
	    my $pre = $line;
	    $pre =~ s/:.*$//;
	    $line =~ s/^[^:]*:\s//;
	    $CConf{$pre} = $line;
	}
	# Description state.
	elsif ($state =~ /Description/) {
	    my ($pkg, $desc) = split /\s+\-\s+/, $line;
	    $pkg =~ s/^\s*//;
	    $desc =~ s/\s*$//;
	    $CDesc{$pkg} = $desc;
	    pdebug(6, "Saving desc '$desc' indexed by $pkg.\n");
	}
	# PGP Sign
	elsif ($state =~ /PGP/) {
	    pdebug(6, "Do nothing with $line\n");
	}
	# Changes state.
	elsif ($state =~ /Changes/) {
	    pdebug(6, "Do nothing with $line\n");
	}
	# Files state.
	elsif ($state =~ /Files/ && $line =~ /^ /) {
	    my @f = split / /, $line;
	    shift @f;
	    my $file = pop @f;
	    $CFiles{$file} = "$f[0] $f[1] $f[2] $f[3]";#[ @f ];
	    pdebug (6, "Saving file $file.\n");
	}
    }
}

###############################################################################
# Name:		parseOverrideFile
# Description:	Parses the override file.
# Arguments:	The distribution (like unstable)
#		The major dir (like main or contrib)
#		The src extention (undef or .src)
# Changes:	%Override	The override structure this overrides the
#				packages information.
# Changelog:
#  2001-06-26 Ola Lundqvist <ola@inguza.com>
#	Written.
#  2007-10-09 Turbo Fredriksson <turbo@bayour.com>
#       Change in foreach to use my variable.
###############################################################################

sub parseOverrideFile($$$) {
    my ($distr, $major, $srcext) = @_;
    my $def = ".pkg";
    if (defined $srcext && $srcext !~ /^\s*$/) {
	$def = $srcext;
    }
    pdebug(5, "override $def");
    if (! defined $Override{$distr, $major, $def}) {
	pdebug(5, "Load override file for $distr, $major");
	my $odir = "$destdir/$distr/$major";
	my @o = readfile("$odir/override$srcext");
	$Override{$distr,$major, $def} = 1;
	foreach my $tmp (@o) {
	    my ($pkg, $prio, $section, $maint) = split(/\s+/, $tmp, 4);
	    $pkg = "$pkg$srcext";
	    $Override{$distr, $major, $pkg, Priority} = $prio
		if ($prio    !~ /^\s*$/ && defined $prio   );
	    $Override{$distr, $major, $pkg, Section} = $section
		if ($section !~ /^\s*$/ && defined $section);
	    $Override{$distr, $major, $pkg, Maintainer} = $maint
		if ($maint   !~ /^\s*$/ && defined $maint  );
	    $Override{$distr, $major, $pkg} = 1;
	}
    }
}

###############################################################################
# Name:		relativePath
# Description:	Returns the relative path to another path.
# Arguments:	path to check for
#		path to give it against.
# Returns:	($pkgname, $version, $arch, $ext)
# Changelog:
#  2001-06-26 Ola Lundqvist <ola@inguza.com>
#	Written.
##############################################################################

sub relativePath ($$) {
    my ($p1, $p2) = @_;
    if ($p1 =~ /^\//) {
	return $p1;
    }
    elsif ($p1 =~ /^\~\//) {
	$p1 =~ s/^~\//$ENV{HOME}\//;
	return $p1;
    }
    $p2 =~ s/\/$//;
    return "$p2/$p1";
}

###############################################################################
# Name:		secondIfNotEmpty
# Description:	Returns the relative path to another path.
# Arguments:	two arguments
# Returns:	the second one if it is not empty, else the first one.
# Changelog:
#  2001-06-26 Ola Lundqvist <ola@inguza.com>
#	Written.
###############################################################################

sub secondIfNotEmpty ($$) {
    my ($p1, $p2) = @_;
    if (defined $p2 && $p2 !~ /^\s*$/) {
	return $p2;
    }
    return $p1;
}

###############################################################################
# Name:         check_commands
# Description:  Check command available through the hash %cmds
# Arguments:    %include_hr: set of commands to check
#                            they must be available into the hash %cmds
#               %exclude_hr: set of commands to exclude from the check
#                            they must be available into the hash %cmds
# Uses:         %cmds
# Changelog:
#  2004       Michael Rash <mbr@cipherdyne.com>
#   Function written (fwknop).
#  2008-09-28 Michael Rash <mbr@cipherdyne.com>
#   Updated (fwknop).
#  2009-03-15 Franck Joncourt <franck.mail@dthconnex.com>
#   Taken from fwknop (cipherdyne.com) (see changelog above)
#   and updated to suite debarchiver.
###############################################################################
sub check_commands() {
    my ($include_hr, $exclude_hr) = @_;

    my @path = qw(
        /bin
        /sbin
        /usr/bin
        /usr/sbin
        /usr/local/bin
        /usr/local/sbin
    );

    for my $cmd (keys %cmds) {
        if (keys %$include_hr) {
            next unless defined $include_hr->{$cmd};
        }
        if (keys %$exclude_hr) {
            next if defined $exclude_hr->{$cmd};
        }

        unless (-x $cmds{$cmd}) {
            my $found = 0;
            pdebug(4, "$cmd not located/executable at $cmds{$cmd}\n");

            PATH: for my $dir (@path) {
                if (-x "${dir}/${cmd}") {
                    $cmds{$cmd} = "${dir}/${cmd}";
                    $found = 1;
                    last PATH;
                }
            }

            if ($found) {
                pdebug(4,"Found $cmd at $cmds{$cmd}\n");
            } else {
                $err = 1;
                pdebug(4,  "Could not find $cmd anywhere.");
                return 1;
            }
        }

        unless (-x $cmds{$cmd}) {
            pdebug(4,  "Command $cmd is located at $cmds{$cmd}, but is not executable by uid: $<");
            return 1;
        }
    }

    return 0;
 }

###############################################################################
# Name:         check_mailconfig
# Description:  Check the mail settings
# Arguments:    none
# Uses:         @mailsearch, %cmds, $usermailcmd, $mailformat
# Changelog:
#  2009-03-15 Franck Joncourt <franck.mail@dthconnex.com>
#   Written
###############################################################################
sub  check_mailconfig()
{
    my @mailsearch = ();
    # If the user defines his own mail command through the --mailcmd option,
    # we check which mail format has to be used according to the --mailformat
    # option. Sendmail is the default behavior.
    if ( ($mailformat ne "") && ($usermailcmd eq "") ) {
        pdebug(2, "The mailformat option must be used in conjunction to the mailcmd option.");
    } elsif ( ($mailformat eq "sendmail") || ($mailformat eq "") ) {
        @mailsearch = ("sendmail", "mail");
    } elsif ($mailformat eq "mail") {
        @mailsearch = ("mail", "sendmail");
    } else {
        pdebug(2, "The mailformat option only supports either sendmail or mail format.");
    }

    # Check whether the user has specified its own mail command or not.
    # The full path to this one is stored in the cmd specify by first
    # value in the  array $mailformat.
    if ($usermailcmd ne "") {
        if (!File::Spec->file_name_is_absolute($usermailcmd)) {
            $usermailcmd = File::Spec->rel2abs($usermailcmd);
        }
        $usermailcmd !~ m|^(.*\/)+(.*)|;
        $cmds{$2} = $usermailcmd;
        $usermailcmd = $2;

        my $err = &check_commands({$usermailcmd => ''}, {});
        if ($err) {
            pdebug(2, "Unable to find $usermailcmd");
        }
        $cmds{$mailsearch[0]} = $cmds{$usermailcmd};
    }

    # Go through all of the mail commands, find one available and remove
    # the others from the hash.
    my $nberr = 0;
    my $found = 0;
    foreach $cmd (@mailsearch) {
        my $err = &check_commands({$cmd => ''}, {});
        if ($err) {
            delete $cmds{$cmd};
            $nberr++;
        } elsif ($found == 0) {
            $found = 1;
        } else {
            delete $cmds{$cmd};
        }
    }
    if ($nberr >= @mailsearch) {
        pdebug(2, "No mail command has been found.");
    }
}

__END__


###############################################################################
############################# DOCUMENTATION ###################################
###############################################################################

=head1 NAME

debarchiver - Tool to sort debian packages into a package archive.

=head1 SYNOPSIS

debarchiver [options]

=head1 DESCRIPTION

The debian archiver is a tool that installs debian packages into a file structure suitable for apt-get, aptitude, dselect and similar tools. This can be used for updating the Debian system. It is meant to be used by local administrators that need special packages, or tweaked versions to ease administration.

The file structure is based on the potato file structure and does not support package pools.

=head1 OPTIONS

=over 4

=item B<-a | --autoscan>

Does both --autoscanpackages and --autoscansources.

=item B<--autoscanall>

Same as --scanall --autoscan.

=item B<--autoscanpackages>

Automatically run dpkg-scanpackages after all new packages are installed.

=item B<--autoscansources>

Automatically run dpkg-scansources after all new packages are installed.

=item B<-b | --bzip>

Create bzip2 compressed Packages.bz2 and Sources.bz2 files. 

=item B<--cachedir> dir

The apt-ftparchive package cache directory, if --index is used. The default is $cachedir.

=item B<--cinstall> dir

Where the .changes file will be installed to. Use the empty string to remove the .changes file instead. The default is $cinstall.

=item B<--configfile> file

Specifies an extra configuration file to read. Will be read after etc configuration and after user configuration files.

=item B<--copycmd>

The install command to use where the default is $copycmd. Both packages and .changes files are installed using this command.

=item B<-d | --dest | --destdir> dir

Destination directory. The base directory where all the distribution packages will reside and where the $distrib/$major/$arch/$section directory structure will be created. The default is $destdir, relative to the input directory.

=item B<--debug-level | --dl> level

What information that should be printed. 1=critical, 2=error, 3=normal, 4=message, 5=debug, 6=verbose debug (modules).

=item B<--distinputcriteria>

The criteria for what binary packages should be installed even if they do not have a .changes file. The default is $distinputcriteria.
 
=item B<--gpgkey>

The GnuPG key to use to sign the archive.

=item B<--gpgpassfile>

The file that provides the password to GnuPG.

=item B<--help>

Prints this information.

=item B<-i | --input | --indir | --inputdir> dir

This is the directory where debarchiver will look for new package versions and corresponding *.changes files that should be installed to the --dest directory. The default is $instdir.

=item B<--ignoredestcheck>

Force install of .changes file even if some files specified in the .changes file already exists with wrong size or md5 hash.

=item B<--incompletetime>

The time to allow .changes file to be incomplete in seconds.
The default is 24 hours.

=item B<--index | -x>

Automatically run apt-ftparchive after all new packages are installed. Use this *or* --autoscan, not both.

=item B<--instcmd>

DEPRECATED!

=item B<--lockfile> file

The lockfile to use. The default is $lockfile.

=item B<--mailcmd>

The command to use to send emails. The default behavior is to use the
sendmail command.
You can disable email sending by specifying the /bin/true command.

=item B<--mailformat>

Defines the format to be used to send emails with, by the command specified
by --mailfrom. Only 'sendmail' and 'mail' formats are supported. By default
debarchiver assumes 'sendmail' format. The argument can be one of the
following:
  sendmail = use of the sendmail format
  mail     = use of the mail format

=item B<--mailfrom>

Specify mail sender.

=item B<--majordefault>

Default major section to use. The default is 'main'.

=item B<--movecmd>

Command to move files (currently not used at all).

=item B<--nosort>

Do not sort packages.

=item B<--nostructurefix>

Do not create directories and touch Package files.

=item B<-o | --addoverride>

Automatically add new packages to the override file.

=item B<--quit-level> level

On what level to quit the application, see debug level.

=item B<--rmcmd>

The remove command to use. The default is $rmcmd. This can be used to move away the old packages to some other place.

=item B<--scanall>

Scan all distributions, sections, etc.

=item B<--scandetect | -s>

Scan using 'apt-ftparchive' or 'dpkg-scan*' (dpkg-scanpackages and dpkg-scansources) depending on what is installed on the system. This is the recommended way. Only use --index or --autoscan if you know what you are doing.

=item B<--scanonly>

Same as --nosort --nostructurefix.

=item B<-v | --version>

Prints the version string.

=back

=head1 CONFIGURATION FILES

You can also place configuration files with the following names (in the
following order) /etc/debarchiver.conf, ~/.debarchiver.conf and input.conf
(relative to input directory) that will be read before the arguments to this
program will be parsed. In the above files you can change the following
variables:

The configuration files are read as perl modules they should end with a true
value. Therefore they should always end with a line that states '1;'.

=over 4

=item B<$bzip>

If set to 0 no bzip2 files will be generated. If set to 1 bzip2 files will
be generated.

=item B<$cachedir>

The cache directory for apt-ftparchive used if --index is used.

=item B<$cinstall>

Where the .changes files are installed (see --cinstall above).

=item B<$copycmd>

The install command (see --copycmd).

=item B<$destdir>

The destination directory (see --destdir above).

=item B<$distinputcriteria>

The criteria for which packages that should be installed even if it does not have a .changes file. The default is $distinputcriteria.

=item B<%distinputdirs>

Directories (distribution => dir) to be searched for extra binary packages that does not need a .changes file to be installed but match $distinputcriteria.  The default is to accept kernel packages generated by make-kpkg (which does not generate a .changes file). Additionally binary packages with a valid .changes file will have the default distribution overridden to be the current queue directory. This cause uploads to a specific queue to place the package into that distribution directly.

=item B<$gpgkey>

The GnuPG key to use to sign the archive. If this variable is set, the Release file for each changed section of the archive will be signed with GnuPG using $gpgkey as the key ID.  Unless you use a key that has no passphrase or use $gpgpassfile, you will need to run B<debarchiver> interactively when using this option so that you can supply the passphrase.

=item B<$gpgpassfile>

The file that contains the passphrase for the GnuPG key. See $gpgkey for more
information.

=item B<$ignoredestcheck>

Force install of .changes file even if some files specified in the .changes file already exist with wrong size or md5 hash. Default to 0 (do not ignore).

=item B<$incompletetime>

Time to allow .changes files to be incomplete in seconds. Useful for slow uploads.
The default is 24 hours.

=item B<$inputdir>

The input directory (no effect in $inputconfigfile).

=item B<$lockfile>

The lockfile to use. The default is $lockfile.

=item B<@mailtos>

An array of strings that will receive emails. If the string contains an email address that one is used. If it contains an incomplete email address, i.e. @hostname, the username owning the file is used @ the hostname specified. If no '@' character is found in the string, it is considered as a field in the .changes file. Such a field can for example be Maintainer or Uploaders.

=item B<$mailformat>

The format to use to send emails (see --mailformat above).

=item B<$mailfrom>

Specifies the sender of emails. The default is none ("")

=item B<$majordefault>

Default major section (see --majordefault above).

=item B<$movecmd>

The move command (see --movecmd).

=item B<%release>

Additional information to add to generated Release files. Supported keys are 'origin', 'label', and 'description'.

=item B<$rmcmd>

The remove command (see --rmcmd above).

=item B<$vrfycmd>

The verify command. Deprecated. Still functional but you are adviced to set
@vrfycmd instead as the $vrfycmd may be removed in future releases.

=item B<@vrfycmd>

The verify command. If the @vrfycmd list is empty is set to the list ($vrfycmd) just before the verify command is executed. It was made like this for backwards compatibility reasons.

=item B<$verifysignatures>

Choose to enable (1) or disable (0) signature verification for packages uploaded into $inputdir (not %distinputdirs).

=item B<$verifysignaturesdistinput>

Choose to enable (1) or disable (2) signature verification for packages uploaded into %distinputdirs. This works independently from $verifysignatures.

=item B<$usermailcmd>

It allows the user to tell debarchiver to use a specific command to send emails.
You may also want to specify the mailformat your mail command handles by
setting the value of the $mailformat variable. Using the --mailcmd option on the
command line will superseed this variable.
You can disable email sending by specifying the /bin/true command.

=back

=head1 PACKAGE INDEXING

There are two ways to generate the indexes that B<apt-get> relies on.

Using B<--autoscanpackages>, B<--autoscansources>, or B<--autoscan> will use B<dpkg-scanpackages> and B<dpkg-scansources>. This will generate the Packages and Sources files, but will not generate Contents files and can be slow with a large repository.

Alternatively, the B<--index> I<config> option will call B<apt-ftparchive> to index the package tree. B<apt-ftparchive> can also generate Contents files (for use with B<apt-file>), and can optionally use a cache of package information to speed up multiple runs.  The B<apt-ftparchive> configuration file will be generated automatically. This is however not fully tested.

You should use either B<--autoscanpackages> and B<--autoscansources> or B<--index>, not both, as they do basically the same thing.

The default action (and the recommended) is B<--scandetect> that probe for installed software and use the best choice depending on what software you have installed (chooses between --index and --autoscan right now).

=head1 REJECT

Changes files are rejected in the following conditions:
 * A file that is about to be installed already exist in the archive and is not identical to the one that is about to be installed.
 * Changes file is incomplete and has been there for $incompletetime time.
 * A file that is part of the Changes file is not yet big enough and the changes file has been there for $incompletetime time.
 * A file that is part of the Changes file is bigger than specified.
 * Verify signatures is enabled and signature do not match.

head  EXAMPLES

Suppose you have just uploaded package to repository e.g. with dput(1),
and you don't want to wait for the cron process to pick them up. You
can force immediate handling of incoming queue with this command. The
second option allows overwriting existing archive files.
 
 # debarchiver --scandetect --addoverride

=head1 FILES

B</etc/debarchiver.conf>

=head1 SEE ALSO

B<apt-ftparchive>(1)

=head1 AUTHOR

Ola Lundqvist <ola@inguza.com>

=cut
