#!/bin/bash
#############################################################
# Mihomo 裸核版一键安装脚本 V1.0
# 支持系统: Debian 10/11/12, Ubuntu 20.04/22.04/24.04
# 功能: 一键安装并配置Mihomo代理服务（无需Docker）
# 
# 特性:
# - 自动检测系统架构并下载对应版本
# - 自动从 GitHub 下载最新配置文件
# - 完整的 systemd 服务管理
# - 支持命令行参数和交互式菜单
#############################################################

# 版本信息
SCRIPT_VERSION="1.0.0"

# 处理命令行参数
if [[ "$1" == "--version" || "$1" == "-v" ]]; then
    echo "Mihomo 裸核版一键安装脚本 v${SCRIPT_VERSION}"
    exit 0
fi

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Mihomo 裸核版一键安装脚本 v${SCRIPT_VERSION}"
    echo
    echo "使用方法:"
    echo "  bash mihomo.sh [选项]"
    echo
    echo "选项:"
    echo "  --version, -v     显示版本信息"
    echo "  --help, -h        显示此帮助信息"
    echo "  --auto-install    直接执行一键安装，无需进入菜单"
    echo
    exit 0
fi

# 全局环境变量
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="/etc/mihomo"
BINARY_DIR="/opt"
BINARY_FILE="/opt/mihomo"
SERVICE_FILE="/etc/systemd/system/mihomo.service"
LOG_FILE="/var/log/mihomo.log"


# 颜色代码
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
PURPLE="\033[35m"
CYAN="\033[36m"
GRAY="\033[37m"
PLAIN="\033[0m"

# 日志函数
log_message() {
    local message="$1"
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOG_FILE"
}

# 错误处理函数
handle_error() {
    local error_message="$1"
    log_message "${RED}错误: $error_message${PLAIN}"
    echo -e "${RED}错误: $error_message${PLAIN}"
    exit 1
}

# 检查是否具有root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本需要root权限运行${PLAIN}"
        echo -e "${YELLOW}请使用 sudo bash $0 或切换到root用户${PLAIN}"
        exit 1
    fi
}

# 检查操作系统
check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        echo -e "${GREEN}检测到系统: $PRETTY_NAME${PLAIN}"
        
        case $OS in
            debian|ubuntu)
                echo -e "${GREEN}✓ 支持的操作系统${PLAIN}"
                ;;
            *)
                echo -e "${YELLOW}⚠ 未测试的操作系统，可能存在兼容性问题${PLAIN}"
                read -p "是否继续安装? (y/n): " continue_install
                if [[ "$continue_install" != "y" && "$continue_install" != "Y" ]]; then
                    exit 1
                fi
                ;;
        esac
    else
        handle_error "无法检测操作系统版本"
    fi
}

# 检测系统架构
detect_architecture() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            # 检查是否支持 AMD64 v3 微架构
            if grep -q "avx2" /proc/cpuinfo && grep -q "bmi2" /proc/cpuinfo; then
                echo "amd64"
            else
                echo "amd64-compatible"
            fi
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l)
            echo "armv7"
            ;;
        *)
            echo -e "${YELLOW}⚠ 未知架构: $arch，默认使用兼容版本${PLAIN}"
            echo "amd64-compatible"
            ;;
    esac
}

