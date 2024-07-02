#!/bin/bash
###
 # COPYRIGHT NOTICE
 # Copyright 2023 Horizon Robotics, Inc.
 # All rights reserved.
 # @Date: 2023-03-15 15:58:13
 # @LastEditTime: 2023-05-15 14:50:53
###

archive_url="http://sunrise.horizon.cc/ubuntu-rdk"

deb_pkg_list=(hobot-multimedia-samples \
    hobot-sp-samples \
    hobot-io-samples \
    hobot-bpu-drivers \
    hobot-kernel-headers \
    hobot-miniboot \
    hobot-configs hobot-utils \
    hobot-display hobot-wifi \
    hobot-models-basic \
    tros )

download_pkg_list=()

download_file()
{
    pkg_file="$1"
    pkg_url="$2"
    md5sum="$3"

    # Download the deb package
    echo "Downloading ${pkg_file} ..."
    if ! curl -fs -O --connect-timeout 5 "$PKG_URL"; then
        echo "Error: Unable to download ${pkg_file}" >&2
        rm -f ${pkg_file}
        return 1
    fi

    # Calculate the md5sum of the downloaded file
    DOWNLOADED_MD5SUM=$(md5sum "${pkg_file}" | awk '{print $1}')

    # Verify the md5sum value of the downloaded file
    if [[ "${md5sum}" == "${DOWNLOADED_MD5SUM}" ]]; then
        echo "File ${pkg_file} verify successfully"
    else
        echo "File ${pkg_file} verify md5sum failed, Expected to be ${md5sum}, actually ${DOWNLOADED_MD5SUM}"
        rm ${pkg_file}
        return -1
    fi
}

# Download the latest version of the deb package
get_download_pkg_list()
{
    pkg_list=($@)

    # Loop through each package name in the list
    for pkg_name in ${pkg_list[@]}
    do
        # if pkg_name in download_pkg_list, skip add it
        if [[ ${download_pkg_list[@]} =~ "${pkg_name}," ]]; then
            continue
        fi

        # Get the latest version number from the Packages file
        VERSION=$(cat Packages | awk -v pkg=${pkg_name} '$1 == "Package:" && $2 == pkg {getline; print}' | awk '{print $2}' | sort -V | tail -n1)
        FILENAME=$(grep -A 10 -E "^Package: ${pkg_name}$" Packages | grep -A 9 -B 1 -E "Version: ${VERSION}$" | grep '^Filename: ' | cut -d ' ' -f 2 | sort -V | tail -n1)
        MD5SUM=$(grep -A 10 -B 1 -E "Package: ${pkg_name}$" Packages | grep -A 9 -B 1 -E "Version: ${VERSION}$" | grep '^MD5sum: ' | cut -d ' ' -f 2 | sort -V | tail -n1)
        DEPENDS=$(grep -A 10 -B 1 -E "Package: ${pkg_name}$" Packages | grep -A 9 -B 1 -E "Version: ${VERSION}$" | grep '^Depends: ' | cut -d ' ' -f 2- | sed 's/,/ /g')

        # echo "Package: ${pkg_name} Version: ${VERSION} FILENAME: ${FILENAME} MD5SUM: ${MD5SUM} DEPENDS: ${DEPENDS}"

        if [[ -z "$VERSION" ]]; then
            echo "Error: Unable to retrieve version number for $pkg_name" >&2
            return 1
        fi

        # Construct the name of the deb package
        PKG_FILE=$(basename "${FILENAME}")

        # Construct the download URL for the deb package
        PKG_URL="${archive_url}/${FILENAME}"

        # Add ${pkg_name},${PKG_FILE},${PKG_URL},${MD5SUM} into download_pkg_list
        download_pkg_list+=("${pkg_name},${VERSION},${PKG_FILE},${PKG_URL},${MD5SUM}")

        # delete name dose not start with "hobot" abd "tros"
        DEPENDS=$(echo ${DEPENDS} | awk '{for(i=1;i<=NF;i++) if($i ~ /^hobot/ || $i ~ /^tros/) print $i}')

        # delete head and tail empty string
        DEPENDS=$(echo "${DEPENDS[@]}" | sed 's/^ *//g' | sed 's/ *$//g')
        # if depends not null, recursively parse dependent packages
        [ ! -z "${DEPENDS[@]}" ] && get_download_pkg_list "${DEPENDS[@]}"
    done
}

