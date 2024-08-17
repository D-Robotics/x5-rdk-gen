# 开发环境搭建及编译说明

## 概述

介绍 SDK 开发环境的搭建方法、源码目录结构、系统镜像的编译说明。

## 开发环境

交叉编译是指在主机上开发和构建软件，然后把构建的软件部署到开发板上运行。主机一般拥有比开发板更高的性能和更多的内存，可以高效完成代码的构建，可以安装更多的开发工具。

**主机编译环境要求**

推荐使用 Ubuntu 操作系统，若使用其它系统版本，可能需要对编译环境做相应调整。

Ubuntu 18.04 系统安装以下软件包：

```shell
sudo apt-get install -y build-essential make cmake libpcre3 libpcre3-dev bc bison \
flex python-numpy mtd-utils zlib1g-dev debootstrap \
libdata-hexdumper-perl libncurses5-dev zip qemu-user-static \
curl git liblz4-tool apt-cacher-ng libssl-dev checkpolicy autoconf \
android-tools-fsutils mtools parted dosfstools udev rsync
```

Ubuntu 20.04 系统安装以下软件包：

```shell
sudo apt-get install -y build-essential make cmake libpcre3 libpcre3-dev bc bison \
flex python-numpy mtd-utils zlib1g-dev debootstrap \
libdata-hexdumper-perl libncurses5-dev zip qemu-user-static \
curl git liblz4-tool apt-cacher-ng libssl-dev checkpolicy autoconf \
android-sdk-libsparse-utils android-sdk-ext4-utils mtools parted dosfstools udev rsync
```

Ubuntu 22.04 系统安装以下软件包：

```shell
sudo apt-get install -y build-essential make cmake libpcre3 libpcre3-dev bc bison \
flex python3-numpy mtd-utils zlib1g-dev debootstrap \
libdata-hexdumper-perl libncurses5-dev zip qemu-user-static \
curl repo git liblz4-tool apt-cacher-ng libssl-dev checkpolicy autoconf \
android-sdk-libsparse-utils mtools parted dosfstools udev rsync
```

**安装交叉编译工具链**

执行以下命令下载交叉编译工具链：

```shell
curl -fO http://archive.d-robotics.cc/toolchain/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu.tar.xz
```

解压并安装，建议安装到 /opt 目录下，通常向 /opt 目录写数据需要 sudo 权限，例如：

```shell
sudo tar -xvf gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu.tar.xz -C /opt
```

配置交叉编译工具链的环境变量：

```shell
export CROSS_COMPILE=/opt/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-
export PATH=$PATH:/opt/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu/bin
export ARCH=arm64
```

以上命令是临时配置环境变量，要想配置永久生效，可以把以上命令添加到环境变量文件 `~/.profile` 或者 `~/.bash_profile` 的末尾。

## rdk-gen

rdk-gen 用于构建适用于 RDK 的操作系统镜像。它提供了一个可扩展的框架，允许用户根据自己的需求定制和构建 RDK 的 Ubuntu 操作系统。

rdk-gen提供两个主要的功能：

- 构建适用于 RDK 的操作系统镜像。使用本功能下载 RDK 官方的资料，生成与官方发布的完全一样的系统镜像；在这个镜像制作方法中，用户可以预装更多需要的软件包。
- 本仓库提供二次开发官方系统软件和应用 deb 包的方法，提供脚本程序完成所有软件源码的构建。

rdk-gen 源码下载方式：

```shell
git clone https://github.com/D-Robotics/rdk-gen.git
```

下载完成后，rdk-gen 的主要文件、目录说明如下：

| **目录**                  | **说明**                                                     |
| ------------------------- | ------------------------------------------------------------ |
| pack_image.sh             | 构建系统镜像的主代码入口                                     |
| build_params              | 构建系统镜像的配置文件，指定下载 Samplefs 和 deb 包的路径、版本等信息 |
| download_samplefs.sh      | 下载预先制作的基础 Ubuntu 根文件系统                         |
| download_deb_pkgs.sh      | 下载 RDK 官方 debian 软件包，会被预装到系统镜像中，包括内核、多媒体库、示例代码、tros.bot 等 |
| hobot_customize_rootfs.sh | 定制化修改 Ubuntu 文件系统，如创建用户、启用或禁止自启动项等 |
| config                    | 存放需要放到系统镜像 /hobot/config 目录下的内容，该目录时一个 vfat 格式的分区，如果是 sd 卡启动方式，用户可以在 PC 上修改该分区的内容，如设置自启动项等。 |
| VERSION                   | 系统镜像的版本信息                                           |

当需要定制化开发系统镜像和软件包时，需要关注以下资源

