#!/bin/bash -e

# - - - - - - - - - - - - - - - - - - - - user configure - - - - - - - - - - - - - - - - - - - - - - - #


BOOT_SIZE_MB=40  				# First paritition(kernel) size, include kernel image and DTB.
ROOTFS_SIZE_MB=30				# Second paritition(rootfs) size, effect when ROOTFS_DIR_EN = yes, otherwise it depends on ROOTFS_IMG size.
ROOTFS_DIR_EN=yes				# yes: enable ROOTFS_DIR, ROOTFS_IMG file will be invalid.	 
ROOTFS_IMG=rootfs.img				# rootfs image name.
ROOTFS_DIR="./buildroot/output/target"	# Custom rootfs directory relative path, effect when ROOTFS_DIR_EN not equal to yes.

# - - - - - - - - ! Do not change anything below unless you know what you're doing ! - - - - - - - - -#
LOCALPATH=$(pwd)
OUT_DIR_NAME=out			
SYSTEM=system.img
OUT=$LOCALPATH/$OUT_DIR_NAME
ROOTFS_UUID=614e0000-0000-4b53-8000-1d28000054a9
ROOTFS_DIR_REAL="`readlink -f $LOCALPATH/$ROOTFS_DIR`"
uboot_version="`make --no-print-directory -C u-boot/ ubootversion`"

LOADER1_SIZE=8000			# unit: 1 Sector = 512 Byte
RESERVED1_SIZE=128
RESERVED2_SIZE=8192
LOADER2_SIZE=8192
ATF_SIZE=8192
BOOT_SIZE=$((${BOOT_SIZE_MB} * 1024 * 1024 / 512))	
ROOTFS_SIZE=$((${ROOTFS_SIZE_MB} * 1024 * 1024 / 512))
RESERVED3_SIZE=64

SYSTEM_START=0
LOADER1_START=64
RESERVED1_START=$(expr ${LOADER1_START} + ${LOADER1_SIZE})
RESERVED2_START=$(expr ${RESERVED1_START} + ${RESERVED1_SIZE})
LOADER2_START=$(expr ${RESERVED2_START} + ${RESERVED2_SIZE})
ATF_START=$(expr ${LOADER2_START} + ${LOADER2_SIZE})
BOOT_START=$(expr ${ATF_START} + ${ATF_SIZE})
ROOTFS_START=$(expr ${BOOT_START} + ${BOOT_SIZE})
RESERVED3_START=$(expr ${ROOTFS_START} + ${ROOTFS_SIZE})
SYSTEM_END=$(expr ${RESERVED3_START} + ${RESERVED3_SIZE} - 1)

if [ "$USER" != "root" ]; then
	echo -e "[\e[31m Warning \e[0m]:  Please run as administrator"
	echo -e "\nFor example:\n\tsudo $0 $*"
	echo -e "More info:\n\tsudo $0 usage"
	exit
fi

usage() {
	echo -e "\nUsage: \e[1msudo $0 [option] [target]\e[0m"
	echo ""	
	echo -e "Initiate this SDK"	
	echo -e "\e[32m	sudo $0 init\e[0m		- Choose default board level config file"	
	echo -e "Flash firmwar into virtual disk file: $OUT/$SYSTEM"	
	echo -e "\e[32m	sudo $0 uboot\e[0m		- Flash u-boot into $SYSTEM"
	echo -e "\e[32m	sudo $0 kernel\e[0m		- Flash linux into $SYSTEM"
	echo -e "\e[32m	sudo $0 rootfs\e[0m		- Flash rootfs into $SYSTEM"
	echo -e "\e[32m	sudo $0 all\e[0m  		- merger [ uboot|kernel|rootfs ] into $SYSTEM"
	echo -e "Flash firmwar into USB SD Card Reader: /dev/sdx"
	echo -e "\e[32m	sudo $0 -e uboot\e[0m		- Flash u-boot into external SD disk"
	echo -e "\e[32m	sudo $0 -e kernel\e[0m		- Flash linux into external SD disk"
	echo -e "\e[32m	sudo $0 -e rootfs\e[0m		- Flash rootfs into external SD disk"
	echo -e "\e[32m	sudo $0 -e all\e[0m		- Flash [ uboot|kernel|rootfs ] into external disk"
	echo -e "Clean firmware"
	echo -e "\e[32m	sudo $0 -d  [target]\e[0m	- It will clean [ uboot|kernel|rootfs ] which in $SYSTEM"
	echo -e "\e[32m	sudo $0 -de [target]\e[0m	- It will clean [ uboot|kernel|rootfs ] which in external SD disk"
	echo -e "Export environments"
	echo -e "\e[32m	sudo $0 exports\e[0m		- This cmd will export environments"		
	echo -e "Make defconfig"
	echo -e "\e[32m	sudo $0 def\e[0m		- This cmd will run 'make xxx_defconfig' and export environments"
	echo ""			
	echo -e "  1.you need modify some variables in this file if you have more requirements"
	echo -e "  2.you could use custom rootfs image by replace $OUT_DIR_NAME/$ROOTFS_IMG"
	echo ""			
}

