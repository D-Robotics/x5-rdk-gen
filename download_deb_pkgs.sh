#!/bin/bash
###
 # COPYRIGHT NOTICE
 # Copyright 2024 D-Robotics, Inc.
 # All rights reserved.
 # @Date: 2023-03-15 15:58:13
 # @LastEditTime: 2023-05-15 14:50:53
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

download_pkg_list=()

download_file()
{
    pkg_file="$1"
    pkg_url="$2"
    md5sum="$3"

    # Download the deb package
    echo "Downloading ${pkg_file} ..."
    if ! curl -fs -O --connect-timeout 5 --speed-limit 1024 --speed-time 5 --retry 3 "${pkg_url}"; then
        echo "Error: Unable to download ${pkg_file}" >&2
        rm -f "${pkg_file}"
        return 1
    fi

    # Calculate the md5sum of the downloaded file
    DOWNLOADED_MD5SUM=$(md5sum "${pkg_file}" | awk '{print $1}')

    # Verify the md5sum value of the downloaded file
    if [[ "${md5sum}" == "${DOWNLOADED_MD5SUM}" ]]; then
        echo "File ${pkg_file} verify successfully"
    else
        echo "File ${pkg_file} verify md5sum failed, Expected to be ${md5sum}, actually ${DOWNLOADED_MD5SUM}"
        rm "${pkg_file}"
        return 1
    fi
}

# Download the latest version of the deb package
get_download_pkg_list()
{
    pkg_list=($@)
    search_line=10;

    # Loop through each package name in the list
    for pkg_name in "${pkg_list[@]}"
    do
        # if pkg_name in download_pkg_list, skip add it
        if [[ ${download_pkg_list[@]} =~ "${pkg_name}," ]]; then
            continue
        fi

        # Get the latest version number from the Packages file
        VERSION=$(cat Packages | awk -v pkg="${pkg_name}" '$1 == "Package:" && $2 == pkg {while (getline) {if ($1 == "Version:") {print $2;break;}}}' | sort -V | tail -n1)
        if [[ $pkg_name == *xserver* ]]; then
            search_line=20
        else
            search_line=10
        fi
        FILENAME=$(grep -A ${search_line} -E "^Package: ${pkg_name}$" Packages | \
            grep -A $((search_line - 1)) -B 1 -E "Version: ${VERSION}$" | \
            grep '^Filename: ' | cut -d ' ' -f 2 | \
            sort -V | tail -n1)
        MD5SUM=$(grep -A ${search_line} -B 1 -E "Package: ${pkg_name}$" Packages | \
            grep -A $((search_line - 1)) -B 1 -E "Version: ${VERSION}$" | \
            grep '^MD5sum: ' | cut -d ' ' -f 2 | \
            sort -V | tail -n1)
        DEPENDS=$(grep -A ${search_line} -B 1 -E "Package: ${pkg_name}$" Packages | \
            grep -A $((search_line - 1)) -B 1 -E "Version: ${VERSION}$" | \
            grep '^Depends: ' | \
            cut -d ' ' -f 2- | \
            sed 's/,/ /g' || true)
        # echo "Package: ${pkg_name} Version: ${VERSION} FILENAME: ${FILENAME} MD5SUM: ${MD5SUM} DEPENDS: ${DEPENDS}"

        if [[ -z "$VERSION" ]]; then
            echo "Error: Unable to retrieve version number for $pkg_name" >&2
            return 1
        fi

        # Construct the name of the deb package
        PKG_FILE=$(basename "${FILENAME}")

        # Construct the download URL for the deb package
        PKG_URL="${RDK_ARCHIVE_URL}/${FILENAME}"

        # Add ${pkg_name},${PKG_FILE},${PKG_URL},${MD5SUM} into download_pkg_list
        download_pkg_list+=("${pkg_name},${VERSION},${PKG_FILE},${PKG_URL},${MD5SUM}")

        # Filter dependencies to include only those that start with "hobot" "tros" "xserver"
        DEPENDS=$(echo "${DEPENDS}" | awk '{for(i=1;i<=NF;i++) if($i ~ /^hobot/ || $i ~ /^tros/ || $i ~ /^xserver/) print $i}' | tr '\n' ' ')

        # Remove leading and trailing whitespace
        DEPENDS=$(echo "${DEPENDS}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # If DEPENDS is not empty, recursively parse dependent packages
        if [[ -n "${DEPENDS}" ]]; then
            get_download_pkg_list ${DEPENDS}
fi

    done
}

download_deb_pkgs()
{
    pkg_list=($@)

    # Loop through each package name in the list
    for pkg_info in "${pkg_list[@]}"; do
        # parse pkg_info into pkg_name, pkg_file, pkg_url, md5sum
        pkg_name=$(echo "${pkg_info}" | cut -d ',' -f 1)
        VERSION=$(echo "${pkg_info}" | cut -d ',' -f 2)
        PKG_FILE=$(echo "${pkg_info}" | cut -d ',' -f 3)
        PKG_URL=$(echo "${pkg_info}" | cut -d ',' -f 4)
        MD5SUM=$(echo "${pkg_info}" | cut -d ',' -f 5)

        # Get a list of all .deb files in the current directory with the same package name as pkg_name
        FILES=$(ls "${pkg_name}"_*.deb 2>/dev/null || true)

        # Loop through each file and delete any with a lower version number than the latest version
        for file in $FILES; do
            file_version="${file#${pkg_name}_}"
            file_version="${file_version%_arm64.deb}"

            if [[ $pkg_name == *xserver* ]]; then
                file_version="${file_version%_all.deb}"
                file_version="2:${file_version}"
            fi

            if [[ $file_version < $VERSION ]]; then
                echo "Deleting older version of ${file}"
                rm "${file}"
            fi
        done

        # Check if the package has already been downloaded
        if [[ -f "$PKG_FILE" ]]; then
            echo "$PKG_FILE already exists. Skipping download."
            # Calculate the md5sum of the downloaded file
            DOWNLOADED_MD5SUM=$(md5sum "${PKG_FILE}" | awk '{print $1}')

            # Verify the md5sum value of the downloaded file
            if [[ "${MD5SUM}" == "${DOWNLOADED_MD5SUM}" ]]; then
                echo "File ${PKG_FILE} verify successfully"
                continue
            else
                echo "File ${PKG_FILE} verify md5sum failed, Expected to be ${MD5SUM}, actually ${DOWNLOADED_MD5SUM}"
                rm "${PKG_FILE}"
            fi
        fi

        download_file "${PKG_FILE}" "${PKG_URL}" "${MD5SUM}"
        if [ $? -ne 0 ]; then
            echo "Error: Unable to download ${PKG_FILE}" >&2
            return 1
        fi
    done
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

    package_url="/dists/${RDK_UBUNTU_VERSION}/main/binary-arm64/Packages"

    [ -n "${RDK_DEB_PKG_DIR}" ] && [ ! -d "${RDK_DEB_PKG_DIR}" ] && mkdir "${RDK_DEB_PKG_DIR}"
    cd "${RDK_DEB_PKG_DIR}"

    if curl -sfO --connect-timeout 5 "${RDK_ARCHIVE_URL}${package_url}"; then
        echo "Packages downloaded successfully"
    else
        echo "Packages downloaded failed"
        return 1
    fi

    get_download_pkg_list "${RDK_DEB_PKG_LIST[@]}"
    # delete same item in download_pkg_list
    mapfile -t download_pkg_list < <(printf "%s\n" "${download_pkg_list[@]}" | sort -u)

    download_deb_pkgs "${download_pkg_list[@]}"
}

args=("$@")
main "${args[@]}"