| **目录**     | **说明**                                                     |
| ------------ | ------------------------------------------------------------ |
| mk_kernel.sh | 进行内核开发时，需要使用本脚本编译内核、设备树和驱动模块     |
| mk_debs.sh   | 进行自定义软件包开发时，需要使用本脚本生成 debian 软件包     |
| samplefs     | 进行自定义根文件系统开发时，需要使用本目录下的 make_ubuntu_samplefs.sh 脚本定制 samplefs |
| source       | 进行软件开发时，下载的源码会在本目录下，默认不下载源码       |

## 编译系统镜像

构建适用于 RDK 的操作系统镜像，运行以下命令进行系统镜像的打包，本方法可以构建出与官方发布一样的镜像。

```shell
cd rdk-gen
sudo ./pack_image.sh
```

需要有 sudo 权限进行编译，成功后会在deploy目录下生成 `*.img` 的系统镜像文件。

### pack_image.sh 打包步骤

1. 调用 download_samplefs.sh 和 download_deb_pkgs.sh 两个脚本从 RDK 官方的文件服务器上下载 samplefs 和需要预装的 debian 软件包
2. 解压 samplefs，调用 hobot_customize_rootfs.sh 脚本对 filesystem 做定制化配置
3. 把 debian 软件包安装进 filesystem
4. 生成系统镜像

如果用户有额外的需要安装的系统镜像的 debian 包，可以创建 third_packages 目录，并把 deb 包放到 third_packages  目录中，在第 3 步时会自动安装进系统。

PS： pack_image.sh 支持 -l 选项完成本地编译，不会从 RDK 官方源下载 samplefs 和 debian 软件包，在深度开发 RDK 系统时，可以使用本选项进行调试。

```
sudo ./pack_image.sh -l
```

## 深度开发 RDK 系统

### 下载完整的源码