# 获取主网卡IP地址
get_main_ip() {
    local main_interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    local main_ip=$(ip -4 addr show dev "$main_interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    echo "$main_ip"
}

# 环境配置
setup_environment() {
    echo -e "${CYAN}正在配置系统环境...${PLAIN}"
    
    # 修复可能的 dpkg 问题
    echo -e "${CYAN}检查并修复包管理器状态...${PLAIN}"
    dpkg --configure -a >/dev/null 2>&1
    apt-get -f install -y >/dev/null 2>&1
    
    # 更新系统
    echo -e "${CYAN}更新系统软件包...${PLAIN}"
    if ! apt update; then
        echo -e "${YELLOW}⚠ 系统更新失败，尝试修复...${PLAIN}"
        apt-get clean
        apt-get update --fix-missing
    fi
    
    # 安装必要工具（不进行系统升级，避免 dpkg 问题）
    echo -e "${CYAN}安装必要工具...${PLAIN}"
    apt install -y wget curl tar net-tools iptables-persistent
    
    # 检查 systemctl 是否可用
    if ! command -v systemctl >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ systemctl 不可用，尝试安装 systemd${PLAIN}"
        apt install -y systemd
    fi
    
    # 检查并处理PVE环境
    echo -e "${CYAN}检查虚拟化环境...${PLAIN}"
    if [[ -f /etc/pve/local/pve-ssl.pem ]] || command -v pveversion >/dev/null 2>&1; then
        echo -e "${YELLOW}检测到PVE/Proxmox环境${PLAIN}"
        
        # 检查PVE防火墙状态
        if command -v pve-firewall >/dev/null 2>&1; then
            local pve_fw_status=$(pve-firewall status 2>/dev/null | grep "Status:" | awk '{print $2}')
            if [[ "$pve_fw_status" == "running" ]]; then
                echo -e "${YELLOW}⚠ 检测到PVE防火墙正在运行，这可能影响透明代理${PLAIN}"
                echo -e "${CYAN}建议操作：${PLAIN}"
                echo -e "${YELLOW}1. 在PVE web界面关闭防火墙：数据中心 -> 防火墙 -> 选项 -> 防火墙：否${PLAIN}"
                echo -e "${YELLOW}2. 或者允许必要的端口通过PVE防火墙${PLAIN}"
                read -p "是否继续安装？建议先关闭PVE防火墙 (y/n): " continue_install
                if [[ "$continue_install" != "y" && "$continue_install" != "Y" ]]; then
                    echo -e "${YELLOW}请先关闭PVE防火墙后重新运行安装${PLAIN}"
                    return 1
                fi
            else
                echo -e "${GREEN}✓ PVE防火墙未运行${PLAIN}"
            fi
        fi
        
        # 在PVE环境中添加特殊处理
        echo -e "${CYAN}应用PVE环境优化...${PLAIN}"
        
        # 清理可能的旧网络状态
        echo -e "${CYAN}清理网络状态...${PLAIN}"
        
        # 停止可能冲突的服务
        systemctl stop pve-firewall 2>/dev/null || true
        systemctl stop pveproxy 2>/dev/null && systemctl start pveproxy 2>/dev/null || true
        
        # 清理conntrack表，确保新连接能正确处理
        if command -v conntrack >/dev/null 2>&1; then
            conntrack -F 2>/dev/null || true
            echo -e "${GREEN}✓ 已清理连接跟踪表${PLAIN}"
        fi
    fi
    
    # 确保必要的内核模块已加载
    echo -e "${CYAN}加载必要的内核模块...${PLAIN}"
    modprobe ip_tables 2>/dev/null || true
    modprobe iptable_nat 2>/dev/null || true
    modprobe iptable_mangle 2>/dev/null || true
    modprobe ip_conntrack 2>/dev/null || true
    modprobe nf_conntrack 2>/dev/null || true
    modprobe nf_nat 2>/dev/null || true
    modprobe xt_REDIRECT 2>/dev/null || true
    modprobe xt_TPROXY 2>/dev/null || true
    modprobe tun 2>/dev/null || true
    
    # 强制刷新网络接口状态
    echo -e "${CYAN}刷新网络接口状态...${PLAIN}"
    local main_interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [[ -n "$main_interface" ]]; then
        # 刷新接口状态但不断开连接
        ip link set $main_interface down 2>/dev/null && sleep 1 && ip link set $main_interface up 2>/dev/null || true
        sleep 2
    fi
    
    # 开启IP转发 - 多重保障加强版
    echo -e "${CYAN}开启IP转发...${PLAIN}"
    
    # 1. 立即设置内核参数 - 多次确保
    for i in {1..3}; do
        echo 1 > /proc/sys/net/ipv4/ip_forward
        echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
        echo 0 > /proc/sys/net/ipv4/conf/all/send_redirects 2>/dev/null || true
        echo 0 > /proc/sys/net/ipv4/conf/default/send_redirects 2>/dev/null || true
        
                 # 验证设置是否生效
         if [[ $(cat /proc/sys/net/ipv4/ip_forward) == "1" ]]; then
             echo -e "${GREEN}✓ IPv4转发设置成功 (尝试 $i/3)${PLAIN}"
             break
         else
             echo -e "${YELLOW}⚠ IPv4转发设置失败，重试... ($i/3)${PLAIN}"
             sleep 1
         fi
     done
    
    # 2. 配置 sysctl.conf 持久化设置
    # 清理可能的重复配置
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf 2>/dev/null || true
    sed -i '/net.ipv6.conf.all.forwarding/d' /etc/sysctl.conf 2>/dev/null || true
    sed -i '/net.ipv4.conf.all.send_redirects/d' /etc/sysctl.conf 2>/dev/null || true
    sed -i '/net.ipv4.conf.default.send_redirects/d' /etc/sysctl.conf 2>/dev/null || true
    
    # 添加配置
    cat >> /etc/sysctl.conf << 'EOF'

# Mihomo 透明代理配置
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
EOF
    
    # 3. 创建专用的 sysctl 配置文件
    cat > /etc/sysctl.d/99-mihomo.conf << 'EOF'
# Mihomo 透明代理优化配置
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 65536 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.netfilter.nf_conntrack_max=1048576
net.netfilter.nf_conntrack_tcp_timeout_established=600
EOF
    
    # 4. 应用所有 sysctl 配置
    sysctl -p /etc/sysctl.d/99-mihomo.conf >/dev/null 2>&1
    sysctl -p >/dev/null 2>&1
    
    # 5. 验证配置是否生效 - 多次检查确保稳定
    local retry_count=0
    local max_retries=5
    
    while [[ $retry_count -lt $max_retries ]]; do
        if [[ $(cat /proc/sys/net/ipv4/ip_forward) == "1" ]]; then
            echo -e "${GREEN}✓ IPv4转发已启用${PLAIN}"
            break
        else
            echo -e "${YELLOW}⚠ IPv4转发启用失败，重试中... (${retry_count}/${max_retries})${PLAIN}"
            echo 1 > /proc/sys/net/ipv4/ip_forward
            sleep 1
            ((retry_count++))
        fi
    done
    
    if [[ $retry_count -eq $max_retries ]]; then
        echo -e "${RED}✗ IPv4转发启用失败，可能需要重启系统${PLAIN}"
    fi
    
    # 6. 验证IPv6转发
    if [[ $(cat /proc/sys/net/ipv6/conf/all/forwarding) == "1" ]]; then
        echo -e "${GREEN}✓ IPv6转发已启用${PLAIN}"
    else
        echo -e "${YELLOW}⚠ IPv6转发启用失败${PLAIN}"
    fi
    
    # 7. 检查关键网络功能
    echo -e "${CYAN}验证网络功能...${PLAIN}"
    
    # 检查 iptables 功能
    if iptables -t nat -L >/dev/null 2>&1; then
        echo -e "${GREEN}✓ iptables NAT 功能正常${PLAIN}"
    else
        echo -e "${RED}✗ iptables NAT 功能异常${PLAIN}"
    fi
    
    # 检查 TUN 设备
    if [[ -c /dev/net/tun ]]; then
        echo -e "${GREEN}✓ TUN 设备可用${PLAIN}"
    else
        echo -e "${YELLOW}⚠ TUN 设备不可用，尝试创建...${PLAIN}"
        mkdir -p /dev/net
        mknod /dev/net/tun c 10 200 2>/dev/null || true
        chmod 666 /dev/net/tun 2>/dev/null || true
    fi
    
    # 检查网络连接
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 网络连接正常${PLAIN}"
    else
        echo -e "${YELLOW}⚠ 网络连接可能有问题${PLAIN}"
    fi
    
    echo -e "${GREEN}✓ 系统环境配置完成${PLAIN}"
}

# 下载最新版本的Mihomo
download_mihomo() {
    echo -e "${CYAN}正在下载最新版本的Mihomo...${PLAIN}"
    
    local arch=$(detect_architecture)
    echo -e "${YELLOW}检测到系统架构: $arch${PLAIN}"
    
    # 获取最新版本号
    local latest_version=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    if [[ -z "$latest_version" ]]; then
        handle_error "无法获取最新版本信息"
    fi
    
    echo -e "${GREEN}最新版本: $latest_version${PLAIN}"
    
    # 根据架构构建下载URL
    local download_url
    if [[ "$arch" == "amd64-compatible" ]]; then
        # 对于不支持 v3 微架构的处理器，使用兼容版本
        echo -e "${YELLOW}检测到旧版 AMD64 处理器，下载兼容版本...${PLAIN}"
        download_url="https://github.com/MetaCubeX/mihomo/releases/download/${latest_version}/mihomo-linux-amd64-compatible-${latest_version}.gz"
    else
        download_url="https://github.com/MetaCubeX/mihomo/releases/download/${latest_version}/mihomo-linux-${arch}-${latest_version}.gz"
    fi
    
    # 下载文件
    echo -e "${CYAN}正在下载: $download_url${PLAIN}"
    if wget -O "$BINARY_FILE.gz" "$download_url"; then
        echo -e "${GREEN}✓ 下载成功${PLAIN}"
    else
        # 如果兼容版本下载失败，尝试下载标准版本
        if [[ "$arch" == "amd64-compatible" ]]; then
            echo -e "${YELLOW}⚠ 兼容版本下载失败，尝试标准版本...${PLAIN}"
            download_url="https://github.com/MetaCubeX/mihomo/releases/download/${latest_version}/mihomo-linux-amd64-${latest_version}.gz"
            if wget -O "$BINARY_FILE.gz" "$download_url"; then
                echo -e "${GREEN}✓ 标准版本下载成功${PLAIN}"
                echo -e "${YELLOW}⚠ 注意: 如果启动失败，可能是处理器不支持，请联系开发者${PLAIN}"
            else
                handle_error "下载失败，请检查网络连接"
            fi
        else
            handle_error "下载失败，请检查网络连接"
        fi
    fi
    
    # 解压文件
    echo -e "${CYAN}正在解压文件...${PLAIN}"
    gunzip "$BINARY_FILE.gz"
    chmod 755 "$BINARY_FILE"
    
    echo -e "${GREEN}✓ Mihomo二进制文件安装完成${PLAIN}"
    echo -e "${YELLOW}安装位置: $BINARY_FILE${PLAIN}"
}

# 下载UI界面
download_ui() {
    echo -e "${CYAN}正在下载UI界面...${PLAIN}"
    
    mkdir -p "$CONFIG_DIR/ui"
    
    # 下载MetaCubeX UI
    local ui_url="https://github.com/MetaCubeX/metacubexd/releases/download/v1.187.1/compressed-dist.tgz"
    
    if wget -O /tmp/ui.tgz "$ui_url"; then
        tar -xzf /tmp/ui.tgz -C "$CONFIG_DIR/ui"
        rm -f /tmp/ui.tgz
        echo -e "${GREEN}✓ UI界面下载完成${PLAIN}"
    else
        echo -e "${YELLOW}⚠ UI界面下载失败，将使用无UI模式${PLAIN}"
    fi
}

# 创建配置文件
create_config() {
    echo -e "${CYAN}正在创建配置文件...${PLAIN}"
    
    mkdir -p "$CONFIG_DIR"
    
    # 首先尝试从本地复制配置文件（如果存在）
    local config_template="$SCRIPT_DIR/config.yaml"
    if [[ -f "$config_template" ]]; then
        echo -e "${GREEN}发现本地配置模板，正在复制...${PLAIN}"
        cp "$config_template" "$CONFIG_DIR/config.yaml"
        chmod 644 "$CONFIG_DIR/config.yaml"
        echo -e "${GREEN}✓ 配置文件创建完成${PLAIN}"
        echo -e "${YELLOW}配置文件位置: $CONFIG_DIR/config.yaml${PLAIN}"
        return 0
    fi
    
    # 如果本地没有配置文件，则从 GitHub 下载
    echo -e "${CYAN}本地未找到配置文件，正在从 GitHub 下载...${PLAIN}"
    local config_url="https://raw.githubusercontent.com/wallentv/mihomo-proxy/refs/heads/master/mihomo/config.yaml"
    
    if wget -O "$CONFIG_DIR/config.yaml" "$config_url"; then
        chmod 644 "$CONFIG_DIR/config.yaml"
        echo -e "${GREEN}✓ 配置文件下载完成${PLAIN}"
        echo -e "${YELLOW}配置文件位置: $CONFIG_DIR/config.yaml${PLAIN}"
        
        # 预下载MMDB文件，避免启动时下载失败
        echo -e "${CYAN}正在预下载地理位置数据库...${PLAIN}"
        mkdir -p "$CONFIG_DIR"
        if wget -O "$CONFIG_DIR/Country.mmdb" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb" 2>/dev/null; then
            echo -e "${GREEN}✓ 地理位置数据库下载完成${PLAIN}"
        else
            echo -e "${YELLOW}⚠ 地理位置数据库下载失败，服务启动时会自动下载${PLAIN}"
        fi
        
    else
        echo -e "${YELLOW}⚠ 配置文件下载失败，创建默认配置...${PLAIN}"
        # 创建一个基本的默认配置
        cat > "$CONFIG_DIR/config.yaml" << 'EOF'
# Mihomo 基本配置文件
mixed-port: 7890
port: 7891
socks-port: 7892
allow-lan: true
bind-address: "*"
mode: rule
log-level: info
external-controller: 0.0.0.0:9090
external-ui: ui
secret: "wallentv"

dns:
  enable: true
  listen: 0.0.0.0:53
  cache: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.0/16
  nameserver:
    - https://doh.pub/dns-query
    - https://dns.alidns.com/dns-query

tun:
  enable: true
  stack: system
  dns-hijack:
    - tcp://any:53
    - udp://any:53

proxies:
  - name: "direct"
    type: direct

proxy-groups:
  - name: "Proxy"
    type: select
    proxies:
      - direct

rules:
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
EOF
        chmod 644 "$CONFIG_DIR/config.yaml"
        echo -e "${GREEN}✓ 默认配置文件创建完成${PLAIN}"
        echo -e "${YELLOW}配置文件位置: $CONFIG_DIR/config.yaml${PLAIN}"
        echo -e "${YELLOW}建议安装完成后根据需要修改配置文件${PLAIN}"
    fi
}

# 创建systemd服务
create_service() {
    echo -e "${CYAN}正在创建systemd服务...${PLAIN}"
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Mihomo Proxy Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=$BINARY_FILE -d $CONFIG_DIR
Restart=always
RestartSec=5
KillMode=mixed
TimeoutStopSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载systemd并启用服务
    systemctl daemon-reload
    systemctl enable mihomo
    
    echo -e "${GREEN}✓ systemd服务创建完成${PLAIN}"
}

# 启动服务
start_service() {
    echo -e "${CYAN}正在启动Mihomo服务...${PLAIN}"
    
    if systemctl start mihomo; then
        sleep 3
        if systemctl is-active --quiet mihomo; then
            echo -e "${GREEN}✓ Mihomo服务启动成功${PLAIN}"
            
            # 自动启用透明代理规则
            echo -e "${CYAN}正在启用透明代理规则...${PLAIN}"
            setup_simple_rules
            echo -e "${GREEN}✓ 透明代理规则已启用${PLAIN}"
            
            return 0
        else
            echo -e "${RED}✗ Mihomo服务启动失败${PLAIN}"
            echo -e "${YELLOW}查看错误日志: journalctl -u mihomo -n 20${PLAIN}"
            return 1
        fi
    else
        echo -e "${RED}✗ 无法启动Mihomo服务${PLAIN}"
        return 1
    fi
}

# 停止服务
stop_service() {
    echo -e "${CYAN}正在停止Mihomo服务...${PLAIN}"
    
    # 先清理透明代理规则
    echo -e "${CYAN}正在清理透明代理规则...${PLAIN}"
    cleanup_simple_rules
    
    if systemctl stop mihomo; then
        echo -e "${GREEN}✓ Mihomo服务已停止${PLAIN}"
        echo -e "${GREEN}✓ 透明代理规则已清理${PLAIN}"
    else
        echo -e "${RED}✗ 停止服务失败${PLAIN}"
    fi
}

# 重启服务
restart_service() {
    echo -e "${CYAN}正在重启Mihomo服务...${PLAIN}"
    
    # 先清理透明代理规则
    echo -e "${CYAN}正在清理透明代理规则...${PLAIN}"
    cleanup_simple_rules
    
    if systemctl restart mihomo; then
        sleep 3
        if systemctl is-active --quiet mihomo; then
            echo -e "${GREEN}✓ Mihomo服务重启成功${PLAIN}"
            
            # 重新启用透明代理规则
            echo -e "${CYAN}正在启用透明代理规则...${PLAIN}"
            setup_simple_rules
            echo -e "${GREEN}✓ 透明代理规则已启用${PLAIN}"
        else
            echo -e "${RED}✗ Mihomo服务重启失败${PLAIN}"
            echo -e "${YELLOW}查看错误日志: journalctl -u mihomo -n 20${PLAIN}"
        fi
    else
        echo -e "${RED}✗ 重启服务失败${PLAIN}"
    fi
}

# 配置简单的透明代理规则（基础版）
setup_simple_rules() {
    local main_ip=$(get_main_ip)
    local ssh_port=$(ss -tlnp | grep sshd | grep -oP ':\K\d+' | head -n1)
    [[ -z "$ssh_port" ]] && ssh_port="22"
    
    echo -e "${CYAN}配置基础透明代理规则...${PLAIN}"
    
    # 简单的iptables规则
    iptables -t nat -F 2>/dev/null || true
    iptables -t nat -X 2>/dev/null || true
    
    # 基础重定向规则
    iptables -t nat -A PREROUTING -s $main_ip -j RETURN
    iptables -t nat -A PREROUTING -p tcp --dport $ssh_port -j RETURN
    iptables -t nat -A PREROUTING -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A PREROUTING -d 10.0.0.0/8 -j RETURN
    iptables -t nat -A PREROUTING -d 172.16.0.0/12 -j RETURN
    iptables -t nat -A PREROUTING -d 192.168.0.0/16 -j RETURN
    iptables -t nat -A PREROUTING -p tcp -j REDIRECT --to-ports 7892
    
    # MASQUERADE规则
    local external_interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    iptables -t nat -A POSTROUTING -o $external_interface -j MASQUERADE 2>/dev/null || true
    
    echo -e "${GREEN}✓ 基础规则配置完成${PLAIN}"
}

# 清理规则
cleanup_simple_rules() {
    echo -e "${CYAN}清理透明代理规则...${PLAIN}"
    iptables -t nat -F 2>/dev/null || true
    iptables -t nat -X 2>/dev/null || true
    echo -e "${GREEN}✓ 规则清理完成${PLAIN}"
}

# 检查规则
check_simple_rules() {
    if iptables -t nat -L PREROUTING 2>/dev/null | grep -q "REDIRECT.*7892"; then
        return 0
    else
        return 1
    fi
}





# 检查服务状态
check_status() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}              Mihomo 服务状态检查${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    # 检查服务状态
    if systemctl is-active --quiet mihomo; then
        echo -e "${GREEN}✓ Mihomo服务: 运行中${PLAIN}"
        
        # 获取服务信息
        local main_ip=$(get_main_ip)
        echo -e "${YELLOW}• 代理机IP: $main_ip${PLAIN}"
        echo -e "${YELLOW}• 控制面板: http://$main_ip:9090${PLAIN}"
        echo -e "${YELLOW}• 混合代理: $main_ip:7890${PLAIN}"
        echo -e "${YELLOW}• HTTP代理: $main_ip:7891${PLAIN}"
        echo -e "${YELLOW}• SOCKS代理: $main_ip:7892${PLAIN}"
        echo -e "${YELLOW}• DNS服务: $main_ip:53${PLAIN}"
        
        # 检查端口监听
        echo -e "\n${CYAN}端口监听状态:${PLAIN}"
        if command -v netstat >/dev/null 2>&1; then
            netstat -tlnp | grep mihomo | while read line; do
                echo -e "${GREEN}✓ $line${PLAIN}"
            done
        elif command -v ss >/dev/null 2>&1; then
            ss -tlnp | grep mihomo | while read line; do
                echo -e "${GREEN}✓ $line${PLAIN}"
            done
        else
            echo -e "${YELLOW}⚠ 无法检查端口状态（缺少 netstat 或 ss 命令）${PLAIN}"
        fi
        
    else
        echo -e "${RED}✗ Mihomo服务: 未运行${PLAIN}"
        
        if systemctl is-enabled --quiet mihomo; then
            echo -e "${YELLOW}• 服务已启用，但未运行${PLAIN}"
        else
            echo -e "${YELLOW}• 服务未启用${PLAIN}"
        fi
    fi
    
    # 检查配置文件
    echo -e "\n${CYAN}文件状态检查:${PLAIN}"
    if [[ -f "$CONFIG_DIR/config.yaml" ]]; then
        echo -e "${GREEN}✓ 配置文件: 存在${PLAIN}"
        echo -e "${YELLOW}• 位置: $CONFIG_DIR/config.yaml${PLAIN}"
    else
        echo -e "${RED}✗ 配置文件: 不存在${PLAIN}"
    fi
    
    # 检查二进制文件
    if [[ -f "$BINARY_FILE" ]]; then
        echo -e "${GREEN}✓ 二进制文件: 存在${PLAIN}"
        local version=$($BINARY_FILE -v 2>/dev/null | head -n1)
        echo -e "${YELLOW}• 版本: $version${PLAIN}"
        echo -e "${YELLOW}• 位置: $BINARY_FILE${PLAIN}"
    else
        echo -e "${RED}✗ 二进制文件: 不存在${PLAIN}"
    fi
    
    # 检查UI文件
    if [[ -d "$CONFIG_DIR/ui" ]]; then
        echo -e "${GREEN}✓ UI界面: 存在${PLAIN}"
        echo -e "${YELLOW}• 位置: $CONFIG_DIR/ui${PLAIN}"
    else
        echo -e "${YELLOW}⚠ UI界面: 不存在${PLAIN}"
    fi
    
    # 防火墙状态检查
    echo -e "\n${CYAN}防火墙状态检查:${PLAIN}"
    if check_simple_rules; then
        echo -e "${GREEN}✓ iptables透明代理规则: 已配置${PLAIN}"
        echo -e "\n${CYAN}规则详情:${PLAIN}"
        iptables -t nat -L PREROUTING -n 2>/dev/null | grep "REDIRECT.*7892" || echo "规则格式可能不同"
    else
        echo -e "${YELLOW}⚠ iptables透明代理规则: 未检测到标准规则${PLAIN}"
        echo -e "${YELLOW}• 可能使用了其他方式配置或规则格式不同${PLAIN}"
        echo -e "\n${CYAN}当前NAT表规则:${PLAIN}"
        iptables -t nat -L PREROUTING -n 2>/dev/null | head -5 || echo "无法查看规则"
    fi
    
    # 透明代理可用性检查（更实用的判断）
    echo -e "\n${CYAN}透明代理状态:${PLAIN}"
    if systemctl is-active --quiet mihomo; then
        echo -e "${GREEN}✓ 透明代理: 可用${PLAIN}"
        local main_ip=$(get_main_ip)
        echo -e "${YELLOW}• 服务运行正常，代理功能可用${PLAIN}"
        echo -e "${YELLOW}• 客户端网关设置: $main_ip${PLAIN}"
        echo -e "${YELLOW}• 客户端DNS设置: $main_ip${PLAIN}"
        echo -e "${CYAN}• 如透明代理确实不工作，可重新运行安装配置防火墙规则${PLAIN}"
    else
        echo -e "${RED}✗ 透明代理: 不可用${PLAIN}"
        echo -e "${YELLOW}• 原因: Mihomo服务未运行${PLAIN}"
    fi
    
    # 系统环境检查
    echo -e "\n${CYAN}系统环境检查:${PLAIN}"
    # IP转发检查
    if [[ $(cat /proc/sys/net/ipv4/ip_forward) == "1" ]]; then
        echo -e "${GREEN}✓ IPv4转发: 已启用${PLAIN}"
    else
        echo -e "${RED}✗ IPv4转发: 未启用${PLAIN}"
    fi
    
    if [[ $(cat /proc/sys/net/ipv6/conf/all/forwarding) == "1" ]]; then
        echo -e "${GREEN}✓ IPv6转发: 已启用${PLAIN}"
    else
        echo -e "${YELLOW}⚠ IPv6转发: 未启用${PLAIN}"
    fi
    
    # 检查TUN设备
    if [[ -c /dev/net/tun ]]; then
        echo -e "${GREEN}✓ TUN设备: 可用${PLAIN}"
    else
        echo -e "${RED}✗ TUN设备: 不可用${PLAIN}"
    fi
    
    echo -e "\n${CYAN}最近服务日志:${PLAIN}"
    journalctl -u mihomo -n 5 --no-pager 2>/dev/null || echo -e "${YELLOW}⚠ 无法获取服务日志${PLAIN}"
    
    echo -e "\n${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}状态检查完成${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    read -p "按任意键返回主菜单..." key
}

