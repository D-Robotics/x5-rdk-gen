#!/bin/bash
###
 # COPYRIGHT NOTICE
 # Copyright 2023 Horizon Robotics, Inc.
 # All rights reserved.
 # @Date: 2023-03-16 15:02:28
 # @LastEditTime: 2023-03-22 18:52:51
###

set -e

export CROSS_COMPILE=/opt/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-
export LD_LIBRARY_PATH=/opt/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu/lib64:$LD_LIBRARY_PATH
export ARCH=arm64
export HR_TOP_DIR=$(realpath $(cd $(dirname $0); pwd))
export HR_LOCAL_DIR=$(realpath $(cd $(dirname $0); pwd))


# 编译出来的镜像保存位置
export IMAGE_DEPLOY_DIR=${HR_TOP_DIR}/deploy
[ -n "${IMAGE_DEPLOY_DIR}" ] && [ ! -d "$IMAGE_DEPLOY_DIR" ] && mkdir "$IMAGE_DEPLOY_DIR"

KERNEL_BUILD_DIR=${IMAGE_DEPLOY_DIR}/kernel
[ -n "${IMAGE_DEPLOY_DIR}" ] && [ ! -d ""${KERNEL_BUILD_DIR}"" ] && mkdir "$KERNEL_BUILD_DIR"

N=$(($(grep -c 'processor' /proc/cpuinfo) - 2 ))

# 默认使用emmc配置，对于nor、nand需要使用另外的配置文件
kernel_config_file=hobot_x5_rdk_ubuntu_defconfig
kernel_image_name="Image.lz4"

KERNEL_SRC_DIR=${HR_TOP_DIR}/source/kernel

kernel_version=$(awk "/^VERSION =/{print \$3}" "${KERNEL_SRC_DIR}"/Makefile)
kernel_patch_lvl=$(awk "/^PATCHLEVEL =/{print \$3}" "${KERNEL_SRC_DIR}"/Makefile)
kernel_sublevel=$(awk "/^SUBLEVEL =/{print \$3}" "${KERNEL_SRC_DIR}"/Makefile)
export KERNEL_VER="${kernel_version}.${kernel_patch_lvl}.${kernel_sublevel}"

function pre_pkg_preinst() {
    # Get the signature algorithm used by the kernel.
    module_sig_hash="$(grep -Po '(?<=CONFIG_MODULE_SIG_HASH=").*(?=")' "${KERNEL_SRC_DIR}/.config")"
    # Get the key file used by the kernel.
    module_sig_key="$(grep -Po '(?<=CONFIG_MODULE_SIG_KEY=").*(?=")' "${KERNEL_SRC_DIR}/.config")"
    module_sig_key="${module_sig_key:-certs/hobot_fixed_signing_key.pem}"
    # Path to the key file or PKCS11 URI
    if [[ "${module_sig_key#pkcs11:}" == "${module_sig_key}" && "${module_sig_key#/}" == "${module_sig_key}" ]]; then
        local key_path="${KERNEL_SRC_DIR}/${module_sig_key}"
    else
        local key_path="${module_sig_key}"
    fi
    # Certificate path
    local cert_path="${KERNEL_SRC_DIR}/certs/signing_key.x509"
    # Sign all installed modules before merging.
    find "${KO_INSTALL_DIR}"/lib/modules/"${KERNEL_VER}"/ -name "*.ko" -exec "${KERNEL_SRC_DIR}/scripts/sign-file" "${module_sig_hash}" "${key_path}" "${cert_path}" '{}' \;
}

