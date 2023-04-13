# ROCKCHIP SDK

## Description:

    This SDK is based on the Rockchip official release version which contain as little redundant code as possible. 

    There are a small size and simple packaging program compared with the official SDK.

## Support List

- <kbd>RADXA ROCK 3 MODEL A</kbd>

- <kbd>RADXA ROCK 5 MODEL B</kbd>

## Get Sart

**Fetch SDK :** 

```shell
git clone https://github.com/Hao-boyan/rockchip_sdk.git
```

```shell
git submodule init
```

```shell
git submodule update
```

**Install Dependencies :**

 Platform : Ubuntu20.04

```shell
sudo apt-get install git ssh make gcc libssl-dev liblz4-tool expect \
g++ patchelf chrpath gawk texinfo chrpath diffstat binfmt-support \
qemu-user-static live-build bison flex fakeroot cmake gcc-multilib \
g++-multilib unzip device-tree-compiler ncurses-dev libgucharmap-2-90-dev \
bzip2 expat gpgv2 cpp-aarch64-linux-gnu time mtd-utils swig
```

```shell
pip3 install pyelftools
```

**View Usage Information :**

```shell
sudo ./img.sh usage
```

**Initiate SDK :**

```shell
sudo ./img.sh init
```

```shell
sudo ./img.sh def
```

## Build

**u-boot**

```shell
cd u-boot
```

```shell
./make.sh
```

**kernel**

```shell
cd kernel
```

```shell
make
```

**buildroot**

```shell
cd buildroot
```

```shell
make
```

## Generate Image

```shell
sudo ./img.sh all
```

Flash <kbd>./out/system.img</kbd> into SD card



you can flash separate firmware into USB SD reader

```shell
sudo ./img.sh -e xxx
```




