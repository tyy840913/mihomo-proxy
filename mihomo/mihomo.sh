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

# 手动选择架构
manual_architecture_selection() {
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}              手动选择架构版本${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${YELLOW}如果自动检测的架构不正确，请手动选择:${PLAIN}"
    echo
    echo -e "${GREEN} [1] amd64 (现代 AMD64 处理器，支持 v3 微架构)${PLAIN}"
    echo -e "${GREEN} [2] amd64-compatible (旧版 AMD64 处理器兼容版本)${PLAIN}"
    echo -e "${GREEN} [3] arm64 (ARM 64位处理器)${PLAIN}"
    echo -e "${GREEN} [4] armv7 (ARM 32位处理器)${PLAIN}"
    echo -e "${GREEN} [0] 使用自动检测${PLAIN}"
    echo
    
    read -p "请选择架构 [0-4]: " arch_choice
    
    case $arch_choice in
        1)
            echo "amd64"
            ;;
        2)
            echo "amd64-compatible"
            ;;
        3)
            echo "arm64"
            ;;
        4)
            echo "armv7"
            ;;
        0|*)
            detect_architecture
            ;;
    esac
}

# 系统修复函数
fix_system() {
    echo -e "${CYAN}正在修复系统包管理器问题...${PLAIN}"
    
    # 修复 dpkg 中断的安装
    echo -e "${CYAN}修复中断的包安装...${PLAIN}"
    dpkg --configure -a
    
    # 修复损坏的依赖关系
    echo -e "${CYAN}修复损坏的依赖关系...${PLAIN}"
    apt-get -f install -y
    
    # 清理包缓存
    echo -e "${CYAN}清理包缓存...${PLAIN}"
    apt-get clean
    apt-get autoclean
    
    # 更新包列表
    echo -e "${CYAN}更新包列表...${PLAIN}"
    apt-get update --fix-missing
    
    echo -e "${GREEN}✓ 系统修复完成${PLAIN}"
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
    apt install -y wget curl tar net-tools
    
    # 检查 systemctl 是否可用
    if ! command -v systemctl >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ systemctl 不可用，尝试安装 systemd${PLAIN}"
        apt install -y systemd
    fi
    
    # 开启IP转发
    echo -e "${CYAN}开启IP转发...${PLAIN}"
    # 检查是否已经设置过，避免重复添加
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    fi
    if ! grep -q "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf; then
        echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
    fi
    sysctl -p >/dev/null 2>&1
    
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

[Service]
Type=simple
User=root
ExecStart=$BINARY_FILE -d $CONFIG_DIR
Restart=always
RestartSec=5

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
    
    if systemctl stop mihomo; then
        echo -e "${GREEN}✓ Mihomo服务已停止${PLAIN}"
    else
        echo -e "${RED}✗ 停止服务失败${PLAIN}"
    fi
}

