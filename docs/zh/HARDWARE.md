# 硬件

本文档描述泰山派 RK3566 One-KVM 设备的物理连接：板子、Y 型线、USB 角色、UVC 采集卡，以及防止向板子倒灌供电的 VBUS 安全规则。

`AGENTS.md` 第 1 节是拓扑的权威来源。本文档对其展开，并把所有依赖用户实际线缆的细节标记为待确认（TODO）。

> 英文原版：[`../HARDWARE.md`](../HARDWARE.md)

---

## 1. 板子

| 项目 | 值 |
|---|---|
| 板卡 | LCKFB 泰山派 / TaishanPi |
| SoC | Rockchip RK3566 |
| 规格 | 1M / 2G RAM + 16G eMMC |
| 存储 | eMMC，约 16 GB |
| 内存 | 约 2 GB |
| USB 设备口 | Type-C，Rockchip DWC3 |
| USB 主机口 | Type-A |
| 网络 | 板载 AP6212 Wi-Fi |
| 维护 | 经 Wi-Fi 的 SSH，UART 兜底 |

这块板子不是通用服务器。它是一台 KVM 设备：对被控计算机表现为键盘、鼠标和可移动磁盘，同时采集该计算机的 HDMI 输出。

---

## 2. USB 角色

两个 USB 口角色固定且相反，不可互换。

| 端口 | 角色 | 方向 | 承载 |
|---|---|---|---|
| Type-C | USB 设备 / 外设 | 泰山派 → 被控计算机 | HID 键盘、鼠标、虚拟媒体 |
| Type-A | USB 主机 | 被控计算机 → 泰山派 | UVC HDMI 采集流 |

Type-C 运行 Rockchip DWC3 控制器。设备树被打补丁，使该控制器解析为：

```dts
&usbdrd_dwc3 {
    dr_mode = "peripheral";
};
```

活动板级 DTS 路径由 `scripts/kernel/detect-board.sh` 从 SDK 检测。补丁由 `make patch` 应用，由 `make kernel` 校验。构建步骤见 [`BUILD.md`](BUILD.md)。

Type-A 是普通主机口。UVC 采集卡插在这里，对内核呈现为 V4L2 视频设备。

---

## 3. Y 型线拓扑

Type-C 口既要给板子供电，又要向被控计算机传输 USB 数据。Y 型线把这两个功能分开。

```text
                         +---- 5V 电源
                         |
泰山派 Type-C -- Y -------+---- USB 数据到被控计算机
                         |     被控计算机分支仅有 D+/D-/GND
                         |     该分支的 VBUS 必须隔离
                         |
泰山派 Type-A ------------ UVC HDMI 采集卡
                              ^
                              |
被控计算机 HDMI --------------+

泰山派 AP6212 Wi-Fi --------- 局域网 / 恢复热点
```

读图说明：

- Y 的一支接 5V 电源，为板子供电。
- 另一支接被控计算机，仅传输 USB 数据。
- 被控计算机的 HDMI 输出接 Type-A 上的采集卡。
- Wi-Fi 把板子接入局域网或恢复热点。

---

## 4. VBUS 隔离（安全关键）

Y 型线连接被控计算机的分支不得将 VBUS 倒灌进泰山派的供电通路。

为什么重要：如果被控计算机的 5V VBUS 在板子已由自身 5V 电源供电时到达板子的电源输入，两路电源会互相冲突。这可能损坏板子、被控计算机的 USB 口，或两者都损坏。还会干扰 DWC3 控制器的角色检测。

规则：

- 被控计算机分支仅承载 **D+、D- 和 GND**。
- 该分支的 VBUS 必须隔离：使用不连接 VBUS 的线缆、纯数据适配器或 VBUS 阻断元件。
- GND 必须在所有分支间共地。
- D+ 和 D- 必须与被控计算机保持连接。

不要指望被控计算机的口给板子供电。板子必须由自己的 5V 电源供电。

TODO（用你的线缆确认）：具体隔离方式取决于你购买或自制 Y 型线的方式。记录 VBUS 是物理上不存在、被二极管阻断，还是被纯数据适配器阻断。见第 8 节的清单。

---

## 5. 地线与数据线

| 线 | 要求 |
|---|---|
| GND | 电源、泰山派、被控计算机三方共地 |
| D+ | 泰山派 Type-C 与被控计算机之间连接 |
| D- | 泰山派 Type-C 与被控计算机之间连接 |
| VBUS（被控分支） | 隔离，不得进入泰山派供电通路 |

