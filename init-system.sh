#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ==================== 帮助菜单 ====================
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Debian 13 (Trixie) 现代化服务器初始化与加固脚本"
    echo "用法: $0 [用户名] [密码] [时区] [镜像源y/N] [生成Readme Y/n]"
    echo ""
    echo "参数说明:"
    echo "  [用户名]      自定义用户名，传空字符串 \"\" 则随机生成 6-8 位安全字符"
    echo "  [密码]        自定义密码，传空字符串 \"\" 则随机生成 10 位安全字符"
    echo "  [时区]        系统时区，默认 Asia/Shanghai"
    echo "  [镜像源y/N]   是否使用清华源，y 或 Y 表示使用，N 表示不使用"
    echo "  [生成Readme Y/n] 是否在用户目录生成指南，Y 表示生成，n 或 N 表示不生成"
    echo ""
    echo "示例:"
    echo "  1. 交互式运行:"
    echo "     sudo bash $0"
    echo ""
    echo "  2. 无人值守全参数运行:"
    echo "     sudo bash $0 admin 'MyPass123!' Asia/Shanghai y Y"
    echo ""
    echo "  3. 无人值守自动生成账号密码运行:"
    echo "     sudo bash $0 '' '' America/New_York n Y"
    exit 0
fi

# ==================== 0. 环境检查与基础交互设置 ====================
if [[ $(id -u) -ne 0 ]] ; then echo "Please run as root" ; exit 1 ; fi

if ! grep -qi "trixie" /etc/os-release; then
    echo "Warning: This script is optimized for Debian 13 (Trixie)."
fi

echo "================ Debian 13 (Trixie) 现代化服务器初始化与加固 ================"
echo "提示: 运行 'bash $0 -h' 查看无人值守参数说明"

# 支持位置参数，实现无人值守
username=${1:-}
password=${2:-}
timezone=${3:-}
use_mirror=${4:-}
gen_readme=${5:-}

# 若未提供参数，则进入交互提示
if [ -z "$username" ]; then
    read -p "请输入用户名 (留空则随机生成6-8位安全字符): " username
fi
if [ -z "$password" ]; then
    read -p "请输入密码 (留空则随机生成10位安全字符): " password
fi
if [ -z "$timezone" ]; then
    read -p "请输入系统时区 [Asia/Shanghai]: " timezone
fi
if [ -z "$use_mirror" ]; then
    read -p "是否配置国内镜像源(清华源)加速访问? [y/N]: " use_mirror
fi
if [ -z "$gen_readme" ]; then
    read -p "是否在用户目录下生成后续操作指南? [Y/n]: " gen_readme
fi

# 设置默认值
timezone=${timezone:-"Asia/Shanghai"}
use_mirror=${use_mirror:-N}
gen_readme=${gen_readme:-Y}

# 随机凭据生成逻辑
if [ -z "$username" ]; then
    # 去除 l, o, i 等易混淆字母；|| true 避免 pipefail + head 触发 SIGPIPE
    username=$(tr -dc 'abcdefghjkmnpqrstuvwxyz' < /dev/urandom | head -c$(( RANDOM % 3 + 6 ))) || true
fi

if [ -z "$password" ]; then
    # 去除 0, 1, l, o, i 等易混淆字符；|| true 避免 pipefail + head 触发 SIGPIPE
    password=$(tr -dc 'abcdefghjkmnpqrstuvwxyz23456789' < /dev/urandom | head -c 10) || true
fi

timedatectl set-timezone "$timezone"
echo -e "应用配置 -> 用户: \033[32m$username\033[0m | 时区: \033[32m$timezone\033[0m"
echo "=============================================================================="

# ==================== 1. 系统更新与源配置 ====================
export DEBIAN_FRONTEND=noninteractive

if [ -f /etc/apt/sources.list ]; then
    mv /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%F)
fi

if [[ "$use_mirror" =~ ^[Yy]$ ]]; then
    echo "选择使用国内镜像源 (HTTP)..."
    BASE_URI="http://mirrors.tuna.tsinghua.edu.cn/debian"
    SEC_URI="http://mirrors.tuna.tsinghua.edu.cn/debian-security"
else
    echo "选择使用官方默认源 (HTTP)..."
    BASE_URI="http://deb.debian.org/debian"
    SEC_URI="http://deb.debian.org/debian-security"
fi

cat > /etc/apt/sources.list.d/debian.sources << EOF
Types: deb
URIs: ${BASE_URI}
Suites: trixie trixie-updates trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: ${SEC_URI}
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

echo "正在更新软件包索引 (HTTP)..."
apt-get update

echo "正在安装 HTTPS 支持所需的基础包..."
apt-get install -y apt-transport-https ca-certificates

sed -i 's/http:/https:/g' /etc/apt/sources.list.d/debian.sources

echo "正在执行系统升级 (HTTPS)..."
apt-get update && 
    apt-get -o Dpkg::Options::="--force-confold" upgrade -q -y &&
    apt-get -o Dpkg::Options::="--force-confold" dist-upgrade -q -y
unset DEBIAN_FRONTEND