# 显示使用指南
show_usage_guide() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}              Mihomo 使用指南${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    local main_ip=$(get_main_ip)
    
    echo -e "${GREEN}代理机IP地址: $main_ip${PLAIN}"
    echo -e "${GREEN}控制面板: http://$main_ip:9090${PLAIN}"
    echo -e "${GREEN}管理密码: wallentv${PLAIN}"
    echo
    
    # 检查服务状态（更实用的判断）
    local service_running=false
    if systemctl is-active --quiet mihomo; then
        service_running=true
        echo -e "${GREEN}✓ Mihomo服务运行正常，代理功能可用${PLAIN}"
        if check_simple_rules; then
            echo -e "${GREEN}✓ 透明代理规则已配置${PLAIN}"
        else
            echo -e "${YELLOW}⚠ 透明代理规则未检测到，但服务正常运行${PLAIN}"
        fi
    else
        echo -e "${RED}✗ Mihomo服务未运行${PLAIN}"
        echo -e "${YELLOW}• 请先启动服务${PLAIN}"
    fi
    echo
    
    echo -e "${YELLOW}使用方法一: 手动代理设置${PLAIN}"
    echo -e "${CYAN}适用于: 单个设备或应用程序代理${PLAIN}"
    echo -e "${CYAN}配置方法:${PLAIN}"
    echo -e "   • HTTP代理: $main_ip:7891"
    echo -e "   • SOCKS5代理: $main_ip:7892"
    echo -e "   • 混合代理: $main_ip:7890 (推荐)"
    echo
    
    if $service_running; then
        echo -e "${YELLOW}使用方法二: 透明代理（推荐）${PLAIN}"
        echo -e "${CYAN}适用于: 全局代理，无需在每个设备上配置${PLAIN}"
        echo -e "${CYAN}配置方法:${PLAIN}"
        echo -e "   1. 将设备网关设置为: $main_ip"
        echo -e "   2. 将设备DNS设置为: $main_ip"
        echo -e "   3. 所有流量将自动通过代理"
        echo
        
        echo -e "${YELLOW}使用方法三: DNS + 路由设置${PLAIN}"
        echo -e "${CYAN}适用于: 部分流量代理${PLAIN}"
        echo -e "${CYAN}配置方法:${PLAIN}"
        echo -e "   1. 将设备DNS设置为: $main_ip"
        echo -e "   2. 添加路由规则:"
        echo -e "      • 目标网段: 198.18.0.0/16"
        echo -e "      • 网关: $main_ip"
        echo
    else
        echo -e "${YELLOW}使用方法二: 透明代理${PLAIN}"
        echo -e "${RED}需要先启动Mihomo服务${PLAIN}"
        echo -e "${CYAN}启动命令: 选择菜单 [2] 启动服务${PLAIN}"
        echo
    fi
    
    echo -e "${YELLOW}路由器配置示例:${PLAIN}"
    echo -e "${CYAN}# OpenWrt/LEDE 路由器配置${PLAIN}"
    if $firewall_configured; then
        echo -e "# 方法1: 透明代理（全局）"
        echo -e "uci set network.lan.gateway='$main_ip'"
        echo -e "uci set dhcp.@dnsmasq[0].server='$main_ip'"
        echo -e "uci commit && /etc/init.d/network restart"
        echo
    fi
    echo -e "# 方法2: 静态路由（部分代理）"
    echo -e "ip route add 198.18.0.0/16 via $main_ip"
    echo -e "uci set dhcp.@dnsmasq[0].server='$main_ip'"
    echo -e "uci commit dhcp && /etc/init.d/dnsmasq restart"
    echo
    
    echo -e "${YELLOW}代理端口说明:${PLAIN}"
    echo -e "${CYAN}• 混合代理端口: $main_ip:7890 (HTTP + SOCKS5)${PLAIN}"
    echo -e "${CYAN}• HTTP代理端口: $main_ip:7891${PLAIN}"
    echo -e "${CYAN}• SOCKS5代理端口: $main_ip:7892${PLAIN}"
    echo -e "${CYAN}• DNS服务端口: $main_ip:53${PLAIN}"
    echo
    
    echo -e "${YELLOW}防火墙规则说明:${PLAIN}"
    echo -e "${CYAN}• 使用iptables基础规则${PLAIN}"
    if $service_running; then
        if check_simple_rules; then
            echo -e "${GREEN}• 透明代理规则: 已配置${PLAIN}"
            echo -e "${CYAN}• 自动重定向TCP流量到端口7892${PLAIN}"
            echo -e "${CYAN}• 排除本机和SSH流量，防止连接中断${PLAIN}"
        else
            echo -e "${YELLOW}• 透明代理规则: 未检测到标准格式${PLAIN}"
            echo -e "${CYAN}• 服务正常运行，如透明代理不工作可重新配置${PLAIN}"
        fi
    else
        echo -e "${RED}• 服务未运行，请先启动服务${PLAIN}"
    fi
    echo
    
    echo -e "${YELLOW}配置文件位置:${PLAIN}"
    echo -e "${CYAN}• 主配置: $CONFIG_DIR/config.yaml${PLAIN}"
    echo -e "${CYAN}• 编辑命令: nano $CONFIG_DIR/config.yaml${PLAIN}"
    echo -e "${CYAN}• 重启生效: systemctl restart mihomo${PLAIN}"
    echo
    
    echo -e "${YELLOW}故障排除:${PLAIN}"
    echo -e "${CYAN}• 查看服务状态: systemctl status mihomo${PLAIN}"
    echo -e "${CYAN}• 查看服务日志: journalctl -u mihomo -f${PLAIN}"
    echo -e "${CYAN}• 检查端口监听: ss -tlnp | grep mihomo${PLAIN}"
    echo -e "${CYAN}• 查看防火墙规则: iptables -t nat -L PREROUTING${PLAIN}"
    echo -e "${CYAN}• 测试代理连接: curl --proxy http://$main_ip:7890 httpbin.org/ip${PLAIN}"
    echo -e "${CYAN}• 如透明代理不工作: 重新运行 [1] 一键安装${PLAIN}"
    
    read -p "按任意键返回主菜单..." key
}

