# BatGuard · 电池守护

一个给已 root 的 Android 手机用的模块：**充电控制 + 实时功率 + 电池健康统计 + 温控档位**，一个模块全包。

面向 KernelSU / Magisk / APatch，纯 shell 实现，不需要编译、不联网、没有遥测。

> 灵感来自 [QSC-Battery](https://github.com/eikeitsu/QSC-Battery)（充电控制）与
> [CRecordEvolution](https://github.com/f1owkang/CRecordEvolution)（电池健康数据展示），
> 两者能力合并成一个更轻的模块，并补上实时充电功率与温控档位。

---

## 功能

### 1. 充电控制
- 到设定阈值停充（默认 80%），掉到回落阈值以下自动恢复（默认 75%）
- **自动探测本机可用的停充方法**：不同厂商/内核暴露的节点差异很大，模块启动后会逐个试写并检查 `status` 是否真的变化，只保留真正生效的那个，结果写进 `data/detect.json` 并在 WebUI 里显示
- 支持的方法（按顺序探测，全部来自实测过的真实路径）：

| 方法 | 节点 |
|---|---|
| `mca_suspend` | `/sys/devices/platform/soc/soc:mca_charge_interface/input_suspend` |
| `mca_charge_enable` | `…/mca_charge_interface/charge_enable` |
| `psy_input_suspend` | `/sys/class/power_supply/battery/input_suspend` |
| `psy_charging_enabled` | `/sys/class/power_supply/battery/charging_enabled` |
| `psy_store_mode` | `/sys/class/power_supply/battery/store_mode` |
| `psy_cc_limit` | `/sys/class/power_supply/battery/charge_control_limit` |
| `qcom_cc_toggle` | `/sys/class/qcom-battery/cc_toggle` |
| `usb_current_max` | `/sys/class/power_supply/usb/current_max` |

**诚实说明**：如果你的手机所有方法都是只读（部分 HyperOS 新机型如此，内核直接拒绝写入），模块会在 WebUI 里明确标注「不可用」，而不是假装在停充。

### 2. 实时充电功率
- 读输入侧 `voltage_now × current_now` 计算瓦数，充电时每 15 秒刷新
- 记录本次会话峰值功率、历史平均功率、功率曲线
- 充放电会话按次记录：起止电量、时长、充入 mAh、峰值功率

### 3. 电池健康
- 健康度 = `charge_full / charge_full_design`（实测容量与设计容量之比）
- 循环次数、电池温度、充电器温度
- **容量与健康度直接写进模块描述**，在管理器模块列表里一眼可见：
  `⚡7.2W · 100% · 健康99% · 37循环 · 37.6°C · 上限80%`

### 4. 温控档位
- 调整 `/sys/class/thermal/thermal_message/sconfig`：`-1` 跟随系统，`0` 最激进，数值越大越保守
- 注意：这是**整机温控档位**，不是单纯充电温度。调 0 会让 CPU 与充电一起放宽限制

---

## 安装

```sh
# KernelSU / Magisk 管理器里刷入 zip
BatGuard-v0.2.0.zip
```

或手动：

```sh
unzip BatGuard-v0.2.0.zip -d /data/adb/modules/BatGuard
chmod 755 /data/adb/modules/BatGuard/bin/daemon.sh /data/adb/modules/BatGuard/*.sh
nohup /system/bin/sh /data/adb/modules/BatGuard/bin/daemon.sh >/dev/null 2>&1 &
```

重启后由 `service.sh` 自动拉起。

## 配置

`/data/adb/modules/BatGuard/config/config.conf`（改完下一轮生效，不用重启）：

```ini
enabled=1            # 1 启用充电控制，0 只统计
limit=80             # 停充阈值 %
resume=75            # 回落阈值 %
mode=auto            # auto 自动探测
sample_charging=15   # 充电时采样间隔（秒）
sample_idle=60       # 未充电时采样间隔
desc_interval=300    # 模块描述刷新间隔
thermal_level=-1     # 温控档位 -1~10
```

## WebUI

管理器里点模块 → 打开 WebUI，三页：

- **总览**：电量环、实时功率、电流/电压/峰值/温度/健康/循环、控制方法与停充探测结果
- **历史**：电量、功率、温度三张曲线 + 充电会话列表
- **设置**：阈值、温控档位、开关、采样间隔

## 数据位置

```
/data/adb/modules/BatGuard/
├── config/config.conf     配置
├── data/samples.jsonl     原始采样（滚动保留 3000 条）
├── data/sessions.jsonl    充电会话
├── data/detect.json       停充方法探测结果
├── data/daemon.log        运行日志
└── webroot/               WebUI 与共享数据
```

## 卸载

管理器里卸载即可。`uninstall.sh` 会停掉守护并把充电恢复为开启状态，避免停在「已停止充电」。

## 已知限制

- **停充依赖厂商节点**：能不能停充取决于你的内核有没有开放写接口，模块只做探测与如实汇报
- **功率限制不可用**：多数 HyperOS 机型把 `current_max` / `ichg_limit` 设为内核拒写，模块不提供假的限流开关
- 只在 Android 17 / HyperOS 4 / arm64 上实测过

## License

MIT
