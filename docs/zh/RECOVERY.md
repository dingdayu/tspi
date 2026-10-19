# 恢复

按破坏性从小到大排列。UART 是最后手段的控制台。

> 英文原版：[`../RECOVERY.md`](../RECOVERY.md)

## 1. 网络恢复（恢复热点）

若站点网络消失导致 SSH 或 One-KVM Web UI 不可达，恢复热点（见 `docs/zh/NETWORK.md`）会在 `RECOVERY_AP_TIMEOUT` 秒后在 `192.168.66.1/24` 的本地热点上找回设备。连接 `RECOVERY_AP_SSID`，然后 SSH 到热点地址。

## 2. SSH 恢复

主机可达但 Web UI 不可用时：

```bash
ssh kvm@taishankvm.local
systemctl status one-kvm
journalctl -u one-kvm -n 100 --no-pager
```

## 3. UART 控制台

UART 保留为厂商串口控制台和最后恢复手段。在设备稳定且明确要求加固之前，不要移除厂商串口控制台。

以下情况使用 UART：

- Wi-Fi 无法启动且恢复热点未启动；
- SSH 不可达且登录账号损坏；
- 板子无法启动；
- USB gadget 卡死。

将 3.3V USB-UART 适配器接到板子的调试 UART（TX/RX/GND，交叉），然后
`picocom -b 1500000 /dev/ttyUSB0`（波特率以厂商文档为准），经串口控制台登录。

## 4. ADB 调试模式（仅显式开启）

ADB 默认禁用。它与 One-KVM 的 USB Device Controller 所有权互斥，因此启用前必须停掉 One-KVM 并释放 gadget。

启用：

```bash
sudo /usr/local/sbin/adb-debug-enable.sh
```

禁用并把 UDC 还给 One-KVM：

```bash
sudo /usr/local/sbin/adb-debug-disable.sh
```

辅助脚本强制的顺序：

1. 停止 `one-kvm.service`；
2. 解绑并清理当前 ConfigFS gadget；
3. 取消 ADB 屏蔽并启动；
4. 禁用时反向执行并重新屏蔽 ADB。

两个脚本都持有 `/run/one-kvm-adb.lock`，绝不并发运行。需要 `ENABLE_ADB_DEBUG=1`（在 `config/build.env` 或 `/etc/default/one-kvm-adb` 中）才允许启用该模式。

绝不让 ADB 和 One-KVM 同时作为同一 UDC 的所有者。

## 5. MaskRom 恢复

仅在板子完全无法启动时使用 MaskRom。在泰山派上按厂商文档进入 MaskRom 模式（上电/复位时按住 MaskRom/恢复键），然后连接 USB 到主机并确认出现 Rockchip USB 设备：

```bash
lsusb | grep -i rockchip
```

随后可用 loader/升级工具（如 `rkdeveloptool` 或 Rockchip `upgrade_tool`）重刷 loader 和镜像。使用前对照你安装的工具版本确认确切参数。见 `docs/zh/FLASHING.md`。

## 6. 判断故障类别

`scripts/verify/target-smoke.sh`（在目标机上用 `sudo` 运行）将故障归类为内核/UDC、ADB/gadget 所有权、视频采集、Wi-Fi 或 One-KVM 服务。恢复前先运行它，以便修复正确的层。
