#!/bin/bash

set -e

API=https://practical-scheme.net/gauche/releases

# Ensure Gauche availability
# https://github.com/shirok/get-gauche/README

function usage() {
    cat <<"EOF"
Usage:
    get-gauche.sh [--system|--home|--current|--prefix PREFIX]
                  [--version VERSION][--check-only][--force][--list]
Options:
    --check-only
        detect Gauche and report result, but not to attempt download
        and install.

    --current
        install Gauche under the current directory.
        Equivalent to --prefix `pwd`.

    --force
        do not check if Gauche has already installed or not, and always
        download ans install one.

    --home
        install Gauche under the user's home directory.
        Equivalent to --preifx $HOME.

    --list
        show valid Gauche versions for --version option and exit.  No
        other operations are performed.

    --prefix PREFIX
        install Gauche under PREFIX.  The gosh executable is in PREFIX/bin,
        binary libraries are in PREFIX/lib, etc.

    --static
        build and install static library as well.  Note: The static library
        excludes gdbm libraries to avoid licensing complication.

    --system
        install Gauche under system directory.
        Equivalen to --prefix /usr.

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

function do_check_gosh {
    if [ $prefix = `pwd` ]; then
        PATH=`pwd`/bin:$PATH
    fi
}

function do_fetch_and_install {
    CWD=`pwd`
    WORKDIR=`mktemp -d $CWD/tmp.XXXXXXXX`

    cd $WORKDIR
    if ! curl -f -L -o Gauche-$version.tgz $API/$version.tgz; then
        echo "Failed URL:" $API/$version.tgz
        exit 1
    fi
    tar xf Gauche-$version.tgz
    # The actual directory name may differ when $version is latest or snapshot
    cd Gauche-*
    ./configure --prefix=$prefix
    make -j
    make -s check
    make install
    if test X"$staticlib" = Xyes; then
        echo `pwd`
        (cd src; LIBGAUCHE_STATIC_EXCLUDES=dbm.gdbm,dbm.ndbm,dbm.odbm make --no-print-directory BUILD_GOSH=$prefix/bin/gosh static)
        cp src/libgauche-static-*.a $prefix/lib
    fi

    echo "################################################################"
    echo "#  Gauche installed under $prefix/bin"
    echo "################################################################"
}

################################################################
# main entry point
#

prefix=$HOME
version=latest
check_only=no
force=no

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

        --version)  version=$optarg; $extra_shift ;;
        
        --check-only) check_only=yes ;;
        --force)      force=yes ;;

        --static)   staticlib=yes ;;

        *) usage; exit 1;;
    esac
    shift
done

if [ "$force" = yes -o "$check_only" != yes ]; then
    do_fetch_and_install
fi