USB 信号需要共地。没有它，数据线没有参考电平，枚举会失败或不稳定。

---

## 6. UVC HDMI 采集卡

采集卡是通用 UVC 设备，MS2109 或 MS2130 类。插在 Type-A 上，把被控计算机的 HDMI 输出以 V4L2 视频设备的形式呈现给内核。

V1 推荐工作点：

- 采集卡支持时使用 MJPEG；
- 1920x1080；
- 30 FPS。

1080p60 不是 V1 的硬性要求，不要围绕它设计。

确切的 `/dev/videoN` 编号在重启或不同卡型之间不稳定。不要硬编码。可行时建立稳定的 udev 别名或按属性发现设备。

在目标机上运行的校验命令：

```bash
lsusb
ls -l /dev/video*
v4l2-ctl --list-devices
v4l2-ctl -d /dev/video0 --list-formats-ext
```

关于卡型的说明：

- MS2109 类卡常见且便宜，通常暴露 MJPEG 和 YUYV。用 `v4l2-ctl --list-formats-ext` 确认实际格式。
- MS2130 类卡较新，常支持更高帧率。把宣传规格当作待验证的声明，而非事实。
- 部分卡还暴露 USB 音频。为此启用了 `CONFIG_SND_USB_AUDIO`。

TODO（用你的卡确认）：记录确切芯片型号、`lsusb` 中的 USB VID:PID，以及卡实际报告的格式和帧率。

---

## 7. 不要臆测接线

不要假设任何未经实测或未从线缆文档确认的接线细节。对 VBUS 隔离的错误假设可能损坏硬件；对 D+/D- 的错误假设可能让你在看似软件 bug 的枚举故障上浪费数小时。

细节不明时，标记为未知，并在给被控计算机上电之前确认。构建工具检测不到你的线缆。只有你能确认。

---

## 8. 接线记录清单

为你的实际接线填写此表，并妥善保管。

| 项目 | 值 | 已确认？ |
|---|---|---|
| Y 型线型号 / 料号 | TODO | TODO |
| Y 型线来源（购买 / 自制） | TODO | TODO |
| 被控分支 VBUS 隔离方式 | TODO（无 VBUS / 二极管 / 纯数据适配器） | TODO |
| 电源规格（5V，电流） | TODO | TODO |
| 所有分支共地 | TODO | TODO |
| D+ 接到被控计算机 | TODO | TODO |
| D- 接到被控计算机 | TODO | TODO |
| 采集卡芯片型号 | TODO | TODO |
| 采集卡 USB VID:PID | TODO | TODO |
| 采集卡最大格式 / 帧率 | TODO | TODO |
| 被控计算机 USB 口类型 | TODO | TODO |

接线确认后，把上面的 TODO 替换为真实值并删除 TODO 标记。在此之前，每一行 TODO 都视为未验证。

---

## 9. 物理验收检查

对应 `AGENTS.md` 第 18.3 节的功能验收标准。在真实硬件上执行，不在构建流水线中。

1. 无键盘、无显示的情况下冷启动。
2. 加入配置的 Wi-Fi，或进入文档所述的恢复热点。
3. 网络可达 SSH。
4. `wlan0` 稳定。
5. UDC 出现在 `/sys/class/udc/`。
6. UVC 采集卡出现并可出流。
7. One-KVM Web UI 可访问。
8. 被控计算机识别键盘/鼠标 gadget。
9. 在被控计算机允许标准 USB HID 的前提下，BIOS/UEFI 中键盘可用。
10. 相对/绝对鼠标按配置工作。
11. 虚拟媒体可挂载和卸载。
12. 重启后回到同样的健康状态。
13. 正常模式下 ADB 不占用 UDC。

支撑这些检查的上机冒烟测试是 `scripts/verify/target-smoke.sh`，通过 `make target-smoke` 获取运行说明。完整测试矩阵见 [`VALIDATION.md`](VALIDATION.md)。

---

## 10. 相关文档

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — 系统边界与 USB 角色。
- [`BUILD.md`](BUILD.md) — 构建在硬件上运行的镜像。
- [`FLASHING.md`](FLASHING.md) — 手动烧录流程。
- [`RECOVERY.md`](RECOVERY.md) — UART、ADB 调试与 MaskRom 恢复。
