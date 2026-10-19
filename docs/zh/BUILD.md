# 构建

本文档是从空仓库 + 已下载厂商 SDK 到 `dist/` 最终工件的精确可复现流程。它遵循顶层 `Makefile` 定义的 Make 目标和 `AGENTS.md` 的契约。

厂商 SDK 尚未放入仓库（State A）。所有不依赖 SDK 的内容已就绪；SDK 就位后相关步骤自动激活。凡依赖真实 SDK 的细节，本文档均予说明并描述检测机制，而非硬编码猜测。

> 英文原版：[`../BUILD.md`](../BUILD.md)

---

## 1. 宿主机前置条件

构建机需要：

| 要求 | 说明 |
|---|---|
| Linux 主机 | 推荐 x86_64 |
| Docker 或 Podman | 文档默认 Docker 命令 |
| Git | 用于仓库与厂商 repo 工具 |
| Make | 驱动流水线 |
| 磁盘空间 | SDK 和构建产物很大；预留数十 GB |
| 网络 | 拉取构建器基础镜像和软件包 |

构建器容器是一次性 Ubuntu 22.04 沙箱。厂商 rootfs、chroot、binfmt、mount 流程可能需要 `--privileged`。仓库 bind-mount 进沙箱。数 GB 的 SDK 绝不复制进镜像。

先校验宿主机：

```bash
make doctor
```

`make doctor` 检查 Docker、Git、SDK 存在性和配置，可安全重复运行。

---

## 2. 构建构建器并进入

```bash
make builder     # 构建 taishanpi-kvm-builder:22.04
make shell       # 可选：交互式特权 shell
```

`make builder` 运行 `scripts/host/build-builder.sh`。`make shell` 运行
`scripts/host/enter-builder.sh`，带你在沙箱中打开仓库（位于 `/work`）。

无需交互 shell、在沙箱内运行单条命令：

```bash
scripts/host/enter-builder.sh -- scripts/kernel/build.sh
```

Makefile 对所有容器内目标使用同一包装器，通常无需直接调用。

构建器设计要点：

- 默认 `python` 解析为 Python 3（`python-is-python3`）。
- Python 2.7 仅为旧厂商脚本安装，必须显式以 `python2.7` 调用。
- 非 root 的 `builder` 用户拥有免密 sudo，兼容既需用户又需 root 的厂商脚本。
- 镜像构建时设 `ENABLE_CCACHE=1` 可加 ccache，正确性从不依赖它。

---

## 3. 放置 SDK（State A 到 B）

下载多卷 SDK，将解压出的文件夹放在：

```text
sdk/vendor/tspi_1m_linux_kernel6.1_sdk_20260807/
```

文件夹应包含厂商 `extract_sdk.sh` 和 SDK 压缩包。打包细节因版本而异；脚本检测实际内容，不假设固定内部布局。

如厂商使用不同目录名，可在 `config/versions.env` 中通过 `SDK_VENDOR_DIRNAME`
和 `SDK_WORK_DIRNAME` 覆盖目录名。

SDK 收纳目录和工作树均被 gitignore，不要提交。

