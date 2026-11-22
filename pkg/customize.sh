#!/system/bin/sh
# KernelSU/Magisk 安装时执行
SKIPUNZIP=0
ui_print "- BatGuard: 充电控制 + 电池统计"
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/bin/daemon.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
mkdir -p "$MODPATH/data" "$MODPATH/webroot"
# 升级时保留已有配置
if [ -f "/data/adb/modules/BatGuard/config/config.conf" ] && [ ! -d "$MODPATH/config" ]; then
  mkdir -p "$MODPATH/config"
  cp -f "/data/adb/modules/BatGuard/config/config.conf" "$MODPATH/config/config.conf"
fi
