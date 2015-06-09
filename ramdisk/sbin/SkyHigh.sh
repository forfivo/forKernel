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
sleep 30
$BB sh /res/synapse/actions/cortex_start;


#
# Run GPU Governor Control script
#
sleep 60
$BB sh /res/synapse/actions/gpucontrol;
