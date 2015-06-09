#!/sbin/busybox sh

# Credits:
# Zacharias.maladroit
# Voku1987
# Collin_ph@xda
# Dorimanx@xda
# Gokhanmoral@xda
# Johnbeetee
# halaszk@xda
# UpInTheAir@xda : adapted to suit my SkyHigh Samsung Galaxy Tab-S Exynos5420 kernels

# TAKE NOTE THAT LINES PRECEDED BY A "#" IS COMMENTED OUT.
# This script must be activated after init start =< 25sec or parameters from /sys/* will not be loaded.

# read setting from profile to boot value
cortexbrain_background_process=`cat /res/synapse/SkyHigh/cortexbrain_background_process`;
SYNAPSE_PWM_VALUE=`cat /res/synapse/SkyHigh/cortexbrain_dvfs_pwm`;
cortexbrain_power_efficient=`cat /res/synapse/SkyHigh/cortexbrain_power_efficient`;
cortexbrain_kernel=`cat /res/synapse/SkyHigh/cortexbrain_kernel`;
cortexbrain_memory=`cat /res/synapse/SkyHigh/cortexbrain_memory`;
cortexbrain_system=`cat /res/synapse/SkyHigh/cortexbrain_system`;
cortexbrain_battery=`cat /res/synapse/SkyHigh/cortexbrain_battery`;
cortexbrain_tcp_ram=`cat /res/synapse/SkyHigh/cortexbrain_tcp_ram`;
cortexbrain_network=`cat /res/synapse/SkyHigh/cortexbrain_network`;
cortexbrain_android_logger=`cat /res/synapse/SkyHigh/cortexbrain_android_logger`;
cortexbrain_kernel_logger=`cat /res/synapse/SkyHigh/cortexbrain_kernel_logger`;

# ==============================================================
# GLOBAL VARIABLES || without "local" also a variable in a function is global
# ==============================================================

FILE_NAME=$0;
PIDOFCORTEX=$$;
BB="/sbin/busybox";
PROP="/system/bin/setprop";
sqlite="/sbin/sqlite3";
DB="/data/data/com.android.providers.settings/databases";
DB_SYNAPSE="/data/data/com.af.synapse/databases";

if [ -e /system/bin/dumpsys ]; then
	DUMPSYS=1;
else
	DUMPSYS=0;
fi;

READ_CONFIG()
{
cortexbrain_background_process=`cat /res/synapse/SkyHigh/cortexbrain_background_process`;
SYNAPSE_PWM_VALUE=`cat /res/synapse/SkyHigh/cortexbrain_dvfs_pwm`;
cortexbrain_power_efficient=`cat /res/synapse/SkyHigh/cortexbrain_power_efficient`;
cortexbrain_kernel=`cat /res/synapse/SkyHigh/cortexbrain_kernel`;
cortexbrain_memory=`cat /res/synapse/SkyHigh/cortexbrain_memory`;
cortexbrain_system=`cat /res/synapse/SkyHigh/cortexbrain_system`;
cortexbrain_battery=`cat /res/synapse/SkyHigh/cortexbrain_battery`;
cortexbrain_tcp_ram=`cat /res/synapse/SkyHigh/cortexbrain_tcp_ram`;
cortexbrain_network=`cat /res/synapse/SkyHigh/cortexbrain_network`;
cortexbrain_android_logger=`cat /res/synapse/SkyHigh/cortexbrain_android_logger`;
cortexbrain_kernel_logger=`cat /res/synapse/SkyHigh/cortexbrain_kernel_logger`;
log -p i -t $FILE_NAME "*** CONFIG ***: READED";
}

# Please don't kill "cortexbrain"
DONT_KILL_CORTEX()
{
	PIDOFCORTEX=`pgrep -f "/sbin/cortexbrain-tune.sh"`;
	for i in $PIDOFCORTEX; do
		echo "-950" > /proc/${i}/oom_score_adj;
	done;

	log -p i -t $FILE_NAME "*** DONT_KILL_CORTEX ***";
}

