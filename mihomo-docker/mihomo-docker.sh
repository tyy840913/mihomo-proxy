#!/bin/bash
#############################################################
# Mihomo 一键安装脚本 V1.0 (简化版)
# 支持系统: Debian 10/11/12, Ubuntu 20.04/22.04/24.04
# 功能: 一键安装并配置Mihomo代理服务 (无状态文件)
#############################################################

# 全局变量
script_dir=$(cd "$(dirname "$0")" && pwd)
FILES_DIR="$script_dir/files"
LOG_FILE="/var/log/mihomo_install.log"
PROXY_SCRIPT="$FILES_DIR/setup_proxy.sh"
ROUTER_SCRIPT="$FILES_DIR/setup_router.sh"
CHECK_SCRIPT="$FILES_DIR/check_status.sh"
CONFIG_TEMPLATE="$FILES_DIR/config.yaml"
CUSTOM_CONFIG="/etc/mihomo/config.yaml"
MAIN_INTERFACE=""

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
    if [[ -n "$message" ]]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOG_FILE"
    fi
}

# 错误处理函数
handle_error() {
    local error_message="$1"
    log_message "${RED}错误: $error_message${PLAIN}"
    echo -e "${RED}错误: $error_message${PLAIN}"
    exit 1
}

# 检查并安装jq
check_and_install_jq() {
    if ! command -v jq &> /dev/null; then
        echo -e "${CYAN}正在安装jq...${PLAIN}"
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y jq || handle_error "jq安装失败"
        elif command -v yum &> /dev/null; then
            yum install -y jq || handle_error "jq安装失败"
        elif command -v dnf &> /dev/null; then
            dnf install -y jq || handle_error "jq安装失败"
        elif command -v apk &> /dev/null; then
            apk add jq || handle_error "jq安装失败"
        else
            handle_error "无法安装jq，请手动安装"
        fi
        echo -e "${GREEN}jq安装成功${PLAIN}"
    fi
}

# 检查files目录
check_files_dir() {
    if [[ ! -d "$FILES_DIR" ]]; then
        echo -e "${YELLOW}创建files目录...${PLAIN}"
        mkdir -p "$FILES_DIR" || handle_error "无法创建目录 $FILES_DIR"
    fi
}

# 下载缺失文件
download_missing_files() {
    local github_base_url="https://raw.githubusercontent.com/wallentv/mihomo-proxy/master/mihomo-docker/files"
    local required_files=("setup_proxy.sh" "setup_router.sh" "check_status.sh" "config.yaml")
    local download_needed=0
    
    echo -e "${CYAN}检查必要文件...${PLAIN}"
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$FILES_DIR/$file" ]]; then
            echo -e "${YELLOW}缺失文件: $file${PLAIN}"
            download_needed=1
        fi
    done
    
    if [[ $download_needed -eq 0 ]]; then
        echo -e "${GREEN}所有必要文件已存在${PLAIN}"
        return 0
    fi
    
    # 检查下载工具
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        handle_error "系统中没有找到curl或wget，无法下载文件"
    fi
    
    echo -e "${CYAN}正在下载缺失文件...${PLAIN}"
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$FILES_DIR/$file" ]]; then
            echo -e "${CYAN}下载: $file${PLAIN}"
            
            if command -v curl &> /dev/null; then
                curl -fsSL "$github_base_url/$file" -o "$FILES_DIR/$file" || {
                    echo -e "${RED}下载失败: $file${PLAIN}"
                    return 1
                }
            else
                wget -q "$github_base_url/$file" -O "$FILES_DIR/$file" || {
                    echo -e "${RED}下载失败: $file${PLAIN}"
                    return 1
                }
            fi
            
            if [[ "$file" == *.sh ]]; then
                chmod +x "$FILES_DIR/$file"
            fi
            echo -e "${GREEN}✓ 下载成功: $file${PLAIN}"
        fi
    done
    
    echo -e "${GREEN}所有文件下载完成!${PLAIN}"
    return 0
}

# 检查执行脚本
check_exec_scripts() {
    check_files_dir
    
    if ! download_missing_files; then
        handle_error "文件下载失败，请检查网络连接"
    fi
    
    local scripts=("$PROXY_SCRIPT" "$ROUTER_SCRIPT" "$CHECK_SCRIPT")
    for script in "${scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            handle_error "缺少必要脚本: $(basename "$script")"
        fi
        chmod +x "$script"
    done
    
    if [[ ! -f "$CONFIG_TEMPLATE" ]]; then
        handle_error "缺少配置文件: config.yaml"
    fi
    
    return 0
}

# 检查操作系统
check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION_ID=$VERSION_ID
    else
        handle_error "无法检测操作系统"
    fi
    
    if [[ $OS != "debian" && $OS != "ubuntu" ]]; then
        handle_error "此脚本只支持 Debian 或 Ubuntu 系统"
    fi
    
    echo -e "${GREEN}检测到系统: $OS $VERSION_ID${PLAIN}"
}