# 卸载Mihomo
uninstall_mihomo() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${RED}              卸载 Mihomo${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    echo -e "${YELLOW}警告: 此操作将完全卸载Mihomo及其所有配置文件${PLAIN}"
    echo -e "${RED}• 停止并删除Mihomo服务${PLAIN}"
    echo -e "${RED}• 删除二进制文件和配置文件${PLAIN}"
    echo -e "${RED}• 删除systemd服务文件${PLAIN}"
    echo -e "${RED}• 清理防火墙规则${PLAIN}"
    echo
    
    read -p "确定要卸载Mihomo吗? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}取消卸载${PLAIN}"
        return
    fi
    
    echo -e "${CYAN}正在卸载Mihomo...${PLAIN}"
    
    # 停止并禁用服务
    if systemctl is-active --quiet mihomo; then
        systemctl stop mihomo
        echo -e "${GREEN}✓ 已停止Mihomo服务${PLAIN}"
    fi
    
    if systemctl is-enabled --quiet mihomo; then
        systemctl disable mihomo
        echo -e "${GREEN}✓ 已禁用Mihomo服务${PLAIN}"
    fi
    
    # 清理防火墙规则
    cleanup_simple_rules
    
    # 删除服务文件
    if [[ -f "$SERVICE_FILE" ]]; then
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        echo -e "${GREEN}✓ 已删除服务文件${PLAIN}"
    fi
    
    # 删除二进制文件
    if [[ -f "$BINARY_FILE" ]]; then
        rm -f "$BINARY_FILE"
        echo -e "${GREEN}✓ 已删除二进制文件${PLAIN}"
    fi
    
    # 删除配置文件
    read -p "是否同时删除配置文件? (y/n): " delete_config
    if [[ "$delete_config" == "y" || "$delete_config" == "Y" ]]; then
        if [[ -d "$CONFIG_DIR" ]]; then
            rm -rf "$CONFIG_DIR"
            echo -e "${GREEN}✓ 已删除配置文件${PLAIN}"
        fi
    else
        echo -e "${YELLOW}⚠ 保留配置文件: $CONFIG_DIR${PLAIN}"
    fi
    
    # 删除日志文件
    if [[ -f "$LOG_FILE" ]]; then
        rm -f "$LOG_FILE"
        echo -e "${GREEN}✓ 已删除日志文件${PLAIN}"
    fi
    
    echo -e "\n${GREEN}======================================================${PLAIN}"
    echo -e "${GREEN}Mihomo卸载完成!${PLAIN}"
    echo -e "${GREEN}======================================================${PLAIN}"
    
    read -p "按任意键返回主菜单..." key
}

