#!/system/bin/sh
# BatGuard 守护 v0.2
# 充电控制（自动探测可用方法）+ 电池健康统计 + 实时功率 + 温控档位

MODDIR=${0%/*}; MODDIR=${MODDIR%/bin}
CFG="$MODDIR/config/config.conf"; DATA="$MODDIR/data"; WEB="$MODDIR/webroot"
LOG="$DATA/daemon.log"; DETECT="$DATA/detect.json"
mkdir -p "$DATA" "$WEB"

log() {
  echo "$(date '+%F %T') $*" >> "$LOG"
  n=$(wc -l < "$LOG" 2>/dev/null || echo 0)
  [ "$n" -gt 1500 ] && tail -800 "$LOG" > "$LOG.t" && mv "$LOG.t" "$LOG"
}
cfg() { v=$(sed -n "s/^$1=//p" "$CFG" 2>/dev/null | head -1 | tr -d '\r'); echo "${v:-$2}"; }

BAT=/sys/class/power_supply/battery
[ -d "$BAT" ] || BAT=/sys/class/power_supply/bms
USB=/sys/class/power_supply/usb
QB=/sys/class/qcom-battery
TM=/sys/class/thermal/thermal_message
rd() { cat "$1" 2>/dev/null | head -1 | tr -d '\r\n '; }

# ---------- 读数 ----------
cap()  { c=$(rd $BAT/capacity); [ -z "$c" ] && c=$(rd $BAT/capacity_raw); echo "${c:-0}"; }
st()   { rd $BAT/status; }
tmp()  { t=$(rd $BAT/temp); [ -z "$t" ] && t=$(rd $BAT/battery_temp)
         [ -z "$t" ] && { echo 0; return; }
         awk -v t="$t" 'BEGIN{ printf (t>200? "%.1f" : "%.1f"), (t>200? t/10 : t) }'; }
chg_tmp() {
         t=""
         for z in /sys/class/thermal/thermal_zone*; do
           [ "$(rd $z/type)" = "charger_therm" ] && { t=$(rd $z/temp); break; }
         done
         [ -z "$t" ] && t=$(rd $TM/charger_temp)
         [ -z "$t" ] && t=$(rd $BAT/charger_temp)
         [ -z "$t" ] && { echo 0; return; }
         awk -v t="$t" 'BEGIN{ printf (t>1000? "%.1f" : "%.1f"), (t>1000? t/1000 : t) }'; }
# 功率：取输入侧 V×I
power_w() {
  uv=$(rd $USB/voltage_now); ui=$(rd $USB/current_now)
  [ -z "$ui" ] || [ "$ui" = "0" ] && { uv=$(rd $BAT/voltage_now); ui=$(rd $BAT/current_now); }
  awk -v v="${uv:-0}" -v i="${ui:-0}" 'BEGIN{
    if(i<0)i=-i; w=v*i/1e12; printf "%.1f", (w<0.05?0:w) }'
}
usb_a() { ui=$(rd $USB/current_now); awk -v i="${ui:-0}" 'BEGIN{ if(i<0)i=-i; printf "%.2f", i/1e6 }'; }
volt_v() { uv=$(rd $USB/voltage_now); [ -z "$uv" ] || [ "$uv" = "0" ] && uv=$(rd $BAT/voltage_now)
           awk -v v="${uv:-0}" 'BEGIN{ printf "%.2f", v/1e6 }'; }
c_full() { f=$(rd $BAT/charge_full); [ -z "$f" ] && f=$(rd $BAT/charge_full_design)
           awk -v f="${f:-0}" 'BEGIN{ printf "%d", f/1000 }'; }
c_design() { f=$(rd $BAT/charge_full_design); awk -v f="${f:-0}" 'BEGIN{ printf "%d", f/1000 }'; }
cycles() { c=$(rd $BAT/cycle_count); echo "${c:-0}"; }
health() { d=$(c_design); f=$(c_full)
           [ "$d" -gt 0 ] && awk -v a="$f" -v b="$d" 'BEGIN{ h=a*100/b; if(h>100)h=100; printf "%d", h }' || echo 0; }
thermal_lv() { v=$(rd $TM/sconfig); echo "${v:--1}"; }

# ---------- 停充方法表 ----------
# 每个方法一行：名称|节点|停充值|恢复值
methods() {
cat <<'M'
mca_suspend|/sys/devices/platform/soc/soc:mca_charge_interface/input_suspend|1|0
mca_charge_enable|/sys/devices/platform/soc/soc:mca_charge_interface/charge_enable|0|1
psy_input_suspend|/sys/class/power_supply/battery/input_suspend|1|0
psy_charging_enabled|/sys/class/power_supply/battery/charging_enabled|0|1
psy_batt_charging_enabled|/sys/class/power_supply/battery/battery_charging_enabled|0|1
psy_store_mode|/sys/class/power_supply/battery/store_mode|1|0
psy_charge_disable|/sys/class/power_supply/battery/charge_disable|1|0
psy_cc_limit|/sys/class/power_supply/battery/charge_control_limit|16|0
qcom_cc_toggle|/sys/class/qcom-battery/cc_toggle|1|0
usb_current_max|/sys/class/power_supply/usb/current_max|100000|0
M
}

write_ok() {  # $1=节点 $2=值 → 真写入成功与否（回读比对，容忍不可读）
  [ -w "$1" ] || return 1
  echo "$2" > "$1" 2>/dev/null || return 1
  now=$(rd "$1")
  [ -z "$now" ] && return 0
  [ "$now" = "$2" ] && return 0
  return 1
}

# 学习：检测哪个方法真能让 status 变化
detect_methods() {
  st0=$(st)
  case "$st0" in
    Charging) ;;
    *)  log "当前 $st0，非充电状态无法判定停充，跳过探测"
        echo "{\"time\":\"$(date '+%F %T')\",\"skipped\":\"$st0\",\"items\":[]}" > "$DETECT"
        return 0 ;;
  esac
  log "开始探测停充方法（当前 $st0）…"
  methods | while IFS='|' read -r name node off on; do
    [ -w "$node" ] || continue
    if write_ok "$node" "$off"; then
      sleep 5
      s1=$(st)
      write_ok "$node" "$on"
      sleep 2
      case "$s1" in
        *Discharg*|*"Not charging"*) r=ok ;;
        *) r=node_only ;;
      esac
    else
      r=denied
    fi
    echo "{\"name\":\"$name\",\"node\":\"$node\",\"result\":\"$r\"}"
  done > "$DATA/.detect.lines"
  { echo "{\"time\":\"$(date '+%F %T')\",\"initial_status\":\"$st0\",\"items\":["; paste -sd, "$DATA/.detect.lines"; echo "]}"; } > "$DETECT"
  okn=$(grep -c '"result":"ok"' "$DETECT" 2>/dev/null || echo 0)
  log "探测完成，可用方法 $okn 个"
  echo "$okn"
}

pick_method() {  # 只用探测确认可用(ok)的方法；没有就返回空
  [ -f "$DETECT" ] || return 0
  nm=$(grep -o '"name":"[^"]*","node":"[^"]*","result":"ok"' "$DETECT" 2>/dev/null | head -1 | sed 's/.*"name":"\([^"]*\)".*/\1/')
  [ -z "$nm" ] && return 0
  methods | grep "^$nm|" | head -1
}