finish() {
	cd $LOCALPATH
	echo -e "\e[31m Packge image failed !\e[0m\n"
	exit -1
}
trap finish ERR

system_img_format()
{
	echo "Start $SYSTEM formatting"
	loop_block_device=$(losetup -f)
	losetup $loop_block_device $OUT/$SYSTEM
	parted -s $loop_block_device mklabel gpt
	parted -s $loop_block_device unit s mkpart boot fat16 $BOOT_START $(expr ${ROOTFS_START} - 1)
	parted -s $loop_block_device set 1 esp on
	parted -s $loop_block_device -- unit s mkpart rootfs ext4 ${ROOTFS_START} -34s
	
	mkfs.vfat -n "boot" -S 512 ${loop_block_device}p1
	mkfs.ext4 -FL "rootfs" -b 4096 -U $ROOTFS_UUID ${loop_block_device}p2
	
	losetup -d $loop_block_device	
	echo -e "[\e[34m OK \e[0m]: $SYSTEM formatting completed"
}

check_system_image() 
{
	if [ "$ROOTFS_DIR_EN" = "yes" ]; then
		SYSTEM_IMG_SECTOR_SIZE=$(expr $RESERVED3_START + ${RESERVED3_SIZE})
	else
		ROOTFS_IMG_BYTE_SIZE=$(stat -L --format="%s" $OUT/$ROOTFS_IMG)
		SYSTEM_IMG_SECTOR_SIZE=$(expr $ROOTFS_START + $ROOTFS_IMG_BYTE_SIZE \/ 512 + ${RESERVED3_SIZE})	
	fi
	
	SYSTEM_IMG_BYTE_SIZE=$(expr ${SYSTEM_IMG_SECTOR_SIZE} \* 512)
	
	if [ -f $OUT/$SYSTEM ]; then	
		OLD_SYSTEM_IMG_BYTE_SIZE=$(stat -L --format="%s" $OUT/$SYSTEM)
	else
		OLD_SYSTEM_IMG_BYTE_SIZE=0
	fi	
	
	if [ "$SYSTEM_IMG_BYTE_SIZE" = "$OLD_SYSTEM_IMG_BYTE_SIZE" ]; then
		echo "$SYSTEM is ready, file size=$(expr ${SYSTEM_IMG_BYTE_SIZE} \/ 1024 \/ 1024)MB"
	else
		dd if=/dev/zero of=$OUT/$SYSTEM bs=512 count=0 seek=$SYSTEM_IMG_SECTOR_SIZE	
		echo -e "[\e[34m OK \e[0m]: generate blank image: $OUT/$SYSTEM, file size= $(expr ${SYSTEM_IMG_BYTE_SIZE} \/ 1024 \/ 1024)MB"
		echo -e "[\e[34m OK \e[0m]: uboot kernel rootfs have cleaned, you need flash them again !"
		system_img_format
	fi
}

