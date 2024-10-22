#!/bin/bash
###
 # COPYRIGHT NOTICE
 # Copyright 2024 D-Robotics, Inc.
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
[ -n "${IMAGE_DEPLOY_DIR}" ] && [ ! -d "${KERNEL_BUILD_DIR}" ] && mkdir "$KERNEL_BUILD_DIR"

[ $(cat /proc/cpuinfo |grep 'processor'|wc -l) -gt 2 ] \
    && N="$((($(cat /proc/cpuinfo |grep 'processor'|wc -l)) - 2))" || N=1

# 默认使用emmc配置，对于nor、nand需要使用另外的配置文件
kernel_config_file=hobot_x5_rdk_ubuntu_defconfig
kernel_image_name="Image.lz4"

KERNEL_SRC_DIR=${HR_TOP_DIR}/source/kernel

kernel_version=$(awk "/^VERSION =/{print \$3}" "${KERNEL_SRC_DIR}"/Makefile)
kernel_patch_lvl=$(awk "/^PATCHLEVEL =/{print \$3}" "${KERNEL_SRC_DIR}"/Makefile)
kernel_sublevel=$(awk "/^SUBLEVEL =/{print \$3}" "${KERNEL_SRC_DIR}"/Makefile)
export KERNEL_VER="${kernel_version}.${kernel_patch_lvl}.${kernel_sublevel}"

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
    find scripts -iname "*.c" -print0 | while IFS= read -r -d '' file; do
        cp --parents -Rf "$file" "${HDRDIR}"
    done
    make M="${HDRDIR}"/scripts clean
    cp -Rf ${SRCDIR}/scripts/module.lds ${HDRDIR}/scripts
    cp -Rf ${SRCDIR}/scripts/module.lds.S ${HDRDIR}/scripts

    cd "${HR_LOCAL_DIR}"
    rm -rf "${HDRDIR}"/arch/arm64/mach*
    rm -rf "${HDRDIR}"/arch/arm64/plat*

    mv "${HDRDIR}"/include/asm-generic/ "${HDRDIR}"/
    rm -rf "${HDRDIR}"/inclde/asm-*
    mv "${HDRDIR}"/asm-generic "${HDRDIR}"/include/

    rm -rf "${HDRDIR}"/arch/arm64/configs

    rm -rf "${HDRDIR}"/debian
}

function build_pre_modules()
{
    cd "${HR_TOP_DIR}"/source/hobot-drivers/bpu-hw_io
    make INSTALL_MOD_PATH="${KO_INSTALL_DIR}" \
        INSTALL_MOD_STRIP=1 || {
        echo "[ERROR]: make modules_depmod for ${KO_INSTALL_DIR} kernel modules failed"
        exit 1
    }
    cd -
}

function build_all()
{
    # 生成内核配置.config
    make $kernel_config_file || {
        echo "make ${kernel_config_file} failed"
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

    # 编译、安装外部内核模块
    build_pre_modules "all" || {
        echo "build_pre_modules failed"
        exit 1
    }

    # 执行DEPMOD生成内核模块依赖关系
    make -j"${N}" modules_depmod \
        INSTALL_MOD_PATH="${KO_INSTALL_DIR}" || {
        echo "[ERROR]: make modules_depmod for ${KO_INSTALL_DIR} kernel modules failed"
        exit 1
    }

    # strip 内核模块, 去掉debug info
    # ${CROSS_COMPILE}strip -g ${KO_INSTALL_DIR}/lib/modules/${KERNEL_VER}/*.ko
    find "${KO_INSTALL_DIR}"/lib/modules/"${KERNEL_VER}"/ -name "*.ko" -exec ${CROSS_COMPILE}strip -g '{}' \;

    rm -rf "${KO_INSTALL_DIR}"/lib/modules/"${KERNEL_VER}"/{build,source}

    # 拷贝 内核 zImage.lz4
    cp -f "arch/arm64/boot/${kernel_image_name}" "${KERNEL_BUILD_DIR}"/
    # 拷贝 内核 Image
    cp -f "arch/arm64/boot/Image" "${KERNEL_BUILD_DIR}"/

    # 生成 dtb 镜像
    mkdir -p "${KERNEL_BUILD_DIR}"/dtb
    cp -arf arch/arm64/boot/dts/hobot/*.dtb "${KERNEL_BUILD_DIR}"/dtb
    cp -arf arch/arm64/boot/dts/hobot/*.dts "${KERNEL_BUILD_DIR}"/dtb
    cp -arf arch/arm64/boot/dts/hobot/*.dtsi "${KERNEL_BUILD_DIR}"/dtb

    # 生成内核头文件
    make_kernel_headers
}

function kernel_menuconfig() {
	# Check if kernel_config_file variable is set
	if [ -z "${kernel_config_file}" ]; then
		echo "[ERROR]: Kernel defconfig file is not set. Aborting menuconfig."
		return 1
	fi

	# Run menuconfig with the specified Kernel configuration file
	KERNEL_DEFCONFIG=$(basename "${kernel_config_file}")
	echo "[INFO]: Kernel menuconfig with ${KERNEL_DEFCONFIG}"
	make ${BUILD_OPTIONS} -C "${KERNEL_SRC_DIR}" "${KERNEL_DEFCONFIG}"

	# 执行 make menuconfig
	script -q -c "make ${BUILD_OPTIONS} -C ${KERNEL_SRC_DIR} menuconfig" /dev/null

	# Check if menuconfig was successful
	if [ $? -eq 0 ]; then
		# Run savedefconfig to save the configuration back to the original file
		make ${BUILD_OPTIONS} -C "${KERNEL_SRC_DIR}" savedefconfig
		dest_defconf_path="${HR_TOP_DIR}/source/kernel/arch/arm64/configs/${KERNEL_DEFCONFIG}"
		echo "**** Saving Kernel defconfig to ${dest_defconf_path} ****"
		cp -f "${KERNEL_SRC_DIR}/defconfig" "${dest_defconf_path}"
	fi

	# Check if savedefconfig was successful
	if [ $? -ne 0 ]; then
		echo "[ERROR]: savedefconfig failed. Configuration may not be saved."
		return 1
	fi

	echo "[INFO]: Kernel menuconfig completed successfully."
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
elif [ "$1" = "menuconfig" ]; then
	kernel_menuconfig
fi