# 重启服务
restart_service() {
    echo -e "${CYAN}正在重启Mihomo服务...${PLAIN}"
    
    if systemctl restart mihomo; then
        sleep 3
        if systemctl is-active --quiet mihomo; then
            echo -e "${GREEN}✓ Mihomo服务重启成功${PLAIN}"
        else
            echo -e "${RED}✗ Mihomo服务重启失败${PLAIN}"
            echo -e "${YELLOW}查看错误日志: journalctl -u mihomo -n 20${PLAIN}"
        fi
    else
        echo -e "${RED}✗ 重启服务失败${PLAIN}"
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
    if [[ -f "$CONFIG_DIR/config.yaml" ]]; then
        echo -e "${GREEN}✓ 配置文件: 存在${PLAIN}"
    else
        echo -e "${RED}✗ 配置文件: 不存在${PLAIN}"
    fi
    
    # 检查二进制文件
    if [[ -f "$BINARY_FILE" ]]; then
        echo -e "${GREEN}✓ 二进制文件: 存在${PLAIN}"
        local version=$($BINARY_FILE -v 2>/dev/null | head -n1)
        echo -e "${YELLOW}• 版本: $version${PLAIN}"
    else
        echo -e "${RED}✗ 二进制文件: 不存在${PLAIN}"
    fi
    
    echo -e "\n${CYAN}最近日志:${PLAIN}"
    journalctl -u mihomo -n 5 --no-pager
    
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
    
    echo -e "${YELLOW}使用方法一: DNS + 路由设置（推荐用于部分设备代理）${PLAIN}"
    echo -e "${CYAN}1. 将设备DNS设置为: $main_ip${PLAIN}"
    echo -e "${CYAN}2. 添加路由规则:${PLAIN}"
    echo -e "   • 目标网段: 198.18.0.0/16"
    echo -e "   • 网关: $main_ip"
    echo
    
    echo -e "${YELLOW}使用方法二: 透明代理（推荐用于全局代理）${PLAIN}"
    echo -e "${CYAN}1. 将设备网关设置为: $main_ip${PLAIN}"
    echo -e "${CYAN}2. 将设备DNS设置为: $main_ip${PLAIN}"
    echo
    
    echo -e "${YELLOW}路由器配置示例:${PLAIN}"
    echo -e "${CYAN}# 添加静态路由（OpenWrt/LEDE）${PLAIN}"
    echo -e "ip route add 198.18.0.0/16 via $main_ip"
    echo
    echo -e "${CYAN}# 修改DHCP DNS服务器${PLAIN}"
    echo -e "uci set dhcp.@dnsmasq[0].server='$main_ip'"
    echo -e "uci commit dhcp"
    echo -e "/etc/init.d/dnsmasq restart"
    echo
    
    echo -e "${YELLOW}代理端口说明:${PLAIN}"
    echo -e "${CYAN}• 混合代理端口: $main_ip:7890 (HTTP + SOCKS5)${PLAIN}"
    echo -e "${CYAN}• HTTP代理端口: $main_ip:7891${PLAIN}"
    echo -e "${CYAN}• SOCKS5代理端口: $main_ip:7892${PLAIN}"
    echo
    
    echo -e "${YELLOW}配置文件位置:${PLAIN}"
    echo -e "${CYAN}• 主配置: $CONFIG_DIR/config.yaml${PLAIN}"
    echo -e "${CYAN}• 编辑命令: nano $CONFIG_DIR/config.yaml${PLAIN}"
    echo -e "${CYAN}• 重启生效: systemctl restart mihomo${PLAIN}"
    
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
    fi
    
    # 执行安装步骤
    echo -e "${CYAN}[1/7] 检查系统环境...${PLAIN}"
    check_root
    check_os
    
    echo -e "${CYAN}[2/7] 配置系统环境...${PLAIN}"
    if ! setup_environment; then
        echo -e "${YELLOW}⚠ 环境配置失败，尝试系统修复...${PLAIN}"
        fix_system
        setup_environment
    fi
    
    echo -e "${CYAN}[3/7] 下载Mihomo二进制文件...${PLAIN}"
    download_mihomo
    
    echo -e "${CYAN}[4/7] 下载UI界面...${PLAIN}"
    download_ui
    
    echo -e "${CYAN}[5/7] 创建配置文件...${PLAIN}"
    create_config
    
    echo -e "${CYAN}[6/7] 创建系统服务...${PLAIN}"
    create_service
    
    echo -e "${CYAN}[7/7] 启动服务...${PLAIN}"
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
        echo -e "${YELLOW}推荐下一步:${PLAIN}"
        echo -e "${YELLOW}1. 访问控制面板配置代理节点${PLAIN}"
        echo -e "${YELLOW}2. 查看使用指南了解如何配置客户端${PLAIN}"
        echo -e "${YELLOW}3. 根据需要编辑配置文件${PLAIN}"
        echo -e "${GREEN}======================================================${PLAIN}"
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
        echo -e "${GREEN} [7] 系统修复${PLAIN}"
        echo -e "${GREEN} [8] 手动选择架构重装${PLAIN}"
        echo -e "${GREEN} [9] 卸载 Mihomo${PLAIN}"
        echo -e "${GREEN} [0] 退出脚本${PLAIN}"
        echo -e "${CYAN}======================================================${PLAIN}"
        
        # 显示当前状态
        if systemctl is-active --quiet mihomo 2>/dev/null; then
            local main_ip=$(get_main_ip)
            echo -e "${YELLOW}当前状态: ${GREEN}运行中${PLAIN}"
            echo -e "${YELLOW}控制面板: ${GREEN}http://$main_ip:9090${PLAIN}"
        else
            echo -e "${YELLOW}当前状态: ${RED}未运行${PLAIN}"
        fi
        echo
        
        read -p "请输入选择 [0-9]: " choice
        
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
                fix_system
                ;;
            8)
                # 手动选择架构重装
                clear
                echo -e "${CYAN}======================================================${PLAIN}"
                echo -e "${CYAN}              手动选择架构重装${PLAIN}"
                echo -e "${CYAN}======================================================${PLAIN}"
                
                # 停止现有服务
                if systemctl is-active --quiet mihomo; then
                    stop_service
                fi
                
                # 删除现有二进制文件
                if [[ -f "$BINARY_FILE" ]]; then
                    rm -f "$BINARY_FILE"
                    echo -e "${GREEN}✓ 已删除现有二进制文件${PLAIN}"
                fi
                
                # 手动选择架构
                local selected_arch=$(manual_architecture_selection)
                echo -e "${GREEN}选择的架构: $selected_arch${PLAIN}"
                
                # 重新下载
                echo -e "${CYAN}正在重新下载 Mihomo...${PLAIN}"
                
                # 临时覆盖架构检测函数
                detect_architecture() {
                    echo "$selected_arch"
                }
                
                download_mihomo
                start_service
                
                read -p "按任意键继续..." key
                ;;
            9)
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
    
    # 处理 --auto-install 参数
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