# ==================== 2. 安装基础与监控软件 ====================
echo "正在安装基础软件与监控工具..."
apt-get install -y sudo nftables curl wget gnupg unattended-upgrades apt-listchanges
# 使用元包安装最新内核头文件，避免因特定版本头文件从源中移除导致安装失败
apt-get install -y bpfcc-tools linux-headers-amd64

# ==================== 3. 智能主机名设置 (国别码-server-MAC后6位) ====================
echo "正在计算智能主机名..."

DEFAULT_IFACE=$(ip route show default | awk '/default/ {print $5}' | head -n1) || true
if [ -z "$DEFAULT_IFACE" ]; then
    DEFAULT_IFACE="eth0"
fi

MAC_ADDR=$(cat /sys/class/net/$DEFAULT_IFACE/address 2>/dev/null || echo "00:00:00:00:00:00")
MAC_SHORT=$(echo "$MAC_ADDR" | tr -d ':' | grep -oE '.{6}$')

COUNTRY_CODE="xx"
CC_RESPONSE=$(curl -s --max-time 5 http://ip-api.com/json?fields=countryCode 2>/dev/null)

if [[ "$CC_RESPONSE" =~ \"countryCode\":\"([A-Za-z]{2})\" ]]; then
    COUNTRY_CODE=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
fi

NEW_HOSTNAME="${COUNTRY_CODE}-server-${MAC_SHORT}"
hostnamectl set-hostname "$NEW_HOSTNAME"

if grep -q "127.0.1.1" /etc/hosts; then
    sed -i "s/127.0.1.1.*/127.0.1.1\t$NEW_HOSTNAME/g" /etc/hosts
else
    echo "127.0.1.1\t$NEW_HOSTNAME" >> /etc/hosts
fi
echo "主机名已设置为: $NEW_HOSTNAME"

# ==================== 4. 创建用户与 sudo 管理 ====================
if getent passwd "$username" > /dev/null; then
    echo "用户名: $username 已存在。"
    usermod -aG sudo "$username"
else
    useradd -m -c "admin account" -G sudo -s /bin/bash "$username"
    echo "$username:$password" | chpasswd
    echo "已创建用户 $username 并加入 sudo 组"
fi

echo "正在配置 $username 的 sudo 免密权限..."
echo "$username ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$username
chmod 440 /etc/sudoers.d/$username
visudo -cf /etc/sudoers.d/$username > /dev/null

# ==================== 5. 配置 SSH 基础加固 ====================
mkdir -p /home/$username/.ssh
cat > /home/$username/.ssh/authorized_keys << 'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGEmRnAsJaTbLCKuVXeY5AsLmTjxTL/VlRM7tuvC47JO nanyang@qa.sukean
EOF

chmod 600 /home/$username/.ssh/authorized_keys
chmod 700 /home/$username/.ssh
chown -R $username:$username /home/$username/.ssh

sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/g' /etc/ssh/sshd_config
# 彻底禁止 root 登录
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/g' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/g' /etc/ssh/sshd_config

systemctl restart ssh.service

# ==================== 6. 安装 Tailscale (官方 Debian Trixie 源) ====================
echo "正在配置 Tailscale (官方 Debian Trixie 仓库)..."

curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg \
    | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null

curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list \
    | tee /etc/apt/sources.list.d/tailscale.list >/dev/null

apt-get update
apt-get install -y tailscale

systemctl restart tailscaled.service

echo "================= Tailscale 安装完毕 ================="
echo "已使用 Tailscale 官方 Debian Trixie 仓库。"
echo "======================================================"

# ==================== 7. 配置 nftables 防火墙 ====================
echo "正在配置 nftables 防火墙..."

cat > /etc/nftables.conf << 'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet firewall {
    chain input {
        type filter hook input priority 0; policy drop;

        iif "lo" accept
        ct state invalid drop
        ct state established,related accept
        
        tcp flags & (fin|syn|rst|psh|ack|urg) == fin|syn|rst|psh|ack|urg drop
        tcp flags & (fin|syn|rst|psh|ack|urg) == 0 drop
        tcp flags & syn != syn ct state new drop

        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        iifname "tailscale0" accept
        tcp dport { 80, 443 } accept
        # 可选: 若未来需要开启 Peer Relay, 可在此处添加对应 UDP 端口放行规则
        # udp dport 40000 accept
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
        # 放行来自 tailscale0 的转发流量 (支持作为 Exit Node / 子网路由 / Relay)
        iifname "tailscale0" accept
        ct state established,related accept
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

nft -f /etc/nftables.conf
systemctl enable nftables.service
systemctl restart nftables.service

# ==================== 8. 内核网络参数加固 ====================
echo "正在配置内核网络参数..."

# 1. 专属 Tailscale 转发配置 (独立文件，易于管理)
cat > /etc/sysctl.d/99-tailscale.conf << 'EOF'
# Tailscale 网络转发支持 (用于 Exit Node / Subnet Router / Relay)
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

# 2. 通用安全加固配置
cat > /etc/sysctl.d/99-security-hardening.conf << 'EOF'
# ----- Security Hardening -----
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.log_martians = 1
kernel.dmesg_restrict = 1
EOF

# 统一加载所有 sysctl.d 配置
sysctl --system 2>/dev/null || true

# ==================== 9. 配置无人值守更新与 Systemd 条件重启 ====================
echo "正在配置无人值守更新..."

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

CONF_FILE="/etc/apt/apt.conf.d/50unattended-upgrades"
# 优化 sed 匹配规则，兼容不同空格数量的情况
sed -i 's|^\s*//?\s*Unattended-Upgrade::Remove-Unused-Kernel-Packages "false";|Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";|' $CONF_FILE
sed -i 's|^\s*//?\s*Unattended-Upgrade::Remove-Unused-Dependencies "false";|Unattended-Upgrade::Remove-Unused-Dependencies "true";|' $CONF_FILE
sed -i 's|^\s*//?\s*Unattended-Upgrade::Automatic-Reboot "false";|Unattended-Upgrade::Automatic-Reboot "false";|' $CONF_FILE

systemctl restart unattended-upgrades.service

cat > /etc/systemd/system/conditional-reboot.service << 'EOF'
[Unit]
Description=Conditional Reboot for Pending Security Updates
ConditionPathExists=/var/run/reboot-required

[Service]
Type=oneshot
ExecStart=/sbin/shutdown -r now "Weekly scheduled reboot for security updates"
EOF

cat > /etc/systemd/system/conditional-reboot.timer << 'EOF'
[Unit]
Description=Weekly Conditional Reboot Timer

[Timer]
OnCalendar=Sun *-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now conditional-reboot.timer

# ==================== 结束提示与生成 Readme ====================
# 将输出内容暂存于变量，避免重复执行，逻辑更清晰
summary_content=$(cat <<EOF
============= Debian 13 (Trixie) 现代化服务器初始化与加固完成 =============
主机名: $NEW_HOSTNAME
系统已更新至 Debian 13 最新状态，时区: $timezone
防火墙已配置：公网已彻底封死 SSH，仅 Tailscale 网络可登录。
eBPF 监控工具集已就绪。
用户 $username 已创建，并已配置 sudo 免密权限。
Tailscale 已使用官方 Debian Trixie 仓库安装。
内核转发已开启 (/etc/sysctl.d/99-tailscale.conf)。
无人值守更新已启用 (Systemd 接管：每周日 04:00 仅在需要时自动重启)。

请完成以下最后步骤：

1. 将服务器加入 Tailnet:
   sudo tailscale up --ssh --accept-routes --hostname=${NEW_HOSTNAME}

2. 在 Tailscale 控制台 ACL 的 "ssh" 字段中添加以下规则以启用 Tailscale SSH:
   "ssh": [
     {
       "action": "accept",
       "src":    ["autogroup:member"],
       "dst":    ["autogroup:self"],
       "users":  ["autogroup:nonroot"]
     }
   ]

3. 客户端 SSH 登录配置示例 (~/.ssh/config):

   场景 A: 客户端已安装 Tailscale，强制代理流量
   -----------------------------------------------------------
   Host my-debian
       # 你的服务器在 Tailscale 网络中的名称或 100.x.x.x IP
       HostName ${NEW_HOSTNAME}
       # 你的系统用户名
       User $username
       IdentityFile ~/.ssh/id_ed25519
       # 核心魔法：将 SSH 流量代理给本地的 tailscale 客户端处理
       ProxyCommand tailscale nc %h %p
   -----------------------------------------------------------

   场景 B: 客户端在局域网内，通过局域网的 Tailscale 网关跳转
   -----------------------------------------------------------
   # 假设局域网网关局域网 IP 为 192.168.1.10，且该网关在 Tailnet 中
   Host lan-gateway
       HostName 192.168.1.10
       User gateway_user

   Host my-debian
       HostName ${NEW_HOSTNAME}  # 目标服务器的 Tailscale 名称/IP
       User $username
       ProxyJump lan-gateway     # 使用网关作为跳板机，网关负责将流量送入 Tailnet
   -----------------------------------------------------------

==============================================================================
[可选进阶操作] 若未来需要将此节点作为 Peer Relay 私有中继：
1. 执行命令开启中继功能:
   sudo tailscale set --relay-server-port=40000

2. 放行防火墙端口:
   sed -i 's/# udp dport 40000 accept/    udp dport 40000 accept/g' /etc/nftables.conf
   sudo nft -f /etc/nftables.conf

3. 在 Tailscale 控制台 ACL 中添加对应 grants 策略:
   "grants": [
     {
       "src": ["tag:nat-locked"],
       "dst": ["tag:china-relays"],
       "app": {"tailscale.com/cap/relay": [""]}
     }
   ]
==============================================================================
EOF
)

# 打印到终端屏幕
echo "$summary_content"

# 根据用户选择决定是否写入文件
if [[ "$gen_readme" =~ ^[Yy]$ ]]; then
    echo "$summary_content" > /home/$username/Readme.txt
    chown $username:$username /home/$username/Readme.txt
    chmod 644 /home/$username/Readme.txt
    echo ""
    echo "操作指南已保存至 /home/$username/Readme.txt"
fi