# ==============================================================
# KERNEL-TWEAKS
# ==============================================================
KERNEL_TWEAKS()
{
	local state="$1";

	if [ "$cortexbrain_kernel_tweaks" == "1" ]; then
		if [ "${state}" == "awake" ]; then
			echo "0" > /proc/sys/vm/oom_kill_allocating_task; # default: 0
			echo "0" > /proc/sys/vm/panic_on_oom; # default: 0
			echo "120" > /proc/sys/kernel/panic; # default: 5
			if [ "$cortexbrain_memory" == "1" ]; then
				echo "32 64" > /proc/sys/vm/lowmem_reserve_ratio; # default: 128 128
			fi;
		elif [ "${state}" == "sleep" ]; then
			echo "0" > /proc/sys/vm/oom_kill_allocating_task;
			echo "1" > /proc/sys/vm/panic_on_oom;
			echo "0" > /proc/sys/kernel/panic;
			if [ "$cortexbrain_memory" == "1" ]; then
				echo "32 32" > /proc/sys/vm/lowmem_reserve_ratio;
			fi;
		else
			echo "0" > /proc/sys/vm/oom_kill_allocating_task;
			echo "0" > /proc/sys/vm/panic_on_oom;
			echo "120" > /proc/sys/kernel/panic;
			echo "32 64" > /proc/sys/vm/lowmem_reserve_ratio;
		fi;
	
		log -p i -t $FILE_NAME "*** KERNEL_TWEAKS ***: ${state} ***: enabled";
		return 0;
	else
		return 1;
	fi;
}
KERNEL_TWEAKS;

# ==============================================================
# MEMORY-TWEAKS
# ==============================================================
MEMORY_TWEAKS()
{
	if [ "$cortexbrain_memory" == "1" ]; then
		echo "4" > /proc/sys/vm/min_free_order_shift; # default: 4
		echo "1" > /proc/sys/vm/overcommit_memory; # default: 1
		echo "50" > /proc/sys/vm/overcommit_ratio; # default: 50
		echo "3" > /proc/sys/vm/page-cluster; # default: 3
		echo "4096" > /proc/sys/vm/min_free_kbytes; # default: 2839

		log -p i -t $FILE_NAME "*** MEMORY_TWEAKS ***: enabled";

		return 1;
	else
		return 0;
	fi;
}
MEMORY_TWEAKS;

# ==============================================================
# SYSTEM-TWEAKS
# ==============================================================
SYSTEM_TWEAKS()
{
	if [ "$cortexbrain_system" == "1" ]; then
	# enable Hardware Rendering
	$PROP video.accelerate.hw 1;
	$PROP debug.performance.tuning 1;
	$PROP debug.sf.hw 1;
	$PROP persist.sys.use_dithering 1;
	$PROP persist.sys.ui.hw true; # ->reported as problem maker in some ROMs.

	# render UI with GPU
	$PROP hwui.render_dirty_regions false;
	$PROP profiler.force_disable_err_rpt 1;
	$PROP profiler.force_disable_ulog 1;

	# more Tweaks
	$PROP persist.adb.notify 0;
	$PROP pm.sleep_mode 1;
        $PROP wifi.supplicant_scan_interval 180;

		log -p i -t $FILE_NAME "*** SYSTEM_TWEAKS ***: enabled";

		return 0;
	else
		return 1;
	fi;
}
SYSTEM_TWEAKS;

# ==============================================================
# BATTERY-TWEAKS
# ==============================================================
BATTERY_TWEAKS()
{
	if [ "$cortexbrain_battery" == "1" ]; then

		# USB power support
		local POWER_LEVEL=`ls /sys/bus/usb/devices/*/power/level`;
		for i in $POWER_LEVEL; do
			chmod 777 $i;
			echo "auto" > $i; # default: auto
		done;

		local POWER_AUTOSUSPEND=`ls /sys/bus/usb/devices/*/power/autosuspend`;
		for i in $POWER_AUTOSUSPEND; do
			chmod 777 $i;
			echo "1" > $i; # default: 0
		done;

		# BUS power support
		buslist="spi i2c";
		for bus in $buslist; do
			local POWER_CONTROL=`ls /sys/bus/$bus/devices/*/power/control`;
			for i in $POWER_CONTROL; do
				chmod 777 $i;
				echo "auto" > $i; # default: auto
			done;
		done;

		log -p i -t $FILE_NAME "*** BATTERY_TWEAKS ***: enabled";

		return 0;
	else
		return 1;
	fi;
}
if [ "$cortexbrain_background_process" == 0 ]; then
	BATTERY_TWEAKS;