# ---------- 控制 ----------
CTRL=$(pick_method)
CNAME=$(echo "$CTRL" | cut -d'|' -f1)
CNODE=$(echo "$CTRL" | cut -d'|' -f2)
COFF=$(echo "$CTRL" | cut -d'|' -f3)
CON=$(echo "$CTRL" | cut -d'|' -f4)
LIMIT=$(cfg limit 80); RESUME=$(cfg resume 75)
SOC_STATE=0   # 0=正常 1=已停充
[ -z "$CNAME" ] && { CNAME=none; log "未找到可用的停充方法（可能当前不在充电，或内核不支持软件停充）"; }
log "控制方法=$CNAME 节点=$CNODE 阈值=${LIMIT}/${RESUME}"

apply_thermal() {
  want=$(cfg thermal_level -1)
  cur=$(thermal_lv)
  [ "$want" = "$cur" ] && return
  if echo "$want" > "$TM/sconfig" 2>/dev/null; then
    log "温控档位 $cur → $want"
  fi
}

apply_control() {
  [ "$(cfg enabled 1)" = "1" ] || return
  [ -z "$CNODE" ] && return
  c=$(cap); s=$(st)
  case "$s" in
    Charging)
      if [ "$c" -ge "$LIMIT" ] && [ "$SOC_STATE" = "0" ]; then
        if write_ok "$CNODE" "$COFF"; then
          SOC_STATE=1; sleep 3
          log "停充 $c% via $CNAME → status=$(st)"
        fi
      fi
      ;;
    Discharging|"Not charging"|Unknown|"")
      if [ "$c" -le "$RESUME" ] && [ "$SOC_STATE" = "1" ]; then
        if write_ok "$CNODE" "$CON"; then
          SOC_STATE=0; log "恢复充电 $c% via $CNAME"
        fi
      fi
      ;;
  esac
}

