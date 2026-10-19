# 校验

校验分三层：宿主机/静态门禁、上机冒烟测试、功能验收清单。

> 英文原版：[`../VALIDATION.md`](../VALIDATION.md)

## 宿主机 / 静态门禁

在开发机上运行：

```bash
make verify
```

`scripts/verify/static.sh` 检查：

- 所有必需项目文件存在；
- 所有脚本通过 `bash -n`；
- shellcheck 无告警（若已安装）；
- `Makefile` 引用的每个脚本都存在；
- `config/local.env` 与 `config/build.env` 未被 git 跟踪；
- 没有被跟踪文件包含字面 Wi-Fi 或恢复热点 PSK。

`make verify` 提供 `--quick` 变体，跳过 shellcheck 和机密扫描，用于快速检查。

其他宿主机门禁由构建目标自身运行：

- `make kernel` 以 `scripts/kernel/verify.sh` 收尾，对照**生效的** `.config` 检查 `config/kernel-required.config` 中的每个符号，并确认构建的 DTB 将 `&usbdrd_dwc3` 设为 `dr_mode = "peripheral"`。
- `make rootfs-verify` 检查解包后的 rootfs：SSH、NetworkManager、Wi-Fi 配置、原生 One-KVM、ADB 已屏蔽、`libcomposite`，以及无 Docker/containerd/snapd/cloud-init。

## 上机冒烟测试

把 `scripts/verify/target-smoke.sh` 复制到已启动的板子上并运行：

```bash
sudo bash target-smoke.sh
```

它执行只读检查，输出分类结论，区分：

- **内核 / UDC 故障**：`/sys/class/udc` 无 UDC、configfs 未挂载；
- **ADB / gadget 所有权冲突**：存在遗留 `g_*` 模块或活跃 `adbd`；
- **视频采集故障**：无 UVC 设备或无 `/dev/video*`；
- **Wi-Fi 故障**：`wlan0` 缺失或 NetworkManager 未运行；
- **One-KVM 服务故障**：单元未启用/未运行。

## 功能验收清单

来自 AGENTS.md 第 18.3 节的可测试标准，每项对应能证明它的命令。

| # | 标准 | 证明 |
|---|-----------|-------|
| 1 | 无键盘/显示器冷启动 | 断电重启，观察 Wi-Fi 关联 |
| 2 | 加入站点 Wi-Fi 或进入恢复热点 | `nmcli device status` |
| 3 | SSH 可达 | `ssh kvm@taishankvm.local` |
| 4 | `wlan0` 稳定 | `ip -brief addr show wlan0` |
| 5 | UDC 出现 | `ls /sys/class/udc` |
| 6 | UVC 采集卡出流 | `v4l2-ctl --list-devices`、`v4l2-ctl -d /dev/video0 --list-formats-ext` |
| 7 | One-KVM Web UI 可达 | 浏览器打开 `http://<host>:8080` |
| 8 | 被控机识别键鼠 gadget | 在被控机上 `lsusb` |
| 9 | BIOS/UEFI 中键盘可用 | 在 POST 阶段操作 |
| 10 | 相对/绝对鼠标可用 | 在 Web UI 中移动指针 |
| 11 | 虚拟媒体挂载/卸载 | 在 Web UI 中挂载再弹出 ISO |
| 12 | 重启回到健康状态 | `reboot`，重复检查 2-5 |
| 13 | ADB 不占用 UDC | `systemctl is-active adbd` 返回 inactive |

### 预期工作点

视频采集目标为 MJPEG 1920x1080 30 FPS。1080p60 不是 V1 要求。

## 故障解读

- 内核/UDC 和视频故障指向内核 `.config`/DTB；重跑 `make kernel-verify`。
- gadget 所有权冲突指向厂商 ADB 初始化；复查 `scripts/rootfs/customize.sh` 中的屏蔽逻辑。
- Wi-Fi 故障指向由 `config/local.env` 生成的配置；核对 SSID 及 keyfile 权限是否为 `0600`。
- One-KVM 服务故障：`systemctl status one-kvm` 和 `journalctl -u one-kvm -n 100`。