fi;

# ==============================================================
# TCP-TWEAKS
# ==============================================================
TCP_TWEAKS()
{

	if [ "$cortexbrain_tcp_ram" == "1" ]; then
		echo "4194304" > /proc/sys/net/core/wmem_max; # default: 2097152
		echo "4194304" > /proc/sys/net/core/rmem_max; # default: 1048576
		echo "20480" > /proc/sys/net/core/optmem_max; # default: 10240
		echo "4096 87380 4194304" > /proc/sys/net/ipv4/tcp_wmem; # default: 524288 1048576 4525824
		echo "4096 87380 4194304" > /proc/sys/net/ipv4/tcp_rmem; # default: 524288 1048576 4525824
	fi;

		log -p i -t $FILE_NAME "*** TCP_RAM_TWEAKS ***: enabled";
}
TCP_TWEAKS;

# ==============================================================
# SCREEN-FUNCTIONS
# ==============================================================
WORKQUEUE_CONTROL()
{
	local state="$1";

	if [ "$state" == "awake" ]; then
		if [ "$cortexbrain_power_efficient" == "1" ]; then
			echo "Y" > /sys/module/workqueue/parameters/power_efficient;
		else
			echo "N" > /sys/module/workqueue/parameters/power_efficient;
		fi;
	elif [ "$state" == "sleep" ]; then
		if [ "$cortexbrain_power_efficient" == "1" ] || [ "$cortexbrain_power_efficient" == "0" ]; then
			echo "Y" > /sys/module/workqueue/parameters/power_efficient;
		fi;
	fi;

	log -p i -t "$FILE_NAME" "*** WORKQUEUE_CONTROL ***: ${state}";
}

ANDROID_LOGGER()
{
	local state="$1";

	if [ "${state}" == "awake" ]; then
		if [ "$cortexbrain_android_logger" == "1" ]; then
			echo "1" > /sys/kernel/logger_mode/logger_mode;
		else
			echo "0" > /sys/kernel/logger_mode/logger_mode;
		fi;
	elif [ "${state}" == "sleep" ]; then
		if [ "$cortexbrain_android_logger" == "1" ] || [ "$cortexbrain_android_logger" == "0" ]; then
			echo "0" > /sys/kernel/logger_mode/logger_mode;
		fi;
	fi;

	log -p i -t $FILE_NAME "*** ANDROID_LOGGER ***: ${state}";
}

KERNEL_LOGGER()
{
	local state="$1";

	if [ "${state}" == "awake" ]; then
		if [ "$cortexbrain_kernel_logger" == "1" ]; then
			echo "1" > /sys/kernel/printk_mode/printk_mode;
		else
			echo "0" > /sys/kernel/printk_mode/printk_mode;
		fi;
	elif [ "${state}" == "sleep" ]; then
		if [ "$cortexbrain_kernel_logger" == "1" ] || [ "$cortexbrain_kernel_logger" == "0" ]; then
			echo "0" > /sys/kernel/printk_mode/printk_mode;
		fi;
	fi;

	log -p i -t $FILE_NAME "*** KERNEL_LOGGER ***: ${state}";
}

NMI()
{
	local state="$1";

	if [ "${state}" == "awake" ]; then
		echo "0" > /proc/sys/kernel/nmi_watchdog;
	elif [ "${state}" == "sleep" ]; then
		echo "1" > /proc/sys/kernel/nmi_watchdog;
	fi;

	log -p i -t "$FILE_NAME" "*** NMI ***: ${state}";
}

NET()
{
	local state="$1";

	if [ "$cortexbrain_network" == "1" ]; then
		if [ "${state}" == "awake" ]; then
			echo "5" > /proc/sys/net/ipv4/tcp_keepalive_probes; # default: 9
			echo "1800" > /proc/sys/net/ipv4/tcp_keepalive_time; # default: 7200
			echo "30" > /proc/sys/net/ipv4/tcp_keepalive_intvl; # default: 75
			echo "10" > /proc/sys/net/ipv4/tcp_retries2; # default: 15
		elif [ "${state}" == "sleep" ]; then
			echo "2" > /proc/sys/net/ipv4/tcp_keepalive_probes;
			echo "300" > /proc/sys/net/ipv4/tcp_keepalive_time;
			echo "5" > /proc/sys/net/ipv4/tcp_keepalive_intvl;
			echo "5" > /proc/sys/net/ipv4/tcp_retries2;
		fi;
	fi;

	log -p i -t $FILE_NAME "*** NET ***: ${state}";	
}

