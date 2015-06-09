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
SDCARD_FOLDER="/storage/sdcard1"

function set_version {
	DATE_START=$(date +"%s")
	echo -e "${yellow}"
	read -p "### enter kernel version: " VERSION
	echo -e "${restore}"
	KERNEL_VERSION="$BASE_KERNEL_VERSION$VERSION"
	echo -e "${red}"
	echo "### kernel version: $KERNEL_VERSION"
	echo -e "${restore}"
}

function export_sys_variables {
	export KBUILD_BUILD_VERSION=$VERSION
	export LOCALVERSION=~`echo $KERNEL_VERSION`
	export ARCH=arm
	export SUBARCH=arm
	#export CROSS_COMPILE="$HOME/android/arm-cortex_a15-linux-gnueabihf-linaro_4.9.3-2015.02/bin/arm-cortex_a15-linux-gnueabihf-"
	#export CROSS_COMPILE="$HOME/Documentos/arm-cortex_a15-linux-gnueabihf-linaro_4.9_2015/bin/arm-cortex_a15-linux-gnueabihf-"
	export CROSS_COMPILE="$HOME/Documentos/LinaroMod-arm-eabi-4.9/bin/arm-eabi-"
}

function build_zImage {
	echo -e "${green}"
	echo "### build zImage"
	echo -e "${restore}"
	make $DEFCONF
	make -j$JOBS
}

function build_zip {
	echo -e "${green}"
	echo "### copy zImage to $PACKAGE_DIR"
	echo -e "${restore}"
	cp arch/arm/boot/zImage $PACKAGE_DIR/kernel/

	zipfile="$KERNEL_VERSION"
	echo -e "${green}"
	echo "### zipping the kernel"
	echo -e "${restore}"
	cd "$PACKAGE_DIR"
	rm -f *.zip
	zip -9 -r "$zipfile" *
	rm -f /tmp/*.zip
	cp *.zip /tmp

	rm -f "$PACKAGE_DIR/kernel/zImage"
	mv *.zip "$OUTPUT_DIR"

	echo -e "${red}"
	echo "### ZIP $KERNEL_VERSION is ready"
	echo -e "${restore}"
	DATE_END=$(date +"%s")
	DIFF=$(($DATE_END - $DATE_START))
	echo "Time: $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds."
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

while read -p "Build kernel (y/n) or clean everything (c)? " first_choice
do
case "$first_choice" in
	y|Y)
		set_version
		export_sys_variables
		build_zImage
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
		echo "Invalid entry. Assuming you want to build the kernel!"
		set_version
		export_sys_variables
		build_zImage
		build_zip
		break
		;;
esac
done

while read -p "Do you want to flash the kernel right now (y/n)? The kernel will reboot to recovery if your answer is positive." second_choice
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
		echo "Invalid entry. Assuming you don't want to flash it now!"
		break
		;;
esac
done
