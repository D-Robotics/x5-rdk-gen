#!/bin/bash
###
 # COPYRIGHT NOTICE
 # Copyright 2023 Horizon Robotics, Inc.
 # All rights reserved.
 # @Date: 2023-04-15 00:47:08
 # @LastEditTime: 2023-05-23 16:56:41
### 

set -e

export HR_LOCAL_DIR=$(realpath $(cd $(dirname $0); pwd))

this_user="$(whoami)"
if [ "${this_user}" != "root" ]; then
    echo "[ERROR]: This script requires root privileges. Please execute it with sudo."
    exit 1
fi


# 编译出来的镜像保存位置
export IMAGE_DEPLOY_DIR=${HR_LOCAL_DIR}/deploy
[ ! -z ${IMAGE_DEPLOY_DIR} ] && [ ! -d $IMAGE_DEPLOY_DIR ] && mkdir $IMAGE_DEPLOY_DIR

IMG_FILE="${IMAGE_DEPLOY_DIR}/ubuntu-preinstalled-desktop-arm64.img"
ROOTFS_ORIG_DIR=${HR_LOCAL_DIR}/rootfs
ROOTFS_BUILD_DIR=${IMAGE_DEPLOY_DIR}/rootfs

if [[ $# -ge 1 && "$1" = "server" ]]; then
    IMG_FILE="${IMAGE_DEPLOY_DIR}/ubuntu-preinstalled-server-arm64.img"
    ROOTFS_ORIG_DIR=${HR_LOCAL_DIR}/rootfs_server
    ROOTFS_BUILD_DIR=${IMAGE_DEPLOY_DIR}/rootfs_server
fi

rm -rf ${ROOTFS_BUILD_DIR}
[ ! -d $ROOTFS_BUILD_DIR ] && mkdir ${ROOTFS_BUILD_DIR}


function install_deb_chroot()
{
    local package=$1
    local dst_dir=$2

    cd "${dst_dir}/app/hobot_debs"
    echo "###### Installing" "${package} ######"
    depends=$(dpkg-deb -f "${package}" Depends | sed 's/([^()]*)//g')
    if [ -f ${package} ];then
        chroot "${dst_dir}" /bin/bash -c "dpkg --ignore-depends=${depends// /} -i /app/hobot_debs/${package}"
    fi
    echo "###### Installed" "${package} ######"
}

function install_packages()
{
    local dst_dir=$1
    if [ ! -d ${dst_dir} ]; then
        echo "dst_dir is not exist!" "${dst_dir}"
        exit -1
    fi

    echo "Start install hobot packages"

    cd "${dst_dir}/app/hobot_debs"
    deb_list=$(ls)

    for deb_name in ${deb_list[@]}
    do
        install_deb_chroot "${deb_name}" "${dst_dir}"
    done

    chroot ${dst_dir} /bin/bash -c "apt clean"
    echo "Install hobot packages is finished"
}

function unmount(){
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
    }

function unmount_image(){
    sync
    sleep 1
    LOOP_DEVICE=$(losetup --list | grep "$1" | cut -f1 -d' ')
    if [ -n "$LOOP_DEVICE" ]; then
        for part in "$LOOP_DEVICE"p*; do
            if DIR=$(findmnt -n -o target -S "$part"); then
                unmount "$DIR"
            fi
        done
        losetup -d "$LOOP_DEVICE"
    fi
}

# 制作 ubuntu 根文件系统镜像
function make_ubuntu_image()
{
    # ubuntu 系统直接解压制作image
    echo "tar -xzf ${ROOTFS_ORIG_DIR}/samplefs*.tar.gz -C ${ROOTFS_BUILD_DIR}"
    tar --same-owner --numeric-owner -xzpf ${ROOTFS_ORIG_DIR}/samplefs*.tar.gz -C ${ROOTFS_BUILD_DIR}
    mkdir -p ${ROOTFS_BUILD_DIR}/{home,home/root,mnt,root,usr/lib,var,media,tftpboot,var/lib,var/volatile,dev,proc,tmp,run,sys,userdata,app,boot/hobot,boot/config}
    cat "${HR_LOCAL_DIR}/VERSION" > ${ROOTFS_BUILD_DIR}/etc/version

    # Custom Special Modifications
    echo "Custom Special Modifications"
    source hobot_customize_rootfs.sh
    hobot_customize_rootfs ${ROOTFS_BUILD_DIR}

    # install debs
    echo "Install hobot debs in /app/hobot_debs"
    mkdir -p ${ROOTFS_BUILD_DIR}/app/hobot_debs
    [ -d "${HR_LOCAL_DIR}/deb_packages" ] && find "${HR_LOCAL_DIR}/deb_packages" -maxdepth 1 -type f -name '*.deb' -exec cp -f {} "${ROOTFS_BUILD_DIR}/app/hobot_debs" \;
    [ -d "${HR_LOCAL_DIR}/third_packages" ] && find "${HR_LOCAL_DIR}/third_packages" -maxdepth 1 -type f -name '*.deb' -exec cp -f {} "${ROOTFS_BUILD_DIR}/app/hobot_debs" \;
    # merge deploy deb packages to rootfs, they are customer packages
    [ -d "${HR_LOCAL_DIR}/deploy/deb_pkgs" ] && find "${HR_LOCAL_DIR}/deploy/deb_pkgs" -maxdepth 1 -type f -name '*.deb' -exec cp -f {} "${ROOTFS_BUILD_DIR}/app/hobot_debs" \;
    # delete same deb packages, keep the latest version
    cd "${ROOTFS_BUILD_DIR}/app/hobot_debs"
    deb_list=$(ls -1 *.deb | sort)
    for file in ${deb_list[@]}; do
        # Extract package name and version
        package=$(echo $file | awk -F"_" '{print $1}')
        version=$(echo $file | awk -F"_" '{print $2}')

        # If the current package name is different from the previous one, keep the current file (latest version)
        if [ "$package" != "$previous_package" ]; then
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

    install_packages ${ROOTFS_BUILD_DIR}
    rm ${ROOTFS_BUILD_DIR}/app/hobot_debs/ -rf
    rm -rf ${ROOTFS_BUILD_DIR}/lib/aarch64-linux-gnu/dri/

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
    # 设置为启动分区
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

    md5sum "${IMG_FILE}" > ${IMG_FILE}.md5sum

    echo "Make Ubuntu Image successfully"

    exit 0
}

if [[ $# -eq 0 || ( $# -eq 1 && "$1" = "server" ) ]]; then
    if [[ $# -eq 1 && "$1" = "server" ]]; then
        ${HR_LOCAL_DIR}/download_samplefs.sh ${ROOTFS_ORIG_DIR} "-u" "jammy" "-t" "server"
    else
        ${HR_LOCAL_DIR}/download_samplefs.sh ${ROOTFS_ORIG_DIR} "-u" "jammy"
    fi
    ${HR_LOCAL_DIR}/download_deb_pkgs.sh ${HR_LOCAL_DIR}/deb_packages "-u" "jammy"
fi

make_ubuntu_image

