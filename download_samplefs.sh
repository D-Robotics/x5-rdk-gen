#!/bin/bash
###
 # COPYRIGHT NOTICE
 # Copyright 2023 Horizon Robotics, Inc.
 # All rights reserved.
 # @Date: 2023-03-24 21:02:31
 # @LastEditTime: 2023-05-15 14:35:12
### 

set -e

main()
{
    #./download_samplefs.sh 
        #rootfs_dir must first
        #-t desktop/server default desktop
        #-u focal/jammy default focal 
        #-v v2.0.0/v2.1.0 default latest
    ubuntu_version="focal"
    ubuntufs_src="desktop"
    samplefs_version="latest"

    if [ $# -ge 1 ] ; then
        rootfs_dir="$1"
        shift
        echo "usag: ./download_samplefs.sh rootfs_dir -u jammy -t desktop -v latest or v2.1.0"
    else
        echo "failed!!!"
        echo "usag: ./download_samplefs.sh rootfs_dir -u jammy -t desktop -v latest or v2.1.0"
        return
    fi

    while (($# > 0))
    do
        if [ "$1" == "-t" ] ; then
            shift
            ubuntufs_src=$1
        fi
        if [ "$1" == "-u" ] ; then
            shift
            ubuntu_version=$1
        fi
        if [ "$1" == "-v" ] ; then
            shift
            samplefs_version=$1
        fi
        shift
    done

    echo $rootfs_dir $ubuntu_version $ubuntufs_src $samplefs_version

    [ ! -z ${rootfs_dir} ] && [ ! -d ${rootfs_dir} ] && mkdir ${rootfs_dir}
    cd ${rootfs_dir}

    # Set the URL of the file server
    SERVER_URL="http://sunrise.horizon.cc/samplefs"

    FILE_NAME="samplefs_""$ubuntufs_src"
    echo "FILE_NAME: " $FILE_NAME
    
    if [ "$samplefs_version" == "latest" ] ; then
        VERSION_FILE="samplefs_""$ubuntufs_src""_""$ubuntu_version""_latest.txt"

        echo "VERSION_FILE: "$VERSION_FILE

        # Download the version information file
        if curl -fs -O --connect-timeout 5 "${SERVER_URL}/${FILE_NAME}/${ubuntu_version}/${VERSION_FILE}"; then
            echo "File ${VERSION_FILE} downloaded successfully"
        else
            echo "File ${VERSION_FILE} downloaded failed"
        return -1
        fi

        # Extract the list of files to download from the version information file
        FILE=$(cat "$VERSION_FILE" | grep -v "^#")
    else
        FILE="samplefs_""$ubuntufs_src""_""$ubuntu_version""-""$samplefs_version"".tar.gz"
    fi

    echo "FILE: "$FILE
    MD5_FILE=${FILE::-6}"md5sum"
    echo "MD5_FILE: " $MD5_FILE

    # Check if the file has already been downloaded
    if [[ -f "${FILE}" ]]; then
        echo "File ${FILE} already exists, skipping download"
        return 0
    fi

    # Download the md5sum file for the file
    if curl -fs -O --connect-timeout 5 "${SERVER_URL}/${FILE_NAME}/${ubuntu_version}/${MD5_FILE}"; then
        echo "File ${MD5_FILE} downloaded successfully"
    else
        echo "File ${MD5_FILE} downloaded failed"
        return -1
    fi

    # Extract the file name and md5sum value from the md5sum file
    FILE_MD5SUM=$(cat "${MD5_FILE}" | grep ${FILE_NAME} | cut -d " " -f1)

    # Download the file
    echo "Downloading ${FILE} ..."
    if curl -f -O --connect-timeout 5 "${SERVER_URL}/${FILE_NAME}/${ubuntu_version}/${FILE}"; then
        echo "File ${FILE} downloaded successfully"
    else
        echo "File ${FILE} downloaded failed"
        rm -f ${FILE}
        return -1
    fi

    # Calculate the md5sum of the downloaded file
    DOWNLOADED_MD5SUM=$(md5sum "${FILE}" | awk '{print $1}')

    # Verify the md5sum value of the downloaded file
    if [[ "${FILE_MD5SUM}" == "${DOWNLOADED_MD5SUM}" ]]; then
        echo "File ${FILE} verify successfully"
    else
        echo "File ${FILE} verify md5sum failed, Expected to be ${FILE_MD5SUM}, actually ${DOWNLOADED_MD5SUM}"
        rm ${FILE}
        return -1
    fi


    return 0
}

main $@
