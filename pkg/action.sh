#!/system/bin/sh
MODDIR=${0%/*}
D="$MODDIR/data"
W="$MODDIR/webroot"
if [ -f "$W/data.json" ]; then
  echo "===== BatGuard 状态 ====="
  sed 's/[{}"]//g; s/,/\n/g' "$W/data.json" | sed 's/^/  /'
else
  echo "还没有数据，守护可能未启动"
fi
echo
echo "=== 充电控制节点 ==="
for n in /sys/class/power_supply/battery/charge_control_end_threshold \
         /sys/class/power_supply/battery/input_suspend \
         /sys/class/power_supply/battery/charging_enabled; do
  [ -e "$n" ] && echo "  $n = $(cat $n 2>/dev/null) $( [ -w "$n" ] && echo '(可写)')"
done
echo
grep -E '^(enabled|limit|resume|mode)=' "$MODDIR/config/config.conf"
