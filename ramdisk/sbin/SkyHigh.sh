#!/system/bin/sh

BB=/sbin/busybox;

mount -o remount,rw /
mount -o remount,rw /system /system

#
# Set SELinux permissive by default
#
#
setenforce 0
setprop ro.boot.selinux 0
setprop selinux.reload_policy 0

# Fix ROM dev wrong sets.
setprop persist.adb.notify 0
setprop persist.service.adb.enable 1
setprop pm.sleep_mode 1

# some nice thing for dev
if [ ! -e /cpufreq ]; then
	$BB ln -s /sys/devices/system/cpu/cpu0/cpufreq /cpufreq;
	$BB ln -s /sys/devices/system/cpu/cpufreq/ /cpugov;
	$BB ln -s /sys/devices/system/cpu/cpufreq/all_cpus/ /all_cpus;
fi;

# cleaning
$BB rm -rf /cache/lost+found/* 2> /dev/null;
$BB rm -rf /data/lost+found/* 2> /dev/null;
$BB rm -rf /data/tombstones/* 2> /dev/null;

CRITICAL_PERM_FIX()
{
	# critical Permissions fix
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
	$BB chmod 0755 /sbin/busybox;
}
CRITICAL_PERM_FIX;

# oom and mem perm fix
$BB chmod 666 /sys/module/lowmemorykiller/parameters/cost;
$BB chmod 666 /sys/module/lowmemorykiller/parameters/adj;
$BB chmod 666 /sys/module/lowmemorykiller/parameters/minfree

# make sure we own the device nodes
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

# make sure our max gpu clock is set via sysfs
echo 480 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq_gpu
echo 100 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq_gpu

# set min max boot freq to default.
echo "1900000" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq;
echo "1900000" > /sys/devices/system/cpu/cpu1/cpufreq/scaling_max_freq;
echo "1900000" > /sys/devices/system/cpu/cpu2/cpufreq/scaling_max_freq;
echo "1900000" > /sys/devices/system/cpu/cpu3/cpufreq/scaling_max_freq;
echo "250000" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq;
echo "250000" > /sys/devices/system/cpu/cpu1/cpufreq/scaling_min_freq;
echo "250000" > /sys/devices/system/cpu/cpu2/cpufreq/scaling_min_freq;
echo "250000" > /sys/devices/system/cpu/cpu3/cpufreq/scaling_min_freq;

# tune uksm
echo "1000" > /sys/kernel/mm/uksm/sleep_millisecs
echo "90" > /sys/kernel/mm/uksm/max_cpu_percentage

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
# Synapse start
#
$BB mount -t rootfs -o remount,rw rootfs
$BB chmod -R 755 /res/synapse
$BB chmod -R 755 /res/synapse/SkyHigh/*
/sbin/uci
# Synapse end
#

#
# Fast Random Generator (frandom) support on boot
#
chmod 444 /dev/erandom
chmod 444 /dev/frandom

#
# allow untrusted apps to read from debugfs (mitigate SELinux denials)
#
/system/xbin/supolicy --live \
	"allow untrusted_app debugfs file { open read getattr }" \
	"allow untrusted_app sysfs_lowmemorykiller file { open read getattr }" \
	"allow untrusted_app sysfs_devices_system_iosched file { open read getattr }" \
	"allow untrusted_app persist_file dir { open read getattr }" \
	"allow debuggerd gpu_device chr_file { open read getattr }" \
	"allow netd netd capability fsetid" \
	"allow netd { hostapd dnsmasq } process fork" \
	"allow { system_app shell } dalvikcache_data_file file write" \
	"allow { zygote mediaserver bootanim appdomain }  theme_data_file dir { search r_file_perms r_dir_perms }" \
	"allow { zygote mediaserver bootanim appdomain }  theme_data_file file { r_file_perms r_dir_perms }" \
	"allow system_server { rootfs resourcecache_data_file } dir { open read write getattr add_name setattr create remove_name rmdir unlink link }" \
	"allow system_server resourcecache_data_file file { open read write getattr add_name setattr create remove_name unlink link }" \
	"allow system_server dex2oat_exec file rx_file_perms" \
	"allow mediaserver mediaserver_tmpfs file execute" \
	"allow drmserver theme_data_file file r_file_perms" \
	"allow zygote system_file file write" \
	"allow atfwd property_socket sock_file write" \
	"allow untrusted_app sysfs_display file { open read write getattr add_name setattr remove_name }" \
	"allow debuggerd app_data_file dir search"


mkdir -p /mnt/ntfs
chmod 777 /mnt/ntfs
mount -o mode=0777,gid=1000 -t tmpfs tmpfs /mnt/ntfs

#
# kernel custom test
#
if [ -e /data/.SkyHigh_test.log ]; then
rm /data/.SkyHigh_test.log
fi

echo  Kernel script is working !!! >> /data/.SkyHigh_test.log
echo "excecuted on $(date +"%d-%m-%Y %r" )" >> /data/.SkyHigh_test.log

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

$BB run-parts /system/etc/init.d

$BB mount -t rootfs -o remount,ro rootfs
$BB mount -o remount,ro /system /system
$BB mount -o remount,rw /data

#
# Run Cortexbrain script
#
sleep 20
$BB sh /res/synapse/actions/cortex_start;


#
# Run GPU Governor Control script
#
sleep 15
$BB sh /res/synapse/actions/gpucontrol;