下载来源：立创泰山派官方
[资料下载中心](https://wiki.lckfb.com/zh-hans/tspi-rk3566/download-center.html)
（百度网盘）。其中托管 Linux/Android SDK 包、系统镜像，以及
[`FLASHING.md`](FLASHING.md) 引用的烧录工具（`RKDevTool`、`DriverAssistant`、
`SDDiskTool`）。本项目目标是 Linux 6.1 SDK
`tspi_1m_linux_kernel6.1_sdk_20260807`（或厂商提供的最新 6.1 版本）。

---

## 4. SDK 生命周期状态

项目支持五个状态，由 `scripts/lib/sdk.sh` 检测，由 `make sdk-check` 报告。

| 状态 | 含义 | 下一步 |
|---|---|---|
| A | SDK 缺失 | 将 SDK 放到 `sdk/vendor/` |
| B | 已下载多卷文件夹 | `make sdk-extract` |
| C | 已解压含 `.repo/`，工作树未同步 | `make sdk-sync` |
| D | 工作树完整同步（内核树存在） | `make baseline` |
| E | 基线构建产物存在 | 进入打补丁与构建 |

检测基于已知标志并报告实际结果；除这些标志外不硬编码 20260807 的内部布局。

### State A：SDK 缺失

仓库已完整搭建。`make all` 停止并给出指引：

```text
SDK absent, run: make sdk-extract && make sdk-sync after placing it.
```

### State B：已下载多卷文件夹

厂商解压器可用。运行幂等解压：

```bash
make sdk-check
make sdk-extract
```

### State C：已解压，工作树未同步

目录树含 `.repo/` 但工作树不完整。使用本地对象的厂商 repo 工具：

```bash
make sdk-sync
```

同步以本地优先。若 SDK 已打包为本地同步，不要替换为重网络的 repo sync。

### State D：工作树完整同步

内核树与设备配置已就绪。打补丁前先运行 SDK 内省，结果持久化到
`docs/STATUS.md` 和/或生成的 `build/sdk-inspection.txt`。

### State E：基线构建产物存在

未修改的厂商构建已产出工件。现在可以放心应用我们的补丁——工具链已被证明健康。

---

## 5. 检查 SDK

```bash
make sdk-check
```

`make sdk-check` 运行 `scripts/sdk/inspect.sh`，检测状态并检查厂商目录树。内省在 SDK 允许的范围内识别：

- 板级 lunch/config 目标；
- 选定的内核树；
- 选定的板级 DTS/DTSI；
- Debian/rootfs 构建入口；
- 镜像打包入口；
- 启动分区与镜像布局。

这些是**检测到的**值，不是固定事实。记录到 `docs/STATUS.md`。

---

## 6. 先做基线构建

```bash
make baseline
```

`make baseline` 运行 `scripts/sdk/baseline-build.sh`，执行最小的未修改厂商构建。日志保存在 `build/logs/`。

为什么先基线：它把"厂商 SDK 坏了"与"我们的补丁坏了"分开。基线失败说明问题在宿主机依赖、SDK 解压/同步或厂商源码。先修复再动内核。不要用 `|| true` 掩盖错误。

基线失败时按层定位：

- 宿主机依赖问题：修构建器镜像或宿主机；
- SDK 解压/同步问题：重跑 `make sdk-extract` 或 `make sdk-sync`；
- 厂商源码问题：作为外部阻塞精确记录；
- 仓库问题：直接修复。

---

## 7. 打补丁并构建内核

```bash
make kernel-detect     # 找到活动板级 DTS 和 DWC3 节点
make patch             # 应用 DWC3 peripheral 模式补丁（幂等）
make kernel-configure  # 应用必需内核配置片段
make kernel            # 配置 + 构建 + 校验生效 .config 和 DTB
```

`make kernel` 依赖 `patch` 和 `kernel-configure`，随后运行
`scripts/kernel/build.sh` 与 `scripts/kernel/verify.sh`。

补丁的作用：强制泰山派 Type-C DWC3 控制器为 `dr_mode = "peripheral"`。只补选定的泰山派板级路径，绝不波及所有 Rockchip 板。补丁存放在
`patches/kernel/`，幂等应用（先 `git apply --check`，已应用则跳过）。

配置的作用：启用 `config/kernel-required.config` 列出的 USB gadget、ConfigFS、UVC/V4L2 能力。设备关键的 gadget 组件优先内建（`=y`）。

校验针对**生效的生成 `.config`**，而非 defconfig 片段。
`scripts/kernel/verify.sh` 检查每个必需符号并报告偏差。可行时反编译构建的 DTB 确认 DWC3 生效模式。

若 20260807 内核中某必需符号改名或不存在，调查厂商 Kconfig 并记录等价物。不要强写不存在的符号。

随时复查：

```bash
make kernel-verify
```

---

## 8. 构建 rootfs

```bash
make rootfs
make rootfs-verify
```

`make rootfs` 运行 `scripts/rootfs/build.sh`。它从 SDK 支持的 Debian/rootfs 路径出发，然后定制：

1. 构建厂商支持的 Debian rootfs。
2. 检查其软件包集与板级附加内容。
3. 保留 AP6212 Wi-Fi、DWC3、UVC、存储/eMMC 和板级初始化所需的固件、模块、udev、systemd 组件。
4. 应用 `config/packages-target.txt`。
5. 只移除明确无用的通用软件包。
6. 应用 `rootfs-overlay/`。
7. 安装并固定 One-KVM ARM64 包。
8. 启用 NetworkManager。
9. 启用 SSH。
10. 禁用/屏蔽厂商 ADB gadget 启动。
11. 按需加载 `libcomposite`。
12. 配置主机名与 mDNS。
13. 针对 eMMC 配置日志轮转与 journald 限额。
14. 校验目标机无 Docker 或容器运行时。
15. 生成软件包清单。

在理解用途之前，不要激进清除厂商软件包。

### SSH 与账号策略

默认值，可在 `config/build.env` 配置：

```text
hostname: taishankvm
user: kvm
root SSH login: disabled
SSH service: enabled
public-key auth: enabled
password auth: development-only/configurable
```

若既未配置 SSH 公钥也未显式批准密码认证开发模式，生产构建应失败或大声警告。

### 来自 gitignored 配置的 Wi-Fi 预设

站点 Wi-Fi 凭据来自 gitignored 的 `config/local.env`。复制模板并填写：

```bash
cp config/local.env.example config/local.env
# 编辑 config/local.env：WIFI_SSID、WIFI_PSK、WIFI_COUNTRY、SSH 公钥、恢复热点
```

构建时注入这些值。PSK 绝不写入日志或被跟踪文件。`scripts/lib/common.sh`
提供 `sanitize_stream`，对捕获输出中疑似机密的 `KEY=VALUE` 做脱敏。

绝不提交 `config/local.env`，绝不打印 PSK。

### One-KVM

One-KVM 版本固定在 `config/versions.env`（`ONE_KVM_VERSION`）。安装路径优先官方 ARM64 `.deb`（缓存在 gitignored 的 `downloads/`），使用包自带 systemd 单元，仅加最小 drop-in。目标机没有 Docker。

---

## 9. 打包镜像并写清单

```bash
make image
make image-manifest
```

`make image` 运行 `scripts/image/build.sh`，走实际的厂商 SDK 打包流程。
`make image-manifest` 运行 `scripts/image/manifest.sh`，写出：

```text
dist/MANIFEST.txt
dist/SHA256SUMS
```

收集到 `dist/` 的工件（取决于真实厂商布局）可能包括：

```text
boot.img
rootfs.img
uboot.img
MiniLoaderAll.bin
parameter.txt
update.img
*.dtb
```

不要假设每一项都存在。检查 SDK 并收集它实际产出的内容。

`dist/MANIFEST.txt` 记录：

- 构建时间戳；
- SDK 名称与日期；
- 可用时的 SDK/repo manifest 修订；
- 内核版本与 commit；
- 生效板级配置；
- One-KVM 版本；
- 目标软件包清单哈希；
- 最终工件哈希。

`dist/SHA256SUMS` 存放校验和。两文件默认被 gitignore；仅在有价值的少量清单可入库。

---

## 10. 校验

```bash
make verify
```

`make verify` 运行 `scripts/verify/static.sh`，检查宿主机/静态门禁：

- 构建器镜像可构建；
- shell 脚本语法通过；
- 必需项目文件存在；
- 无被跟踪的机密；
- SDK 检查通过；
- 内核生效配置包含必需符号；
- 打补丁后的 DTS/DTB 解析为 peripheral 模式；
- 目标 rootfs 含 SSH 与 NetworkManager；
- SSH 已启用；
- One-KVM 已安装并启用；
- 厂商 ADB gadget 服务已禁用或屏蔽；
- 目标 rootfs 无 Docker/containerd（除非显式要求）；
- 最终工件哈希存在。

编译退出码为 0 不等于构建完成。完整矩阵（含上机冒烟测试）见
[`VALIDATION.md`](VALIDATION.md)。

上机测试：

```bash
make target-smoke
```

会打印操作说明。把 `scripts/verify/target-smoke.sh` 复制到已启动的泰山派上运行。它不做任何破坏性修改。

---

## 11. 完整流水线

```bash
make all
```

`make all` 先跑 `doctor`、`builder`、`sdk-check`。SDK 缺失（State A）则停止并给出指引；否则依次执行：

```text
baseline -> patch -> kernel -> rootfs -> image -> verify
```

所有目标在可行时均可安全重跑。

---

## 12. 故障排查

本节各项均标注 **verify against the real SDK**（对照真实 SDK 验证）。它们是厂商 Kernel 6.1 SDK 工作流的已知摩擦点，但 20260807 SDK 可能不同。依赖前请对照实际目录树确认。

### Python 2.7 必须显式调用

构建器将默认 `python` 设为 Python 3。部分旧厂商脚本仍调用 `python` 并期望 Python 2。若厂商脚本报 Python 3 语法或导入错误，不要改全局 `python`
软链。用 `python2.7` 显式调用，或给厂商脚本打补丁改为调用 `python2.7`。

症状：看似陈旧的厂商脚本报 `SyntaxError` 或 `ModuleNotFoundError`。
修复：以 `python2.7 script.py` 运行。

### 镜像源与包拉取问题

构建器将 Ubuntu archive 重写为镜像源（`config/versions.env` 的
`UBUNTU_MIRROR`）。若 `apt-get update` 或包拉取失败，可能是镜像源在你的网络不可达。换一个可达的 `UBUNTU_MIRROR` 并重建构建器镜像。

厂商 rootfs 构建可能从其自配镜像拉取 Debian 包。若失败，检查厂商 rootfs 配置和网络路径，而不是我们的脚本。

### mksquashfs extern 陷阱

部分厂商 rootfs 流程使用 `mksquashfs` 的外部压缩器或 `-comp` 选项，依赖主机上的特定工具。若 rootfs 构建在 squashfs 步骤报缺少压缩器或 "extern"
错误，检查厂商流程是否需要特定 `mksquashfs` 构建或外部二进制。修改前对照真实 SDK 确认确切要求。

### SDK 状态异常

若 `make sdk-check` 报告意外状态，检查其打印的标志：工作树路径、`.repo/`
存在性、`device/rockchip` 存在性、内核树存在性、`output/` 存在性。检测基于标志。若厂商使用不同目录名，在 `config/versions.env` 中覆盖
`SDK_VENDOR_DIRNAME` 或 `SDK_WORK_DIRNAME`。

### 基线失败

不要在坏的基线上打补丁。先修基线。`build/logs/` 下的日志会显示是哪一层失败。见第 6 节。

---

## 13. 烧录是手动的

构建工具不烧录硬件：不写原始块设备、不重分区主机、不调用破坏性的 Rockchip
烧录命令。最终烧录步骤手动且显式。

`make image` 与 `make image-manifest` 产出工件和校验和，到此为止。手动流程见
[`FLASHING.md`](FLASHING.md)；UART、ADB 调试与 MaskRom 恢复见
[`RECOVERY.md`](RECOVERY.md)。

---

## 14. 相关文档

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — 边界与流水线映射。
- [`HARDWARE.md`](HARDWARE.md) — 接线与 USB 角色。
- [`VALIDATION.md`](VALIDATION.md) — 完整测试矩阵。
- [`FLASHING.md`](FLASHING.md) — 手动烧录流程。
- [`STATUS.md`](../STATUS.md) — 当前实施状态（英文）。
