#!/system/bin/sh
# 卸载时恢复充电并停掉守护
MODDIR=${0%/*}
pkill -f "BatGuard/bin/daemon.sh" 2>/dev/null
for n in /sys/class/power_supply/battery/input_suspend \
         /sys/class/power_supply/battery/charging_enabled \
         /sys/class/power_supply/battery/battery_charging_enabled; do
  [ -w "$n" ] && echo 1 > "$n" 2>/dev/null
done
