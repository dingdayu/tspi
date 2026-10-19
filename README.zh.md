# 泰山派 RK3566 One-KVM 设备

基于厂商 Linux 6.1 SDK `tspi_1m_linux_kernel6.1_sdk_20260807`，面向 **LCKFB 泰山派 / TaishanPi RK3566**（1M 版）的可复现 IP-KVM 整机镜像构建项目。

> [English](README.md) | 简体中文

## 特性

- 🖥️ 厂商 Linux 6.1 + U-Boot BSP，Type-C DWC3 强制 **USB peripheral** 模式
- ⌨️ **One-KVM (Rust)** 原生运行：HID 键鼠、相对/绝对鼠标、虚拟媒体（目标机不装 Docker/containerd）
- 📹 Type-A USB Host 接通用 UVC HDMI 采集卡（1080p30 MJPEG 起步）
- 📶 板载 AP6212 Wi-Fi 组网，支持断网自动恢复热点（Recovery AP）
- 🔐 OpenSSH 开机自启、独立于 ADB 的首要维护通道，UART 兜底
- 🛡️ 厂商 ADB USB Gadget 默认禁用
- 🐳 Docker（仅构建机）一键构建，`make` 驱动的完整流水线

目标是一台 **KVM 设备**，而不是通用服务器。`AGENTS.md` 是权威的项目契约（含 §24 代理引导/实施说明），本 README 是快速上手路径。

## 当前状态

厂商 SDK **尚未就位**（State A）。仓库的脚手架、脚本、构建器、配置与文档已全部就绪；SDK 就位后相关步骤自动激活。详见 [`docs/STATUS.md`](docs/STATUS.md)。

## 快速开始

```bash
# 1) 校验宿主机环境并检查配置
make doctor

# 2) 构建 Ubuntu 22.04 构建沙箱（仅开发机上使用 Docker/Podman）
make builder
make shell                 # 可选：进入构建器交互 shell

# 3) 放置 SDK（见 sdk/README.md），然后：
make sdk-check             # 检测状态（A..E）并检查厂商目录树
make sdk-extract           # 幂等解压
make sdk-sync              # 幂等本地 .repo sync

# 4) 构建设备
make baseline              # 最小未修改厂商构建（验证工具链）
make patch                 # DWC3 -> peripheral 模式（幂等）
make kernel                # 配置 + 编译 + 校验生效的 .config/DTB
make rootfs                # 精简 Debian + SSH + NetworkManager + One-KVM
make image                 # 打包厂商镜像
make image-manifest        # dist/MANIFEST.txt + dist/SHA256SUMS

# 5) 校验（非破坏性）
make verify
```

`make all` 运行完整安全流水线；SDK 缺失时会停止并给出指引。

## 配置

| 文件 | 是否入库 | 用途 |
|------|---------|------|
| `config/versions.env` | 是 | 固定的 SDK / One-KVM / 构建器版本 |
| `config/build.env.example` | 是 | 非敏感构建选项模板 |
| `config/build.env` | **否**（已 gitignore） | 本地非敏感覆盖 |
| `config/local.env.example` | 是 | 机密模板（空） |
| `config/local.env` | **否**（已 gitignore） | 真实 Wi-Fi / SSH / 恢复热点机密 |
| `config/packages-target.txt` | 是 | 明确的目标机软件包基线 |
| `config/kernel-required.config` | 是 | 必需的生效内核符号 |

**切勿提交 `config/local.env`。** Wi-Fi 凭据在构建时从 `config/local.env` 注入，密码不会写入日志或被跟踪的文件。预设的站点 SSID 为 `DIY-K3`，见 [`docs/NETWORK.md`](docs/NETWORK.md)。

## 仓库结构

```text
builder/          Ubuntu 22.04 构建沙箱（Dockerfile、entrypoint）
config/           版本、构建选项、机密模板、清单
patches/kernel/   可复现的内核/设备树补丁
rootfs-overlay/   合并到目标 rootfs 的文件
scripts/          host | sdk | kernel | rootfs | image | verify | lib
sdk/vendor/       下载的 SDK 存放处（gitignored）
sdk/work/         解压/同步后的 SDK 目录树（gitignored）
docs/             架构、硬件、构建、网络、恢复等文档
dist/             最终烧录产物（gitignored）
```

## 文档

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — 构建机/目标机边界与拓扑
- [`docs/BUILD.md`](docs/BUILD.md) — 完整可复现构建流程
- [`docs/HARDWARE.md`](docs/HARDWARE.md) — Y 型线、VBUS 安全、USB 角色、UVC
- [`docs/NETWORK.md`](docs/NETWORK.md) — Wi-Fi 站点模式、恢复热点、mDNS、SSH
- [`docs/RECOVERY.md`](docs/RECOVERY.md) — UART、ADB 调试、MaskRom、网络恢复
- [`docs/FLASHING.md`](docs/FLASHING.md) — 手动烧录流程
- [`docs/VALIDATION.md`](docs/VALIDATION.md) — 静态与上机测试
- [`docs/STATUS.md`](docs/STATUS.md) — 当前实施状态

## 安全须知

- 工具链不会执行硬件烧录，也不会写原始块设备 —— 最终烧录步骤是手动且明确的。
- 厂商 ADB 永远不会与 One-KVM 争抢 USB Device Controller。
- 构建容器是一次性沙箱，可能需要 `--privileged`。
