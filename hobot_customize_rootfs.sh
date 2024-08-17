#!/bin/bash

set -e

function hobot_customize_rootfs()
{
  DST_ROOTFS_DIR="${1}"

  CONSOLE_CHAR="UTF-8"
  DEST_LANG="en_US.UTF-8"

  # Configure hostname
  HOST="ubuntu"
  echo "$HOST" > ${DST_ROOTFS_DIR}/etc/hostname
  echo "127.0.1.1		${HOST}" >> "${DST_ROOTFS_DIR}/etc/hosts"

  # Configure ssh
  # permit root login via SSH for the first boot
  sed -i 's/#\?PermitRootLogin .*/PermitRootLogin yes/' "${DST_ROOTFS_DIR}"/etc/ssh/sshd_config
  # enable PubkeyAuthentication
  sed -i 's/#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' "${DST_ROOTFS_DIR}"/etc/ssh/sshd_config

  # console fix due to Debian bug
  sed -e 's/CHARMAP=".*"/CHARMAP="'$CONSOLE_CHAR'"/g' -i "${DST_ROOTFS_DIR}"/etc/default/console-setup

  # add the /dev/urandom path to the rng config file
  echo "HRNGDEVICE=/dev/urandom" >> "${DST_ROOTFS_DIR}"/etc/default/rng-tools

  # configure network manager
  sed "s/managed=\(.*\)/managed=true/g" -i "${DST_ROOTFS_DIR}"/etc/NetworkManager/NetworkManager.conf

  # Just regular DNS and maintain /etc/resolv.conf as a file
  sed "/dns/d" -i "${DST_ROOTFS_DIR}"/etc/NetworkManager/NetworkManager.conf
  sed "s/\[main\]/\[main\]\ndns=default\nrc-manager=file/g" -i "${DST_ROOTFS_DIR}"/etc/NetworkManager/NetworkManager.conf
  if [[ -n "${NM_IGNORE_DEVICES:-}" ]]; then
      mkdir -p "${DST_ROOTFS_DIR}"/etc/NetworkManager/conf.d/
      cat <<-EOF > "${DST_ROOTFS_DIR}"/etc/NetworkManager/conf.d/10-ignore-interfaces.conf
[keyfile]
unmanaged-devices=$NM_IGNORE_DEVICES
EOF
  fi

  # Resize the size of the tty
  cat <<-EOF >> "${DST_ROOTFS_DIR}"/etc/skel/.bashrc
# Make sure we are on a serial console (i.e. the device used starts with
# /dev/tty[A-z]), otherwise we confuse e.g. the eclipse launcher which tries do
# use ssh
case \$(tty 2>/dev/null) in
        /dev/tty[A-z]*) [ -x /usr/bin/resize_tty ] && /usr/bin/resize_tty >/dev/null;;
esac
EOF

  # most likely we don't need to wait for nm to get online
  # Disabling NetworkManager-wait-online.service
  echo "Disabling NetworkManager-wait-online.service"
  if [ -h "${DST_ROOTFS_DIR}/etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service" ]; then
    rm "${DST_ROOTFS_DIR}/etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service"
  fi

  	# Remove the spawning of ondemand service
  if [ -h "${DST_ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/ondemand.service" ]; then
    rm -f "${DST_ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/ondemand.service"
  fi

  # initial date for fake-
  # Configure fake-hwclock
  date '+%Y-%m-%d %H:%M:%S' > "${DST_ROOTFS_DIR}"/etc/fake-hwclock.data

  # Disable unattended upgrade
  if [ -e "${DST_ROOTFS_DIR}/etc/apt/apt.conf.d/20auto-upgrades" ]; then
    sed -i "s/Unattended-Upgrade \"1\"/Unattended-Upgrade \"0\"/" \
      "${DST_ROOTFS_DIR}/etc/apt/apt.conf.d/20auto-upgrades"
  fi

  # Disable release upgrade
  if [ -e "${DST_ROOTFS_DIR}/etc/update-motd.d/91-release-upgrade" ]; then
    rm -f "${DST_ROOTFS_DIR}/etc/update-motd.d/91-release-upgrade"
  fi
  if [ -e "${DST_ROOTFS_DIR}/etc/update-manager/release-upgrades" ]; then
    sed -i "s/Prompt=lts/Prompt=never/" \
      "${DST_ROOTFS_DIR}/etc/update-manager/release-upgrades"
  fi

  groups_list="audio gpio i2c video misc vps ipu jpu graphics weston-launch lightdm gdm render vpu kmem dialout disk"
  extra_groups="EXTRA_GROUPS=\"${groups_list}\""
  sed -i "/\<EXTRA_GROUPS\>=/ s/^.*/${extra_groups}/" \
    "${DST_ROOTFS_DIR}/etc/adduser.conf"
  sed -i "/\<ADD_EXTRA_GROUPS\>=/ s/^.*/ADD_EXTRA_GROUPS=1/" \
    "${DST_ROOTFS_DIR}/etc/adduser.conf"

    for group_name in ${groups_list}
    do
        chroot "${DST_ROOTFS_DIR}" /bin/bash -c "groupadd -rf ${group_name} || true"
    done

   # Create User
  SUN_USERNAME="sunrise"
  ROOTPWD="root"
  SUN_PWD="sunrise"
  chroot "${DST_ROOTFS_DIR}" /bin/bash -c "(echo $ROOTPWD;echo $ROOTPWD;) | passwd root"
  chroot "${DST_ROOTFS_DIR}" /bin/bash -c "useradd -U -m -d /home/${SUN_USERNAME} -k /etc/skel/ -s /bin/bash -G sudo,${groups_list//' '/','} ${SUN_USERNAME}"
  chroot "${DST_ROOTFS_DIR}" /bin/bash -c "(echo ${SUN_PWD};echo ${SUN_PWD};) | passwd ${SUN_USERNAME}"

  chroot "${DST_ROOTFS_DIR}" /bin/bash -c "cp -aRf /etc/skel/. /root/"
  chroot "${DST_ROOTFS_DIR}" /bin/bash -c "cp -aRf /etc/skel/. /home/${SUN_USERNAME}"
}
