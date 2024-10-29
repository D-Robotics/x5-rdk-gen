[简体中文](./README.md) | English

# Development environment setup and compilation instructions

## Overview

This document provides an introduction to setting up the RDK development environment, the source code directory structure, and instructions for compiling the system image.

## Development Environment

Cross-compilation refers to developing and building software on a host machine and then deploying the built software to a development board for execution. The host machine typically has higher performance and more memory than the development board, enabling efficient code compilation and the installation of more development tools.

**Host Compilation Environment Requirements**

It is recommended to use the Ubuntu operating system. If using other system versions, the compilation environment may require adjustments.

Install the following packages on Ubuntu 18.04:

```shell
sudo apt-get install -y build-essential make cmake libpcre3 libpcre3-dev bc bison \
                        flex python-numpy mtd-utils zlib1g-dev debootstrap \
                        libdata-hexdumper-perl libncurses5-dev zip qemu-user-static \
                        curl git liblz4-tool apt-cacher-ng libssl-dev checkpolicy autoconf \
                        android-tools-fsutils mtools parted dosfstools udev rsync
```
Install the following packages on Ubuntu 20.04:

```shell
sudo apt-get install -y build-essential make cmake libpcre3 libpcre3-dev bc bison \
                        flex python-numpy mtd-utils zlib1g-dev debootstrap \
                        libdata-hexdumper-perl libncurses5-dev zip qemu-user-static \
                        curl git liblz4-tool apt-cacher-ng libssl-dev checkpolicy autoconf \
                        android-sdk-libsparse-utils android-sdk-ext4-utils mtools parted dosfstools udev rsync
```

Install the following packages on Ubuntu 22.04:

```shell
sudo apt-get install -y build-essential make cmake libpcre3 libpcre3-dev bc bison \
                        flex python3-numpy mtd-utils zlib1g-dev debootstrap \
                        libdata-hexdumper-perl libncurses5-dev zip qemu-user-static \
                        curl repo git liblz4-tool apt-cacher-ng libssl-dev checkpolicy autoconf \
                        android-sdk-libsparse-utils mtools parted dosfstools udev rsync
```

**Install the cross-compilation toolchain**

Download the cross-compilation toolchain by running the following command:

```shell
curl -fO http://archive.d-robotics.cc/toolchain/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu.tar.xz
```

Extract and install the toolchain, preferably to the `/opt` directory. Writing data to the `/opt` directory usually requires `sudo` permissions, for example:

```shell
sudo tar -xvf gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu.tar.xz -C /opt
```

Configure the environment variables for the cross-compilation toolchain:

```shell
export CROSS_COMPILE=/opt/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-
export PATH=$PATH:/opt/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu/bin
export ARCH=arm64
```

These commands temporarily configure the environment variables. To make them permanent, add the above commands to the end of the environment variable files `~/.profile` or `~/.bash_profile`.

## rdk-gen

`rdk-gen` is used to build operating system images suitable for RDK. It provides an extensible framework allowing users to customize and build Ubuntu operating systems for RDK according to their needs.

`rdk-gen` offers two main functionalities:

- **Building Operating System Images for RDK:** This function downloads official RDK materials and generates a system image identical to the one officially released. Users can pre-install additional software packages in this image.
- **Secondary Development of Official System Software and Applications:** This repository provides methods for secondary development of official system software and application Debian packages, along with scripts to complete the build of all software source code.

Download the `rdk-gen` source code using the following command:

```
git clone https://github.com/D-Robotics/x5-rdk-gen.git
```

After downloading, the main files and directories of `rdk-gen` are as follows:

| **Directory**               | **Description**                                              |
| --------------------------- | ------------------------------------------------------------ |
| `pack_image.sh`             | The main entry point for building system images              |
| `build_params`              | Configuration file for building system images, specifying paths, versions, and other information for downloading Samplefs and Debian packages |
| `download_samplefs.sh`      | Downloads the pre-made Ubuntu root filesystem                |
| `download_deb_pkgs.sh`      | Downloads RDK official Debian packages to be pre-installed in the system image, including the kernel, multimedia libraries, sample code, tros.bot, etc. |
| `hobot_customize_rootfs.sh` | Customizes the Ubuntu filesystem, such as creating users, enabling or disabling startup items, etc. |
| `config`                    | Stores content to be placed in the `/hobot/config` directory of the system image. This directory is a vfat partition, which can be modified on a PC if the system boots from an SD card, such as setting startup items. |
| `VERSION`                   | Version information of the system image                      |

