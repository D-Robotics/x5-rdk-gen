#!/bin/bash

set -eu

this_user="$(whoami)"
if [ "${this_user}" != "root" ]; then
	echo "[ERROR]: This script requires root privileges. Please execute it with sudo."
	exit 1
fi

BUILD_USER=$(echo $SUDO_USER)
echo "current build user:${BUILD_USER}."
LOCAL_DIR="$( cd "$( dirname "$(readlink -f "${BASH_SOURCE[0]}")" )" && pwd )"

# Ubuntu 20.04
# RELEASE="focal"
# Ubuntu 22.04
# RELEASE="jammy"
# Ubuntu 24.04
RELEASE="noble"
ARCH=arm64
DEBOOTSTRAP_COMPONENTS="main,universe"
UBUNTU_MIRROR="mirrors4.tuna.tsinghua.edu.cn/ubuntu-ports/"
ROS2_MIRROR="mirrors4.tuna.tsinghua.edu.cn/ros2/ubuntu"

# apt-cacher-ng path forwarding: debootstrap and sources.list inside chroot must use the same URL to share the cache
# (Acquire::http::Proxy is unreliable with nested quoting in chroot eval, and sources.list pointing directly at the mirror bypasses the cache)
APT_CACHER="http://localhost:3142"
apt_deb_url="${APT_CACHER}/${UBUNTU_MIRROR}"
ros2_deb_url="${APT_CACHER}/${ROS2_MIRROR}"
board_deb_url="http://${UBUNTU_MIRROR}"
board_ros2_deb_url="http://${ROS2_MIRROR}"
apt_mirror="${apt_deb_url}"

PYTHON_PACKAGE_LIST="numpy==1.26.4 opencv-python pySerial i2cdev spidev matplotlib pillow \
websocket websockets lark-parser netifaces google protobuf==3.20.1 scipy build scikit-build-core pybind11 wheel pandas-stubs"

DEBOOTSTRAP_LIST="systemd udev dbus locales apt-utils sudo init kmod bash-completion"
get_package_list()
{
	package_list_file="${LOCAL_DIR}/${RELEASE}/ubuntu-${1}-${ARCH}-packages"
	if [ ! -f "${package_list_file}" ]; then
		echo "ERROR: package list file - ${package_list_file} not found" > /dev/stderr
		exit 1
	fi
	PACKAGE_LIST=$(sed ':a;N;$!ba;s/\n/ /g' < "${package_list_file}")
	echo "${PACKAGE_LIST}"
}

# The default version is Ubuntu Desktop
ADD_PACKAGE_LIST="$(get_package_list "base") $(get_package_list "server") $(get_package_list "desktop") "
ubuntufs_src="${LOCAL_DIR}/desktop"
samplefs_version="v3.1.0"
tar_file=${ubuntufs_src}/samplefs_desktop_${RELEASE}-${samplefs_version}.tar.gz


if [ $# -ge 1 ] ; then
	# Ubuntu Desktop
	if [[ $1 == "d"*  ]] ; then
		ADD_PACKAGE_LIST="$(get_package_list "base") $(get_package_list "server") $(get_package_list "desktop") "
		ubuntufs_src="${LOCAL_DIR}/desktop"
		tar_file=${ubuntufs_src}/samplefs_desktop_${RELEASE}-${samplefs_version}.tar.gz
	fi

	# Ubuntu Server
	if [[ $1 == "s"*  ]] ; then
		ADD_PACKAGE_LIST="$(get_package_list "base") $(get_package_list "server") "
		ubuntufs_src="${LOCAL_DIR}/server"
		tar_file=${ubuntufs_src}/samplefs_server_${RELEASE}-${samplefs_version}.tar.gz
	fi

	# Ubuntu Base
	if [[ $1 == "b"*  ]] ; then
		ADD_PACKAGE_LIST="$(get_package_list "base") "
		ubuntufs_src="${LOCAL_DIR}/base"
		tar_file=${ubuntufs_src}/samplefs_base_${RELEASE}-${samplefs_version}.tar.gz
	fi
fi

echo "Make ${tar_file}"

root_path=${ubuntufs_src}/${RELEASE}-rdk-${ARCH}

# Release specific packages
case $RELEASE in
	bionic)
		# Dependent debootstarp packages
		DEBOOTSTRAP_COMPONENTS="main,universe"
		DEBOOTSTRAP_LIST+=" module-init-tools"
		ADD_PACKAGE_LIST+=" android-tools-adbd"
	;;
	focal)
		# Dependent debootstarp packages
		DEBOOTSTRAP_COMPONENTS="main,universe"
		DEBOOTSTRAP_LIST+=""
		ADD_PACKAGE_LIST+="ros-foxy-ros-base"
	;;
	jammy)
		# Dependent debootstarp packages
		DEBOOTSTRAP_COMPONENTS="main,universe"
		DEBOOTSTRAP_LIST+=""
		ADD_PACKAGE_LIST+=""
	;;
	noble)
		# Dependent debootstarp packages
		DEBOOTSTRAP_COMPONENTS="main,universe"
		DEBOOTSTRAP_LIST+=""
		ADD_PACKAGE_LIST+=""
	;;
