# 开发环境搭建及编译说明

./source_sync.sh -t develop
该程序默认会把源码下载到 source 目录下：

```
source
├── bootloader
├── hobot-boot
├── hobot-dtb
└── kernel
└── uboot
```

## 最小启动镜像
cd source/bootloader/
cp ../uboot ./ -rf
cd build
./xbuild.sh lunch

You're building on #41~22.04.2-Ubuntu SMP PREEMPT_DYNAMIC Mon Jun  3 11:32:55 UTC 2
Lunch menu... pick a combo:
      0. horizon/x5/board_rdk_x5_ubuntu_nand_sdcard_release_config.mk
Which would you like? [0] : 

选择0

./xbuild.sh no_secure
得到最新系统，source/bootloader/out/product
使用D-navigation工具进行烧录，evb启动模式切换，烧录方式请参考X5 EVB SDK文档

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











