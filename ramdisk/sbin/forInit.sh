#!/sbin/busybox sh

BB=/sbin/busybox;

mount -o remount,rw /
mount -o remount,rw /system /system

#
# Boot with CFQ I/O Gov
#
$BB echo "cfq" > /sys/block/mmcblk0/queue/scheduler;

#
# Wolfson sound default (parametric equalizer presets & tuning by heyjoe66)
#
# Main Speakers
#
echo "6" > /sys/class/misc/wolfson_control/eq_sp_gain_1
echo "10" > /sys/class/misc/wolfson_control/eq_sp_gain_2
echo "-2" > /sys/class/misc/wolfson_control/eq_sp_gain_3
echo "-1" > /sys/class/misc/wolfson_control/eq_sp_gain_4
echo "-2" > /sys/class/misc/wolfson_control/eq_sp_gain_5

#
# HeadPhones
#
echo "0x0fc6 0x03ff 0x00e8 0x1ed9 0xf11a 0x040a 0x045d 0x1e60 0xf150 0x040a 0x64cc 0x0b46 0xfed3 0x040a 0x3ab5 0xfc8f 0x0400 0x323c" > /sys/devices/virtual/misc/wolfson_control/eq_hp_freqs
echo "6" > /sys/class/misc/wolfson_control/eq_hp_gain_1
echo "3" > /sys/class/misc/wolfson_control/eq_hp_gain_2
echo "0" > /sys/class/misc/wolfson_control/eq_hp_gain_3
echo "1" > /sys/class/misc/wolfson_control/eq_hp_gain_4
echo "3" > /sys/class/misc/wolfson_control/eq_hp_gain_5

#
# Processes to be preserved from killing
#
if [ -f /sys/module/lowmemorykiller/parameters/donotkill_sysproc ]; then
	echo 1 > /sys/module/lowmemorykiller/parameters/donotkill_sysproc
	echo "android.process.acore,com.android.phone,com.sec.android.app.launcher,com.sec.android.widgetapp.at.hero.accuweather" > /sys/module/lowmemorykiller/parameters/donotkill_sysproc_names
fi
if [ -f /sys/module/lowmemorykiller/parameters/donotkill_proc ]; then
	echo 1 > /sys/module/lowmemorykiller/parameters/donotkill_proc
	echo "com.af.synapse" > /sys/module/lowmemorykiller/parameters/donotkill_proc_names
fi

#
# Synapse
#
busybox mount -t rootfs -o remount,rw rootfs
busybox chmod -R 755 /res/synapse
busybox ln -fs /res/synapse/uci /sbin/uci
/sbin/uci


#
# kernel custom test
#
if [ -e /data/Kerneltest.log ]; then
rm /data/Kerneltest.log
fi

echo  Kernel script is working !!! >> /data/Kerneltest.log
echo "excecuted on $(date +"%d-%m-%Y %r" )" >> /data/Kerneltest.log

mount -o remount,rw /

#
# Fast Random Generator (frandom) support on boot
#
if [ -c "/dev/frandom" ]; then
	# Redirect random and urandom generation to frandom char device
	chmod 0666 /dev/frandom
	chmod 0666 /dev/erandom
	mv /dev/random /dev/random.ori
	mv /dev/urandom /dev/urandom.ori
	rm -f /dev/random
	rm -f /dev/urandom
	ln /dev/frandom /dev/random
	chmod 0666 /dev/random
	ln /dev/frandom /dev/urandom
	chmod 0666 /dev/random
fi

mkdir -p /mnt/ntfs
chmod 777 /mnt/ntfs
mount -o mode=0777,gid=1000 -t tmpfs tmpfs /mnt/ntfs

mount -o remount,rw /
mount -o rw,remount /system

#
# Init.d
#
if [ ! -d /system/etc/init.d ]; then
	mkdir -p /system/etc/init.d/;
	chown -R root.root /system/etc/init.d;
	chmod 777 /system/etc/init.d/;
fi;

busybox run-parts /system/etc/init.d

