# Debian 13 Server Init

Debian 13 (Trixie) 服务器初始化与安全加固脚本。

## 使用场景

通过 [reinstall](https://github.com/bin456789/reinstall) 重装为 Debian 13 后运行。

**重装前（可选）**：
```bash
# 查看系统配置
curl -Lso- bench.sh | bash
# 检测网络质量
# https://github.com/xykt/NetQuality
bash <(curl -Ls https://Check.Place) -N
# 重装系统
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O ${_##*/} $_
bash reinstall.sh debian
```

## 快速使用

```bash
sudo bash init-system.sh              # 交互式
sudo bash init-system.sh -h           # 无人值守帮助
```

## 主要功能

系统更新、SSH 加固（仅密钥+Tailscale 登录）、nftables 防火墙、eBPF 监控、无人值守更新。

## 详细文档

见 [docs/init-guide.md](docs/init-guide.md)
