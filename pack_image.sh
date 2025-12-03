#!/bin/bash
###
 # COPYRIGHT NOTICE
 # Copyright 2024 D-Robotics, Inc.
 # All rights reserved.
 # @Date: 2023-04-15 00:47:08
 # @LastEditTime: 2023-05-23 16:56:41
###

set -euo pipefail

export HR_LOCAL_DIR="$( cd "$( dirname "$(readlink -f "${BASH_SOURCE[0]}")" )" && pwd )"

this_user="$(whoami)"
if [ "${this_user}" != "root" ]; then
    echo "[ERROR]: This script requires root privileges. Please execute it with sudo."
    exit 1
fi

# Default configuration file
DEFAULT_CONFIG="${HR_LOCAL_DIR}/build_params/ubuntu-22.04_desktop_rdk-x5_release.conf"

# Initialize variable
CONFIG_FILE="$DEFAULT_CONFIG"
LOCAL_BUILD="false"

# Display help information
show_help() {
    echo "Usage: $0 [-c config_file] [-h]"
    echo
    echo "Options:"
    echo "  -c config_file  Specify the configuration file to use."
    echo "  -l              Local build, skip download debain packages"
    echo "  -h              Display this help message."
    echo
    echo "If no configuration file is specified, the default file"
    echo "at ${DEFAULT_CONFIG} will be used."
}

# Parse options
while getopts ":c:lh" opt; do
    case ${opt} in
        c )
            CONFIG_FILE="$OPTARG"
            ;;
        l )
            LOCAL_BUILD="true"
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

# Output the configuration file being used (optional)
echo "Using configuration file: $CONFIG_FILE"
export | grep " RDK_"

# The location where the image is saved
export IMAGE_DEPLOY_DIR=${HR_LOCAL_DIR}/deploy
[ -n "${IMAGE_DEPLOY_DIR}" ] && [ ! -d "$IMAGE_DEPLOY_DIR" ] && mkdir "$IMAGE_DEPLOY_DIR"

IMG_FILE="${IMAGE_DEPLOY_DIR}/${RDK_IMAGE_NAME}"
ROOTFS_ORIG_DIR=${HR_LOCAL_DIR}/${RDK_ROOTFS_DIR}
ROOTFS_BUILD_DIR=${IMAGE_DEPLOY_DIR}/${RDK_ROOTFS_DIR}

rm -rf "${ROOTFS_BUILD_DIR}"
[ ! -d "$ROOTFS_BUILD_DIR" ] && mkdir "${ROOTFS_BUILD_DIR}"

function install_deb_chroot()
{
    local package=$1
    local dst_dir=$2

    if [[ $package == *xserver* ]]; then
        if ! chroot "${dst_dir}" /bin/bash -c "dpkg -l | grep xserver"; then
            echo "[INFO] rootfs do not have xserver, so do not install" "${package}"
            return 0
        fi
    fi

    cd "${dst_dir}/app/hobot_debs"
    echo "[INFO] Installing" "${package}"
    depends=$(dpkg-deb -f "${package}" Depends | sed 's/([^()]*)//g')
    if [ -f "${package}" ];then
        chroot "${dst_dir}" /bin/bash -c "dpkg --ignore-depends=${depends// /} -i /app/hobot_debs/${package}"
    fi
    echo "[INFO] Installed" "${package}"
    return 0
}

function install_packages()
{
    local dst_dir=$1
    if [ ! -d "${dst_dir}" ]; then
        echo "dst_dir is not exist!" "${dst_dir}"
        exit 1
    fi

    echo "Start install hobot packages"

    cd "${dst_dir}/app/hobot_debs"
    deb_list=$(ls | grep "^xserver" && ls | grep -v "^xserver")

    for deb_name in ${deb_list[@]}
    do
        install_deb_chroot "${deb_name}" "${dst_dir}"
    done

    chroot "${dst_dir}" /bin/bash -c "apt clean"
    echo "Install hobot packages is finished"
    return 0
}

function unmount() {
    if [ -z "$1" ]; then
        DIR=$PWD
    else
        DIR=$1
    fi

    while mount | grep -q "$DIR"; do
        local LOCS
        LOCS=$(mount | grep "$DIR" | cut -f 3 -d ' ' | sort -r)
        for loc in $LOCS; do
            umount "$loc"
        done
    done
    return 0
}