When customizing the system image and software packages, pay attention to the following resources:

| **Directory**  | **Description**                                              |
| -------------- | ------------------------------------------------------------ |
| `mk_kernel.sh` | Used when developing the kernel, this script compiles the kernel, device tree, and driver modules |
| `mk_debs.sh`   | Used when developing custom software packages, this script generates Debian packages |
| `samplefs`     | Used when developing custom root filesystems, this directory contains the `make_ubuntu_samplefs.sh` script for customizing Samplefs |
| `source`       | The directory where downloaded source code is stored, which by default does not download source code |

## Compiling System Images

To build operating system images for RDK, run the following command to package the system image. This method can produce an image identical to the one officially released.

```
cd rdk-gen
sudo ./pack_image.sh
```

`sudo` permissions are required for compilation. Upon success, the system image file with the `*.img` suffix will be generated in the `deploy` directory.

### Steps for `pack_image.sh`

1. Calls the `download_samplefs.sh` and `download_deb_pkgs.sh` scripts to download Samplefs and the required Debian packages from the RDK official file server.
2. Extracts Samplefs and calls the `hobot_customize_rootfs.sh` script to customize the filesystem.
3. Installs the Debian packages into the filesystem.
4. Generates the system image.

If users need to install additional Debian packages into the system image, they can create a `third_packages` directory and place the Debian packages inside. These will be automatically installed into the system during step 3.

**Note:** The `pack_image.sh` script supports the `-l` option for local compilation, which avoids downloading Samplefs and Debian packages from the RDK official source. This option is useful for deep development and debugging of the RDK system.

```
sudo ./pack_image.sh -l
```

## Advanced RDK System Development

### Downloading the Complete Source Code