prepare()
{
	echo "Start check file"
	if [ "$ALL_OPTIONS" = "uboot" ]; then	
		mkdir -p $OUT/u-boot

		if [ "$uboot_version" = "2017.09" ] && [ ! -f $LOCALPATH/u-boot/u-boot.itb ] && [ -f $LOCALPATH/u-boot/u-boot.bin ]; then
			cd ./u-boot
			su $SUDO_USER -c './make.sh --idblock'
			su $SUDO_USER -c './make.sh itb'
			cd $LOCALPATH	
		fi

		if [ -f $LOCALPATH/u-boot/idblock.bin ] && [ ! -f $LOCALPATH/u-boot/idbloader.img ]; then
			ln -rsf ./u-boot/idblock.bin ./u-boot/idbloader.img
		fi
					
		if [ -f $LOCALPATH/u-boot/idbloader.img ]; then
			ln -rsf ./u-boot/idbloader.img ./$OUT_DIR_NAME/u-boot/idbloader.img
		else	
			echo -e "[\e[31m Warning \e[0m]:  Not found u-boot tpl/spl bin, ${LOCALPATH}/u-boot/idbloader.img"
			finish
		fi
			
		if [ -f $LOCALPATH/u-boot/u-boot.itb ]; then
			ln -rsf ./u-boot/u-boot.itb ./$OUT_DIR_NAME/u-boot/u-boot.itb			
		else
			echo -e "[\e[31m Warning \e[0m]:  Not found u-boot bin, ${LOCALPATH}/u-boot/u-boot.itb"
			finish
		fi							

	fi
		
	if [ "$ALL_OPTIONS" = "kernel" ]; then
		mkdir -p $OUT/kernel	
		if [ -f $LOCALPATH/kernel/arch/arm64/boot/Image ]; then
			ln -rsf ./kernel/arch/arm64/boot/Image ./$OUT_DIR_NAME/kernel/Image	
		else
			echo -e "[\e[31m Warning \e[0m]:  Not found kernel image, ${LOCALPATH}/kernel/arch/arm64/boot/Image"
			finish
		fi
		
		if [ -f $LOCALPATH/kernel/arch/arm64/boot/dts/rockchip/${RK_KERNEL_DTS}.dtb ];then
			ln -rsf ./kernel/arch/arm64/boot/dts/rockchip/${RK_KERNEL_DTS}.dtb ./$OUT_DIR_NAME/kernel/${RK_KERNEL_DTS}.dtb		
		else
			echo -e "[\e[31m Warning \e[0m]:  Not found kernel DTB, ${LOCALPATH}/kernel/arch/arm64/boot/dts/rockchip/${RK_KERNEL_DTS}.dtb"
			finish
		fi
	fi

	if [ "$ALL_OPTIONS" = "rootfs" ]; then	
		if [ "$ROOTFS_DIR_EN" = "yes" ]; then
			if [ "`ls -A $ROOTFS_DIR_REAL`" != "" ] && [ -d $ROOTFS_DIR_REAL ]; then
				ln -rsf $ROOTFS_DIR ./$OUT_DIR_NAME/rootfs		
			else
 				echo -e "[\e[31m Warning \e[0m]:  rootfs directory is empty, $ROOTFS_DIR_REAL"
				finish 
			fi
		else
			if [ ! -f $OUT/$ROOTFS_IMG ]; then
				if [ ! -L $OUT/$ROOTFS_IMG ] && [ -f $LOCALPATH/buildroot/output/images/rootfs.ext2 ]; then	
					ln -rsf ./buildroot/output/images/rootfs.ext2 ./$OUT_DIR_NAME/$ROOTFS_IMG			
				else
					echo -e "[\e[31m Warning \e[0m]:  Not found rootfs image, $LOCALPATH/buildroot/output/images/rootfs.ext2"
					finish
				fi		
			fi
		
		fi		
	fi

	mkdir -p $OUT/kernel/extlinux
	if [ ! -f $OUT/kernel/extlinux/extlinux.conf ]; then	
# - - - - - - - - - -  Do not modify format - - - - - - - - - - - - - - - - - #
		cat > $OUT/kernel/extlinux/extlinux.conf <<EOF
label kernel-5.10
    kernel /Image
    fdt /${RK_KERNEL_DTS}.dtb
    append  earlyprintk rw root=/dev/mmcblk0p2 rootfstype=ext4 init=/sbin/init rootwait
EOF
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - #
		chown -R $SUDO_USER $OUT/kernel/extlinux
		chgrp -R $SUDO_USER $OUT/kernel/extlinux	
		echo -e "[\e[34m OK \e[0m]: generate boot config file, Ctrl + Left Mouse to edit: $OUT/kernel/extlinux/extlinux.conf"
	fi
	echo -e "[\e[34m OK \e[0m]: check complete."		
}

