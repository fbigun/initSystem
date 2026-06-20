# Debian 13 (Trixie) 服务器初始化与加固

## 概述

本脚本用于将服务器重装为 Debian 13 (Trixie) 后的初始化与安全加固，提供交互式和无人值守两种运行模式。

## 核心配置与功能

1. **自动化与参数：** 支持通过位置参数实现无人值守安装（`username`、`password`、`timezone`、`use_mirror`、`gen_readme`）。添加了 `-h` / `--help` 帮助菜单。
2. **凭据管理：** 用户名和密码的输入/生成逻辑移至脚本最开头。支持留空自动生成安全随机字符串（去除易混淆字符如 `0,1,l,o,i`）。
3. **源与系统更新：** 采用现代 `deb822` 格式（`debian.sources`），先用 HTTP 安装依赖再无缝切换至 HTTPS。执行系统完整升级。
4. **软件安装：** 安装基础工具、`bpfcc-tools`，并将内核头文件改为 `linux-headers-amd64` 元包，避免因版本更新导致的安装失败。
5. **智能主机名：** 通过 API 获取国别码，结合默认网卡 MAC 后 6 位，自动生成主机名 `[国别码]-server-[MAC后6位]`。
6. **用户与 SSH：** 创建用户并配置 sudo 免密。SSH 加固为仅公钥认证，彻底禁止密码和 root 登录。预设了特定的公钥。
7. **Tailscale：** 通过官方 Debian Trixie 仓库安装。配置独立的 `sysctl.d` 文件开启 IPv4/IPv6 转发，以支持 Exit Node 和子网路由。
8. **nftables 防火墙：** 默认丢弃入站流量，拦截异常 TCP 标志。放行已建立连接、`tailscale0` 接口、80/443 端口及 ICMP。预留了 UDP 40000 (Peer Relay) 的注释规则。
9. **无人值守维护：** 配置 `unattended-upgrades` 自动清理无用依赖和内核。创建 Systemd 定时器，每周日 04:00 检查并在需要时（存在 `reboot-required`）自动重启。
10. **输出与 Readme：** 将最终指南暂存于变量中以防重复执行。内容包含：Tailscale `up` 指令、SSH ACL 配置、客户端 SSH 连接示例（直连使用 `ProxyCommand tailscale nc %h %p`，局域网网关跳转使用 `ProxyJump`），以及未来开启私有中继的进阶说明。


## 前置准备

### 1. 重装系统

使用 [reinstall](https://github.com/bin456789/reinstall) 将服务器重装为 Debian 13：

```bash
# 详见 reinstall 项目文档选择对应重装命令
```

### 2. 查看系统配置（可选）

```bash
wget -qO- bench.sh | bash
# 或
curl -Lso- bench.sh | bash
```

### 3. 检测网络质量（可选）

```bash
# 使用 NetQuality 测试网络
# https://github.com/xykt/NetQuality
```

## 快速开始

### 交互式运行

```bash
sudo bash init-system.sh
```

### 无人值守运行

```bash
# 指定用户名、密码、时区、镜像源、Readme 生成
sudo bash init-system.sh admin 'MyPass123!' Asia/Shanghai y Y

# 随机生成账号密码
sudo bash init-system.sh '' '' America/New_York n Y
```

## 功能清单

| 模块 | 说明 |
|------|------|
| 系统更新 | 升级至最新，可选清华镜像源加速 |
| 基础工具 | sudo、nftables、curl、wget、gnupg 等 |
| eBPF 监控 | bpfcc-tools + 内核头文件 |
| 智能主机名 | `国家码-server-MAC后6位` 格式 |
| 用户管理 | 创建用户、sudo 免密配置 |
| SSH 加固 | 仅密钥登录、禁止 root、禁止密码 |
| Tailscale | 官方 Debian Trixie 仓库安装 |
| nftables 防火墙 | 默认拒绝入站，仅放行 Tailscale 及 80/443 |
| 内核参数 | IP 转发、SYN Cookie、RP Filter 等 |
| 无人值守更新 | 自动安全更新 + 条件重启定时器 |

## 防火墙规则

- 公网 SSH 端口已彻底封死
- 仅可通过 Tailscale 网络 (`tailscale0`) 登录
- 对外暴露 HTTP (80) 与 HTTPS (443)

## 登录方式

服务器仅接受 SSH 密钥认证，必须通过 Tailscale 网络连接。配置示例：

```
Host my-debian
    HostName <tailscale-name-or-ip>
    User <your-username>
    IdentityFile ~/.ssh/id_ed25519
    ProxyCommand tailscale nc %h %p
```

## 可选：开启 Peer Relay 中继

```bash
sudo tailscale set --relay-server-port=40000
# 同时需在 nftables.conf 中放行 UDP 40000
```

## 文件说明

- `init-system.sh` — 主初始化脚本
- `docs/` — 详细文档目录

## 许可证

MIT License