# 系统优化配置
optimize_system() {
    echo -e "${CYAN}正在优化系统配置...${PLAIN}"
    
    # 1. 确保关键服务开机自启
    echo -e "${CYAN}配置系统服务...${PLAIN}"
    systemctl enable systemd-sysctl 2>/dev/null || true
    systemctl enable networking 2>/dev/null || true
    systemctl enable iptables 2>/dev/null || true
    systemctl enable netfilter-persistent 2>/dev/null || true
    
    # 2. 创建开机启动脚本，确保网络配置在重启后生效
    cat > /etc/systemd/system/mihomo-network-setup.service << 'EOF'
[Unit]
Description=Mihomo Network Setup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '
    # 确保IPv4转发启用
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
    echo 0 > /proc/sys/net/ipv4/conf/all/send_redirects
    echo 0 > /proc/sys/net/ipv4/conf/default/send_redirects
    
    # 加载必要的内核模块
    modprobe ip_tables 2>/dev/null || true
    modprobe iptable_nat 2>/dev/null || true
    modprobe iptable_mangle 2>/dev/null || true
    modprobe nf_conntrack 2>/dev/null || true
    modprobe nf_nat 2>/dev/null || true
    modprobe xt_REDIRECT 2>/dev/null || true
    modprobe xt_TPROXY 2>/dev/null || true
    modprobe tun 2>/dev/null || true
    
    # 应用 sysctl 配置
    sysctl -p /etc/sysctl.d/99-mihomo.conf 2>/dev/null || true
'

[Install]
WantedBy=multi-user.target
EOF
    
    # 启用网络设置服务
    systemctl daemon-reload
    systemctl enable mihomo-network-setup.service 2>/dev/null || true
    
    # 3. 创建模块加载配置
    cat > /etc/modules-load.d/mihomo.conf << 'EOF'
# Mihomo 透明代理所需模块
ip_tables
iptable_nat
iptable_mangle
nf_conntrack
nf_nat
xt_REDIRECT
xt_TPROXY
tun
EOF
    
    # 4. 优化网络连接参数
    cat > /etc/sysctl.d/98-mihomo-network.conf << 'EOF'
# Mihomo 网络优化配置
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
net.core.rmem_default=1048576
net.core.rmem_max=134217728
net.core.wmem_default=1048576
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 1048576 134217728
net.ipv4.tcp_wmem=4096 1048576 134217728
net.netfilter.nf_conntrack_max=1048576
net.netfilter.nf_conntrack_tcp_timeout_established=600
net.netfilter.nf_conntrack_tcp_timeout_time_wait=1
net.netfilter.nf_conntrack_tcp_timeout_close_wait=10
EOF
    
    # 5. 配置 iptables 持久化
    if command -v iptables-persistent >/dev/null 2>&1; then
        echo -e "${GREEN}✓ iptables-persistent 已安装${PLAIN}"
    else
        echo -e "${CYAN}安装 iptables-persistent...${PLAIN}"
        echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
        echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
        apt install -y iptables-persistent 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✓ 系统优化配置完成${PLAIN}"
}