# 网络检测
detect_network() {
    echo -e "${CYAN}检测网络环境...${PLAIN}"
    MAIN_INTERFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
    
    if [[ -z "$MAIN_INTERFACE" ]]; then
        MAIN_INTERFACE=$(ip -o -4 addr | grep -v "127.0.0.1" | awk '{print $2}' | head -n1)
        [[ -z "$MAIN_INTERFACE" ]] && MAIN_INTERFACE="eth0"
    fi
    
    if ! ip link show dev "$MAIN_INTERFACE" &>/dev/null; then
        echo -e "${RED}网络接口 $MAIN_INTERFACE 不存在${PLAIN}"
        read -p "请输入正确的网络接口名称: " MAIN_INTERFACE
        if ! ip link show dev "$MAIN_INTERFACE" &>/dev/null; then
            handle_error "指定的网络接口不存在"
        fi
    fi
    
    INTERFACE_IP=$(ip -o -4 addr show dev "$MAIN_INTERFACE" | awk '{print $4}' | cut -d/ -f1 | head -n1)
    [[ -z "$INTERFACE_IP" ]] && handle_error "无法获取网络接口IP地址"
    
    echo -e "${GREEN}网络接口: ${CYAN}$MAIN_INTERFACE${PLAIN}"
    echo -e "${GREEN}接口IP地址: ${CYAN}$INTERFACE_IP${PLAIN}"
}

# 显示主菜单
show_menu() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}          Mihomo 一键安装脚本 (简化版)${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    echo
    echo -e " ${GREEN}[1] 一键安装${PLAIN}"
    echo -e " ${GREEN}[2] 检查状态${PLAIN}"
    echo -e " ${GREEN}[3] 重启服务${PLAIN}"
    echo -e " ${GREEN}[4] 配置路由器${PLAIN}"
    echo -e " ${RED}[5] 卸载Mihomo${PLAIN}"
    echo -e " ${GREEN}[0] 退出脚本${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    read -p "请输入选择 [0-5]: " choice
    
    case $choice in
        1) one_key_install ;;
        2) check_status ;;
        3) restart_service ;;
        4) setup_router ;;
        5) uninstall_mihomo ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选项${PLAIN}"; sleep 1; show_menu ;;
    esac
}

# 一键安装
one_key_install() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}              Mihomo 一键安装${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    # 检查环境
    check_os
    detect_network
    check_exec_scripts
    
    # 安装Mihomo
    echo -e "${CYAN}正在安装Mihomo...${PLAIN}"
    bash "$PROXY_SCRIPT" || handle_error "Mihomo安装失败"
    
    echo -e "${GREEN}======================================================${PLAIN}"
    echo -e "${GREEN}Mihomo 安装成功!${PLAIN}"
    echo -e "${GREEN}======================================================${PLAIN}"
    echo -e "${YELLOW}控制面板: ${GREEN}http://${INTERFACE_IP}:9090/ui${PLAIN}"
    echo -e "${YELLOW}HTTP代理: ${GREEN}${INTERFACE_IP}:7891${PLAIN}"
    echo -e "${YELLOW}SOCKS5代理: ${GREEN}${INTERFACE_IP}:7892${PLAIN}"
    echo -e "${GREEN}======================================================${PLAIN}"
    
    read -p "按任意键返回主菜单..." key
    show_menu
}

# 检查状态
check_status() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}              Mihomo 服务状态${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    if [[ -f "$CHECK_SCRIPT" ]]; then
        bash "$CHECK_SCRIPT"
    else
        echo -e "${RED}状态检查脚本不存在${PLAIN}"
        
        # 基本状态检查
        if docker ps --filter "name=mihomo" --format "{{.Status}}" | grep -q "Up"; then
            echo -e "${GREEN}Mihomo容器正在运行${PLAIN}"
        else
            echo -e "${RED}Mihomo容器未运行${PLAIN}"
        fi
    fi
    
    read -p "按任意键返回主菜单..." key
    show_menu
}

# 重启服务
restart_service() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}              重启Mihomo服务${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    if [[ -f "$PROXY_SCRIPT" ]]; then
        bash "$PROXY_SCRIPT" restart
        echo -e "${GREEN}服务重启命令已执行${PLAIN}"
    else
        echo -e "${RED}代理脚本不存在${PLAIN}"
    fi
    
    read -p "按任意键返回主菜单..." key
    show_menu
}

# 配置路由器
setup_router() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}              路由器配置${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    if [[ -f "$ROUTER_SCRIPT" ]]; then
        bash "$ROUTER_SCRIPT"
    else
        echo -e "${RED}路由器配置脚本不存在${PLAIN}"
    fi
    
    read -p "按任意键返回主菜单..." key
    show_menu
}

# 卸载Mihomo
uninstall_mihomo() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${RED}              卸载Mihomo${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    echo -e "${YELLOW}警告: 此操作将完全移除Mihomo及其配置${PLAIN}"
    read -p "确定要卸载Mihomo吗? (y/n): " confirm
    
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        if [[ -f "$PROXY_SCRIPT" ]]; then
            bash "$PROXY_SCRIPT" uninstall
            echo -e "${GREEN}Mihomo已卸载${PLAIN}"
        else
            echo -e "${RED}代理脚本不存在，尝试手动卸载...${PLAIN}"
            docker rm -f mihomo &>/dev/null
            rm -rf /etc/mihomo
            echo -e "${GREEN}已尝试手动移除容器和配置${PLAIN}"
        fi
    else
        echo -e "${GREEN}已取消卸载操作${PLAIN}"
    fi
    
    read -p "按任意键返回主菜单..." key
    show_menu
}

# 主执行流程
check_os
detect_network
show_menu
