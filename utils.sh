#!bin/bash

###############################################################################################
# Exit codes:
#   0 - Success
#   1 - Internet error
#   2 - Permissions error
###############################################################################################

function echoerr {
    echo "$@" 1>&2
}

function internet_error {
    echoerr "ERROR: Impossible to connect to Internet, double check your Internet connection."
    exit 1
}

function mkdir_error {
    local DIRECTORY_NAME
    DIRECTORY_NAME=$1
    echoerr "ERROR: Impossible to create directory \"${DIRECTORY_NAME}\", please double check your permissions."
    exit 2
}

function setup_git {
    # Setting user.name to a default value
    git config --global --get user.name
    if [ $? -ne 0 ]
    then
        git config --global user.name "Architech User"
    fi

    # Setting user.email to a default value
    git config --global --get user.email
    if [ $? -ne 0 ]
    then
        git config --global user.email ""
    fi

    git config --global --get color.ui
    if [ $? -ne 0 ]
    then
        git config --global color.ui "auto"
    fi
}

function install_repo {
    echo -n "Installing repo... "
    if [ ! -d ${CUSTOM_BIN_DIRECTORY} ]
    then
        mkdir ${CUSTOM_BIN_DIRECTORY}
        [ $? -eq 0 ] || mkdir_error
    fi
    if [ ! -f ${CUSTOM_BIN_DIRECTORY}/repo ]
    then
        curl http://commondatastorage.googleapis.com/git-repo-downloads/repo > ${CUSTOM_BIN_DIRECTORY}/repo 2> /dev/null
        [ $? -eq 0 ] || internet_error
        chmod a+x ${CUSTOM_BIN_DIRECTORY}/repo
    fi
    echo $PATH | grep "${CUSTOM_BIN_DIRECTORY}"
    if [ $? -ne 0 ]
    then
        export PATH="${PATH}:${CUSTOM_BIN_DIRECTORY}"
    fi

    echo "done!"
}

function prepare_environment {
    local CURRENT_DIRECTORY
    CURRENT_DIRECTORY=`pwd`
    SCRIPT_DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    cd ${SCRIPT_DIRECTORY}/..
    ROOT_DIRECTORY=`pwd`
    YOCTO_DIRECTORY="${ROOT_DIRECTORY}/yocto"
    cd ${CURRENT_DIRECTORY}

    CUSTOM_BIN_DIRECTORY=${HOME}/bin
    NR_CPUS=`grep -c ^processor /proc/cpuinfo`
}

