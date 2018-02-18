#!/bin/bash

set -e

API=https://practical-scheme.net/gauche/releases

# Ensure Gauche availability
# https://github.com/shirok/get-gauche/README

function usage() {
    cat <<"EOF"
Usage:
    get-gauche.sh [--system|--home|--current|--prefix PREFIX|--update]
                  [--auto][--version VERSION][--check-only][--force][--list]
                  [--fixed-path][--sudo]
Options:
    --auto
        When get-gauche.sh finds Gauche needs to be installed, it proceed
        to download and install without asking the user.  By default,
        the user is asked before download begins.

    --check-only
        detect Gauche and report result, but not to attempt download
        and install.

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

    --list
        show valid Gauche versions for --version option and exit.  No
        other operations are performed.

    --prefix PREFIX
        install Gauche under PREFIX.  The gosh executable is in PREFIX/bin,
        binary libraries are in PREFIX/lib, etc.

    --sudo
        invoke 'make install' via sudo.  Needed if you want to install
        Gauche where you don't have write permissions.  You may be asked
        to type your password by sudo.

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
    if [ -d "$WORKDIR" ]; then
        rm -rf "$WORKDIR"
    fi
}

trap cleanup EXIT

function do_list {
    curl -f $API/.txt
    exit 0
}

function do_check_for_windows {
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
                    mingwdir=${MINGWDIR:-/mingw64}
                    ;;
                MINGW32)
                    mingwdir=${MINGWDIR:-/mingw32}
                    ;;
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

function do_check_prefix {
    gauche_config_path=`/usr/bin/which gauche-config ||:`
    if [ ! -z "$gauche_config_path" ]; then
        default_prefix=`gauche-config --prefix`
    else
        default_prefix=/usr/local
    fi
    if [ "$updating" = yes ]; then
        prefix=$existing_prefix
    fi
    if [ -z "$prefix" ]; then
        if [ "$auto" = yes ]; then
            echo "Prefix must be specified with --auto option."
            exit 1
        fi
        echo -n "Where to install Gauche? Enter directory name [$default_prefix]: "
        read prefix < /dev/tty
        if [ -z "$prefix" ]; then
            prefix=$default_prefix
        fi
    fi
    # ensure prefix is absolute
    case $prefix in
        /*) ;;
        [A-Za-z]:*) ;;
        *) prefix=`pwd`/$prefix ;;
    esac

    case `uname -a` in
        CYGWIN*|MINGW*)
            prefix=`cygpath "$prefix"`
            # check install path
            if echo "$prefix" | grep -q "[[:space:]]"; then
                echo "Install path includes white space."
                echo "Please specify install path not including white space"
                echo "and manually copy files to the real install path after"
                echo "this script is finished."
                echo "Aborting."
                exit 1
            fi
            ;;
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
    gosh_path=`/usr/bin/which gosh || :`
    PATH=$old_path
}

function do_fetch_and_install {
    CWD=`pwd`
    WORKDIR=`mktemp -d "$CWD/tmp.XXXXXXXX"`

    cd $WORKDIR
    if ! curl -f -L --progress-bar -o Gauche-$desired_version.tgz $API/$desired_version.tgz; then
        echo "Failed URL:" $API/$desired_version.tgz
        exit 1
    fi
    tar xf Gauche-$desired_version.tgz
    rm Gauche-$desired_version.tgz
    # The actual directory name may differ when $version is latest or snapshot
    cd Gauche-*
    case `uname -a` in
        CYGWIN*|MINGW*)
            ./configure "--prefix=$prefix" --with-dbm=ndbm,odbm
            make
            make -s check
            make install
            (cd src; make install-mingw)
            make install-examples
            ;;
        *)
            ./configure "--prefix=$prefix"
            make -j
            make -s check
            $SUDO make install
            ;;
    esac
    # copy mingw dll
    case `uname -a` in
        MINGW*)
            case "$MSYSTEM" in
                MINGW64|MINGW32)
                    for dll in libwinpthread-1.dll; do
                        if [ -f $mingwdir/bin/$dll ]; then
                            cp $mingwdir/bin/$dll $prefix/bin
                        fi
                    done
                    ;;
                *)
                    cp $mingwdir/bin/mingwm10.dll $prefix/bin
                    ;;
            esac
            ;;
    esac

    echo "################################################################"
    echo "#  Gauche installed under $prefix/bin"
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
SUDO=

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

        --version)  desired_version=$optarg; $extra_shift ;;
        
        --auto)       auto=yes ;;
        --check-only) check_only=yes ;;
        --fixed-path) fixed_path=yes ;;
        --force)      force=yes ;;

        --sudo)       SUDO=sudo ;;

        *) usage; exit 1;;
    esac
    shift
done

do_check_for_windows
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
        $gosh_version -V
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
      echo -n "Install Gauche $desired_version under $prefix? [y/N]: "
      read ans < /dev/tty
      case "$ans" in
          [yY]*) ;;
          *) exit 0;;
      esac
    fi
    echo "Start installing Gauche $desired_version..."
    do_fetch_and_install
fi
