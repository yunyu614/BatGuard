#!/system/bin/sh
# 在 root shell 里跑一次，确认充电控制节点语义
echo "===== 1. mca 接口"
for f in charge_enable input_suspend; do
  p=/sys/devices/platform/soc/soc:mca_charge_interface/$f
  echo "--- $f"
  echo "   权限: $(ls -l $p 2>/dev/null | awk '{print $1,$3,$4}')"
  echo "   内容: [$(cat $p 2>/dev/null)]"
done
echo
echo "===== 2. 电池状态"
for n in capacity status temp current_now voltage_now charge_full charge_full_design cycle_count; do
  echo "   $n = $(cat /sys/class/power_supply/battery/$n 2>/dev/null)"
done
echo
echo "===== 3. 试探 input_suspend 语义（写1后看 status 是否变化）"
echo 1 > /sys/devices/platform/soc/soc:mca_charge_interface/input_suspend 2>&1 && echo "   写1成功"
sleep 3
echo "   status = $(cat /sys/class/power_supply/battery/status 2>/dev/null)"
echo "   capacity = $(cat /sys/class/power_supply/battery/capacity 2>/dev/null)"
echo 0 > /sys/devices/platform/soc/soc:mca_charge_interface/input_suspend 2>&1 && echo "   写0恢复"
sleep 3
echo "   status = $(cat /sys/class/power_supply/battery/status 2>/dev/null)"
echo
echo "===== 4. charge_control_limit 是否可写"
p=/sys/class/power_supply/battery/charge_control_limit
echo "   权限 $(ls -l $p 2>/dev/null | awk '{print $1}') 当前 $(cat $p 2>/dev/null) max $(cat /sys/class/power_supply/battery/charge_control_limit_max 2>/dev/null)"