system_img_mount()
{
	prepare
	check_system_image
	
	if [ "$external_disk" = "yes" ]; then
		if [ "$( lsblk -l --output NAME,UUID -I 8 | grep -c $ROOTFS_UUID )" = "0" ]; then
			echo -e "[\e[31m Warning \e[0m]:  Not found UUID(\e[31m$ROOTFS_UUID\e[0m) disk"	
			echo -e "\n  You can flash $OUT/$SYSTEM into external SD disk then connect it with computer."
			finish		
		elif [ "$( lsblk -l --output NAME,UUID -I 8 | grep -c $ROOTFS_UUID )" = "1" ]; then
			main_block_device=$( lsblk -l --output NAME,UUID -I 8 | grep $ROOTFS_UUID | grep -o sd[a-z] )
			sub_block_boot=${main_block_device}1
			sub_block_rootfs=${main_block_device}2
			
			echo -e "Target device: \e[31m/dev/$main_block_device\e[0m, firmware will be writting here!"			
			lsblk -n --output NAME,SIZE,LABEL,FSTYPE,UUID /dev/$main_block_device

			if [ "`df -l --output=source /dev/$sub_block_boot | grep -o $sub_block_boot`" = "$sub_block_boot" ]; then		
				umount /dev/$sub_block_boot	# remount
			fi
			if [ "`df -l --output=source /dev/$sub_block_rootfs | grep -o $sub_block_rootfs`" = "$sub_block_rootfs" ]; then		
				umount /dev/$sub_block_rootfs	# remount
			fi			
			
		else
			echo -e "[\e[31m Warning \e[0m]:  There are same disk UUID($ROOTFS_UUID) below"
			lsblk -l --output NAME,UUID -I 8 | grep --color $ROOTFS_UUID			
			echo -e "\n  Please keep just one disk active and remove other disk you don't need."
			finish
		fi	
	else
		loop_block_device=$(losetup -f)	
		main_block_device=${loop_block_device##*/}
		sub_block_boot=${main_block_device}p1
		sub_block_rootfs=${main_block_device}p2
				
		echo "Loading virtual disk ./$OUT_DIR_NAME/$SYSTEM to /dev/$main_block_device"
		losetup -P /dev/$main_block_device $OUT/$SYSTEM		
		echo -e "Target device: \e[31m/dev/$main_block_device\e[0m, firmware will be writting here!"
	fi

	mkdir -p /mnt/$sub_block_boot
	if [ ! "`ls -A /mnt/$sub_block_boot`" = "" ]; then
 		echo -e "[\e[31m Warning \e[0m]:  /mnt/$sub_block_boot is not empty."
		finish 
	fi
			
	mkdir -p /mnt/$sub_block_rootfs
	if [ ! "`ls -A /mnt/$sub_block_rootfs`" = "" ]; then
		rmdir /mnt/$sub_block_boot
 		echo -e "[\e[31m Warning \e[0m]:  /mnt/$sub_block_rootfs is not empty."
		finish 
	fi
		
	mount /dev/$sub_block_boot /mnt/$sub_block_boot
	mount /dev/$sub_block_rootfs /mnt/$sub_block_rootfs			
}

system_img_umount()
{
	umount /mnt/$sub_block_boot	
	umount /mnt/$sub_block_rootfs
	
	rmdir /mnt/$sub_block_boot
	rmdir /mnt/$sub_block_rootfs

	if [ "$external_disk" = "yes" ]; then
		eject /dev/$main_block_device
		echo -e "[\e[34m OK \e[0m]: \e[1mExternal disk have ejected successfully: /dev/$main_block_device\e[0m"
	else
		losetup -d /dev/$main_block_device	
		echo -e "[\e[34m OK \e[0m]: \e[1mVirtual disk have removed successfully: /dev/$main_block_device\e[0m"
	fi
	echo -e "[\e[34m OK \e[0m]: All processes completed.\n"
}

update_uboot()
{
	echo -e "\nStart update uboot"
	system_img_mount
	if [ "$delete_old" = "yes" ]; then
		dd if=/dev/zero of=/dev/$main_block_device count=$LOADER1_SIZE seek=$LOADER1_START
		dd if=/dev/zero of=/dev/$main_block_device count=$LOADER2_SIZE conv=fsync seek=$LOADER2_START
		echo -e "[\e[34m OK \e[0m]: u-boot loader1 and loder2 have cleaned!"
		system_img_umount
		return 0			
	fi
	
	dd if=$OUT/u-boot/idbloader.img of=/dev/$main_block_device conv=notrunc,fsync seek=64
	dd if=$OUT/u-boot/u-boot.itb of=/dev/$main_block_device conv=notrunc,fsync seek=16384	

	echo -e "[\e[34m OK \e[0m]: uboot update completed"
	system_img_umount		
}

update_kernel()
{
	echo -e "\nStart update kernel"
	system_img_mount
	
	if [ "$delete_old" = "yes" ]; then
		rm -rf /mnt/$sub_block_boot/*
		echo -e "[\e[34m OK \e[0m]: linux have cleaned!"
		system_img_umount
		return 0	
	fi
	
	mkdir -p /mnt/$sub_block_boot/extlinux/
	cp -Luv $OUT/kernel/Image /mnt/$sub_block_boot
	cp -Luv $OUT/kernel/${RK_KERNEL_DTS}.dtb /mnt/$sub_block_boot
	cp -fv  $OUT/kernel/extlinux/extlinux.conf /mnt/$sub_block_boot/extlinux/
		
	echo -e "[\e[34m OK \e[0m]: kernel update completed"	
	system_img_umount
}

update_rootfs()
{
	echo -e "\nStart update rootfs"
	system_img_mount
	
	if [ "$delete_old" = "yes" ]; then
		rm -rf /mnt/$sub_block_rootfs/*
		echo -e "[\e[34m OK \e[0m]: rootfs have cleaned!"
		system_img_umount
		return 0
	fi
	
	if [ "$ROOTFS_DIR_EN" = "yes" ]; then
		echo "rootfs source: $ROOTFS_DIR_REAL"	
		cp -ru $OUT/rootfs/* /mnt/$sub_block_rootfs	
		
		if [ ! -c "/mnt/$sub_block_rootfs/dev/null" ]; then
			mknod -m 666 /mnt/$sub_block_rootfs/dev/null  c 1 3
		fi
	else	
		rootfs_img_device=$(losetup -f)	
		custom_block_rootfs=${rootfs_img_device##*/}
		losetup -P /dev/$custom_block_rootfs $OUT/$ROOTFS_IMG			
		mkdir -p /mnt/$custom_block_rootfs
		mount /dev/$custom_block_rootfs /mnt/$custom_block_rootfs
		echo "rootfs source: $OUT/$ROOTFS_IMG"
		cp -ru /mnt/$custom_block_rootfs/* /mnt/$sub_block_rootfs
		umount /mnt/$custom_block_rootfs
		rmdir /mnt/$custom_block_rootfs
		losetup -d /dev/$custom_block_rootfs	
	fi	

	sed -i "s/export PS1='# '/export PS1='\\\[\\\033[01;32m\\\]\\\u@\\\h\\\[\\\033[00m\\\]:\\\[\\\033[01;34m\\\]\\\w\\\[\\\033[00m\\\]\\\\# '/g" /mnt/$sub_block_rootfs/etc/profile
	sed -i "s/export PS1='$ '/export PS1='\\\[\\\033[01;32m\\\]\\\u@\\\h\\\[\\\033[00m\\\]:\\\[\\\033[01;34m\\\]\\\w\\\[\\\033[00m\\\]\\\\$ '/g" /mnt/$sub_block_rootfs/etc/profile
		
	linux_ver="`make --no-print-directory -C kernel/ kernelversion`"
	mkdir -p /mnt/$sub_block_rootfs/lib/modules/$linux_ver
	
	if [ "modules_install" = "yes" ]; then
		make --no-print-directory -C kernel/ modules_install INSTALL_MOD_PATH=/mnt/$sub_block_rootfs/lib/modules/$linux_ver
	fi

	echo -e "[\e[34m OK \e[0m]: rootfs update completed"	
	system_img_umount	
}

setup_cross_compile()
{
	if [ "$RK_CHIP" = "rv1126_rv1109" ]; then
		TOOLCHAIN_OS=rockchip
	else
		TOOLCHAIN_OS=none
	fi
	TOOLCHAIN_ARCH=${RK_KERNEL_ARCH/arm64/aarch64}
	TOOLCHAIN_DIR="$(realpath prebuilts/gcc/*/$TOOLCHAIN_ARCH/gcc-arm-*)"
	GCC="$(find "$TOOLCHAIN_DIR" -name "*$TOOLCHAIN_OS*-gcc")"
	if [ ! -x "$GCC" ]; then
		echo -e "[\e[31m Warning \e[0m]:  No prebuilt GCC toolchain!"
		finish
	fi

	export CROSS_COMPILE="${GCC%gcc}"
	echo "Using cross compile toolchain: $CROSS_COMPILE"

	NUM_CPUS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
	JLEVEL=${RK_JOBS:-$(( $NUM_CPUS + 1 ))}
}