The kernel, bootloader, and `hobot-xxx` software package source codes related to `rdk-linux` are hosted on [GitHub](https://github.com/). Before downloading the code, please register and log in to [GitHub](https://github.com/), and add the `SSH Key` of the development server to your user settings as described in [Generating a new SSH key and adding it to the ssh-agent](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent).

To download the mainline branch code, which corresponds to the latest official system image version, run:

```
repo init -u git@github.com:D-Robotics/x5-manifest.git -b main
```

To download the development branch code, which continually adds new features and bug fixes but may not be as stable as the main branch, run:

```
repo init -u git@github.com:D-Robotics/x5-manifest.git -b develop
```

When using the above commands to download the code, the `rdk-gen` repository and all source codes under the `source` directory will be downloaded, which may take some time due to the large volume of source code.

```
source/
├── bootloader
├── hobot-audio-config
├── hobot-boot
├── hobot-camera
├── hobot-configs
├── hobot-dnn
├── hobot-drivers
├── hobot-dtb
├── hobot-io
├── hobot-io-samples
├── hobot-kernel-headers
├── hobot-miniboot
├── hobot-multimedia
├── hobot-multimedia-dev
├── hobot-multimedia-samples
├── hobot-spdev
├── hobot-sp-samples
├── hobot-utils
├── hobot-wifi
└── kernel
```

### Preparation Before Development

Before starting actual development, it's necessary to complete a system image build. This process involves downloading the required root file system and the dependent official `.deb` packages. Once the system build is complete, the extracted root file system will contain the header files and libraries needed for application packages.

```
sudo ./pack_image.sh
```

You need `sudo` privileges to compile. Upon successful completion, a system image file with the `*.img` extension will be generated in the `deploy` directory.

### Compiling the Kernel

To compile the Linux kernel, execute the following command:

```
./mk_kernel.sh
```

After the compilation, the kernel image, driver modules, device tree, and kernel headers will be generated in the `deploy/kernel` directory.

```
dtb  Image  Image.lz4  kernel_headers  modules
```

These files are used by the `hobot-boot`, `hobot-dtb`, and `hobot-kernel-headers` Debian packages. Therefore, if you want to customize these packages, you need to compile the kernel first.

### Compiling RDK Official Debian Packages

Packages starting with `hobot-` are the source and configuration files for RDK's official Debian packages, which are developed and maintained by RDK. After downloading the complete source code, you can rebuild the Debian packages by executing `mk_debs.sh`.

Help information is as follows:

```
$ ./mk_debs.sh help
The debian package named by 'help' is not supported, please check the input parameters.
./mk_debs.sh [all] | [deb_name]
    hobot-boot
    hobot-kernel-headers
    hobot-dtb
    hobot-configs
    hobot-utils
    hobot-wifi
    hobot-io
    hobot-io-samples
    hobot-multimedia
    hobot-multimedia-dev
    hobot-camera
    hobot-dnn
    hobot-spdev
    hobot-sp-samples
    hobot-multimedia-samples
    hobot-miniboot
    hobot-audio-config
```

#### Compiling All Debian Packages

Execute the following commands to rebuild all Debian packages (kernel compilation must be completed first):

```
./mk_kernel.sh
./mk_debs.sh
```

Once the build is complete, the packages with the `.deb` extension will be generated in the `deploy/deb_pkgs` directory.

#### Compiling Individual Debian Packages

`mk_debs.sh` supports building individual packages by specifying the package name as an argument, for example:

```
./mk_debs.sh hobot-configs
```

### Compiling the Bootloader

The `bootloader` source code is used to generate the minimal boot image `miniboot.img`, which contains the partition table, SPL, DDR, BL31, U-Boot, and other essential boot firmware components.

The minimal boot image for RDK is usually maintained and released by RDK. You can download the corresponding version from [miniboot](https://archive.d-robotics.cc/downloads/miniboot/), and the `hobot-miniboot` package will also be updated accordingly. Since the `bootloader` involves the most basic boot process, make sure to fully understand its functionality before modifying this module.

Follow these steps to recompile and generate `miniboot`.

#### Selecting a Board Configuration File

```
cd source/bootloader/build
./xbuild.sh lunch

You're building on #127~20.04.1-Ubuntu SMP Thu Jul 11 15:36:12 UTC 2024
Lunch menu... pick a combo:
      0. rdk/x5/board_x5_evb_ubuntu_nand_sdcard_debug_config.mk
      1. rdk/x5/board_x5_evb_ubuntu_nand_sdcard_release_config.mk
      2. rdk/x5/board_x5_rdk_ubuntu_nand_sdcard_debug_config.mk
      3. rdk/x5/board_x5_rdk_ubuntu_nand_sdcard_release_config.mk
Which would you like? [0] :
```

Select the board configuration file according to the prompt. The preset configuration files above are tailored to the hardware configurations of different development boards.

#### Compiling Miniboot

Navigate to the `build` directory and execute `xbuild.sh` for a complete build:

```
cd source/bootloader/build
./xbuild.sh
```

Once the compilation is successful, various image files such as **miniboot_nand_disk.img**, `uboot.img`, and `miniboot_all.img` will be generated in the image output directory (`out/product`). The **miniboot_nand_disk.img** is the minimal boot image file.

## Creating an Ubuntu File System

This section explains how to create the `samplefs_desktop_jammy-v3.0.0.tar.gz` file system. RDK maintains this file system, but if you have customization needs, you will need to recreate it following the instructions in this chapter.

### Environment Setup

It is recommended to use an Ubuntu host for creating the Ubuntu file system for the development board. First, install the following packages on your host environment:

```
sudo apt-get install wget ca-certificates device-tree-compiler pv bc lzop zip binfmt-support \
                    build-essential ccache debootstrap ntpdate gawk gcc-arm-linux-gnueabihf qemu-user-static \
                    u-boot-tools uuid-dev zlib1g-dev unzip libusb-1.0-0-dev fakeroot parted pkg-config \
                    libncurses5-dev whiptail debian-keyring debian-archive-keyring f2fs-tools libfile-fcntllock-perl \
                    rsync libssl-dev nfs-kernel-server btrfs-progs ncurses-term p7zip-full kmod dosfstools \
                    libc6-dev-armhf-cross imagemagick curl patchutils liblz4-tool libpython2.7-dev linux-base swig acl \
                    python3-dev python3-distutils libfdt-dev locales ncurses-base pixz dialog systemd-container udev \
                    lib32stdc++6 libc6-i386 lib32ncurses5 lib32tinfo5 bison libbison-dev flex libfl-dev cryptsetup gpg \
                    gnupg1 gpgv1 gpgv2 cpio aria2 pigz dirmngr python3-distutils distcc git dos2unix apt-cacher-ng
```

### Key Tools Overview

#### debootstrap

`debootstrap` is a tool used in Debian/Ubuntu to construct a basic system (root file system). The generated directory conforms to the Linux Filesystem Hierarchy Standard (FHS), meaning it includes directories like `/boot`, `/etc`, `/bin`, `/usr`, etc., but it is much smaller than a full Linux distribution and has limited functionality. This basic system can be customized to suit specific Ubuntu system requirements.

To install `debootstrap` on an Ubuntu system (PC):

```
sudo apt-get install debootstrap
```

Usage:

```
# You can add parameters to specify the source
sudo debootstrap --arch [platform] [release_code_name] [directory] [source]
```

#### chroot

`chroot` stands for "change root directory." In a Linux system, the default directory structure starts at `/`, the root. By using `chroot`, the system's directory structure begins from a specified location instead of `/`.

#### parted

The `parted` command is a powerful disk partitioning and resizing tool developed by the GNU organization. Unlike `fdisk`, it supports resizing partitions. Although designed for Linux and not built to handle the wide variety of partition types associated with `fdisk`, it can manage the most common partition formats, including ext2, ext3, FAT16, FAT32, NTFS, ReiserFS, JFS, XFS, UFS, HFS, and Linux swap partitions.

### Creating Ubuntu Root File System Script

Download the `rdk-gen` source code:

```
git clone https://github.com/D-Robotics/x5-rdk-gen.git
```

Execute the following commands to generate the Ubuntu file system:

```
cd samplefs
chmod +x make_ubuntu_rootfs.sh
# By default, compile the desktop version of samplefs
sudo ./make_ubuntu_rootfs.sh
# To compile the server version of samplefs
sudo ./make_ubuntu_rootfs.sh server
```

`sudo` privileges are required to compile.

Output of successful compilation:

```shell
desktop/                                      # Compile output directory
├── jammy-rdk-arm64                           # The root file system generated after successful compilation will have more system temporary files
├── samplefs_desktop_jammy-v3.0.0.tar.gz      # Compress and package the required contents in jammy-rdk-arm64
└── samplefs_desktop_jammy-v3.0.0.tar.gz.info # Which apt packages are installed in the current system

rootfs                                        # After decompressing samplefs_desktop_jammy-v3.0.0.tar.gz, the following files should be included
├── app
├── bin -> usr/bin
├── boot
├── dev
├── etc
├── home
├── lib -> usr/lib
├── media
├── mnt
├── opt
├── proc
├── root
├── run
├── sbin -> usr/sbin
├── snap
├── srv
├── sys
├── tftpboot
├── tmp
├── userdata
├── usr
├── var
└── vendor

23 directories, 0 files
```

### Customization

Key variable definitions in the code:

**PYTHON_PACKAGE_LIST**: Python packages to be installed.

**DEBOOTSTRAP_LIST**: Debian packages installed during debootstrap execution.

**BASE_PACKAGE_LIST**: Debian packages required for a basic Ubuntu system.

**SERVER_PACKAGE_LIST**: Additional Debian packages for the Server version of the Ubuntu system on top of the basic version.

**DESKTOP_PACKAGE_LIST**: Packages required for supporting the desktop graphical interface.

The `samplefs_desktop` file system maintained by RDK includes all the above configuration packages. Users can add or remove packages according to their needs.