function unmount_image() {
    sync
    sleep 1
    LOOP_DEVICE=$(losetup --list | grep "$1" | cut -f1 -d' ' || true)
    if [ -n "${LOOP_DEVICE:-}" ]; then
        for part in "$LOOP_DEVICE"p*; do
            if DIR=$(findmnt -n -o target -S "$part"); then
                unmount "$DIR"
            fi
        done
        losetup -d "$LOOP_DEVICE"
    fi
    return 0
}

# Make Ubuntu rootfile system image
function make_ubuntu_image()
{
    # Unzip ubuntu samplefs to create image
    echo "tar -xzf ${ROOTFS_ORIG_DIR}/samplefs*.tar.gz -C ${ROOTFS_BUILD_DIR}"
    tar --same-owner --numeric-owner -xzpf "${ROOTFS_ORIG_DIR}"/samplefs*.tar.gz -C "${ROOTFS_BUILD_DIR}"
    mkdir -p "${ROOTFS_BUILD_DIR}"/{home,home/root,mnt,root,usr/lib,var,media}
    mkdir -p "${ROOTFS_BUILD_DIR}"/{tftpboot,var/lib,var/volatile,dev,proc,tmp}
    mkdir -p "${ROOTFS_BUILD_DIR}"/{run,sys,userdata,app,boot/hobot,boot/config}
    echo "${RDK_IMAGE_VERSION}" > "${ROOTFS_BUILD_DIR}"/etc/version

    # Custom Special Modifications
    echo "Custom Special Modifications"
    source hobot_customize_rootfs.sh
    hobot_customize_rootfs "${ROOTFS_BUILD_DIR}"

    # install debs
    echo "Install hobot debs in /app/hobot_debs"
    mkdir -p "${ROOTFS_BUILD_DIR}"/app/hobot_debs
    [ -d "${HR_LOCAL_DIR}/${RDK_DEB_PKG_DIR}" ] \
        && find "${HR_LOCAL_DIR}/${RDK_DEB_PKG_DIR}" \
        -maxdepth 1 -type f -name '*.deb' -exec cp -f {} \
        "${ROOTFS_BUILD_DIR}/app/hobot_debs" \;
    [ -d "${HR_LOCAL_DIR}/${RDK_THIRD_DEB_PKG_DIR}" ] \
        && find "${HR_LOCAL_DIR}/${RDK_THIRD_DEB_PKG_DIR}" \
        -maxdepth 1 -type f -name '*.deb' -exec cp -f {} \
        "${ROOTFS_BUILD_DIR}/app/hobot_debs" \;
    # merge deploy deb packages to rootfs, they are customer packages
    [ -d "${HR_LOCAL_DIR}/deploy/deb_pkgs" ] \
        && find "${HR_LOCAL_DIR}/deploy/deb_pkgs" \
        -maxdepth 1 -type f -name '*.deb' -exec cp -f {} \
        "${ROOTFS_BUILD_DIR}/app/hobot_debs" \;

    # delete same deb packages, keep the latest version
    cd "${ROOTFS_BUILD_DIR}/app/hobot_debs"
    deb_list=$(ls -1 *.deb | sort)
    for file in ${deb_list[@]}; do
        # Extract package name and version
        package=$(echo "$file" | awk -F"_" '{print $1}')
        version=$(echo "$file" | awk -F"_" '{print $2}')

        # If the current package name is different from the previous one, keep the current file (latest version)
        if [ "$package" != "${previous_package:-}" ]; then
            previous_file="$file"
            previous_package="$package"
            previous_version="$version"
        else
            # If the current package name is the same as the previous one, compare versions and delete older version files
            if dpkg --compare-versions "$version" gt "$previous_version"; then
                # Current version is newer, delete previous version files
                rm "${previous_file}"
                previous_file="$file"
                previous_version="$version"
            else
                # Previous version is newer, delete the current version file
                rm "$file"
            fi
        fi
    done

    install_packages "${ROOTFS_BUILD_DIR}"
    rm "${ROOTFS_BUILD_DIR}"/app/hobot_debs/ -rf

    chmod -R 775 "${ROOTFS_BUILD_DIR}/app"

    unmount_image "${IMG_FILE}"
    rm -f "${IMG_FILE}"

    ROOTFS_DIR=${IMAGE_DEPLOY_DIR}/rootfs_mount
    rm -rf "${ROOTFS_DIR}"
    mkdir -p "${ROOTFS_DIR}"

    CONFIG_SIZE="$((256 * 1024 * 1024))"
    ROOT_SIZE=$(du --apparent-size -s "${ROOTFS_BUILD_DIR}" --exclude var/cache/apt/archives --exclude boot/config --block-size=1 | cut -f 1)
    # All partition sizes and starts will be aligned to this size
    ALIGN="$((4 * 1024 * 1024))"
    # Add this much space to the calculated file size. This allows for
    # some overhead (since actual space usage is usually rounded up to the
    # filesystem block size) and gives some free space on the resulting
    # image.
    ROOT_MARGIN="$(echo "($ROOT_SIZE * 0.2 + 200 * 1024 * 1024) / 1" | bc)"

    CONFIG_PART_START=$((ALIGN))
    CONFIG_PART_SIZE=$(((CONFIG_SIZE + ALIGN - 1) / ALIGN * ALIGN))
    ROOT_PART_START=$((CONFIG_PART_START + CONFIG_PART_SIZE))
    ROOT_PART_SIZE=$(((ROOT_SIZE + ROOT_MARGIN + ALIGN  - 1) / ALIGN * ALIGN))
    IMG_SIZE=$((CONFIG_PART_START + CONFIG_PART_SIZE + ROOT_PART_SIZE))

    truncate -s "${IMG_SIZE}" "${IMG_FILE}"

    cd "${HR_LOCAL_DIR}"
    parted --script "${IMG_FILE}" mklabel msdos
    parted --script "${IMG_FILE}" unit B mkpart primary fat32 "${CONFIG_PART_START}" "$((CONFIG_PART_START + CONFIG_PART_SIZE - 1))"
    parted --script "${IMG_FILE}" unit B mkpart primary ext4 "${ROOT_PART_START}" "$((ROOT_PART_START + ROOT_PART_SIZE - 1))"
    # Set as boot partition
    parted "${IMG_FILE}" set 2 boot on

    echo "Creating loop device..."
    cnt=0
    until LOOP_DEV="$(losetup --show --find --partscan "$IMG_FILE")"; do
        if [ $cnt -lt 5 ]; then
            cnt=$((cnt + 1))
            echo "Error in losetup.  Retrying..."
            sleep 5
        else
            echo "ERROR: losetup failed; exiting"
            exit 1
        fi
    done

    CONFIG_DEV="${LOOP_DEV}p1"
    ROOT_DEV="${LOOP_DEV}p2"

    ROOT_FEATURES="^huge_file"
    for FEATURE in 64bit; do
        if grep -q "$FEATURE" /etc/mke2fs.conf; then
            ROOT_FEATURES="^$FEATURE,$ROOT_FEATURES"
        fi
    done
    mkdosfs -n CONFIG -F 32 -s 4 -v "$CONFIG_DEV" > /dev/null
    mkfs.ext4 -L rootfs -O "$ROOT_FEATURES" "$ROOT_DEV" > /dev/null

    mount -v "$ROOT_DEV" "${ROOTFS_DIR}" -t ext4
    mkdir -p "${ROOTFS_DIR}/boot/config"
    mount -v "$CONFIG_DEV" "${ROOTFS_DIR}/boot/config" -t vfat

    cd "${HR_LOCAL_DIR}"
    rsync -aHAXx --exclude /var/cache/apt/archives --exclude /boot/config "${ROOTFS_BUILD_DIR}/" "${ROOTFS_DIR}/"
    rsync -rtx "${HR_LOCAL_DIR}/config/" "${ROOTFS_DIR}/boot/config"
    sync
    unmount_image "${IMG_FILE}"
    rm -rf "${ROOTFS_DIR}"

    echo "Make Ubuntu Image successfully"

    exit 0
}

if [ "${LOCAL_BUILD}" == "false" ]; then
    "${HR_LOCAL_DIR}"/download_samplefs.sh -c "${CONFIG_FILE}"
    "${HR_LOCAL_DIR}"/download_deb_pkgs.sh -c "${CONFIG_FILE}"
fi

make_ubuntu_image