export_env()
{
	setup_cross_compile
	if [ "uboot_mainline" = "yes" ]; then
		export BL31="`readlink -f $LOCALPATH/rkbin/bin/rk35/rk3568_bl31_v*.elf`"
		export ROCKCHIP_TPL="`readlink -f $LOCALPATH/rkbin/bin/rk35/rk3568_ddr_1560MHz_v*.bin`"
	fi
		export ARCH=$RK_KERNEL_ARCH	
}
run_defconfig()
{
	export_env
	if [ -f $LOCALPATH/u-boot/configs/${RK_UBOOT_DEFCONFIG}_defconfig ];	then
		su $SUDO_USER -c 'make -C u-boot/ ${RK_UBOOT_DEFCONFIG}_defconfig'
	else
		echo -e "[\e[31m Warning \e[0m]:  not found u-boot config file: $LOCALPATH/u-boot/configs/${RK_UBOOT_DEFCONFIG}_defconfig"
	fi

	if [ -f $LOCALPATH/kernel/arch/$RK_KERNEL_ARCH/configs/$RK_KERNEL_DEFCONFIG ]; then		
		su $SUDO_USER -c 'make -C kernel/ $RK_KERNEL_DEFCONFIG'
	else
		echo -e "[\e[31m Warning \e[0m]:  not found linux config file: $LOCALPATH/kernel/arch/$RK_KERNEL_ARCH/configs/$RK_KERNEL_DEFCONFIG"	
	fi
	
	if [ -f $LOCALPATH/buildroot/configs/${RK_CFG_BUILDROOT}_defconfig ]; then		
		su $SUDO_USER -c 'make -C buildroot/ ${RK_CFG_BUILDROOT}_defconfig'
	else
		echo -e "[\e[31m Warning \e[0m]:  not found buildroot config file: $LOCALPATH/buildroot/configs/${RK_CFG_BUILDROOT}_defconfig"
	fi
}

