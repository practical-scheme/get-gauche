#!/bin/bash

set -e

# Ensure Gauche availability
# https://github.com/shirok/get-gauche/README

function usage() {
    cat <<"EOF"
Usage:
    get-gauche.sh [--system|--home|--current|--prefix PREFIX]
                  [--version VERSION][--check-only][--force]
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

CWD=`pwd`
WORKDIR=`mktemp -d $CWD/tmpXXXXXXXX`

function cleanup {
    if [ -d "$WORKDIR" ]; then
        rm -rf "$WORKDIR"
    fi
}

trap cleanup EXIT

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
        --system)   prefix=/usr ;;
        --home)     prefix=$HOME ;;
        --current)  prefix=`pwd` ;;
        --prefix)   prefix=$optarg; $extra_shift ;;

        --version)  version=$optarg; $extra_shift ;;
        
        --check-only) check_only=yes ;;
        --force)      force=yes ;;

        *) echo "bong"; usage; exit 1;;
    esac
    shift
done


