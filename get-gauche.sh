#!/bin/bash

set -e

API=https://practical-scheme.net/gauche/releases

# Ensure Gauche availability
# https://github.com/shirok/get-gauche/README

function usage {
    cat <<"EOF"
Usage:
    get-gauche.sh [--system|--home|--current|--prefix PREFIX|--update]
                  [--auto][--version VERSION][--check-only][--force][--list]
                  [--fixed-path][--keep-builddir][--sudo]
                  [--skip-tests][--configure-args ARGS][--uninstall]

Options:
    --auto
        When get-gauche.sh finds Gauche needs to be installed, it proceed
        to download and install without asking the user.  By default,
        the user is asked before download begins.

    --check-only
        detect Gauche and report result, but not to attempt download
        and install.

    --configure-args ARGS
        Pass ARGS to `configure' script of Gauche.  ARGS are passed as is.

    --current
        install Gauche under the current directory.
        Equivalent to --prefix `pwd`.

    --fixed-path
        detect Gauche only under prefix (specified by --prefix, --system,
        --home or --current option).  By default, get-gauche.sh also checks
        under directories in PATH.

    --force
        regardless of the result of version check, always download and
        install the specified version of Gauche.

    --home
        install Gauche under the user's home directory.
        Equivalent to --preifx $HOME.

    --keep-builddir
        Do not remove build directory after installation.  Useful for
        troubleshooting.   Build directory is created under the
        current directory with a name 'build-YYYYMMDD_hhmmss.xxxxxx'
        where 'YYYYMMDD_hhmmss' is the timestamp and 'xxxxxx' is a random
        string.

    --list
        show valid Gauche versions for --version option and exit.  No
        other operations are performed.

    --prefix PREFIX
        install Gauche under PREFIX.  The gosh executable is in PREFIX/bin,
        binary libraries are in PREFIX/lib, etc.

    --skip-tests
        Skip running self-tests before installing, in the emergency case
        when you have to do so.
        DO NOT USE THIS, unless you know what you're doing.

    --sudo
        invoke 'make install' via sudo.  Needed if you want to install
        Gauche where you don't have write permissions.  You may be asked
        to type your password by sudo.

    --uninstall
        uninstall the version of Gauche which would've been installed if
        this option weren't given.  The other versions of Gauche remains,
        if they exist.  Note: This operation removes all the files of the
        specified version, but may keep empty directories created by
        installation.

    --update
        install Gauche under the same directory as the currently installed
        one.  If no previous installation is found, get-gauche.sh prompts the
        user to type the directory.

    --system
        install Gauche under system directory.
        Equivalent to --prefix /usr.

    --version VERSION
        specify the desired version of Gauche.  VERSION can be a version
        string (e.g. '0.9.5'), or either 'latest' or 'snapshot'.  The word
        'latest' picks the latest release.  The word 'snapshot' picks the
        newest snapshot tarball if there's any newer than the latest
        release, or the latest release otherwise.
        By default, 'latest' is assumed.
EOF
}

function cleanup {
    if [ "$keep_builddir" != yes ]; then
        if [ -d "$WORKDIR" ]; then
            rm -rf "$WORKDIR"
        fi
    fi
}

trap cleanup EXIT

function do_list {
    curl -f $API/.txt
    exit 0
}

function do_check_for_windows1 {
    # check msys shell
    case `uname -a` in
        MSYS*)
            echo "Msys shell is not supported. Please use Mingw shell."
            echo "Aborting."
            exit 1
            ;;
    esac
    # check current path
    case `uname -a` in
        CYGWIN*|MINGW*)
            if pwd | grep -q "[[:space:]]"; then
                echo "Current path includes white space."
                echo "Please use current path not including white space."
                echo "Aborting."
                exit 1
            fi
            ;;
    esac
    # check openssl
    case `uname -a` in
        CYGWIN*|MINGW*)
            openssl=`/usr/bin/which openssl || :`
            if echo "$openssl" | grep -q -E "/mingw(64|32)"; then
                echo "$openssl causes make check hang-up."
                echo "Please delete or rename this."
                echo "Aborting."
                exit 1
            fi
            ;;
    esac
    # get mingw directory
    case `uname -a` in
        MINGW*)
            case "$MSYSTEM" in
                MINGW64)
                    mingwdir=${MINGWDIR:-/mingw64};;
                MINGW32)
                    mingwdir=${MINGWDIR:-/mingw32};;
                *)
                    #mingwdir=${MINGWDIR:-/mingw}
                    echo 'Environment variable MSYSTEM is neither "MINGW32" or "MINGW64".'
                    echo "Aborting."
                    exit 1
                    ;;
            esac
            ;;
    esac
}

function do_check_for_windows2 {
    # check version (v0.9.4 or earlier)
    case `uname -a` in
        CYGWIN*|MINGW*)
            case "$desired_version" in
                0.9.[234]|0.9.[234][._-]*)
                    echo "On Windows, this script doesn't support Gauche version 0.9.4 or earlier."
                    echo "Aborting."
                    exit 1
                    ;;
            esac
            ;;
    esac
}

function do_check_for_windows3 {
    # check install path (v0.9.6_pre3 or earlier)
    case `uname -a` in
        CYGWIN*|MINGW*)
            case "$desired_version" in
                0.9.6_pre[123]|0.9.[2345]|0.9.[2345][._-]*)
                    if echo "$prefix" | grep -q "[[:space:]]"; then
                        echo "Gauche version $desired_version can't be installed to the path"
                        echo "including white space directly."
                        echo "Please specify install path not including white space"
                        echo "and manually copy files to the real install path after"
                        echo "this script is finished."
                        echo "Aborting."
                        exit 1
                    fi
                    ;;
            esac
            ;;
    esac
    # check write permission
    case `uname -a` in
        CYGWIN*|MINGW*)
            if [ ! -d "$prefix" ]; then
                mkdir -p "$prefix"
            fi
            set +e
            write_check=`mktemp "$prefix/writechk.XXXXXXXX"`
            if [ $? -ne 0 ]; then
                echo "Administrator rights might be required."
                echo "Aborting."
                exit 1
            fi
            set -e
            if [ -f "$write_check" ]; then
                rm -f "$write_check"
            fi
            ;;
    esac
}

function do_check_prefix {
    gauche_config_path=`/usr/bin/which gauche-config 2>/dev/null ||:`
    if [ ! -z "$gauche_config_path" ]; then
        default_prefix=`gauche-config --prefix`
        existing_prefix=$default_prefix
    else
        default_prefix=/usr/local
        existing_prefix=
    fi
    if [ "$updating" = yes ]; then
        prefix=$existing_prefix
    fi
    if [ -z "$prefix" ]; then
        if [ "$auto" = yes ]; then
            echo "Prefix must be specified with --auto option."
            exit 1
        fi
        if [ "$check_only" = yes ]; then
            prefix=$default_prefix
        else
            echo -n "Where to install Gauche? Enter directory name [$default_prefix]: "
            read prefix < /dev/tty
            if [ -z "$prefix" ]; then
                prefix=$default_prefix
            fi
        fi
    fi
    # ensure prefix is absolute
    case $prefix in
        /*) ;;
        [A-Za-z]:*) ;;
        *) prefix=`pwd`/$prefix ;;
    esac

    case `uname -a` in
        CYGWIN*|MINGW*) prefix=`cygpath "$prefix"` ;;
        *) ;;
    esac
}

function do_check_gosh {
    # We already have $prefix set
    old_path=$PATH
    if [ $fixed_path = "yes" ]; then
        PATH=$prefix/bin
    else
        # We add $prefix/bin to path so that if gosh has been installed with
        # the given prefix we can find it.
        PATH=$prefix/bin:$PATH
    fi
    gosh_path=`/usr/bin/which gosh 2>/dev/null || :`
    PATH=$old_path
}

function check_destination {
    path=$1
    if [ -d $path ]; then
        if [ ! -w $path ]; then
            echo "NOTE: You don't have the write permission of the install destination ($prefix)."
            if [ x$auto = xyes ]; then
                echo "Use --sudo option to override permissions."
                exit 1
            else
                echo -n "Do you want to run 'make install' via sudo? [y/N]: "
                read ans < /dev/tty
                case "$ans" in
                    [yY]*) ;;
                    *) echo "Use --sudo option to override permissions."
                       exit 1;;
                esac
                echo "*** You may be asked your password by sudo before installation."
                SUDO=sudo
            fi
        fi
    elif [ -e $path ]; then
        echo "Won't be able to install, because $path is in the way."
        exit 1
    else
        check_destination `dirname $path`
    fi
}

function do_patch_to_source {
    case `uname -a` in
        CYGWIN*|MINGW*)
            # add libdir setting to avoid build error on install path
            patch_file=tools/gc-configure.gnu-gauche.in
            if [ -f $patch_file ]; then
                if ! grep -q -e '--libdir=/usr/local/lib' $patch_file; then
                    cp $patch_file $patch_file.bak
                    sed -e '/CPPFLAGS=/i \    --libdir=/usr/local/lib \\' $patch_file.bak > $patch_file
                fi
            fi
            # add double quotes to avoid build error on install path
            patch_file=lib/Makefile.in
            if [ -f $patch_file ]; then
                if ! grep -q -e '\"\$(exec_prefix)/bin/gosh\"' $patch_file; then
                    cp $patch_file $patch_file.bak
                    sed -e 's@\($(exec_prefix)/bin/gosh\)@\"\1\"@' $patch_file.bak > $patch_file
                fi
            fi
            # add preload module to avoid load error in gen-staticinit
            # (v0.9.6_pre6 or earlier)
            case "$desired_version" in
                0.9.6_pre[123456]|0.9.[2345]|0.9.[2345][._-]*)
                    patch_file=src/preload.scm
                    if [ -f $patch_file ]; then
                        if ! grep -q -e '(use gauche\.threads)' $patch_file; then
                            cp $patch_file $patch_file.bak
                            sed -e '/(use srfi-1)/i (use gauche.threads)' $patch_file.bak > $patch_file
                        fi
                    fi
                    ;;
            esac
            # skip standalone test to avoid link error in MinGW 32bit
            # (v0.9.6_pre6 or earlier)
            case "$desired_version" in
                0.9.6_pre[123456]|0.9.[2345]|0.9.[2345][._-]*)
                    patch_file=test/scripts.scm
                    if [ -f $patch_file ]; then
                        if ! grep -q -e ';(wrap-with-test-directory static-test-1)' $patch_file; then
                            cp $patch_file $patch_file.bak
                            sed -e 's@\((wrap-with-test-directory static-test-1)\)@;\1@' $patch_file.bak > $patch_file
                        fi
                    fi
                    ;;
            esac
            ;;
    esac
}

function do_copy_library_files {
    # copy mingw dll
    case `uname -a` in
        MINGW*)
            case "$MSYSTEM" in
                MINGW64|MINGW32)
                    mingw_dll="libwinpthread-1.dll";;
                *)
                    mingw_dll="mingwm10.dll";;
            esac
            for dll in $mingw_dll; do
                if [ -f $mingwdir/bin/$dll ]; then
                    cp $mingwdir/bin/$dll "$prefix/bin"
                fi
            done
            ;;
    esac
}

# After this, cwd is the top of the extracted source tree ready to be built.
function do_fetch_and_cd {
    CWD=`pwd`
    DATETIME=`date +%Y%m%d_%H%M%S`
    WORKDIR=`mktemp -d "$CWD/build-$DATETIME.XXXXXXXX"`

    uninstall=$1

    cd $WORKDIR
    if ! curl -f -L --progress-bar -o Gauche-$desired_version.tgz $API/$desired_version.tgz; then
        echo "Failed URL:" $API/$desired_version.tgz
        exit 1
    fi
    tar xf Gauche-$desired_version.tgz
    rm Gauche-$desired_version.tgz
    # The actual directory name may differ when $version is latest or snapshot
    cd Gauche-*

    do_patch_to_source
}

# Must be called in the top of extracted source tree
function do_install {
    case `uname -a` in
        CYGWIN*|MINGW*)
            ./configure "--prefix=$prefix" --with-dbm=ndbm,odbm $configure_args
            make
            if [ "$skip_tests" != yes ]; then
               make -s check
            fi
            make install
            (cd src; make install-mingw)
            make install-examples
            ;;
        *)
            ./configure "--prefix=$prefix" $configure_args
            MAKE=make
            if hash gmake 2>/dev/null; then MAKE=gmake; fi
            $MAKE -j
            if [ "$skip_tests" != yes ]; then
               $MAKE -s check
            fi
            $SUDO $MAKE install
            ;;
    esac

    do_copy_library_files

    echo "################################################################"
    echo "#  Gauche installed under $prefix/{bin,lib,share}"
    echo "################################################################"
}

function do_uninstall {
    case `uname -a` in
        CYGWIN*|MINGW*)
            ./configure "--prefix=$prefix" --with-dbm=ndbm,odbm $configure_args
            make uninstall
            ;;
        *)
            ./configure "--prefix=$prefix" $configure_args
            MAKE=make
            if hash gmake 2>/dev/null; then MAKE=gmake; fi
            $SUDO $MAKE uninstall
            ;;
    esac

    echo "################################################################"
    echo "#  Gauche uninstalled from $prefix/{bin,lib,share}"
    echo "################################################################"
}

function compare_version {
    "$gosh_path" -b <<EOF
(use gauche.version)
(if (version>? "$1" "$2")
  (print "GT")
  (print "LE"))
EOF
}

################################################################
# main entry point
#

prefix=
updating=
desired_version=latest
check_only=no
fixed_path=no
force=no
keep_builddir=no
configure_args=
skip_tests=no
SUDO=

if ! curl --version > /dev/null 2>&1; then
    echo "Can't find curl on this machine.  Please install it and run get-gauche.sh again."
    exit 1
fi

while test $# != 0
do
    case $1 in
        --*=?*)
            option=`expr "X$1" : 'X\([^=]*\)='`
            optarg=`expr "X$1" : 'X[^=]*=\(.*\)'`
            extra_shift=:
            ;;
        --*=)
            option=`expr "X$1" : 'X\([^=]*\)='`
            optarg=
            extra_shift=:
            ;;
        *)
            option=$1
            optarg=$2
            extra_shift=shift
            ;;
    esac

    case $option in
        --list)     do_list;;

        --system)   prefix=/usr ;;
        --home)     prefix=$HOME ;;
        --current)  prefix=`pwd` ;;
        --prefix)   prefix=$optarg; $extra_shift ;;
        --update)   updating=yes ;;
        --uninstall) uninstalling=yes ;;

        --version)  desired_version=$optarg; $extra_shift ;;

        --auto)          auto=yes ;;
        --check-only)    check_only=yes ;;
        --fixed-path)    fixed_path=yes ;;
        --force)         force=yes ;;
        --keep-builddir) keep_builddir=yes ;;
        --skip-tests)    skip_tests=yes ;;

        --configure-args) configure_args=$optarg; $extra_shift ;;

        --sudo)       SUDO=sudo ;;

        *) echo "Unrecognized option: $option"; usage; exit 1;;
    esac
    shift
done

do_check_for_windows1
do_check_prefix
do_check_gosh

#
# If --check-only, just report the check result and exit
#
if [ "$check_only" = yes ]; then
    if [ -z "$gosh_path" ]; then
        echo "Gauche not found"
        exit 1
    else
        echo "Found gosh in '$gosh_path'"
        "$gosh_path" -V
        exit 0
    fi
fi

#
# Resolve 'latest' and 'snapshot' versions to the actual version
#
case $desired_version in
    latest)   desired_version=`curl -f $API/latest.txt 2>/dev/null`;;
    snapshot) desired_version=`curl -f $API/snapshot.txt 2>/dev/null`;;
esac
do_check_for_windows2

#
# Compare with current version
#
if [ ! -z "$gosh_path" ]; then
   current_version=`"$gosh_path" -E "print (gauche-version)" -Eexit`
fi

if [ -z "$current_version" ]; then
    if [ "$fixed_path" = "yes" ]; then
        echo "Gauche is not found in $prefix."
    else
        echo "Gauche is not found on the system."
    fi
    need_install=yes
else
    cmp=`compare_version $desired_version $current_version`
    case $cmp in
        GT) echo "You have Gauche $current_version in '$gosh_path'."
            need_install=yes;;
        LE) echo "You already have Gauche $current_version in '$gosh_path'."
            if [ "$force" != yes ]; then
                echo "No need to install.  (Use --force option to install $desired_version.)"
            fi
            ;;
    esac
fi

#
# Proceed to install
#
if [ "$force" = yes -o "$need_install" = yes ]; then
    if [ "$auto" != yes ]; then
      if [ "$uninstalling" != yes ]; then
          echo -n "Install Gauche $desired_version under $prefix? [y/N]: "
      else
          echo -n "Uninstall Gauche $desired_version under $prefix? [y/N]: "
      fi
      read ans < /dev/tty
      case "$ans" in
          [yY]*) ;;
          *) exit 0;;
      esac
      if [ "$skip_tests" = yes ]; then
          echo -n "You specified to skip tests.  Are you sure? [y/N]: "
          read ans < /dev/tty
          case "$ans" in
              [yY]*) ;;
              *) exit 0;;
          esac
      fi
    fi
    case `uname -a` in
        CYGWIN*|MINGW*)
            do_check_for_windows3;;
        *)
            if [ x$SUDO = x ]; then
                check_destination $prefix
            fi
            ;;
    esac
    echo "Start installing Gauche $desired_version..."
    do_fetch_and_cd
    if [ "$uninstalling" != yes ]; then
        do_install
    else
        do_uninstall
    fi
fi