update_all()
{
	echo -e "\nStarting update uboot, kernel, rootfs"
	update_uboot		
	update_kernel
	update_rootfs
}

print_boardconfig()
{
	boardconfig_path="`readlink -f $LOCALPATH/device/rockchip/.BoardConfig.mk`"	
	echo -e "Current board config file: `ls --hyperlink $boardconfig_path`"	
}

choose_board()
{
	echo -e "\nStart initial this SDK, choose SOC product directory and board config file"
	
	echo -e "\nThis SDK have supported"
	echo -e "\t\e[1mBoard Name\e[0m	\e[1mSOC Series\e[0m	\e[1mBoard Config File\e[0m"
	echo -e "\t\e[34;1mROCK 3A\e[0m		rk356x		BoardConfig-rk3568-rock-3a.mk"
	echo -e "\t\e[34;1mROCK 5B\e[0m		rk3588		BoardConfig-rk3588-rock-5b.mk"		
	echo -e "\n\e[1mType SOC series name which you want to choose then Enter\e[0m:\n"
	echo -e "\e[31;1mrk356x\e[0m		- include rk3566 and rk3568"
	echo -e "\e[31;1mrk3588\e[0m		- include rk3588 and rk3588s"
	echo ""
	read -p "[Step 1]: Which would you like?: " TARGET_SOC
	
	if [ "$TARGET_SOC" = "rk356x" ] || [ "$TARGET_SOC" = "rk3588" ]; then
		ln -rsf -T "./device/rockchip/$TARGET_SOC" "./device/rockchip/.target_product"
		echo -e "[\e[34m OK \e[0m]: choosed SOC directory: ./device/rockchip/.target_product -> ./device/rockchip/$TARGET_SOC"		
	else
		echo -e "[\e[31m Warning \e[0m]: not support \e[1m$TARGET_SOC\e[0m"
		finish	
	fi
	
	BOARD_ARRAY=( $(cd $LOCALPATH/device/rockchip/.target_product/; ls BoardConfig*.mk | sort) )

	RK_TARGET_BOARD_ARRAY_LEN=${#BOARD_ARRAY[@]}
	if [ $RK_TARGET_BOARD_ARRAY_LEN -eq 0 ]; then
		echo -e "[\e[31m Warning \e[0m]:  No available Board Config"
		finish
	fi

	echo -e "\n\e[1mType the number which you want to choose then Enter\e[0m:\n"
	echo  ${BOARD_ARRAY[@]} | xargs -n 1 | sed "=" | sed "N;s/\n/. /"
	echo ""
	local INDEX
	read -p "[Step 2]: Which would you like?: " INDEX
	INDEX=$((${INDEX:-0} - 1))

	if echo $INDEX | grep -vq [^0-9]; then
		BOARD="${BOARD_ARRAY[$INDEX]}"
	else
		echo -e "[\e[31m Warning \e[0m]:  Failed to choose boardconfig file"
		finish
	fi

	ln -rsf "./device/rockchip/$TARGET_SOC/$BOARD" "./device/rockchip/.BoardConfig.mk"	
	echo -e "[\e[34m OK \e[0m]: choosed BoardConfig file: ./device/rockchip/.BoardConfig.mk -> ./device/rockchip/$BOARD"
	print_boardconfig

	if [ -f $OUT/kernel/extlinux/extlinux.conf ]; then
		rm $OUT/kernel/extlinux/extlinux.conf	
	fi	

	echo -e "[\e[34m OK \e[0m]: SDK init completed\n"
}


ALL_OPTIONS="${@:-usage}"
args_last="${@: -1}"
if [ $# -ge 3 ]; then
        echo -e "[\e[31m Warning \e[0m]:  arguments quantity too many!"
        echo -e "More info:\n\tsudo $0 usage"
        finish
fi
while getopts ":ed" opt_arg
do
    case "$opt_arg" in
      "e")
        external_disk="yes"
	ALL_OPTIONS="$args_last"
        ;;
      "d")
        delete_old="yes"
	ALL_OPTIONS="$args_last"
        ;;
      ":")
        echo -e "[\e[31m Warning \e[0m]:  Option [-$OPTARG] needs a value"
        finish
        ;;
      "?")
        echo -e "[\e[31m Warning \e[0m]:  Option [-$OPTARG] is not supported"
        finish
        ;;
      *)
        echo -e "[\e[31m ERROR \e[0m]:  Unknown error while processing options"
        finish
        ;;
    esac
done

if [ -f $LOCALPATH/device/rockchip/.BoardConfig.mk ] && [ -d $LOCALPATH/device/rockchip/.target_product ];then
	source $LOCALPATH/device/rockchip/.BoardConfig.mk
elif [ "$ALL_OPTIONS" != "init" ]; then	
	echo -e "[\e[31m Warning \e[0m]:  Not found SOC product directory and board config file, please initial this project."
	echo -e "More info:\n\tsudo $0 usage"
	finish
fi

for option in $ALL_OPTIONS; do
	echo -e "processing option: \e[31;1m$option\e[0m"
	print_boardconfig
	case $option in
		exports) export_env;;
		def) run_defconfig;;
		init) choose_board;;
		all) update_all;;
		uboot) update_uboot;;
		kernel) update_kernel;;
		rootfs) update_rootfs;;
		*) 
			echo -e "[\e[31m Warning \e[0m]: Option \e[31m$ALL_OPTIONS\e[0m is not supported"
			usage ;;
	esac
done
