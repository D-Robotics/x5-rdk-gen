# 开发环境搭建及编译说明

## rdk-gen

rdk-gen用于构建适用于地平线RDK X3的定制操作系统镜像。它提供了一个可扩展的框架，允许用户根据自己的需求定制和构建RDK X3的Ubuntu操作系统。

下载源码：

方式一 使用repo

```shell
repo init -u git@github.com:HorizonRDK/x5-manifest.git -b develop
```
默认情况下，会从https://gerrit.googlesource.com/git-repo下载repo源码，但国内访问googlesource经常访问不到；

可以从先从https://github.com/HorizonRDK/x5-rdk-gen目录下单独下载repo脚本，该脚本使用国内的镜像源，然后执行以下命令下载源代码
```shell
./repo init -u git@github.com:HorizonRDK/x5-manifest.git -b develop
```

方式二 使用git

```shell
git clone https://github.com/HorizonRDK/x5-rdk-gen.git -b develop
```

下载完成后，rdk-gen的目录结构如下：

| **目录**                  | **说明**                                                     |
| ------------------------- | ------------------------------------------------------------ |
| pack_image.sh             | 构建系统镜像的代码入口                                       |
| download_samplefs.sh      | 下载预先制作的基础ubuntu文件系统                       |
| download_deb_pkgs.sh      | 下载地平线的deb软件包，需要预装到系统镜像中，包括内核、多媒体库、示例代码、tros.bot等 |
| hobot_customize_rootfs.sh | 定制化修改ubuntu文件系统                               |
| source_sync.sh            | 下载源码，包括bootloader、uboot、kernel、示例代码等源码      |
| mk_kernel.sh              | 编译内核、设备树和驱动模块                                   |
| mk_debs.sh                | 生成deb软件包                                                |
| make_ubuntu_samplefs.sh   | 制作ubuntu系统filesystem的代码，可以修改本脚本定制samplefs   |
| config                    | 存放需要放到系统镜像/hobot/config目录下的内容，一个vfat根式的分区，如果是sd卡启动方式，用户可以在windows系统下直接修改该分区的内容。 |


rdk-linux相关的内核、bootloader、hobot-xxx软件包源码都托管在 [GitHub](https://github.com/)上。在下载代码前，请先注册、登录  [GitHub](https://github.com/)，并通过 [Generating a new SSH key and adding it to the ssh-agent](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent) 方式添加开发服务器的`SSH Key`到用户设置中。

`source_sync.sh`用于下载源代码，包括bootloader、uboot、kernel、示例代码等，该下载程序通过执行 `git clone git@github.com:xxx.git` 的方式把所有源码下载到本地。

执行以下命令下载主线分支代码：

```shell
./source_sync.sh -t develop
```

该程序默认会把源码下载到 source 目录下：

```
source
├── bootloader
├── hobot-boot
├── hobot-configs
├── hobot-dtb
├── hobot-kernel-headers
├── hobot-wifi
├── hobot-boot
└── kernel
```

## bootloader

`bootloader`源码用于生成最小启动镜像`nand_disk.img`，生成包含分区表、miniboot、uboot一体的启动固件。

RDK X5的最小启动镜像一般会由地平线官方进行维护发布，可以从 [miniboot](http://sunrise.horizon.cc/downloads/miniboot/) 下载对应的版本。

按照以下步骤重新编译生成miniboot。

```shell
cd source/bootloader/
cd build
./xbuild.sh lunch

You're building on #221-Ubuntu SMP Tue Apr 18 08:32:52 UTC 2023
Lunch menu... pick a combo:
      0. horizon/x5/board_rdk_x5_ubuntu_nand_sdcard_release_config.mk
Which would you like? [0] :  
```

选择0

```shell
./xbuild.sh
```

得到最新系统，保存在source/bootloader/out/product
使用D-navigation工具进行烧录，evb启动模式切换到qspi nand，烧录方式请参考X5 EVB SDK文档

## kernel

执行以下命令编译linux内核：

```shell
./mk_kernel.sh
```

编译完成后，会在`deploy/kernel`目录下生成内核镜像、驱动模块、设备树、内核头文件。

## 制作deb包
执行以下命令会重新全部构建所有的debian包（需要先完成kernel的编译）：

```shell
./mk_deb.sh
```

## 制作ubuntu

先执行拉取ubuntu原始镜像

sudo ./pack_image.sh server
删除deb_packages目录下的deb包，这些包都是X3的

sudo ./pack_image.sh server C
使用rdk编译的包构建ubuntu文件系统