function make_kernel_headers() {
    SRCDIR=${KERNEL_SRC_DIR}
    HDRDIR="${KERNEL_BUILD_DIR}"/kernel_headers/usr/src/linux-headers-6.1.83
    mkdir -p "${HDRDIR}"

    cd "${SRCDIR}"

    mkdir -p "${HDRDIR}"/arch
    cp -Rf "${SRCDIR}"/arch/arm64        "${HDRDIR}"/arch/
    cp -Rf "${SRCDIR}"/include           "${HDRDIR}"
    cp -Rf "${SRCDIR}"/scripts           "${HDRDIR}"
    cp -Rf "${SRCDIR}"/Module.symvers    "${HDRDIR}"
    cp -Rf "${SRCDIR}"/Makefile          "${HDRDIR}"
    cp -Rf "${SRCDIR}"/System.map        "${HDRDIR}"
    cp -Rf "${SRCDIR}"/.config           "${HDRDIR}"
    cp -Rf "${SRCDIR}"/security          "${HDRDIR}"
    cp -Rf "${SRCDIR}"/tools             "${HDRDIR}"
    cp -Rf "${SRCDIR}"/certs             "${HDRDIR}"

    rm -rf "${HDRDIR}"/arch/arm64/boot

    cd "${SRCDIR}"
    find . -iname "KConfig*" -print0 | while IFS= read -r -d '' file; do
        cp --parents -Rf "$file" "${HDRDIR}"
    done

    find . -iname "Makefile*" -print0 | while IFS= read -r -d '' file; do
        cp --parents -Rf "$file" "${HDRDIR}"
    done

    find . -iname "*.pl" -print0 | while IFS= read -r -d '' file; do
        cp --parents -Rf "$file" "${HDRDIR}"
    done
    cd "${HR_LOCAL_DIR}"

    find "${HDRDIR}" -depth -name '.svn' -type d  -exec rm -rf {} \;

    find "${HDRDIR}" -depth -name '*.c' -type f -exec rm -rf {} \;

    exclude=("*.c" \
            "*.o" \
            "*.S" \
            "*.s" \
            "*.ko" \
            "*.cmd" \
            "*.a" \
            "modules.builtin" \
            "modules.order")
    for element in "${exclude[@]}"
    do
        find "${HDRDIR}" -depth -name "${element}" -type f -exec rm -rf {} \;
    done

    cd "${SRCDIR}"
    find . -iname "*.c" -print0 | while IFS= read -r -d '' file; do
        cp --parents -Rf "$file" "${HDRDIR}"
    done
    make M="${HDRDIR}"/scripts clean

    cd "${HR_LOCAL_DIR}"
    rm -rf "${HDRDIR}"/arch/arm64/mach*
    rm -rf "${HDRDIR}"/arch/arm64/plat*

    mv "${HDRDIR}"/include/asm-generic/ "${HDRDIR}"/
    rm -rf "${HDRDIR}"/inclde/asm-*
    mv "${HDRDIR}"/asm-generic "${HDRDIR}"/include/

    rm -rf "${HDRDIR}"/arch/arm64/configs

    rm -rf "${HDRDIR}"/debian
}

function build_all()
{
    # 生成内核配置.config
    make $kernel_config_file || {
        echo "make $config failed"
        exit 1
    }

    # 编译生成 zImage.lz4 和 dtb.img
    make ${kernel_image_name} dtbs -j${N} || {
        echo "make ${kernel_image_name} failed"
        exit 1
    }

    # 编译内核模块
    make modules -j${N} || {
        echo "make modules failed"
        exit 1
    }

    # 安装内核模块
    KO_INSTALL_DIR="${KERNEL_BUILD_DIR}"/modules
    [ ! -d "${KO_INSTALL_DIR}" ] && mkdir -p "${KO_INSTALL_DIR}"
    rm -rf "${KO_INSTALL_DIR:?}"/*

    make INSTALL_MOD_PATH="${KO_INSTALL_DIR}" INSTALL_MOD_STRIP=1 modules_install -j${N} || {
        echo "make modules_install to INSTALL_MOD_PATH for release ko failed"
        exit 1
    }

    # strip 内核模块, 去掉debug info
    # ${CROSS_COMPILE}strip -g ${KO_INSTALL_DIR}/lib/modules/${KERNEL_VER}/*.ko
    find "${KO_INSTALL_DIR}"/lib/modules/"${KERNEL_VER}"/ -name "*.ko" -exec ${CROSS_COMPILE}strip -g '{}' \;

    rm -rf "${KO_INSTALL_DIR}"/lib/modules/"${KERNEL_VER}"/{build,source}

    # ko 签名
    pre_pkg_preinst

    # 拷贝 内核 zImage.lz4
    cp -f "arch/arm64/boot/${kernel_image_name}" "${KERNEL_BUILD_DIR}"/
    # 拷贝 内核 Image
    cp -f "arch/arm64/boot/Image" "${KERNEL_BUILD_DIR}"/

    # 生成 dtb 镜像
    mkdir -p "${KERNEL_BUILD_DIR}"/dtb
    cp -arf arch/arm64/boot/dts/hobot/*.dtb "${KERNEL_BUILD_DIR}"/dtb
    cp -arf arch/arm64/boot/dts/hobot/*.dts "${KERNEL_BUILD_DIR}"/dtb
    cp -arf arch/arm64/boot/dts/hobot/*.dtsi "${KERNEL_BUILD_DIR}"/dtb

    path=./tools/dtbmapping

    cd $path

    export TARGET_KERNEL_DIR="${KERNEL_BUILD_DIR}"/dtb
    # build dtb
    python2 makeimg.py || {
        echo "make failed"
        exit 1
    }

    # 生成内核头文件
    make_kernel_headers
}

function build_clean()
{
    make clean
}

function build_distclean()
{
    make distclean
}

# 进入内核目录
cd "${KERNEL_SRC_DIR}"
# 根据命令参数编译
if [ $# -eq 0 ] || [ "$1" = "all" ]; then
    build_all
elif [ "$1" = "clean" ]; then
    build_clean
elif [ "$1" = "distclean" ]; then
    build_distclean
fi