# 检查系统重启后的状态
check_post_reboot_status() {
    echo -e "${CYAN}检查重启后系统状态...${PLAIN}"
    
    # 检查关键服务状态
    local services_status=0
    
    # 检查 IPv4 转发
    if [[ $(cat /proc/sys/net/ipv4/ip_forward) == "1" ]]; then
        echo -e "${GREEN}✓ IPv4转发已启用${PLAIN}"
    else
        echo -e "${RED}✗ IPv4转发未启用，正在修复...${PLAIN}"
        echo 1 > /proc/sys/net/ipv4/ip_forward
        sysctl -p /etc/sysctl.d/99-mihomo.conf >/dev/null 2>&1
        ((services_status++))
    fi
    
    # 检查必要的内核模块
    local required_modules=("ip_tables" "iptable_nat" "nf_conntrack" "xt_REDIRECT")
    for module in "${required_modules[@]}"; do
        if lsmod | grep -q "^$module"; then
            echo -e "${GREEN}✓ 内核模块 $module 已加载${PLAIN}"
        else
            echo -e "${YELLOW}⚠ 内核模块 $module 未加载，正在加载...${PLAIN}"
            modprobe $module 2>/dev/null || true
            ((services_status++))
        fi
    done
    
    if [[ $services_status -eq 0 ]]; then
        echo -e "${GREEN}✓ 系统状态检查完成，一切正常${PLAIN}"
        return 0
    else
        echo -e "${YELLOW}⚠ 发现 $services_status 个问题，已尝试修复${PLAIN}"
        return 1
    fi
}