#
# cleaning
#
$BB rm -rf /cache/lost+found/* 2> /dev/null;
$BB rm -rf /data/lost+found/* 2> /dev/null;
$BB rm -rf /data/tombstones/* 2> /dev/null;

#
# critical Permissions fix
#
$BB chown -R system:system /data/anr;
$BB chown -R root:root /tmp;
$BB chown -R root:root /res;
$BB chown -R root:root /sbin;
$BB chown -R root:root /lib;
$BB chmod -R 777 /tmp/;
$BB chmod -R 775 /res/;
$BB chmod -R 06755 /sbin/ext/;
$BB chmod -R 0777 /data/anr/;
$BB chmod -R 0400 /data/tombstones;
$BB chmod 06755 /sbin/busybox;

#
# oom and mem perm fix
#
$BB chmod 666 /sys/module/lowmemorykiller/parameters/cost;
$BB chmod 666 /sys/module/lowmemorykiller/parameters/adj;
$BB chmod 666 /sys/module/lowmemorykiller/parameters/minfree

#
# make sure we own the device nodes
#
$BB chown system /sys/devices/system/cpu/cpu0/cpufreq/*
$BB chown system /sys/devices/system/cpu/cpu1/online
$BB chown system /sys/devices/system/cpu/cpu2/online
$BB chown system /sys/devices/system/cpu/cpu3/online
$BB chmod 666 /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
$BB chmod 666 /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
$BB chmod 666 /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
$BB chmod 444 /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq
$BB chmod 444 /sys/devices/system/cpu/cpu0/cpufreq/stats/*
$BB chmod 666 /sys/devices/system/cpu/cpu1/online
$BB chmod 666 /sys/devices/system/cpu/cpu2/online
$BB chmod 666 /sys/devices/system/cpu/cpu3/online
$BB chmod 666 /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq_gpu
$BB chmod 666 /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq_gpu
$BB chmod 666 /sys/class/misc/mali0/device/time_in_state
$BB chmod 666 /sys/devices/platform/mali.0/power_policy
$BB chmod 666 /sys/module/lowmemorykiller/parameters/minfree

$BB chown -R root:root /data/property;
$BB chmod -R 0700 /data/property

#
# make sure our max gpu clock is set via sysfs
#
echo 480 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq_gpu
echo 177 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq_gpu

#
# set min max boot freq to default.
#
echo "1900000" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq;
echo "1900000" > /sys/devices/system/cpu/cpu1/cpufreq/scaling_max_freq;
echo "1900000" > /sys/devices/system/cpu/cpu2/cpufreq/scaling_max_freq;
echo "1900000" > /sys/devices/system/cpu/cpu3/cpufreq/scaling_max_freq;
echo "250000" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq;
echo "250000" > /sys/devices/system/cpu/cpu1/cpufreq/scaling_min_freq;
echo "250000" > /sys/devices/system/cpu/cpu2/cpufreq/scaling_min_freq;
echo "250000" > /sys/devices/system/cpu/cpu3/cpufreq/scaling_min_freq;

# 
# Fix ROM dev wrong sets.
#
setprop persist.adb.notify 0
setprop persist.service.adb.enable 1
setprop dalvik.vm.execution-mode int:jit
setprop pm.sleep_mode 1

#
# Selinux permissive
#
echo "0" > /sys/fs/selinux/enforce;
setenforce 0;

#
# ROOT activation if supersu used
#
if [ -e /system/app/SuperSU.apk ] && [ -e /system/xbin/daemonsu ]; then
	if [ "$(pgrep -f "/system/xbin/daemonsu" | wc -l)" -eq "0" ]; then
		/system/xbin/daemonsu --auto-daemon &
	fi;
fi;

# Remove Stweaks if it exists
if [ -f /system/app/STweaks.apk ] || [ -f /data/app/STweaks.apk ] ; then
	$BB rm -f /system/app/STweaks.apk > /dev/null 2>&1;
	$BB rm -f /data/app/STweaks.apk > /dev/null 2>&1;
	$BB rm -f /system/app/STweaks_Googy-Max.apk > /dev/null 2>&1;
	$BB rm -f /data/app/com.gokhanmoral.stweaks* > /dev/null 2>&1;
	$BB rm -f /data/data/com.gokhanmoral.stweaks*/* > /dev/null 2>&1;
fi;

/sbin/busybox mount -t rootfs -o remount,ro rootfs
/sbin/busybox mount -o remount,ro /system /system
/sbin/busybox mount -o remount,rw /data

sleep 60

$BB sh /res/synapse/actions/gpucontrol;