esac

echo "${ADD_PACKAGE_LIST}"

log_out()
{
	# log function parameters to install.log
	local tmp=""
	[[ -n $2 ]] && tmp="[\e[0;33m $2 \x1B[0m]"

	case $3 in
		err)
		echo -e "[\e[0;31m error \x1B[0m] $1 $tmp"
		;;

		wrn)
		echo -e "[\e[0;35m warn \x1B[0m] $1 $tmp"
		;;

		ext)
		echo -e "[\e[0;32m o.k. \x1B[0m] \e[1;32m$1\x1B[0m $tmp"
		;;

		info)
		echo -e "[\e[0;32m o.k. \x1B[0m] $1 $tmp"
		;;

		*)
		echo -e "[\e[0;32m .... \x1B[0m] $1 $tmp"
		;;
	esac
}

# mount_chroot <target>
#
# helper to reduce code duplication
#
mount_chroot()
{
	local target=$1
	log_out "Mounting" "$target" "info"
	mount -t proc chproc "${target}"/proc
	mount -t sysfs chsys "${target}"/sys
	mount -t devtmpfs chdev "${target}"/dev || mount --bind /dev "${target}"/dev
	mount -t devpts chpts "${target}"/dev/pts
}

# unmount_on_exit <target>
#
# helper to reduce code duplication
#
unmount_on_exit()
{
	local target=$1
	trap - INT TERM EXIT
	umount_chroot "${target}/"
	# rm -rf ${target}
}


# umount_chroot <target>
#
# helper to reduce code duplication
#
umount_chroot()
{
	local target=$1
	log_out "Unmounting" "$target" "info"
	while grep -Eq "${target}.*(dev|proc|sys)" /proc/mounts
	do
		umount -l --recursive "${target}"/dev >/dev/null 2>&1
		umount -l "${target}"/proc >/dev/null 2>&1
		umount -l "${target}"/sys >/dev/null 2>&1
		sleep 5
	done
}

write_apt_sources_list()
{
	local release=$1
	local basedir=$2
	local deb_url=$3
	local full=${4:-0}

	if [[ "$full" -eq 1 ]]; then
		cat <<-EOF > "${basedir}"/etc/apt/sources.list
# See http://help.ubuntu.com/community/UpgradeNotes for how to upgrade to
# newer versions of the distribution.
deb ${deb_url} $release main restricted universe multiverse
#deb-src ${deb_url} $release main restricted universe multiverse

deb ${deb_url} ${release}-security main restricted universe multiverse
#deb-src ${deb_url} ${release}-security main restricted universe multiverse

deb ${deb_url} ${release}-updates main restricted universe multiverse
#deb-src ${deb_url} ${release}-updates main restricted universe multiverse

deb ${deb_url} ${release}-backports main restricted universe multiverse
#deb-src ${deb_url} ${release}-backports main restricted universe multiverse
EOF
	else
		cat <<-EOF > "${basedir}"/etc/apt/sources.list
# See http://help.ubuntu.com/community/UpgradeNotes for how to upgrade to
# newer versions of the distribution.
deb ${deb_url} $release main restricted universe multiverse
#deb-src ${deb_url} $release main restricted universe multiverse
EOF
	fi
}

write_ros2_sources_list()
{
	local release=$1
	local basedir=$2
	local ros2_url=$3

	echo "deb [arch=arm64 signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] ${ros2_url} ${release} main" \
		| tee "${basedir}"/etc/apt/sources.list.d/ros2.list >/dev/null
	cp -af "${LOCAL_DIR}"/ros-archive-keyring.gpg "${basedir}"/usr/share/keyrings/
}

create_base_sources_list()
{
	local release=$1
	local basedir=$2
	[[ -z $basedir ]] && log_out "No basedir passed to create_base_sources_list" " " "err"
	write_apt_sources_list "${release}" "${basedir}" "${apt_deb_url}" 0
	write_ros2_sources_list "${release}" "${basedir}" "${ros2_deb_url}"
}

