# 架构

本文档说明泰山派 RK3566 One-KVM 设备的整体构成：构建机上运行什么、板子上运行什么、厂商 BSP 到哪里结束、我们的代码从哪里开始，以及构建流水线如何映射到仓库中的 Make 目标与脚本。

`AGENTS.md` 是权威契约。若本文档与 `AGENTS.md` 冲突，以 `AGENTS.md` 为准。

> 英文原版：[`../ARCHITECTURE.md`](../ARCHITECTURE.md)

---

## 1. 两台机器，两种职责

本项目刻意区分"构建镜像的机器"与"运行镜像的机器"。

| | 构建机 | 目标机（泰山派） |
|---|---|---|
| 角色 | 编译内核、组装 rootfs、打包镜像 | 运行 KVM 设备 |
| 操作系统 | Ubuntu 22.04（Docker 内） | 精简 Debian ARM64 |
| 容器运行时 | Docker 或 Podman，必需 | **永远没有** |
| 内核 | 宿主机内核，无关紧要 | 厂商 Rockchip Linux 6.1 |
| 产物 | `dist/` 工件 | 烧录到 eMMC |

Docker 仅存在于开发机。它提供一次性 Ubuntu 22.04 沙箱，内含厂商 Kernel 6.1 构建依赖。数 GB 的 SDK 以 bind-mount 方式挂入沙箱，绝不复制进镜像。除非用户明确修改需求，目标 rootfs 不得包含 Docker、containerd 或任何容器运行时。

原因很简单：KVM 设备需要一个小巧、可预期、可恢复的系统。目标机上的容器运行时会增加攻击面、启动复杂度，并给 USB gadget 栈被错误进程占用的第二种可能。

---

## 2. 厂商 BSP 边界

技术栈底层是来自 SDK `tspi_1m_linux_kernel6.1_sdk_20260807` 的 Rockchip/LCKFB 厂商 BSP：

- 厂商 U-Boot；
- 厂商 Linux 6.1 内核树；
- 厂商设备树与板级支持；
- 厂商 Wi-Fi 固件与模块集成（AP6212）；
- 厂商启动镜像布局与 Rockchip 打包。

我们不用 Debian generic 或 mainline 内核替换厂商内核。厂商板级支持、DT 绑定和打包是 V1 的稳定基础。为"优雅"而现代化内核明确不在范围内。

我们对 BSP 的改动小且可复现：

1. 一个设备树补丁，强制 Type-C DWC3 控制器为 `dr_mode = "peripheral"`。
2. 一个内核配置片段，启用设备所需的 USB gadget、ConfigFS 与 UVC/V4L2 能力。

两者分别位于 `patches/kernel/` 和 `config/kernel-required.config`，均以幂等方式应用。活动板级 DTS 路径由 `scripts/kernel/detect-board.sh` **从 SDK 检测**，而不是从旧教程硬编码。

确切的 DTS/DTSI 文件名、板级 lunch/config 目标和内核树路径都依赖具体 SDK。脚本检测并报告实际结果。本文档描述机制，而非固定文件名。

---

## 3. Debian 用户态边界

内核之上是精简的 Debian ARM64 用户态。这里的"精简"指小而可控，不是手工拼凑。

起点是 SDK 支持的 Debian/rootfs 构建路径。该路径已携带我们本需自行重建的板级集成：固件、内核模块、udev 规则、启动脚本、用户/组和板级初始化。我们保留它，然后在其上做最小化。

除非先完整梳理 SDK 集成并保留、测试所有必需组件，否则不会跳到独立的 `debootstrap --variant=minbase` rootfs。整体替换厂商 rootfs 是最后手段，不是起点。

最小化通过两个明确、可评审的输入完成：

- `config/packages-target.txt` 列出设备所需软件包。
- `rootfs-overlay/` 存放合并进目标 rootfs 的文件（systemd 单元、SSH 策略、NetworkManager 配置、辅助脚本）。

明确排除在生产镜像之外的软件包：Docker、containerd、snapd、cloud-init、桌面环境、X11、Wayland、GUI 栈和大型编译工具链。构建依赖留在构建机上。

---

## 4. One-KVM 原生运行时

One-KVM 是 Rust 实现，以 ARM64 包原生安装。版本固定在 `config/versions.env`，包缓存在 gitignored 的 `downloads/` 目录。安装路径优先使用官方 ARM64 `.deb` 及其自带 systemd 单元，仅在必要时添加最小 drop-in。

运行时 One-KVM 拥有 USB Device Controller。它通过 Linux ConfigFS 管理 gadget，暴露键盘、相对鼠标、绝对鼠标（如支持）和虚拟媒体（USB 大容量存储）。可选 USB 以太网（NCM/ECM/RNDIS）仅在不复杂化 V1 时提供。

目标机上没有 Docker，因此 One-KVM 与内核之间没有容器边界。服务直接与 ConfigFS 和 UDC 通信。

---

## 5. USB 拓扑

板子有两个 USB 角色，不可混淆。

