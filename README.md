简体中文 | [English](./README_EN.md)

# 开发环境搭建及编译说明

## 概述

介绍 RDK 开发环境的搭建方法、源码目录结构、系统镜像的编译说明。

## 开发环境

交叉编译是指在主机上开发和构建软件，然后把构建的软件部署到开发板上运行。主机一般拥有比开发板更高的性能和更多的内存，可以高效完成代码的构建，可以安装更多的开发工具。

**主机编译环境要求**

推荐使用 Ubuntu 22.04 操作系统，保持和RDK X5相同的系统版本，减少因版本差异产生的依赖问题。

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

解压并安装到 /opt 目录下：

```shell
sudo tar -xvf gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu.tar.xz -C /opt
```

## 下载源码

rdk-linux 相关的内核、bootloader、hobot-xxx 软件包源码都托管在 [GitHub](https://github.com/) 上。在下载代码前，请先注册、登录  [GitHub](https://github.com/)，并通过 [Generating a new SSH key and adding it to the ssh-agent](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent) 方式添加开发服务器的`SSH Key`到用户设置中。

首先，临时更换repo为国内源
```shell
export REPO_URL='https://mirrors.tuna.tsinghua.edu.cn/git/git-repo/'
```

执行以下命令初始化主线分支仓库清单 与官方发布的最新系统镜像版本对应：

```shell
repo init -u git@github.com:D-Robotics/x5-manifest.git -b main
```

执行以下命令同步代码

```shell
repo sync
```

:::tip
也可以下载其他分支代码，比如，使用`-b develop`初始化`develop`分支仓库清单
开发分支的代码会不断新增特性与修复 bug，但是稳定性没有主分支代码高
:::


## 源码目录结构

下载完成后，rdk-gen 的主要文件、目录说明如下：

```
├── build_params                        # 编辑脚本，可以通过sudo ./pack_image.sh -c /build_params/[配置文件名] 选择destktop/server release/beta ，默认选择ubuntu-22.04_desktop_rdk-x5_release.conf
├── download_deb_pkgs.sh                # 下载 RDK 官方 debian 软件包，会被预装到系统镜像中，包括内核、多媒体库、示例代码、tros.bot 等
├── download_samplefs.sh                # 下载预先制作的基础 Ubuntu 根文件系统
├── hobot_customize_rootfs.sh           # 定制化修改 Ubuntu 文件系统，如创建用户、启用或禁止自启动项等
├── mk_debs.sh                          # 使用本脚本编译source目录下的源码，并生成 debian 软件包
├── mk_kernel.sh                        # 编译内核、设备树和驱动模块
├── pack_image.sh                       # 构建系统镜像的主代码入口
├── samplefs                            # Ubuntu原始镜像构建，使用该目录下的 make_ubuntu_samplefs.sh 脚本定制 samplefs
├── source                              # uboot,kernel 多媒体库、示例代码，ubuntu预装软件 等源码会在本目录下
```

## 编译系统镜像
构建适用于 RDK 的操作系统镜像，运行以下命令从下载服务器上的Ubuntu原始镜像和官方发布的deb包，打包成系统镜像的打包，可以构建出与官方发布一样的镜像。

```shell
sudo ./pack_image.sh
```

```
Usage: ./pack_image.sh [-c config_file] [-h]

Options:
  -c config_file  Specify the configuration file to use.
  -l              Local build, skip download debain packages
  -h              Display this help message.
```

成功后需要关注以下目录
```
├── rootfs                              # desktop系统原始镜像
├── rootfs_server                       # server系统原始镜像
├── deb_packages                        # 从服务器下载的deb包
├── deploy                              # 编辑结果目录，包含`*.img` 系统镜像文件，文件系统目录，内核编译中间件等
```

### pack_image.sh 打包步骤

1. 调用 download_samplefs.sh 和 download_deb_pkgs.sh 两个脚本从 RDK 官方的文件服务器上下载 samplefs 和需要预装的 debian 软件包
2. 解压 samplefs，调用 hobot_customize_rootfs.sh 脚本对 filesystem 做定制化配置
3. 把 debian 软件包安装进 filesystem
4. 生成系统镜像

如果用户有额外的需要安装的系统镜像的 debian 包，可以创建 third_packages 目录，并把 deb 包放到 third_packages  目录中，在第 3 步时会自动安装进系统。

PS： pack_image.sh 支持 -l 选项完成本地编译，不会从 RDK 官方源下载 samplefs 和 debian 软件包，在深度开发 RDK 系统时，可以使用本选项进行调试。

## 深度开发 RDK 系统

### 开发前的准备

在实际开发前，需要先完成一次系统镜像的构建，把必要的根文件系统和依赖的官方 deb 包下载下来，构建系统完成后，解压出来的根文件系统内的头文件和库文件会会应用软件包使用。

```
sudo ./pack_image.sh
```

需要有 sudo 权限进行编译，成功后会在deploy目录下生成 `*.img` 的系统镜像文件。

### 了解source目录

```
source/
├── bootloader                         # miniboot镜像和uboot源码
├── hobot-audio-config                 # 音频配置
├── hobot-boot                         # 内核镜像  
├── hobot-camera                       # 摄像头库
├── hobot-configs                      # 系统配置
├── hobot-display                      # mipi显示屏驱动
├── hobot-dnn                          # 神经网络库
├── hobot-drivers                      # bpu驱动
├── hobot-dtb                          # dtb包
├── hobot-io                           # IO库，工具
├── hobot-io-samples                   # IO示例
├── hobot-kernel-headers               # 内核头文件
├── hobot-miniboot                     # miniboot固件
├── hobot-multimedia                   # 多媒体库
├── hobot-multimedia-dev               # 多媒体库头文件
├── hobot-multimedia-samples           # 多媒体示例
├── hobot-spdev                        # 封装的多媒体库
├── hobot-sp-samples                   # 多媒体示例，C，Python
├── hobot-utils                        # 工具库
├── hobot-wifi                         # wif配置
└── kernel                             # linux内核源码
```

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

以 hobot- 开头软件包是 RDK 官方开发和维护的 debian 软件包的源码和配置，下载完整源码后，可以执行 `mk_debs.sh` 重新构建debian包。

帮助信息如下：

```shell
$ ./mk_debs.sh help
The debian package named by 'help' is not supported, please check the input parameters.
./mk_debs.sh [all] | [deb_name]
    hobot-boot
    hobot-kernel-headers
    hobot-dtb
    hobot-configs
    hobot-utils
    hobot-display
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
./mk_debs.sh
```

构建完成后，会在`deploy/deb_pkgs`目录下生成 `*.deb` 后缀的软件包。

#### 构建单独的 debian 软件包

`mk_debs.sh` 支持单独构建指定的软件包，在执行时带包名参数即可，例如：

```shell
./mk_debs.sh hobot-configs
```

### 编译 bootloader

`bootloader`源码用于生成最小启动镜像 `miniboot.img`，生成包含分区表、spl、ddr、bl31、uboot等的最小启动固件。

RDK 的最小启动镜像一般会由 RDK 官方进行维护发布，可以从 [miniboot](https://archive.d-robotics.cc/downloads/miniboot/) 下载对应的版本，`hobot-miniboot` 软件包也会同步更新。`bootloader` 涉及最基础的启动过程，在修改本模块前，请充分了解本模块的功能。

按照以下步骤重新编译生成 miniboot。

#### 选择硬件配置文件

```shell
cd source/bootloader/build
./xbuild.sh lunch

Lunch menu... pick a combo:
      0. rdk/x5/board_x5_rdk_ubuntu_nand_sdcard_debug_config.mk
      1. rdk/x5/board_x5_rdk_ubuntu_nand_sdcard_release_config.mk
Which would you like? [0] :
```

根据提示选择板级配置文件。以上预置配置文件适配不同的开发板的硬件配置。

lunch 命令还支持以下两种使用方式：

- 带数字参数指定板级配置
- 带板级配置文件名指定板级配置

```shell
$ ./xbuild.sh lunch 0

You're building on #127~20.04.1-Ubuntu SMP Thu Jul 11 15:36:12 UTC 2024
You are selected board config: rdk/x5/board_x5_rdk_ubuntu_nand_sdcard_debug_config.mk

$ ./xbuild.sh lunch board_x5_rdk_ubuntu_nand_sdcard_debug_config.mk

You're building on #127~20.04.1-Ubuntu SMP Thu Jul 11 15:36:12 UTC 2024
You are selected board config: rdk/x5/board_x5_rdk_ubuntu_nand_sdcard_debug_config.mk
```

#### 编译 nand_disk.img

进入到 build 目录下，执行 xbuild.sh 进行整体编译：

```shell
cd source/bootloader/build
./xbuild.sh
```

编译成功后，会在编译镜像输出目录（out/product） 目录下生成 **nand_disk.img**，uboot.img， miniboot_all.img 等镜像文件。其中 **nand_disk.img** 即最小启动镜像文件。

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
