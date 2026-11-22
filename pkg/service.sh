#!/system/bin/sh
# BatGuard 开机启动
MODDIR=${0%/*}
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 3; done
sleep 15
[ -f "$MODDIR/module_off" ] && exit 0
pgrep -f "batmod.*daemon.sh|BatGuard/bin/daemon.sh" >/dev/null 2>&1 && exit 0
nohup /system/bin/sh "$MODDIR/bin/daemon.sh" >/dev/null 2>&1 &