download_deb_pkgs()
{
    pkg_list=($@)

    # Loop through each package name in the list
    for pkg_info in ${pkg_list[@]}
    do
        # parse pkg_info into pkg_name, pkg_file, pkg_url, md5sum
        pkg_name=$(echo ${pkg_info} | cut -d ',' -f 1)
        VERSION=$(echo ${pkg_info} | cut -d ',' -f 2)
        PKG_FILE=$(echo ${pkg_info} | cut -d ',' -f 3)
        PKG_URL=$(echo ${pkg_info} | cut -d ',' -f 4)
        MD5SUM=$(echo ${pkg_info} | cut -d ',' -f 5)

        # Get a list of all .deb files in the current directory with the same package name as pkg_name
        FILES=$(ls ${pkg_name}_*.deb 2>/dev/null || true)

        # Loop through each file and delete any with a lower version number than the latest version
        for file in $FILES; do
            file_version=$(echo ${file} | sed "s/${pkg_name}_\(.*\)_arm64.deb/\1/")
            if [[ $file_version < $VERSION ]]; then
                echo "Deleting older version of ${file}"
                rm "${file}"
            fi
        done

        # Check if the package has already been downloaded
        if [[ -f "$PKG_FILE" ]]; then
            echo "$PKG_FILE already exists. Skipping download."
            continue
        fi

        download_file ${PKG_FILE} ${PKG_URL} ${MD5SUM}
        if [ $? -ne 0 ]; then
            echo "Error: Unable to download ${PKG_FILE}" >&2
            return 1
        fi
    done
}

main()
{
    #./download_deb_pkgs.sh
    #deb_dir must first
    #-u focal/jammy default focal 
    #-d release/beta default release
    ubuntu_version="focal"
    develop_version="release"

    if [ $# -ge 1 ] ; then
        dep_pkg_dir="$1"
        shift
        echo "usag: ./download_deb_pkgs.sh dep_pkg_dir -u jammy -d release"
    else
        echo "failed!!!"
        echo "usag: ./download_deb_pkgs.sh dep_pkg_dir -u jammy -d release"
        return
    fi

    while (($# > 0))
    do
        if [ "$1" == "-u" ] ; then
            shift
            ubuntu_version=$1
        fi
        if [ "$1" == "-d" ] ; then
            shift
            develop_version=$1
        fi
        shift
    done

    if [ "$develop_version" == "beta" ] ; then
        archive_url="http://sunrise.horizon.cc/ubuntu-rdk-beta"
    fi

    if [ "$ubuntu_version" == "jammy" ] ; then
        deb_pkg_list=(hobot-multimedia-samples \
        hobot-sp-samples \
        hobot-io-samples \
        hobot-bpu-drivers \
        hobot-kernel-headers \
        hobot-miniboot \
        hobot-configs hobot-utils \
        hobot-display hobot-wifi \
        hobot-models-basic \
        tros-humble )
    fi

    package_url="/dists/""$ubuntu_version""/main/binary-arm64/Packages"

    [ ! -z ${dep_pkg_dir} ] && [ ! -d ${dep_pkg_dir} ] && mkdir ${dep_pkg_dir}
    cd ${dep_pkg_dir}

    if curl -sfO --connect-timeout 5 "${archive_url}${package_url}"; then
        echo "Packages downloaded successfully"
    else
        echo "Packages downloaded failed"
        return -1
    fi

    get_download_pkg_list "${deb_pkg_list[@]}"
    # delete same item in download_pkg_list
    download_pkg_list=($(echo "${download_pkg_list[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    download_deb_pkgs "${download_pkg_list[@]}"
}

main $@
