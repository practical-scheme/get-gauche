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
    curl $API/.txt
    exit 0
}

function do_fetch_and_install {
    CWD=`pwd`
    WORKDIR=`mktemp -d $CWD/tmp.XXXXXXXX`

    cd $WORKDIR
    curl -L -o Gauche-$version.tgz $API/$version.tgz
    tar xf Gauche-$version.tgz
    cd Gauche-$version
    ./configure --prefix=$prefix
    make -j
    make -s check
    make install

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

        *) usage; exit 1;;
    esac
    shift
done

if [ $force = yes -o $check_only != yes ]; then
    do_fetch_and_install
fi

