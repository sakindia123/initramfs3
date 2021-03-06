#!/sbin/busybox sh

BB="/sbin/busybox";

# first mod the partitions then boot
$BB sh /sbin/ext/system_tune_on_init.sh;

# start ADB early to see some logs :)
start adbd;

PIDOFINIT=`pgrep -f "/sbin/ext/post-init.sh"`;
for i in $PIDOFINIT; do
	echo "-600" > /proc/$i/oom_score_adj;
done;

if [ ! -d /data/.siyah ]; then
	$BB mkdir -p /data/.siyah;
fi;

ccxmlsum=`md5sum /res/customconfig/customconfig.xml | awk '{print $1}'`
if [ "a$ccxmlsum" != "a`cat /data/.siyah/.ccxmlsum`" ]; then
	rm -f /data/.siyah/*.profile;
	echo "$ccxmlsum" > /data/.siyah/.ccxmlsum;
fi;

[ ! -f /data/.siyah/default.profile ] && cp -a /res/customconfig/default.profile /data/.siyah/default.profile;
[ ! -f /data/.siyah/battery.profile ] && cp -a /res/customconfig/battery.profile /data/.siyah/battery.profile;
[ ! -f /data/.siyah/performance.profile ] && cp -a /res/customconfig/performance.profile /data/.siyah/performance.profile;
[ ! -f /data/.siyah/extreme_performance.profile ] && cp -a /res/customconfig/extreme_performance.profile /data/.siyah/extreme_performance.profile;
[ ! -f /data/.siyah/extreme_battery.profile ] && cp -a /res/customconfig/extreme_battery.profile /data/.siyah/extreme_battery.profile;

$BB chmod 0777 /data/.siyah/ -R;

. /res/customconfig/customconfig-helper;
read_defaults;
read_config;

#mdnie sharpness tweak
if [ "$mdniemod" == "on" ]; then
	. /sbin/ext/mdnie-sharpness-tweak.sh
fi;

# dual core hotplug
echo "on" > /sys/devices/virtual/misc/second_core/hotplug_on;
echo "off" > /sys/devices/virtual/misc/second_core/second_core_on;

(
	PROFILE=`cat /data/.siyah/.active.profile`;
	. /data/.siyah/$PROFILE.profile;

	if [ $init_d == on ]; then
		/sbin/busybox sh /sbin/ext/run-init-scripts.sh;
	fi;
)&

# cpu undervolting
echo "$cpu_undervolting" > /sys/devices/system/cpu/cpu0/cpufreq/vdd_levels;

# disable debugging on some modules
if [ "$logger" == "off" ]; then
	echo "0" > /sys/module/ump/parameters/ump_debug_level;
	echo "0" > /sys/module/mali/parameters/mali_debug_level;
	echo "0" > /sys/module/kernel/parameters/initcall_debug;
	echo "0" > /sys/module/lowmemorykiller/parameters/debug_level;
	echo "0" > /sys/module/earlysuspend/parameters/debug_mask;
	echo "0" > /sys/module/alarm/parameters/debug_mask;
	echo "0" > /sys/module/alarm_dev/parameters/debug_mask;
	echo "0" > /sys/module/binder/parameters/debug_mask;
	echo "0" > /sys/module/xt_qtaguid/parameters/debug_mask;
fi;

# disable cpuidle log
echo "0" > /sys/module/cpuidle_exynos4/parameters/log_en;

# for ntfs automounting
mkdir /mnt/ntfs;
chmod 777 /mnt/ntfs/ -R;
mount -o mode=0777,gid=1000 -t tmpfs tmpfs /mnt/ntfs

$BB sh /sbin/ext/properties.sh;

(
	$BB sh /sbin/ext/install.sh;
)&

# EFS Backup 
(
	$BB sh /sbin/ext/efs-backup.sh;
)&

# enable kmem interface for everyone by GM
echo "0" > /proc/sys/kernel/kptr_restrict;

(
	# Stop uci.sh from running all the PUSH Buttons in stweaks on boot.
	$BB mount -o remount,rw rootfs;
	$BB chown root:system /res/customconfig/actions/ -R;
	$BB chmod 6755 /res/customconfig/actions/*;
	$BB chmod 6755 /res/customconfig/actions/push-actions/*;
	$BB mv /res/customconfig/actions/push-actions/* /res/no-push-on-boot/;

	# set root access script.
	$BB chmod 6755 /sbin/ext/cortexbrain-tune.sh;

	# apply STweaks settings
	echo "booting" > /data/.siyah/booting;
	echo "1" > /sys/devices/platform/samsung-pd.2/mdnie/mdnie/mdnie/user_mode;
	pkill -f "com.gokhanmoral.stweaks.app";
	$BB sh /res/uci.sh restore;

	# restore all the PUSH Button Actions back to there location
	$BB mount -o remount,rw rootfs;
	$BB mv /res/no-push-on-boot/* /res/customconfig/actions/push-actions/;
	pkill -f "com.gokhanmoral.stweaks.app";
	$BB rm -f /data/.siyah/booting;
	# ==============================================================
	# STWEAKS FIXING
	# ==============================================================

	# JB Sound Bug fix, 3 push VOL DOWN, 4 push VOL UP. and sound is fixed.
	MIUI_JB=0;
	JELLY=0;
	[ "`/sbin/busybox grep -i cMIUI /system/build.prop`" ] && MIUI_JB=1;
	[ -f /system/lib/ssl/engines/libkeystore.so ] && JELLY=1;
	if [ "$JELLY" == "1" ] || [ "$MIUI_JB" == "1" ]; then
		input keyevent 25
		input keyevent 25
		input keyevent 25
		input keyevent 24
		input keyevent 24
		input keyevent 24
		input keyevent 24
	fi;

	# change USB mode MTP or Mass Storage
	/res/customconfig/actions/usb-mode ${usb_mode};
)&

(
	while [ ! `cat /proc/loadavg | cut -c1-4` \< "3.50" ]; do
		echo "Waiting For CPU to cool down";
		sleep 30;
	done;

	PIDOFACORE=`pgrep -f "android.process.acore"`;
	for i in $PIDOFACORE; do
		echo "-600" > /proc/${i}/oom_score_adj;
		renice -15 -p $i;
		log -p i -t boot "*** do not kill -> android.process.acore ***";
	done;

	# run partitions tune after full boot
	/sbin/ext/partitions-tune.sh

	echo "Done Booting" > /data/dm-boot-check;
	date >> /data/dm-boot-check;
)&