# ---------- 采样 ----------
PREV=""; SESS_T0=0; SESS_CAP0=0; W_PEAK=0
TOTAL_MAH=0; SESS_N=0; W_SUM=0; W_N=0
[ -f "$DATA/stats.conf" ] && . "$DATA/stats.conf" 2>/dev/null

sample() {
  c=$(cap); s=$(st); t=$(tmp); w=$(power_w); a=$(usb_a); v=$(volt_v)
  cf=$(c_full); cd=$(c_design); cy=$(cycles); h=$(health); tl=$(thermal_lv); ct=$(chg_tmp)
  ts=$(date +%s)

  echo "{\"t\":$ts,\"cap\":$c,\"st\":\"$s\",\"temp\":$t,\"w\":$w,\"a\":$a,\"v\":$v,\"tl\":$tl}" >> "$DATA/samples.jsonl"

  awk -v w="$w" 'BEGIN{ if(w>0) exit 0; exit 1 }' && { W_SUM=$(awk -v a="$W_SUM" -v b="$w" 'BEGIN{printf "%.2f",a+b}'); W_N=$((W_N+1)); }
  awk -v w="$w" -v p="$W_PEAK" 'BEGIN{ exit !(w>p) }' && W_PEAK=$w

  if [ "$s" = "Charging" ] && [ "$PREV" != "Charging" ]; then SESS_T0=$ts; SESS_CAP0=$c; fi
  if [ "$PREV" = "Charging" ] && [ "$s" != "Charging" ] && [ "$SESS_T0" -gt 0 ]; then
    dur=$((ts - SESS_T0)); dc=$((c - SESS_CAP0))
    [ "$dc" -lt 0 ] && dc=0
    mah=$((dc * cd / 100)); TOTAL_MAH=$((TOTAL_MAH + mah)); SESS_N=$((SESS_N + 1))
    echo "{\"t\":$ts,\"from\":$SESS_CAP0,\"to\":$c,\"min\":$((dur/60)),\"mah\":$mah,\"peak_w\":$W_PEAK}" >> "$DATA/sessions.jsonl"
    log "会话 ${SESS_CAP0}%→${c}% ${mah}mAh 峰值${W_PEAK}W"
    SESS_T0=0; W_PEAK=0
  fi
  PREV="$s"

  cat > "$DATA/stats.conf" <<EOF
TOTAL_MAH=$TOTAL_MAH
SESS_N=$SESS_N
W_SUM=$W_SUM
W_N=$W_N
W_PEAK=$W_PEAK
EOF

  avg_w=$(awk -v s="$W_SUM" -v n="$W_N" 'BEGIN{ printf "%.1f", (n>0? s/n : 0) }')
  dres=$( [ -f "$DETECT" ] && cat "$DETECT" || echo '{"items":[]}' )
  cat > "$WEB/data.json" <<EOF
{"ts":$ts,"time":"$(date '+%H:%M:%S')","cap":$c,"status":"$s","temp":$t,"charger_temp":$ct,
 "w":$w,"a":$a,"v":$v,"peak_w":$W_PEAK,"avg_w":$avg_w,
 "cf":$cf,"cfd":$cd,"health":$h,"cycles":$cy,
 "limit":$LIMIT,"resume":$RESUME,"enabled":$(cfg enabled 1),
 "method":"$CNAME","method_node":"$CNODE","thermal":$tl,
 "total_mah":$TOTAL_MAH,"sessions":$SESS_N,
 "detect":$dres}
EOF

  tail -3000 "$DATA/samples.jsonl" > "$DATA/.s" && mv "$DATA/.s" "$DATA/samples.jsonl"
  tail -720 "$DATA/samples.jsonl" > "$WEB/samples.jsonl"
  tail -50 "$DATA/sessions.jsonl" > "$WEB/sessions.jsonl" 2>/dev/null
}

update_desc() {
  h=$(health); cy=$(cycles); t=$(tmp); w=$(power_w); c=$(cap)
  d="⚡${w}W · ${c}% · 健康${h}% · ${cy}循环 · ${t}°C · 上限$(cfg limit 80)%"
  sed -i "s|^description=.*|description=$d|" "$MODDIR/module.prop" 2>/dev/null
}

# ---------- 启动 ----------
[ -f "$DETECT" ] || detect_methods >/dev/null
apply_thermal
log "守护启动 pid=$$ 方法=$CNAME"
LASTD=0
while true; do
  apply_thermal
  apply_control
  s=$(st)
  [ "$s" = "Charging" ] && iv=$(cfg sample_charging 15) || iv=$(cfg sample_idle 60)
  sample
  now=$(date +%s); di=$(cfg desc_interval 300)
  [ $((now - LASTD)) -ge "$di" ] && { update_desc; LASTD=$now; }
  sleep "$iv"
done