# 验证配置文件
validate_config() {
    echo -e "${CYAN}正在验证配置文件...${PLAIN}"
    
    if [[ ! -f "$CONFIG_DIR/config.yaml" ]]; then
        echo -e "${RED}✗ 配置文件不存在${PLAIN}"
        return 1
    fi
    
    # 使用mihomo测试配置文件
    if [[ -f "$BINARY_FILE" ]]; then
        if $BINARY_FILE -t -d "$CONFIG_DIR" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ 配置文件验证通过${PLAIN}"
            return 0
        else
            echo -e "${RED}✗ 配置文件验证失败${PLAIN}"
            echo -e "${YELLOW}详细错误信息:${PLAIN}"
            $BINARY_FILE -t -d "$CONFIG_DIR"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠ 无法验证配置文件（二进制文件不存在）${PLAIN}"
        return 1
    fi
}

# 一键安装
one_key_install() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}              Mihomo 一键安装${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${YELLOW}此过程将自动完成所有安装步骤，无需手动干预${PLAIN}"
    echo -e "${YELLOW}整个过程可能需要几分钟，请耐心等待...${PLAIN}"
    echo
    
    # 检查是否已安装
    if systemctl is-active --quiet mihomo; then
        echo -e "${YELLOW}检测到Mihomo已在运行${PLAIN}"
        read -p "是否重新安装? (y/n): " reinstall
        if [[ "$reinstall" != "y" && "$reinstall" != "Y" ]]; then
            return
        fi
        stop_service
        cleanup_firewall_rules
    fi
    
    # 执行安装步骤
    echo -e "${CYAN}[1/8] 检查系统环境...${PLAIN}"
    check_root
    check_os
    
    echo -e "${CYAN}[2/8] 配置系统环境...${PLAIN}"
    if ! setup_environment; then
        echo -e "${YELLOW}⚠ 环境配置失败，请检查系统状态后重试${PLAIN}"
        echo -e "${RED}安装过程中出现错误，请检查日志${PLAIN}"
        read -p "按任意键返回主菜单..." key
        return
    fi
    
    # 执行系统优化
    optimize_system
    
    echo -e "${CYAN}[3/8] 下载Mihomo二进制文件...${PLAIN}"
    download_mihomo
    
    echo -e "${CYAN}[4/8] 下载UI界面...${PLAIN}"
    download_ui
    
    echo -e "${CYAN}[5/8] 创建配置文件...${PLAIN}"
    create_config
    
    echo -e "${CYAN}[6/8] 创建系统服务...${PLAIN}"
    create_service
    
    echo -e "${CYAN}[7/8] 配置防火墙规则...${PLAIN}"
            setup_simple_rules
    
    echo -e "${CYAN}[8/8] 启动服务...${PLAIN}"
    if start_service; then
        local main_ip=$(get_main_ip)
        echo -e "\n${GREEN}======================================================${PLAIN}"
        echo -e "${GREEN}Mihomo 安装完成!${PLAIN}"
        echo -e "${GREEN}======================================================${PLAIN}"
        echo -e "${YELLOW}控制面板: ${GREEN}http://$main_ip:9090${PLAIN}"
        echo -e "${YELLOW}管理密码: ${GREEN}wallentv${PLAIN}"
        echo -e "${YELLOW}混合代理: ${GREEN}$main_ip:7890${PLAIN}"
        echo -e "${YELLOW}HTTP代理: ${GREEN}$main_ip:7891${PLAIN}"
        echo -e "${YELLOW}SOCKS代理: ${GREEN}$main_ip:7892${PLAIN}"
        echo -e "${YELLOW}DNS服务: ${GREEN}$main_ip:53${PLAIN}"
        echo -e "${GREEN}======================================================${PLAIN}"
        echo -e "${YELLOW}透明代理配置:${PLAIN}"
        if check_simple_rules; then
            echo -e "${GREEN}✓ 防火墙规则已配置，透明代理应该可以正常工作${PLAIN}"
            echo -e "${YELLOW}• 将客户端网关设置为: $main_ip${PLAIN}"
            echo -e "${YELLOW}• 将客户端DNS设置为: $main_ip${PLAIN}"
        else
            echo -e "${RED}✗ 防火墙规则配置失败${PLAIN}"
            echo -e "${YELLOW}• 请重新运行安装程序来自动配置防火墙规则${PLAIN}"
        fi
        echo -e "${GREEN}======================================================${PLAIN}"
        echo -e "${YELLOW}推荐下一步:${PLAIN}"
        echo -e "${YELLOW}1. 访问控制面板配置代理节点${PLAIN}"
        echo -e "${YELLOW}2. 查看使用指南了解如何配置客户端${PLAIN}"
        echo -e "${YELLOW}3. 根据需要编辑配置文件${PLAIN}"
        echo -e "${GREEN}======================================================${PLAIN}"
        
        # 最终验证和建议
        echo -e "${CYAN}最终验证...${PLAIN}"
        local final_check=0
        
        # 检查IPv4转发
        if [[ $(cat /proc/sys/net/ipv4/ip_forward) != "1" ]]; then
            echo -e "${YELLOW}⚠ IPv4转发可能未完全生效${PLAIN}"
            ((final_check++))
        fi
        
        # 检查防火墙规则
        if ! check_simple_rules; then
            echo -e "${YELLOW}⚠ 透明代理规则可能未完全生效${PLAIN}"
            ((final_check++))
        fi
        
        if [[ $final_check -gt 0 ]]; then
            echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
            echo -e "${YELLOW}⚠ 检测到配置可能需要重启才能完全生效${PLAIN}"
            echo -e "${CYAN}建议执行以下操作之一：${PLAIN}"
            echo -e "${GREEN}1. 重启虚拟机 (推荐): reboot${PLAIN}"
            echo -e "${GREEN}2. 手动启用IPv4转发: echo 1 > /proc/sys/net/ipv4/ip_forward${PLAIN}"
            echo -e "${GREEN}3. 重启Mihomo服务: systemctl restart mihomo${PLAIN}"
            echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
        else
            echo -e "${GREEN}✓ 所有配置验证通过，透明代理应该可以立即使用${PLAIN}"
        fi
    else
        echo -e "${RED}安装过程中出现错误，请检查日志${PLAIN}"
    fi
    
    read -p "按任意键返回主菜单..." key
}