create_sources_list()
{
	local release=$1
	local basedir=$2
	[[ -z $basedir ]] && log_out "No basedir passed to create_sources_list" " " "err"
	write_apt_sources_list "${release}" "${basedir}" "${apt_deb_url}" 1
}

restore_board_sources_list()
{
	local release=$1
	local basedir=$2
	[[ -z $basedir ]] && log_out "No basedir passed to restore_board_sources_list" " " "err"
	write_apt_sources_list "${release}" "${basedir}" "${board_deb_url}" 1
	write_ros2_sources_list "${release}" "${basedir}" "${board_ros2_deb_url}"
}

end_debootstrap()
{
	local target=$1
}

compress_base_root() {
	local tar_file=$1
	local src_dir=$2
	if [ ! -d "$src_dir" ];then
		log_out "Dir is not exist!" "${src_dir}" "err"
		exit 1
	fi
	log_out "Start compress" "${tar_file} from ${src_dir}" "info"
	tar --numeric-owner -czpf "${tar_file}" -C "$src_dir"/ --exclude='./dev/*' --exclude='./proc/*' \
		--exclude='./run/*' --exclude='./tmp/*' --exclude='./sys/*' .
}

configure_chroot_debconf()
{
	local target=$1

	cat <<-EOF > "${target}"/etc/apt/apt.conf.d/99samplefs-noninteractive
Dpkg::Options {
   "--force-confdef";
   "--force-confold";
};
EOF

	chroot "${target}" /bin/bash -c 'debconf-set-selections <<EOF
debconf debconf/frontend select Noninteractive
debconf debconf/priority select critical
resolvconf resolvconf/linkify-resolvconf boolean false
tzdata tzdata/Areas select Asia
tzdata tzdata/Zones/Asia select Shanghai
ucf ucf/use_noninteractive_config boolean true
EOF'
}

chroot_dir=

chroot_sh()
{
	local cmd=$1
	chroot "${chroot_dir}" /usr/bin/env \
		DEBIAN_FRONTEND=noninteractive \
		DEBCONF_NONINTERACTIVE_SEEN=true \
		LC_ALL=C LANG=C \
		/bin/bash -c "${cmd}"
}

install_packages_batch()
{
	local package_list
	local retry=0
	local retry_max=5

	package_list="$(echo ${1} | tr ' ' '\n' | awk 'NF' | sort -u | tr '\n' ' ')"
	[[ -z "${package_list// /}" ]] && return 0

	log_out "Batch installing packages" "$(echo ${package_list} | wc -w) packages" "info"
	while true; do
		if chroot_sh "apt-get -y --no-install-recommends install ${package_list}"; then
			return 0
		fi
		retry=$(("$retry" + 1))
		if [[ "${retry}" -ge "${retry_max}" ]]; then
			return 1
		fi
		sleep 2
		echo "Retrying batch package install (${retry}/${retry_max})"
	done
}

hold_gcc_packages()
{
	case "${RELEASE}" in
		focal)
			log_out "Hold GCC packages" "9.3.x" "info"
			chroot_sh "apt-mark hold cpp-9 g++-9 gcc-9-base gcc-9 libasan5 libgcc-9-dev libstdc++-9-dev"
			;;
		jammy)
			log_out "Hold GCC packages" "11.x.x" "info"
			chroot_sh "apt-mark hold cpp-11 g++-11 gcc-11-base gcc-11 libasan5 libgcc-11-dev libstdc++-11-dev"
			;;
		noble)
			log_out "Hold GCC packages" "13.x.x" "info"
			chroot_sh "apt-mark hold cpp-13 g++-13 gcc-13-base gcc-13 libasan5 libgcc-13-dev libstdc++-13-dev"
			;;
	esac
}


