#!/bin/bash

if [[ $1 == "" ]]

 then
 echo "Error: no arguments defined"
 echo "Please use i.e.: ./save_logs.sh agx_k68"
 echo "exit"
 exit -1

fi

echo "Saving logs for: $1";

dmesg > logs_$1_dmesg.txt
cat /proc/iomem > logs_$1_iomem.txt
cat /proc/interrupts > logs_$1_interrupts.txt
sort /proc/modules > logs_$1_modules.txt
sort <(lsmod) > logs_$1_lsmod.txt
dtc -I fs -O dts /sys/firmware/devicetree/base > logs_$1_dtb.dts
cp /sys/firmware/fdt logs_$1_dtb.dtb
cat /var/log/Xorg.0.log > logs_$1_xorg.txt
ls -lah /sys/bus/platform/devices/ > logs_$1_devices.txt
journalctl -b0 > logs_$1_journalctl.txt
zcat /proc/config.gz > logs_$1_kernel_configs.txt
tree /sys > logs_$1_tree_sys.txt
tree /etc > logs_$1_tree_etc.txt
env > logs_$1_env.txt

