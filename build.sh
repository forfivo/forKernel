#!/bin/bash
# script based on mani/ckret code
# Add Colors to unhappiness
green='\033[01;32m'
red='\033[01;31m'
yellow='\033[1;33m'
restore='\033[0m'

clear

# Kernel Details
BASE_KERNEL_VERSION="for_t800_v"
DEFCONF="for_defconfig"

# Directories & jobs
JOBS=`grep -c "processor" /proc/cpuinfo`
KERNEL_DIR="$HOME/Documentos/IronKernel"
PACKAGE_DIR="$HOME/Documentos/IronKernel/package_files"
OUTPUT_DIR="$HOME/Documentos/IronKernel/output_zips"
RAMDISK_SRC="$HOME/Documentos/IronKernel/ramdisk"
SDCARD_FOLDER="/storage/sdcard1"

function set_version {
	DATE_START=$(date +"%s")
	echo -e -n "${yellow}"
	read -p "TYPE THE KERNEL VERSION: " VERSION
	echo -e -n "${restore}"
	KERNEL_VERSION="$BASE_KERNEL_VERSION$VERSION"
	echo -e -n "${green}"
	echo "KERNEL VERSION: $KERNEL_VERSION"
	echo -e -n "${restore}"
}

function export_sys_variables {
	echo -e -n "${yellow}"
	echo "EXPORTING VARIABLES..." 
	echo -e -n "${restore}"
	export KBUILD_BUILD_VERSION=$VERSION
	export LOCALVERSION=~`echo $KERNEL_VERSION`
	export ARCH=arm
	export SUBARCH=arm
	#export CROSS_COMPILE="$HOME/android/arm-cortex_a15-linux-gnueabihf-linaro_4.9.3-2015.02/bin/arm-cortex_a15-linux-gnueabihf-"
	#export CROSS_COMPILE="$HOME/Documentos/arm-cortex_a15-linux-gnueabihf-linaro_4.9_2015/bin/arm-cortex_a15-linux-gnueabihf-"
	export CROSS_COMPILE="$HOME/Documentos/LinaroMod-arm-eabi-4.9/bin/arm-eabi-"
	echo -e -n "${green}"
	echo "VARIABLES EXPORTED."
	echo -e -n "${restore}"
}

function build_zImage {
	echo -e -n "${yellow}"
	echo "BUILDING ZIMAGE..."
	echo -e -n "${restore}"
	make $DEFCONF
	make -j$JOBS
	echo -e -n "${green}"
	echo "ZIMAGE BUILT."
	echo -e -n "${restore}"
}

function build_boot_img {
	echo -e -n "${yellow}"
	echo "BUILDING BOOT.IMG..."
	echo -e -n "${restore}"
	make $DEFCONF
	make -j$JOBS
	./mkbootfs "$RAMDISK_SRC" | gzip > "$PACKAGE_DIR/ramdisk.gz"
	./mkbootimg --kernel "$KERNEL_DIR/arch/arm/boot/zImage" --ramdisk "$PACKAGE_DIR/ramdisk.gz" --pagesize 2048 --ramdiskaddr 0x11000000 --output $PACKAGE_DIR/boot.img
	rm $PACKAGE_DIR/ramdisk.gz
	echo -e -n "${green}"
	echo "BOOT.IMG BUILT."
	echo -e -n "${restore}"
}

function build_zip {
	#echo -e -n "${green}"
	#echo "COPYING ZIMAGE TO $PACKAGE_DIR..."
	#echo -e -n "${restore}"
	#cp arch/arm/boot/zImage $PACKAGE_DIR/kernel/

	zipfile="$KERNEL_VERSION"
	echo -e -n "${yellow}"
	echo "CREATING ZIP FILE..."
	echo -e -n "${restore}"
	cd "$PACKAGE_DIR"
	rm -f *.zip
	zip -9 -r "$zipfile" *
	rm -f /tmp/*.zip
	cp *.zip /tmp

	#rm -f "$PACKAGE_DIR/kernel/zImage"
	mv *.zip "$OUTPUT_DIR"

	echo -e -n "${green}"
	echo "ZIPFILE $KERNEL_VERSION BUILT."
	echo -e -n "${restore}"

	echo -e -n "${red}"
	echo "KERNEL IS READY TO BE FLASHED."
	echo -e -n "${restore}"
	DATE_END=$(date +"%s")
	DIFF=$(($DATE_END - $DATE_START))
	echo "PROCESSING TIME: $(($DIFF / 60)) MINUTE(S) AND $(($DIFF % 60)) SECONDS."
}

function flash_file {
	#adb shell "rm $SDCARD_FOLDER/kernel.zip"
	adb push "$OUTPUT_DIR/$zipfile.zip" "$SDCARD_FOLDER/kernel.zip" || exit 1
	adb remount
	adb shell "echo 'boot-recovery ' > /cache/recovery/command"
	adb shell "echo '--update_package=$SDCARD_FOLDER/kernel.zip' >> /cache/recovery/command"
	adb shell "echo '--wipe_cache' >> /cache/recovery/command"
	adb shell "echo 'reboot' >> /cache/recovery/command"
	adb reboot recovery
}

echo "###################"
echo "### for.kernel ###"
echo "###################"

while read -p "DO YOU WANT TO BUILD THE KERNEL (Y/N) OR CLEAN THE REPOSITORY (C)? " first_choice
do
case "$first_choice" in
	y|Y)
		set_version
		export_sys_variables
		#build_zImage
		build_boot_img
		build_zip
		break
		;;
	n|N )
		break
		;;
	c|C )
		make clean & make mrproper
		;;
	* )
		echo "INVALID INPUT. ASSUMING YOU WANT TO BUILD THE KERNEL!"
		set_version
		export_sys_variables
		#build_zImage
		build_boot_img		
		build_zip
		break
		;;
esac
done

echo -e -n "${green}"
while read -p "DO YOU WANT TO FLASH THE KERNEL RIGHT NOW (Y/N)? IT WILL REBOOT IMMEDIATELY IF YOUR ANSWER IS POSITIVE." second_choice
do
case "$second_choice" in
	y|Y)
		#flash_file
		break
		;;
	n|N )
		break
		;;
	* )
		echo "INVALID INPUT. ASSUMING YOU DON'T WANT TO FLASH IT NOW!"
		break
		;;
esac
done
echo -e -n "${restore}"