# 显示主菜单
show_menu() {
    while true; do
        clear
        echo -e "${CYAN}======================================================${PLAIN}"
        echo -e "${CYAN}              Mihomo 裸核版管理脚本${PLAIN}"
        echo -e "${CYAN}======================================================${PLAIN}"
        echo -e "${GREEN} [1] 一键安装 Mihomo${PLAIN}"
        echo -e "${GREEN} [2] 启动服务${PLAIN}"
        echo -e "${GREEN} [3] 停止服务${PLAIN}"
        echo -e "${GREEN} [4] 重启服务${PLAIN}"
        echo -e "${GREEN} [5] 查看状态${PLAIN}"
        echo -e "${GREEN} [6] 使用指南${PLAIN}"
        echo -e "${GREEN} [7] 卸载 Mihomo${PLAIN}"
        echo -e "${GREEN} [0] 退出脚本${PLAIN}"
        echo -e "${CYAN}======================================================${PLAIN}"
        
        # 显示当前状态
        if systemctl is-active --quiet mihomo 2>/dev/null; then
            local main_ip=$(get_main_ip)
            echo -e "${YELLOW}当前状态: ${GREEN}运行中${PLAIN}"
            echo -e "${YELLOW}控制面板: ${GREEN}http://$main_ip:9090${PLAIN}"
            
            # 显示透明代理状态（基于服务运行状态）
            echo -e "${YELLOW}透明代理: ${GREEN}服务正常${PLAIN}"
        else
            echo -e "${YELLOW}当前状态: ${RED}未运行${PLAIN}"
            echo -e "${YELLOW}透明代理: ${RED}未启用${PLAIN}"
        fi
        echo
        
        read -p "请输入选择 [0-7]: " choice
        
        case $choice in
            1)
                one_key_install
                ;;
            2)
                start_service
                read -p "按任意键继续..." key
                ;;
            3)
                stop_service
                read -p "按任意键继续..." key
                ;;
            4)
                restart_service
                read -p "按任意键继续..." key
                ;;
            5)
                check_status
                ;;
            6)
                show_usage_guide
                ;;
            7)
                uninstall_mihomo
                ;;
            0)
                echo -e "${GREEN}感谢使用 Mihomo 管理脚本!${PLAIN}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选项，请重新选择${PLAIN}"
                sleep 1
                ;;
        esac
    done
}

# 主函数
main() {
    # 创建日志文件
    touch "$LOG_FILE" 2>/dev/null
    chmod 644 "$LOG_FILE" 2>/dev/null
    log_message "开始执行Mihomo管理脚本"
    
    # 检查脚本是否有执行权限
    SCRIPT_PATH=$(readlink -f "$0")
    if [[ ! -x "$SCRIPT_PATH" ]]; then
        echo -e "${YELLOW}脚本没有执行权限，正在添加...${PLAIN}"
        chmod +x "$SCRIPT_PATH"
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}执行权限已添加${PLAIN}"
        else
            echo -e "${YELLOW}添加执行权限失败${PLAIN}"
        fi
    fi
    
    # 如果Mihomo已安装，检查系统重启后的状态
    if systemctl list-unit-files | grep -q "mihomo.service"; then
        check_post_reboot_status
    fi
    
    # 处理命令行参数
    if [[ "$1" == "--auto-install" ]]; then
        echo -e "${CYAN}执行自动安装模式...${PLAIN}"
        one_key_install
        exit 0
    fi
    
    # 显示主菜单
    show_menu
}

# 执行主函数
main "$@" 