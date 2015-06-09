#!/sbin/sh
#

# Install kernel 
#



cd /tmp

dd if=newboot.img of=/dev/block/platform/dw_mmc.0/by-name/BOOT

# cleanup