DVFS_PWR_MODE()
{
	PWRVALUE=`$sqlite $DB/settings.db "SELECT value FROM system WHERE name = 'powersaving_switch';"`;
	PWRCPU=`$sqlite $DB/settings.db "SELECT value FROM system WHERE name = 'psm_cpu_clock';"`;
	CPUCLK=`$sqlite $DB_SYNAPSE/actionValueStore "SELECT value FROM action_value WHERE key = 'generic /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq';"`;
	chmod 0777 /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq;

	if [ "$SYNAPSE_PWM_VALUE" != "0" ]; then
	if [ "$PWRVALUE" != "0" ] && [ "$PWRCPU" != "0" ]; then
	    	echo "1400000" > /sys/devices/system/cpu/cpufreq/iks-cpufreq/max_freq;
		log -p i -t $FILE_NAME "*** DVFS: POWER_SAVE ***";
	else
		echo $CPUCLK > /sys/devices/system/cpu/cpufreq/iks-cpufreq/max_freq;
		log -p i -t $FILE_NAME "*** DFVS: NORMAL ***";
	fi;
	fi;
}

# ==============================================================
# TWEAKS: if Screen-ON
# ==============================================================
AWAKE_MODE()
{
	READ_CONFIG;

	DVFS_PWR_MODE;

	DONT_KILL_CORTEX;
	
	WORKQUEUE_CONTROL "awake";

	ANDROID_LOGGER "awake";

	KERNEL_LOGGER "awake";

	KERNEL_TWEAKS "awake"; 

	NMI "awake";

	NET "awake";
	
	log -p i -t $FILE_NAME "*** AWAKE: Normal-Mode ***";

}

# ==============================================================
# TWEAKS: if Screen-OFF
# ==============================================================
SLEEP_MODE()
{
	READ_CONFIG;

	if [ "$DUMPSYS" == 1 ]; then
		# check the call state, not on call = 0, on call = 2
		CALL_STATE=`dumpsys telephony.registry | awk '/mCallState/ {print $1}'`;
		if [ "$CALL_STATE" == "mCallState=0" ]; then
			CALL_STATE=0;
		else
			CALL_STATE=2;
		fi;
	else
		CALL_STATE=0;
	fi;

	if [ "$CALL_STATE" == 0 ]; then

	WORKQUEUE_CONTROL "sleep";

	BATTERY_TWEAKS;

	NMI "sleep";
		
	NET "sleep";

	KERNEL_TWEAKS "sleep";

	ANDROID_LOGGER "sleep";

	KERNEL_LOGGER "sleep";

	log -p i -t $FILE_NAME "*** SLEEP mode ***";

	else

	log -p i -t $FILE_NAME "*** On Call! SLEEP aborted! ***";

	fi;

}

# ==============================================================
# Background process to check screen state
# ==============================================================

# Dynamic value do not change/delete
cortexbrain_background_process=1;
already_awake=0;
already_sleep=0;
if [ "$cortexbrain_background_process" == 1 ]; then
	(while [ 1 ]; do
sleep 5;
	SCREEN_OFF=$(cat /sys/class/backlight/panel/brightness); ## Adjusted for SkyHigh Galaxy Tab-S Exynos kernels

		# AWAKE State. all system ON.
		if [ "$SCREEN_OFF" != 0 ] && [ "$already_awake" == 0 ]; then
		AWAKE_MODE;
		already_awake=1;
		already_sleep=0;
		sleep 2;

		# SLEEP state. All system to power save.
                elif [ "$SCREEN_OFF" == 0 ] && [ "$already_sleep" == 0 ]; then
                SLEEP_MODE;
                already_awake=0;
                already_sleep=1;
		sleep 2;
		fi;

	done &);
	else
	if [ "$cortexbrain_background_process" == 0 ]; then
		echo "Cortex background disabled!"
	else
		echo "Cortex background process already running!";
	fi;
fi;
