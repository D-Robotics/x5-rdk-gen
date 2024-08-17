#!/bin/bash
###
 # COPYRIGHT NOTICE
 # Copyright 2024 D-Robotics, Inc.
 # All rights reserved.
 # @Date: 2023-03-24 21:02:31
 # @LastEditTime: 2023-05-15 14:35:12
###

set -euo pipefail

export HR_LOCAL_DIR="$( cd "$( dirname "$(readlink -f "${BASH_SOURCE[0]}")" )" && pwd )"

# Default configuration file
DEFAULT_CONFIG="${HR_LOCAL_DIR}/build_params/ubuntu-22.04_desktop_rdk-x5_release.conf"

# Initialize variable
CONFIG_FILE="$DEFAULT_CONFIG"

# Display help information
show_help() {
    echo "Usage: $0 [-c config_file] [-h]"
    echo
    echo "Options:"
    echo "  -c config_file  Specify the configuration file to use."
    echo "  -h              Display this help message."
    echo
    echo "If no configuration file is specified, the default file"
    echo "at ${DEFAULT_CONFIG} will be used."
}

main()
{
    # Parse options
    while getopts ":c:h" opt; do
        case ${opt} in
            c )
                CONFIG_FILE="$OPTARG"
                ;;
            h )
                show_help
                exit 0
                ;;
            \? )
                echo "Invalid option: -$OPTARG" >&2
                show_help
                exit 1
                ;;
            : )
                echo "Option -$OPTARG requires an argument." >&2
                show_help
                exit 1
                ;;
        esac
    done
    shift $((OPTIND -1))

    # Load the configuration file
    source "$CONFIG_FILE"

    ROOTFS_DIR="${HR_LOCAL_DIR}/${RDK_ROOTFS_DIR}"
    echo "Download Ubuntu ${RDK_UBUNTU_VERSION} ${RDK_IMAGE_TYPE}" \
        "${RDK_SAMPLEFS_VERSION} into ${ROOTFS_DIR}"

    [ -n "${ROOTFS_DIR}" ] && [ ! -d "${ROOTFS_DIR}" ] && mkdir "${ROOTFS_DIR}"
    cd "${ROOTFS_DIR}"

    FILE_NAME="samplefs_""${RDK_IMAGE_TYPE}"
    echo "FILE_NAME: $FILE_NAME"

    if [ "${RDK_SAMPLEFS_VERSION}" == "latest" ] ; then
        VERSION_FILE="samplefs_${RDK_IMAGE_TYPE}_${RDK_UBUNTU_VERSION}_latest.txt"

        echo "VERSION_FILE: ""$VERSION_FILE"

        # Download the version information file
        if curl -fs -O --connect-timeout 5 "${RDK_SAMPLEFS_URL}/${FILE_NAME}/${RDK_UBUNTU_VERSION}/${VERSION_FILE}"; then
            echo "File ${VERSION_FILE} downloaded successfully"
        else
            echo "File ${VERSION_FILE} downloaded failed"
        return 1
        fi

        # Extract the list of files to download from the version information file
        FILE=$(grep -v "^#" "$VERSION_FILE")
    else
        FILE="samplefs_${RDK_IMAGE_TYPE}_${RDK_UBUNTU_VERSION}-${RDK_SAMPLEFS_VERSION}.tar.gz"
    fi

    echo "FILE: ${FILE}"
    MD5_FILE=${FILE::-6}"md5sum"
    echo "MD5_FILE: ${MD5_FILE}"

    # Check if the file has already been downloaded
    if [[ -f "${FILE}" ]]; then
        echo "File ${FILE} already exists, skipping download"
        return 0
    fi

    # Download the md5sum file for the file
    if curl -fs -O --connect-timeout 5 "${RDK_SAMPLEFS_URL}/${FILE_NAME}/${RDK_UBUNTU_VERSION}/${MD5_FILE}"; then
        echo "File ${MD5_FILE} downloaded successfully"
    else
        echo "File ${MD5_FILE} downloaded failed"
        return 1
    fi

    # Extract the file name and md5sum value from the md5sum file
    FILE_MD5SUM=$(grep "${FILE_NAME}" "${MD5_FILE}" | cut -d " " -f1)

    # Download the file
    echo "Downloading ${FILE} ..."
    if curl -f -O --connect-timeout 5 "${RDK_SAMPLEFS_URL}/${FILE_NAME}/${RDK_UBUNTU_VERSION}/${FILE}"; then
        echo "File ${FILE} downloaded successfully"
    else
        echo "File ${FILE} downloaded failed"
        rm -f "${FILE}"
        return 1
    fi

    # Calculate the md5sum of the downloaded file
    DOWNLOADED_MD5SUM=$(md5sum "${FILE}" | awk '{print $1}')

    # Verify the md5sum value of the downloaded file
    if [[ "${FILE_MD5SUM}" == "${DOWNLOADED_MD5SUM}" ]]; then
        echo "File ${FILE} verify successfully"
    else
        echo "File ${FILE} verify md5sum failed, Expected to be ${FILE_MD5SUM}, actually ${DOWNLOADED_MD5SUM}"
        rm "${FILE}"
        return 1
    fi

    return 0
}

args=("$@")
main "${args[@]}"