function install_yocto {
    local BOARD_ALIAS
    local MACHINE_NAME
    local BRANCH
    local BB_NUMBER_THREADS
    local PARALLEL_MAKE
    local MATCH
    local MATCH_LINE
    local META_LAYERS_TO_MATCH
    local BBLAYER
    local BBLAYERS
    local BBLAYERS_FOUND
    local CURRENT_LAYER
    local LAYER_FOUND
    local CURRENT_LAYER_FULL_PATH
    local NUMBER_OF_LINES

    BOARD_ALIAS=$1
    BRANCH=$2
    MACHINE_NAME=$3

    # Yocto directory setup
    mkdir -p ${YOCTO_DIRECTORY} > /dev/null 2>&1
    [ $? -eq 0 ] || mkdir_error
    cd ${YOCTO_DIRECTORY}

    # repo setup
    if [ ! -f ${CUSTOM_BIN_DIRECTORY}/repo ]
    then
        install_repo
    fi

    # OpenEmbedded/Yocto sources installation
    if [ ! -d .repo ]
    then
        echo -n "Downloading ${BOARD_ALIAS} manifest... "
        repo init -u https://github.com/architech-boards/${BOARD_ALIAS}-manifest.git -b ${BRANCH} -m manifest.xml > /dev/null 2>&1
        [ $? -eq 0 ] || { rm -rf .repo; internet_error; }
        echo "done!"
    fi
    echo -n "Downloading OpenEmbedded/Yocto sources... "
    #repo sync > /dev/null 2>&1
    [ $? -eq 0 ] || internet_error
    echo "done!"

    # Configuration files setup    
    echo -n "Configuring Yocto... "
    ./poky/oe-init-build-env > /dev/null 2>&1

    # Setting up bitbake parallelism factor
    BB_NUMBER_THREADS=`echo "${NR_CPUS} * 2" | bc -l`
    if [ -n "`grep "^[ |\t]*BB_NUMBER_THREADS" build/conf/local.conf`" ]
    then        
        MATCH_LINE=`grep "^[ |\t]*BB_NUMBER_THREADS" build/conf/local.conf`
        sed -i "s|^${MATCH_LINE}|BB_NUMBER_THREADS ?= \"${BB_NUMBER_THREADS}\"|g" build/conf/local.conf
    elif [ -n "`grep "^[ |\t]*#[ |\t]*BB_NUMBER_THREADS" build/conf/local.conf`" ]
    then
        MATCH_LINE=`grep "^[ |\t]*#[ |\t]*BB_NUMBER_THREADS" build/conf/local.conf`
        sed -i "s|^${MATCH_LINE}|BB_NUMBER_THREADS ?= \"${BB_NUMBER_THREADS}\"|g" build/conf/local.conf   
    else
        echo "BB_NUMBER_THREADS ?= \"${BB_NUMBER_THREADS}\"" >> build/conf/local.conf
    fi

    # Setting up make parallelism factor
    PARALLEL_MAKE=${BB_NUMBER_THREADS}
    if [ -n "`grep "^[ |\t]*PARALLEL_MAKE" build/conf/local.conf`" ]
    then
        MATCH_LINE=`grep "^[ |\t]*PARALLEL_MAKE" build/conf/local.conf`
        sed -i "s|^${MATCH_LINE}|PARALLEL_MAKE ?= \"-j ${PARALLEL_MAKE}\"|g" build/conf/local.conf
    elif [ -n "`grep "^[ |\t]*#[ |\t]*PARALLEL_MAKE" build/conf/local.conf`" ]
    then
        MATCH_LINE=`grep "^[ |\t]*#[ |\t]*PARALLEL_MAKE" build/conf/local.conf`
        sed -i "s|^${MATCH_LINE}|PARALLEL_MAKE ?= \"-j ${PARALLEL_MAKE}\"|g" build/conf/local.conf   
    else
        echo "PARALLEL_MAKE ?= \"-j ${PARALLEL_MAKE}\"" >> build/conf/local.conf
    fi

    # Setting up machine type
    if [ -n "`grep "^[ |\t]*MACHINE" build/conf/local.conf`" ]
    then
        MATCH_LINE=`grep "^[ |\t]*MACHINE" build/conf/local.conf`
        sed -i "s|^${MATCH_LINE}|MACHINE ??= \"${MACHINE_NAME}\"|g" build/conf/local.conf
    else
        echo "MACHINE ??= \"${MACHINE_NAME}\"" >> build/conf/local.conf
    fi

    # Setting up packages type
    if [ -n "`grep "^[ |\t]*PACKAGE_CLASSES" build/conf/local.conf`" ]
    then
        MATCH_LINE=`grep "^[ |\t]*PACKAGE_CLASSES" build/conf/local.conf`
        sed -i "s|^${MATCH_LINE}|PACKAGE_CLASSES ?= \"package_ipk\"|g" build/conf/local.conf
    else
        echo "PACKAGE_CLASSES ?= \"package_ipk\"" >> build/conf/local.conf
    fi

    # Setting up meta layers
    META_LAYERS_TO_MATCH="poky/meta poky/meta-yocto poky/meta-yocto-bsp"
    for (( BBLAYER=4; BBLAYER<=$#; BBLAYER++ ))
    do
        META_LAYERS_TO_MATCH="${META_LAYERS_TO_MATCH} ${@:$BBLAYER:1}"
    done
    BBLAYERS=""
    BBLAYERS_FOUND=`sed -n "/^BBLAYERS /,/\"/ p" build/conf/bblayers.conf | sed "s|BBLAYERS||g" | sed "s|?||g" | sed "s|=||g" | sed "s|\"||g" | sed "s|\n||g" | sed "s|\\\\\\||g"`

    for BBLAYER in $BBLAYERS_FOUND
    do
        BBLAYERS="$BBLAYERS $BBLAYER"
    done

    for CURRENT_LAYER in ${META_LAYERS_TO_MATCH}
    do
        LAYER_FOUND="no"
        for BBLAYER in $BBLAYERS
        do
            if [ -n "`echo $BBLAYER | grep "$CURRENT_LAYER$"`" ]
            then
                LAYER_FOUND="yes"
            fi
        done
        if [ ${LAYER_FOUND} == "no" ]
        then
            CURRENT_LAYER_FULL_PATH=${YOCTO_DIRECTORY}/${CURRENT_LAYER}
            BBLAYERS="${BBLAYERS} ${CURRENT_LAYER_FULL_PATH}"
        fi
    done

    BBLAYERS="BBLAYERS ?= \"${BBLAYERS}\""

    if [ -z "`grep "^BBLAYERS " build/conf/bblayers.conf`" ]
    then
        echo "$BBLAYERS" >> build/conf/bblayers.conf
    else
        NUMBER_OF_LINES=`sed -n "/^BBLAYERS /,/\"/ {=;}" build/conf/bblayers.conf | wc -l`
        if [ $NUMBER_OF_LINES -gt 1 ]
        then
            sed -i "/^BBLAYERS /,/\"/ s/^/#/" build/conf/bblayers.conf
            echo "$BBLAYERS" >> build/conf/bblayers.conf
        else
            MATCH=`grep "^BBLAYERS " build/conf/bblayers.conf`
            sed -i "s|^${MATCH}|${BBLAYERS}|g" build/conf/bblayers.conf
        fi
    fi

    echo "done!"
}