make_base_root() {
	local dst_dir=$1
	chroot_dir=$dst_dir
	rm -rf "$dst_dir"
	mkdir -p "$dst_dir"
	trap 'unmount_on_exit "${dst_dir}"' INT TERM EXIT
	log_out "APT mirror (debootstrap + chroot)" "${apt_deb_url}" "info"
	log_out "Installing base system : " "Stage 2/1" "info"
	debootstrap --variant=minbase \
		--include="${DEBOOTSTRAP_LIST// /,}" \
		--arch=${ARCH} \
		--components=${DEBOOTSTRAP_COMPONENTS} \
		--foreign ${RELEASE} \
		"$dst_dir" \
		$apt_mirror
	if [[ $? -ne 0 ]] || [[ ! -f $dst_dir/debootstrap/debootstrap ]];then
		log_out "Debootstrap base system first stage failed" "err"
		exit 1
	fi
	if [ ! -f /usr/bin/qemu-aarch64-static ];then
		log_out "File is not exist!" "Please install qemu-user-static with apt first" "err"
		exit 1
	else
		log_out "Copy qemu-aarch64-static to" "$dst_dir/usr/bin" "info"
		cp /usr/bin/qemu-aarch64-static "$dst_dir"/usr/bin
	fi

	log_out "Installing base system : " "Stage 2/2" "info"
	chroot "${dst_dir}" /bin/bash -c "/debootstrap/debootstrap --second-stage"
	if [[ $? -ne 0 ]] || [[ ! -f $dst_dir/bin/bash ]];then
		log_out "Debootstrap base system second stage failed" "err"
		exit 1
	fi
	mount_chroot "${dst_dir}"

	configure_chroot_debconf "${dst_dir}"

	if [ "${RELEASE}" == "focal" ]; then
		# base for gcc 9.3
		create_base_sources_list ${RELEASE} "${dst_dir}"
		log_out "Updating base packages" "${dst_dir}" "info"
		chroot_sh "apt-get -q -y update"
		[[ $? -ne 0 ]] && exit 1
		log_out "Upgrading base packages" "${dst_dir}" "info"
		chroot_sh "apt-get -q -y upgrade"
		[[ $? -ne 0 ]] && exit 1
	fi

	if [ "${RELEASE}" == "jammy" ]; then
		# base for gcc 11.x
		create_base_sources_list ${RELEASE} "${dst_dir}"
		log_out "Updating base packages" "${dst_dir}" "info"
		chroot_sh "apt-get -q -y update"
		[[ $? -ne 0 ]] && exit 1
		log_out "Upgrading base packages" "${dst_dir}" "info"
		chroot_sh "apt-get -q -y upgrade"
		[[ $? -ne 0 ]] && exit 1

		# Add soft links to be compatible with different versions of cross-compilation toolchains
		chroot "${dst_dir}" /bin/bash -c "ln -sf aarch64-linux-gnu/ /lib/aarch64-none-linux-gnu"
		chroot "${dst_dir}" /bin/bash -c "ln -sf . /lib/aarch64-none-linux-gnu/11.2.1"
		chroot "${dst_dir}" /bin/bash -c "ln -sf . /lib/aarch64-none-linux-gnu/11.3.1"

		# Ubuntu Desktop Add firefox from xtradeb/apps
		if [[ $ubuntufs_src == "${LOCAL_DIR}/desktop"  ]] ; then
			chroot_sh "apt remove firefox -y"
			chroot_sh "apt install gpg-agent -y"
			chroot_sh "apt-get install software-properties-common -y"
			chroot "${dst_dir}" /bin/bash -c "add-apt-repository ppa:xtradeb/apps -y"
			chroot "${dst_dir}" /bin/bash -c "apt install firefox -y"
			# PPA 源不走 apt-cacher-ng，无法缓存
			chroot "${dst_dir}" /bin/bash -c "apt install firefox-locale-zh-hans -y"
			chroot "${dst_dir}" /bin/bash -c "add-apt-repository --remove ppa:xtradeb/apps -y"
		fi
	fi

	if [ "${RELEASE}" == "noble" ]; then
		# base for gcc 13.x
		create_base_sources_list ${RELEASE} "${dst_dir}"
		log_out "Updating base packages" "${dst_dir}" "info"
		chroot_sh "apt-get -q -y update"
		[[ $? -ne 0 ]] && exit 1
		log_out "Upgrading base packages" "${dst_dir}" "info"
		chroot_sh "apt-get -q -y upgrade"
		[[ $? -ne 0 ]] && exit 1

		# arm-gnu-toolchain-13.2 triple is aarch64-none-linux-gnu; Ubuntu libs live under aarch64-linux-gnu
		# chroot "${dst_dir}" /bin/bash -c "ln -sf aarch64-linux-gnu/ /lib/aarch64-none-linux-gnu"

		# Ubuntu Desktop Add firefox from xtradeb/apps
		if [[ $ubuntufs_src == "${LOCAL_DIR}/desktop"  ]] ; then
			chroot_sh "apt remove firefox -y"
			chroot_sh "apt install gpg-agent -y"
			chroot_sh "apt-get install software-properties-common -y"
			chroot "${dst_dir}" /bin/bash -c "add-apt-repository ppa:xtradeb/apps -y"
			chroot "${dst_dir}" /bin/bash -c "apt install firefox -y"
			# PPA 源不走 apt-cacher-ng，无法缓存
			# chroot "${dst_dir}" /bin/bash -c "apt install firefox-locale-zh-hans -y"
			chroot "${dst_dir}" /bin/bash -c "add-apt-repository --remove ppa:xtradeb/apps -y"
		fi
	fi

	# upgrade packages
	create_sources_list ${RELEASE} "${dst_dir}"
	log_out "Updating ${RELEASE}-updates and ${RELEASE}-security packages" "${dst_dir}" "info"
	chroot_sh "apt-get -q -y update"
	[[ $? -ne 0 ]] && exit 1
	log_out "Upgrading base packages" "${dst_dir}" "info"
	chroot_sh "apt-get -q -y upgrade"
	[[ $? -ne 0 ]] && exit 1

	log_out "Installing packages" "${dst_dir}" "info"
	if ! install_packages_batch "${ADD_PACKAGE_LIST}"; then
		echo "ERROR: Failed to batch install packages"
		exit 1
	fi
	
	hold_gcc_packages

	if [ "${RELEASE}" == "jammy" ]; then
		chroot_sh "apt install ros-humble-ros-base -y"
		chroot_sh "apt install ros-humble-cv-bridge -y"
		chroot_sh "apt install libpcl-dev libgles2-mesa-dev ocl-icd-libopencl1 opencl-headers -y"
	fi

	if [ "${RELEASE}" == "noble" ]; then
		chroot_sh "apt install ros-jazzy-ros-base -y"
		chroot_sh "apt install ros-jazzy-cv-bridge -y"
		chroot_sh "apt install libpcl-dev libgles2-mesa-dev ocl-icd-libopencl1 opencl-headers -y"
	fi
	
	chroot "${dst_dir}" /bin/bash -c "dpkg --get-selections" | grep -v deinstall | awk '{print $1}' | cut -f1 -d':' | sort > "${tar_file}".info

	pip_install_opts=""
	if [ "${RELEASE}" = "noble" ]; then
		pip_install_opts="--break-system-packages"
	fi
	chroot "${dst_dir}" /bin/bash -c "pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple"
	chroot "${dst_dir}" /bin/bash -c "pip3 config set install.trusted-host pypi.tuna.tsinghua.edu.cn"
	chroot "${dst_dir}" /bin/bash -c "pip3 install ${pip_install_opts} ${PYTHON_PACKAGE_LIST}"
	#chroot "${dst_dir}" /bin/bash -c "pip3 install ${pip_install_opts} --upgrade packaging"
	chroot "${dst_dir}" /bin/bash -c "rm -rf /root/.cache"

	DEST_LANG="en_US.UTF-8"
	DEST_LANG_CN="zh_CN.UTF-8"
	log_out "Configuring locales" "${DEST_LANG}" "${DEST_LANG_CN}" "info"
	if [ -f "${dst_dir}"/etc/locale.gen ];then
		sed -i "s/^# $DEST_LANG/$DEST_LANG/" "$dst_dir"/etc/locale.gen
		sed -i "s/^# $DEST_LANG_CN/$DEST_LANG_CN/" "$dst_dir"/etc/locale.gen
	fi
	eval 'LC_ALL=C LANG=C chroot $dst_dir /bin/bash -c "locale-gen $DEST_LANG"'
	eval 'LC_ALL=C LANG=C chroot $dst_dir /bin/bash -c "locale-gen $DEST_LANG_CN"'
	eval 'LC_ALL=C LANG=C chroot $dst_dir /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG"'

	chroot "${dst_dir}" /bin/bash -c "systemctl disable hostapd NetworkManager-wait-online.service"

	chroot "${dst_dir}" /bin/bash -c "sed 's/5min/2sec/g' /lib/systemd/system/networking.service > /tmp/networking.service"
	chroot "${dst_dir}" /bin/bash -c "mv /tmp/networking.service /lib/systemd/system/networking.service"

	log_out "Restore board-facing sources.list" "${board_deb_url}" "info"
	restore_board_sources_list ${RELEASE} "${dst_dir}"

	chroot_sh "apt clean"

	chroot "${dst_dir}" /bin/bash -c "rm -f /var/lib/apt/lists/mirrors* /var/lib/apt/lists/localhost*"
	chroot "${dst_dir}" /bin/bash -c "rm -rf /home/${BUILD_USER}"

	umount_chroot "${dst_dir}"
	end_debootstrap "${dst_dir}"

	trap - INT TERM EXIT
}

log_out "Build ubuntu base" "root_path=$root_path tar_file=$tar_file" "info"
log_out "Start build" "ubuntu base :${RELEASE}-rdk-${ARCH}" "info"

if [ ! -f "${tar_file}0" ];then
	make_base_root "${root_path}"
	sync
	compress_base_root "${tar_file}" "${root_path}"
	sync
else
	sync
fi

log_out "End build ubuntu" "${ubuntufs_src}" "info"
exit 0