- **Type-C** 是 Rockchip DWC3 控制器。被强制为 `dr_mode = "peripheral"`，使板子对被控计算机表现为 USB 设备。这是承载 HID 和虚拟媒体的通路。
- **Type-A** 是 USB host 口。它承载 UVC HDMI 采集卡。

被控计算机将泰山派识别为键盘、鼠标和大容量存储设备。泰山派通过 Type-A 上的采集卡看到被控计算机的 HDMI 输出。

ADB 默认禁用，绝不与 One-KVM 争抢 UDC。如保留 ADB 调试，它是可选且互斥的：停 One-KVM、解绑其 gadget、启动 ADB；禁用时反向执行。一个 UDC 有两个所有者永远不是合法状态。

物理接线、VBUS 隔离和 Y 型线见 [`HARDWARE.md`](HARDWARE.md)。

---

## 6. 网络拓扑

主网络是板载 AP6212 Wi-Fi，由 NetworkManager 管理。

- 站点模式加入配置的网络并获取 DHCP。
- mDNS/Avahi 默认以 `taishankvm.local` 发布设备名。
- OpenSSH 开机自启，是首要维护通道，不依赖 ADB。
- 站点模式不可用时，可选恢复热点在可配置超时（默认 60 秒）后启动，地址 `192.168.66.1/24`。
- UART 是 Wi-Fi、SSH、启动或 gadget 故障时的最后手段控制台。

Wi-Fi 凭据来自 gitignored 的 `config/local.env`，构建时注入。绝不入库，也绝不写入日志。

---

## 7. 系统框图

```text
                        构建机（Ubuntu 22.04 + Docker）
   +------------------------------------------------------------------+
   |  builder/Dockerfile  ->  taishanpi-kvm-builder:22.04             |
   |  仓库 bind-mount 到 /work（SDK 绝不 COPY 进镜像）                 |
   |                                                                  |
   |  scripts/host   scripts/sdk   scripts/kernel                     |
   |  scripts/rootfs scripts/image scripts/verify                     |
   +---------------------------------+--------------------------------+
                                     |
                                     | 产出
                                     v
   +------------------------------------------------------------------+
   |  dist/  boot.img  rootfs.img  uboot.img  MiniLoaderAll.bin       |
   |         parameter.txt  update.img  *.dtb                         |
   |         MANIFEST.txt  SHA256SUMS                                 |
   +---------------------------------+--------------------------------+
                                     |
                                     | 手动烧录（从不自动）
                                     v
                        目标机（泰山派 RK3566）
   +------------------------------------------------------------------+
   |  厂商 U-Boot -> 厂商 Linux 6.1 -> 精简 Debian ARM64              |
   |                                                                  |
   |  One-KVM (Rust, 原生 systemd)     NetworkManager   OpenSSH       |
   |        |                                |              |         |
   |        | ConfigFS gadget                | wlan0        | sshd    |
   |        v                                v              v         |
   |   Type-C DWC3 (peripheral)        AP6212 Wi-Fi     局域网 / AP   |
   |        |                                                         |
   |        | USB HID + 大容量存储                                    |
   |        v                                                         |
   |   被控计算机  <---- HDMI ---->  Type-A host                      |
   |                                    UVC 采集卡                    |
   +------------------------------------------------------------------+
```

---

## 8. 数据与控制流

**控制路径（KVM 输入）。** 操作员通过网络打开 One-KVM Web UI。One-KVM 将输入事件转成 USB HID 报文，写入 ConfigFS gadget。peripheral 模式的 DWC3 控制器把这些报文以标准键鼠形式呈现给被控计算机。

**视频路径（采集）。** 被控计算机的 HDMI 输出进入 Type-A 上的 UVC 采集卡。厂商内核的 UVC/V4L2 栈将其暴露为 `/dev/videoN` 设备。One-KVM 读取视频流并供 Web UI 使用。

**虚拟媒体路径。** One-KVM 通过同一 ConfigFS gadget 将镜像暴露为 USB 大容量存储 LUN。被控计算机看到一个可移动磁盘。

**管理路径。** 经 Wi-Fi 的 SSH 是常规维护通道。网络或启动损坏时回退到 UART。

**构建路径。** 构建机通过 Make 目标驱动流水线。容器内目标由 `scripts/host/enter-builder.sh` 包装，隐式使用特权容器。流水线以 `dist/` 中的工件和清单结束。烧录是独立的、手动的、明确的步骤。

---

## 9. 流水线阶段与目标、脚本的对应

Makefile 是可发现的接口。宿主机侧目标直接运行；容器内目标经 `scripts/host/enter-builder.sh --` 运行。

