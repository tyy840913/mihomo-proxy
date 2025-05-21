#!/bin/bash
#############################################################
# RouterOS 配置脚本
# 此脚本将显示RouterOS配置命令及详细配置指南
#############################################################

# 设置颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 日志文件路径
LOG_FILE="/var/log/mihomo-router.log"

# 日志函数
log_message() {
    local level=$1
    local message=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" >> "$LOG_FILE"
}

# 错误处理函数
handle_error() {
    local error_msg=$1
    log_message "错误" "$error_msg"
    echo -e "${RED}$error_msg${PLAIN}"
    exit 1
}

# 配置信息 - 将从状态文件中读取
SCRIPT_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
FILES_DIR="$SCRIPT_DIR/files"
STATE_FILE="$FILES_DIR/mihomo_state.json"

# 获取状态值
get_state_value() {
    local key=$1
    if [[ ! -f "$STATE_FILE" ]]; then
        handle_error "错误: 状态文件不存在"
    fi
    
    local value=$(jq -r ".$key" "$STATE_FILE" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        handle_error "错误: 无法读取状态文件"
    fi
    
    echo "$value"
}

# 验证IP地址
validate_ip() {
    local ip=$1
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    
    IFS='.' read -r -a ip_parts <<< "$ip"
    for part in "${ip_parts[@]}"; do
        if [[ $part -lt 0 || $part -gt 255 ]]; then
            return 1
        fi
    done
    
    return 0
}

# 检查网络连接
check_network() {
    local ip=$1
    if ! ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
        echo -e "${YELLOW}警告: 无法ping通Mihomo IP，可能网络不可达${PLAIN}"
        return 1
    fi
    return 0
}

# 主函数
main() {
    # 创建日志文件
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    log_message "信息" "开始执行路由器配置脚本"
    
    # 获取Mihomo IP
    local mihomo_ip=$(get_state_value "mihomo_ip")
    if [[ -z "$mihomo_ip" ]]; then
        handle_error "错误: 未获取到Mihomo IP"
    fi
    
    # 验证IP地址
    if ! validate_ip "$mihomo_ip"; then
        handle_error "错误: IP地址格式无效"
    fi
    
    # 检查网络连接
    check_network "$mihomo_ip"
    
    # 显示RouterOS配置说明
    echo -e "\n${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}              RouterOS 配置命令及说明${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${YELLOW}Mihomo代理服务器信息:${PLAIN}"
    echo -e "${GREEN}● 服务器IP: $mihomo_ip${PLAIN}"
    echo -e "${GREEN}● 控制面板: http://$mihomo_ip:9090/ui${PLAIN}"
    echo -e "${GREEN}● 混合代理: $mihomo_ip:7890${PLAIN}"
    echo -e "${GREEN}● HTTP代理: $mihomo_ip:7891${PLAIN}"
    echo -e "${GREEN}● SOCKS5代理: $mihomo_ip:7892${PLAIN}"
    echo -e "${CYAN}------------------------------------------------------${PLAIN}"
    echo -e "${YELLOW}请将以下命令复制到RouterOS终端执行:${PLAIN}"
    echo -e "${CYAN}------------------------------------------------------${PLAIN}"
    
    # DNS设置
    echo -e "${GREEN}# 设置DNS服务器为Mihomo${PLAIN}"
    echo -e "${GREEN}/ip dns set servers=$mihomo_ip${PLAIN}"
    echo -e "${CYAN}------------------------------------------------------${PLAIN}"
    
    # 路由设置
    echo -e "${GREEN}# 添加198.18.0.1/16网段的路由${PLAIN}"
    echo -e "${GREEN}/ip route add dst-address=198.18.0.0/16 gateway=$mihomo_ip${PLAIN}"
    echo -e "${CYAN}------------------------------------------------------${PLAIN}"
    
    echo -e "${YELLOW}配置说明:${PLAIN}"
    echo -e "1. 第一条命令将DNS服务器设置为Mihomo代理"
    echo -e "2. 第二条命令将198.18.0.1/16网段的流量路由到Mihomo代理"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    log_message "信息" "路由器配置脚本执行完成"
}

# 执行主函数
main
