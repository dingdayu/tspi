# 烧录（手动）

> 构建工具与编码代理绝不烧录硬件。不存在自动烧录目标。以下步骤由人工显式执行。以此保护板子、主机和任何连接的存储。

> 英文原版：[`../FLASHING.md`](../FLASHING.md)

## 烧录前检查清单

1. 校验工件完整性：
   ```bash
   cd dist
   sha256sum -c SHA256SUMS
   ```
2. 确认工件与清单一致：`dist/MANIFEST.txt`。
3. 确认连接的是正确的 Rockchip 设备（不是主机磁盘）：
   ```bash
   lsusb | grep -i rockchip
   ```
4. 确认供电与 USB 接线，包括 `docs/zh/HARDWARE.md` 所述 Y 型线 VBUS 隔离。
5. 备份板子上需要的数据。烧录对目标存储是破坏性的。

## 工件

由 `make image` 产出并收集到 `dist/`（仅包含厂商 SDK 实际产出的工件；`make image-manifest` 会记录找到的项）：

| 工件 | 用途 |
|----------|---------|
| `MiniLoaderAll.bin` | Rockchip loader |
| `uboot.img` | 厂商 U-Boot |
| `boot.img` | 内核 + DTB |
| `rootfs.img` | Debian 设备 rootfs |
| `parameter.txt` | 分区表 |
| `update.img` | 合并镜像（如产出） |
| `*.dtb` | 设备树（参考） |

## 模式

### Loader 模式

板子可启动但未完全运行时，按厂商流程进入 Loader 模式，然后烧录 loader 和镜像。对照你安装的工具确认确切子命令：

```bash
rkdeveloptool ld                       # 列出设备（工具相关）
rkdeveloptool db MiniLoaderAll.bin     # 下载 loader 到 RAM
rkdeveloptool wl 0x0 MiniLoaderAll.bin
rkdeveloptool wl 0x4000 uboot.img
rkdeveloptool rd                       # 复位
```

### MaskRom 模式

板子无法启动时使用。按厂商文档进入 MaskRom，确认 `lsusb | grep -i rockchip`，然后用 loader/升级工具恢复。

### 单一 update 镜像

若产出了 `update.img`，厂商升级工具可一步烧录。使用前确认工具版本和参数。

## 烧录之后

1. 板子重新上电。
2. 等待启动，然后在网络中找到它（站点 Wi-Fi 或恢复热点）。
3. `ssh kvm@taishankvm.local`。
4. 运行冒烟测试：
   ```bash
   sudo bash scripts/verify/target-smoke.sh
   ```
5. 查看 `docs/zh/VALIDATION.md` 获取完整验收清单。

## 安全须知

- 绝不写主机的原始块设备。
- 绝不对未明确识别的设备执行 Rockchip 烧录。
- 工具名与参数（`rkdeveloptool` 与 `upgrade_tool`）因版本而异；以你安装的工具帮助输出为准。