| 阶段 | Make 目标 | 脚本 | 运行位置 | 用途 |
|---|---|---|---|---|
| 宿主机检查 | `make doctor` | `scripts/host/doctor.sh` | 宿主机 | 校验 docker、git、SDK 存在性、配置 |
| 构建器镜像 | `make builder` | `scripts/host/build-builder.sh` | 宿主机 | 构建 Ubuntu 22.04 沙箱 |
| 构建器 shell | `make shell` | `scripts/host/enter-builder.sh` | 宿主机 | 交互式特权 shell |
| SDK 检测 | `make sdk-check` | `scripts/sdk/inspect.sh` | 宿主机 | 检测状态 A..E 并检查目录树 |
| SDK 解压 | `make sdk-extract` | `scripts/sdk/extract.sh` | 构建器 | 幂等厂商解压 |
| SDK 同步 | `make sdk-sync` | `scripts/sdk/sync.sh` | 构建器 | 幂等本地 `.repo` 同步 |
| 基线构建 | `make baseline` | `scripts/sdk/baseline-build.sh` | 构建器 | 最小未修改厂商构建 |
| 板级检测 | `make kernel-detect` | `scripts/kernel/detect-board.sh` | 宿主机 | 找到活动 DTS 和 DWC3 节点 |
| 打补丁 | `make patch` | `scripts/kernel/patch.sh` | 构建器 | 应用 DWC3 peripheral 补丁 |
| 内核配置 | `make kernel-configure` | `scripts/kernel/configure.sh` | 构建器 | 应用必需配置片段 |
| 内核构建 | `make kernel` | `scripts/kernel/build.sh` + `verify.sh` | 构建器 | 构建并校验生效配置/DTB |
| 内核校验 | `make kernel-verify` | `scripts/kernel/verify.sh` | 构建器 | 复查 `.config` 和 DTB 模式 |
| Rootfs | `make rootfs` | `scripts/rootfs/build.sh` | 构建器 | 构建并定制 rootfs |
| Rootfs 校验 | `make rootfs-verify` | `scripts/rootfs/verify.sh` | 宿主机 | 检查 SSH、NetworkManager、One-KVM、无 Docker |
| 镜像 | `make image` | `scripts/image/build.sh` | 构建器 | 打包厂商镜像 |
| 清单 | `make image-manifest` | `scripts/image/manifest.sh` | 宿主机 | 写 `MANIFEST.txt` 和 `SHA256SUMS` |
| 静态校验 | `make verify` | `scripts/verify/static.sh` | 宿主机 | 运行全部宿主机/静态门禁 |
| 上机冒烟 | `make target-smoke` | `scripts/verify/target-smoke.sh` | 目标机 | 上机检查（复制到板子执行） |
| 完整流水线 | `make all` | Makefile | 宿主机 | doctor、builder、sdk-check，随后构建链 |

`make all` 在 SDK 缺失（State A）时停止并给出指引，不会假装构建。

---

## 10. 组件职责

| 组件 | 位置 | 职责 |
|---|---|---|
| 构建器镜像 | `builder/Dockerfile` | 含厂商构建依赖的 Ubuntu 22.04 沙箱；默认 Python 3 |
| 构建器入口 | `builder/entrypoint.sh` | 启动时准备沙箱环境 |
| 宿主机脚本 | `scripts/host/` | 检查、构建镜像、进入沙箱 |
| SDK 脚本 | `scripts/sdk/` | 检测、解压、同步、基线构建厂商 SDK |
| 内核脚本 | `scripts/kernel/` | 检测板级、补丁 DWC3、配置、构建、校验 |
| Rootfs 脚本 | `scripts/rootfs/` | 构建、定制、安装 One-KVM、校验 rootfs |
| 镜像脚本 | `scripts/image/` | 打包厂商镜像、收集工件、写清单 |
| 校验脚本 | `scripts/verify/` | 宿主机静态门禁与上机冒烟测试 |
| 共享库 | `scripts/lib/common.sh` | 严格模式、路径、日志、环境加载、脱敏 |
| SDK 状态库 | `scripts/lib/sdk.sh` | SDK 位置与状态检测（A..E） |
| 内核补丁 | `patches/kernel/` | 可复现、幂等的设备树补丁 |
| Rootfs overlay | `rootfs-overlay/` | 合并进目标 rootfs 的文件 |
| 目标机软件包 | `config/packages-target.txt` | 明确的软件包基线 |
| 必需内核配置 | `config/kernel-required.config` | 在生效 `.config` 中检查的符号 |
| 版本 | `config/versions.env` | 固定的 SDK、One-KVM、构建器版本 |
| 机密 | `config/local.env` | gitignored 的 Wi-Fi、SSH、恢复热点配置 |
| SDK 收纳 | `sdk/vendor/` | 下载的多卷 SDK（gitignored） |
| SDK 工作树 | `sdk/work/` | 解压并同步后的目录树（gitignored） |
| 交付物 | `dist/` | 最终工件、清单、校验和 |

---

## 11. 设计原则

以上选择遵循少量规则，重述自 `AGENTS.md` 第 22 节：

- 可复现性优先于机巧。
- 明确脚本优先于无记录的 shell 历史。
- 原生 systemd 集成优先于目标机容器。
- 厂商 BSP 稳定性优先于不必要的内核现代化。
- 最小且被理解的软件包集合优先于激进删除。
- SSH 与 UART 恢复优先于 ADB 依赖。
- 校验生效配置优先于源文件假设。
- 小而可评审的补丁优先于大规模直接修改。

任何偏离这些规则的情况必须记录具体技术原因。