rdk-linux 相关的内核、bootloader、hobot-xxx 软件包源码都托管在 [GitHub](https://github.com/) 上。在下载代码前，请先注册、登录  [GitHub](https://github.com/)，并通过 [Generating a new SSH key and adding it to the ssh-agent](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent) 方式添加开发服务器的`SSH Key`到用户设置中。

执行以下命令下载主线分支代码，主线分支的代码与官方发布的最新系统镜像版本对应：

```shell
repo init -u git@github.com:D-Robotics/x5-manifest.git -b main
```

执行以下命令下载开发分支代码，开发分支的代码会不断新增特性与修复 bug，但是稳定性没有主分支代码高：

```
repo init -u git@github.com:D-Robotics/x5-manifest.git -b develop
```

使用以上命令下载代码后，在下载 rdk-gen 的同时会把 source 目录下的源码全部下载下来，源码量比较大，下载时间比较长：

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

### 开发前的准备

在实际开发前，需要先完成一次系统镜像的构建，把必要的根文件系统和依赖的官方 deb 包下载下来，构建系统完成后，解压出来的根文件系统内的头文件和库文件会会应用软件包使用。

```
sudo ./pack_image.sh
```

需要有 sudo 权限进行编译，成功后会在deploy目录下生成 `*.img` 的系统镜像文件。

### 编译 kernel

执行以下命令编译linux内核：

```shell
./mk_kernel.sh
```

编译完成后，会在`deploy/kernel`目录下生成内核镜像、驱动模块、设备树、内核头文件。

```shell
dtb  Image  Image.lz4  kernel_headers  modules
```

这些内容会被 hobot-boot、hobot-dtb 和 hobot-kernel-headers 三个 debian 包所使用，所以如果想要自定义修改这三个软件包，需要先编译内核。

### 编译 RDK 官方 debian 软件包

以 hobot- 开头软件包是 RDK 官方开发和维护的 debian 软件包的源码和配置，下载完整源码后，可以执行 `mk_deb.sh` 重新构建debian包。

帮助信息如下：

```shell
$ ./mk_debs.sh help
The debian package named by 'help' is not supported, please check the input parameters.
./mk_deb.sh [all] | [deb_name]
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

#### 编译所有 debian 软件包

执行以下命令会重新构建所有的 debian 包（需要先完成 kernel 的编译）：

```shell
./mk_kernel.sh
./mk_deb.sh
```

构建完成后，会在`deploy/deb_pkgs`目录下生成 `*.deb` 后缀的软件包。

#### 构建单独的 debian 软件包

`mk_deb.sh` 支持单独构建指定的软件包，在执行时带包名参数即可，例如：

```shell
./mk_deb.sh hobot-configs
```

### 编译 bootloader

`bootloader`源码用于生成最小启动镜像 `miniboot.img`，生成包含分区表、spl、ddr、bl31、uboot等的最小启动固件。

RDK 的最小启动镜像一般会由 RDK 官方进行维护发布，可以从 [miniboot](http://sunrise.horizon.cc/downloads/miniboot/) 下载对应的版本，`hobot-miniboot` 软件包也会同步更新。`bootloader` 涉及最基础的启动过程，在修改本模块前，请充分了解本模块的功能。

按照以下步骤重新编译生成 miniboot。

#### 选择硬件配置文件

```shell
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

根据提示选择板级配置文件。以上预置配置文件适配不同的开发板的硬件配置。

lunch 命令还支持以下两种使用方式：

- 带数字参数指定板级配置
- 带板级配置文件名指定板级配置

```shell
$ ./xbuild.sh lunch 2

You're building on #127~20.04.1-Ubuntu SMP Thu Jul 11 15:36:12 UTC 2024
You are selected board config: rdk/x5/board_x5_rdk_ubuntu_nand_sdcard_release_config.mk

$ ./xbuild.sh lunch board_ubuntu_nand_sdcard_config.mk

You're building on #127~20.04.1-Ubuntu SMP Thu Jul 11 15:36:12 UTC 2024
You are selected board config: rdk/x5/board_x5_rdk_ubuntu_nand_sdcard_release_config.mk
```

#### 编译 miniboot

进入到 build 目录下，执行 xbuild.sh 进行整体编译：

```shell
cd source/bootloader/build
./xbuild.sh
```

编译成功后，会在编译镜像输出目录（out/product） 目录下生成 **miniboot_nand_disk.img**，uboot.img， miniboot_all.img 等镜像文件。其中 **miniboot_nand_disk.img** 即最小启动镜像文件。

## Ubuntu 文件系统制作

本章节介绍如何制作 `samplefs_desktop_jammy-v3.0.0.tar.gz` 文件系统，RDK 官方会维护该文件系统，如果有定制化需求，则需按照本章说明重新制作。

### 环境配置

建议使用 ubuntu 主机进行开发板 ubuntu 文件系统的制作，首先在主机环境安装以下软件包：

```shell
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

### 重点工具介绍

#### debootstrap

debootstrap是debian/ubuntu下的一个工具，用来构建一套基本的系统(根文件系统)。生成的目录符合Linux文件系统标准(FHS)，即包含了 /boot、 /etc、 /bin、 /usr 等等目录，但它比发行版本的Linux体积小很多，当然功能也没那么强大，因此只能说是“基本的系统”，因此可以按照自身需求定制相应对ubuntu系统。

ubuntu系统（PC）下安装debootstrap

```shell
sudo apt-get install debootstrap
```

使用方式

```shell
# 可加参数指定源
sudo debootstrap --arch [平台] [发行版本代号] [目录] [源]
```

#### chroot

chroot，即 change root directory (更改 root 目录)。在 linux 系统中，系统默认的目录结构都是以 `/`，即是以根 (root) 开始的。而在使用 chroot 之后，系统的目录结构将以指定的位置作为 `/` 位置。

#### parted

parted命令是由GNU组织开发的一款功能强大的磁盘分区和分区大小调整工具，与fdisk不同，它支持调整分区的大小。作为一种设计用于Linux的工具，它没有构建成处理与fdisk关联的多种分区类型，但是，它可以处理最常见的分区格式，包括：ext2、ext3、fat16、fat32、NTFS、ReiserFS、JFS、XFS、UFS、HFS以及Linux交换分区。

### 制作 Ubuntu rootfs 脚本代码

下载`rdk-gen`源码：

```shell
git clone https://github.com/D-Robotics/rdk-gen.git
```

执行以下命令生成ubuntu文件系统：

```shell
cd samplefs
chmod +x make_ubuntu_rootfs.sh
# 默认编译 desktop 的 samplefs
sudo ./make_ubuntu_rootfs.sh
# 指定编译 server 版本的 samplefs
sudo ./make_ubuntu_rootfs.sh server
```

需要有 sudo 权限进行编译。

编译成功的输出结果：

```shell
desktop/                                         # 编译输出目录
├── jammy-rdk-arm64                              # 编译成功后生成的根文件系统，会有比较多的系统临时文件
├── samplefs_desktop_jammy-v3.0.0.tar.gz         # 压缩打包 jammy-rdk-arm64 内需要的内容
└── samplefs_desktop_jammy-v3.0.0.tar.gz.info    # 当前系统安装了哪些 apt 包

rootfs                                           # 解压 samplefs_desktop_jammy-v3.0.0.tar.gz 后应该包含以下文件
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

### 定制化修改

代码中的关键变量定义：

**PYTHON_PACKAGE_LIST**： 安装的python包

**DEBOOTSTRAP_LIST**：debootstrap执行时安装的Debian软件包

**BASE_PACKAGE_LIST**： 最基本的UBuntu系统所需要安装的Debian软件包

**SERVER_PACKAGE_LIST**：Server 版本的Ubuntu系统会在基本版本上多安装的Debian软件包

**DESKTOP_PACKAGE_LIST**: 支持桌面图形化界面需要安装的软件包

RDK 官方维护的 `samplefs_desktop` 文件系统会包含以上所有配置包的内容，用户可以根据自己的需求进行增、删。





