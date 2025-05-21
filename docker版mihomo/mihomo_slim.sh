#!/bin/bash
#############################################################
# Mihomo 一键安装引导脚本 V1.0 (简化版)
# 支持系统: Debian 10/11/12, Ubuntu 20.04/22.04/24.04
# 功能: 将普通 Debian/Ubuntu 服务器转变为 mihomo 代理机
#############################################################

# ====================================================================================
# 【安装说明】
# 
# 1. 将本脚本放置到 /opt 目录下:
#    wget -O /opt/mihomo.sh https://your-download-url/mihomo.sh
#    或者: 
#    curl -o /opt/mihomo.sh https://your-download-url/mihomo.sh
#
# 2. 运行脚本:
#    bash /opt/mihomo.sh
#    
#    注意: 脚本会自动检查权限并帮助您获取root权限
# ====================================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
PLAIN='\033[0m'

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="$SCRIPT_DIR/files"

# 日志文件
LOG_FILE="$SCRIPT_DIR/install.log"

# 日志函数
log_message() {
    local message="$1"
    
    # 跳过空消息
    if [[ -z "$message" ]]; then
        return 0
    fi
    
    # 添加时间戳并写入日志文件
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOG_FILE"
}

# 错误处理函数
handle_error() {
    local error_message="$1"
    log_message "${RED}错误: $error_message${PLAIN}"
    exit 1
}

# 状态文件版本
STATE_VERSION="1.0"

# 状态文件路径
STATE_FILE="$FILES_DIR/mihomo_state.json"
PROXY_SCRIPT="$FILES_DIR/setup_proxy.sh"
ROUTER_SCRIPT="$FILES_DIR/setup_router.sh"
CHECK_SCRIPT="$FILES_DIR/check_status.sh"
CONFIG_TEMPLATE="$FILES_DIR/config.yaml"

# 状态验证函数
validate_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        handle_error "状态文件不存在"
        return 1
    fi

    # 检查状态文件版本
    local version=$(jq -r '.version // ""' "$STATE_FILE")
    if [[ -z "$version" ]]; then
        # 添加版本号
        jq --arg ver "$STATE_VERSION" '. + {"version": $ver}' "$STATE_FILE" > "${STATE_FILE}.tmp"
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
    elif [[ "$version" != "$STATE_VERSION" ]]; then
        handle_error "状态文件版本不匹配，请重新初始化"
        return 1
    fi

    # 检查必要字段
    local required_fields=("mihomo_ip" "installation_stage" "timestamp")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$STATE_FILE" >/dev/null 2>&1; then
            handle_error "状态文件缺少必要字段: $field"
            return 1
        fi
    done

    return 0
}

# 状态备份函数
backup_state() {
    # 禁用常规备份，不再创建备份文件
    return 0
    
    # 以下代码已禁用
    # 如果状态文件不存在，直接返回
    if [[ ! -f "$STATE_FILE" ]]; then
        return 0
    fi
    
    local backup_file="${STATE_FILE}.bak.$(date '+%Y%m%d%H%M%S')"
    cp "$STATE_FILE" "$backup_file" &> /dev/null
    # 不记录每次备份的日志，减少日志噪音
}

# 状态恢复函数
restore_state() {
    local backup_file=$1
    if [[ -f "$backup_file" ]]; then
        cp "$backup_file" "$STATE_FILE"
        log_message "INFO" "状态已从备份恢复: $backup_file"
        return 0
    fi
    return 1
}

# 处理命令行参数
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo -e "Mihomo 一键安装引导脚本 V1.0 使用说明"
    echo -e "=============================================================="
    echo -e "使用方法: sudo bash mihomo.sh [选项]"
    echo -e ""
    echo -e "选项:"
    echo -e "  无参数   启动交互式安装向导"
    echo -e "  -h, --help  显示此帮助信息"
    echo -e ""
    echo -e "安装流程:"
    echo -e "  1. 设置代理机IP地址 - 为mihomo选择一个局域网IP (自动执行)"
    echo -e "  2. 配置代理机 - 安装Docker和mihomo，设置网络"
    echo -e "  3. 配置路由器 - 生成路由器配置命令"
    echo -e ""
    echo -e "系统要求:"
    echo -e "  - Debian 10/11/12"
    echo -e "  - Ubuntu 20.04/22.04/24.04"
    echo -e "  - 需要root权限"
    echo -e ""
    echo -e "备注:"
    echo -e "  - 控制面板默认访问地址: http://<mihomo-ip>:9090/ui"
    echo -e "  - 代理默认端口: 7890(混合), 7891(HTTP), 7892(SOCKS5)"
    echo -e "=============================================================="
    exit 0
fi

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
FILES_DIR="$SCRIPT_DIR/files"
CONF_DIR="/etc/mihomo"

# 检查files目录是否存在
if [[ ! -d "$FILES_DIR" ]]; then
    echo -e "${RED}错误: files目录不存在${PLAIN}"
    echo -e "${RED}files目录用于存放执行脚本和相关配置文件，请确保该目录存在${PLAIN}"
    exit 1
fi

# 检查执行脚本是否存在
check_exec_scripts() {
    # 检查所需的执行脚本
    local scripts=("$PROXY_SCRIPT" "$ROUTER_SCRIPT" "$CHECK_SCRIPT")
    local missing=0
    
    for script in "${scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            echo -e "${RED}错误: 找不到脚本: $script${PLAIN}"
            missing=1
        else
            # 确保脚本可执行
            chmod +x "$script"
        fi
    done
    
    if [[ $missing -eq 1 ]]; then
        echo -e "${RED}错误: 缺少必要的执行脚本。请确保以下脚本文件存在于 $FILES_DIR 目录:${PLAIN}"
        echo -e "${YELLOW}- setup_proxy.sh${PLAIN}"
        echo -e "${YELLOW}- setup_router.sh${PLAIN}"
        echo -e "${YELLOW}- check_status.sh${PLAIN}"
        exit 1
    fi
    
    return 0
}

# 检查是否具有root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}警告: 当前非root用户，需要root权限才能继续安装${PLAIN}"
        echo -e "${CYAN}尝试获取root权限...${PLAIN}"
        
        # 检查是否有sudo命令
        if command -v sudo &> /dev/null; then
            echo -e "${CYAN}已检测到sudo命令，尝试使用sudo执行脚本...${PLAIN}"
            
            # 询问用户是否自动提权
            read -p "是否自动使用sudo重新执行此脚本? (y/n): " auto_sudo
            if [[ "$auto_sudo" == "y" || "$auto_sudo" == "Y" ]]; then
                echo -e "${GREEN}正在使用sudo重新执行脚本...${PLAIN}"
                
                # 获取当前脚本的绝对路径
                SCRIPT_PATH=$(readlink -f "$0")
                
                # 如果脚本没有执行权限，自动添加
                if [[ ! -x "$SCRIPT_PATH" ]]; then
                    echo -e "${CYAN}脚本没有执行权限，正在添加...${PLAIN}"
                    sudo chmod +x "$SCRIPT_PATH"
                fi
                
                # 使用sudo重新执行脚本，保持原始参数
                exec sudo bash "$SCRIPT_PATH" "$@"
            else
                echo -e "${YELLOW}请以root权限运行此脚本:${PLAIN}"
                echo -e "${CYAN}方法1: ${GREEN}sudo bash $0${PLAIN}"
                echo -e "${CYAN}方法2: ${GREEN}sudo su${PLAIN} 然后 ${GREEN}bash $0${PLAIN}"
                exit 1
            fi
        else
            echo -e "${YELLOW}系统中没有发现sudo命令，请尝试以下方法获取root权限:${PLAIN}"
            echo -e "${CYAN}方法1: ${GREEN}su -${PLAIN} 输入root密码后执行 ${GREEN}bash $0${PLAIN}"
            echo -e "${CYAN}方法2: 重新登录为root用户后执行脚本${PLAIN}"
            echo -e "${CYAN}方法3: ${GREEN}chmod +x $0${PLAIN} 然后以root用户执行 ${GREEN}./$0${PLAIN}"
            exit 1
        fi
    fi
}

# 检查操作系统
check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION_ID=$VERSION_ID
    else
        echo -e "${RED}错误: 无法检测操作系统${PLAIN}"
        exit 1
    fi
    
    if [[ $OS != "debian" && $OS != "ubuntu" ]]; then
        echo -e "${RED}错误: 此脚本只支持 Debian 或 Ubuntu 系统${PLAIN}"
        exit 1
    fi
    
    echo -e "${GREEN}检测到系统: $OS $VERSION_ID${PLAIN}"
}

# 网络接口检测
detect_network() {
    echo -e "${CYAN}正在检测网络环境...${PLAIN}"
    # 检测主网络接口
    MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
    if [[ -z "$MAIN_INTERFACE" ]]; then
        echo -e "${RED}错误: 无法检测到默认网络接口${PLAIN}"
        exit 1
    fi
    
    # 获取当前IP和网段
    CURRENT_IP=$(ip -4 addr show $MAIN_INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
    if [[ -z "$CURRENT_IP" ]]; then
        echo -e "${RED}错误: 无法获取网络接口 $MAIN_INTERFACE 的IP地址${PLAIN}"
        exit 1
    fi
    
    GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n 1)
    SUBNET_PREFIX=$(echo $CURRENT_IP | cut -d '.' -f 1,2,3)
    
    echo -e "${GREEN}检测到网络接口: $MAIN_INTERFACE${PLAIN}"
    echo -e "${GREEN}当前IP地址: $CURRENT_IP${PLAIN}"
    echo -e "${GREEN}网关地址: $GATEWAY${PLAIN}"
    echo -e "${GREEN}网段前缀: $SUBNET_PREFIX.x${PLAIN}"
}

# 初始化状态文件
init_state_file() {
    # 确保 FILES_DIR 目录存在
    if [[ ! -d "$FILES_DIR" ]]; then
        mkdir -p "$FILES_DIR"
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}错误: 无法创建目录 $FILES_DIR${PLAIN}"
            exit 1
        fi
        echo -e "${GREEN}已创建目录: $FILES_DIR${PLAIN}"
    fi
    
    if [[ ! -f "$STATE_FILE" ]]; then
        cat > "$STATE_FILE" << EOF
{
  "version": "$STATE_VERSION",
  "mihomo_ip": "",
  "interface_ip": "",
  "main_interface": "$MAIN_INTERFACE",
  "macvlan_interface": "mihomo_veth",
  "installation_stage": "初始化",
  "config_type": "",
  "docker_method": "direct_pull",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF
        log_message "INFO" "初始化状态文件"
    else
        log_message "INFO" "发现现有配置状态文件"
        if ! validate_state; then
            handle_error "状态文件验证失败"
            return 1
        fi
    fi
}

# 从状态文件读取值
get_state_value() {
    local key=$1
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "" 
        return 1 # File doesn't exist
    fi
    local value
    value=$(jq -r --arg key_jq "$key" '.[$key_jq] // ""' "$STATE_FILE" 2>/dev/null)
    # Check jq's exit status.
    if [[ $? -ne 0 ]]; then
        echo -e "${YELLOW}警告: 无法从状态文件 $STATE_FILE 中使用jq读取 '$key'。${PLAIN}" >&2
        # Fallback to grep for basic cases
        value=$(grep -o "\"$key\": *\"[^\"]*\"" "$STATE_FILE" | sed -E 's/.*"[^"]+":[[:space:]]*"([^"]*)".*/\1/')
        echo "$value"
    else
        echo "$value"
    fi
}

# 更新状态文件中的值
update_state() {
    local key=$1
    local value=$2
    
    # 如果状态文件不存在，创建它
    if [[ ! -f "$STATE_FILE" ]]; then
        echo -e "${YELLOW}状态文件不存在，创建新的状态文件...${PLAIN}"
        # 确保目录存在
        mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null
        # 创建基本状态文件
        cat > "$STATE_FILE" << EOF
{
  "version": "$STATE_VERSION",
  "mihomo_ip": "",
  "interface_ip": "",
  "main_interface": "$MAIN_INTERFACE",
  "macvlan_interface": "mihomo_veth",
  "installation_stage": "初始化",
  "config_type": "",
  "docker_method": "direct_pull",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF
        echo -e "${GREEN}已创建新的状态文件: $STATE_FILE${PLAIN}"
        chmod 644 "$STATE_FILE"
    fi
    
    # 获取当前值，如果相同则不更新
    local current_value=$(get_state_value "$key")
    if [[ "$current_value" == "$value" ]]; then
        # 值相同，不需要更新
        return 0
    fi
    
    # 备份当前状态
    backup_state
    
    # 使用 jq 更新状态
    echo -e "${CYAN}更新状态 $key = $value${PLAIN}"
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}警告: 未安装jq，使用临时方法更新状态${PLAIN}"
        # 如果没有jq，使用临时替代方法
        sed -i "s/\"$key\": *\"[^\"]*\"/\"$key\": \"$value\"/" "$STATE_FILE"
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}状态更新失败: $key = $value${PLAIN}"
            return 1
        fi
    else
        # 使用jq更新
        jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$STATE_FILE" > "${STATE_FILE}.tmp"
        if [[ $? -eq 0 ]]; then
            mv "${STATE_FILE}.tmp" "$STATE_FILE"
        else
            echo -e "${RED}状态更新失败: $key = $value${PLAIN}"
            restore_state "${STATE_FILE}.bak.$(date '+%Y%m%d%H%M%S')"
            return 1
        fi
    fi
    
    # 只有对重要的状态变更才记录日志
    if [[ "$key" == "mihomo_ip" || "$key" == "installation_stage" ]]; then
        log_message "INFO: 更新状态: $key = $value"
        echo -e "${GREEN}已更新状态: $key = $value${PLAIN}"
    fi
    
    return 0
}

# 查找可用的IP地址
find_available_ip() {
    local prefix=$1
    local start=$2
    local end=$3

    echo -e "${CYAN}正在检查网段 ${prefix}.${start}-${end} 中的可用IP...${PLAIN}"

    for i in $(seq $start $end); do
        local ip="${prefix}.${i}"

        # 跳过网关IP
        if [[ "$ip" == "$GATEWAY" ]]; then
            continue
        fi

        # 跳过当前主机IP
        if [[ "$ip" == "$CURRENT_IP" ]]; then
            continue
        fi

        # 检查IP是否已被使用
        if ping -c 1 -W 1 "$ip" &> /dev/null; then
            continue
        fi

        echo -e "${GREEN}找到可用IP: $ip${PLAIN}"
        echo "$ip"
        return 0
    done

    echo -e "${RED}在指定范围内没有找到可用IP${PLAIN}"
    return 1
}

# 交互式设置mihomo IP
setup_mihomo_ip() {
    local stored_ip=$(get_state_value "mihomo_ip")
    
    if [[ -n "$stored_ip" ]]; then
        read -p "检测到之前配置的mihomo IP: $stored_ip, 是否使用此IP? (y/n): " use_stored
        if [[ "$use_stored" == "y" || "$use_stored" == "Y" ]]; then
            MIHOMO_IP=$stored_ip
            return 0
        fi
    fi
    
    # 自动检测合适的IP
    local suggested_ip="${SUBNET_PREFIX}.4"
    if ping -c 1 -W 1 "$suggested_ip" &> /dev/null; then
        # 如果默认IP已使用，寻找可用IP
        for i in {5..20}; do
            local check_ip="${SUBNET_PREFIX}.$i"
            if ! ping -c 1 -W 1 "$check_ip" &> /dev/null; then
                suggested_ip=$check_ip
                break
            fi
        done
    fi
    
    echo -e "${CYAN}请为mihomo选择一个IP地址${PLAIN}"
    echo -e "${CYAN}此IP必须与您的局域网在同一网段，并且不能与现有设备冲突${PLAIN}"
    echo -e "${CYAN}建议使用: ${suggested_ip}${PLAIN}"
    
    read -p "请输入mihomo的IP地址 [默认: ${suggested_ip}]: " MIHOMO_IP
    MIHOMO_IP=${MIHOMO_IP:-$suggested_ip}
    
    # 验证IP格式
    if ! [[ $MIHOMO_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}错误: 无效的IP地址格式${PLAIN}"
        setup_mihomo_ip
        return
    fi
    
    # 检查IP是否已被使用
    if ping -c 1 -W 1 "$MIHOMO_IP" &> /dev/null; then
        echo -e "${RED}错误: IP地址 $MIHOMO_IP 已被使用${PLAIN}"
        setup_mihomo_ip
        return
    fi
    
    echo -e "${GREEN}将使用 $MIHOMO_IP 作为mihomo的IP地址${PLAIN}"
    # 确保状态文件存在
    if [[ ! -f "$STATE_FILE" ]]; then
        echo -e "${YELLOW}状态文件不存在，初始化状态文件...${PLAIN}"
        init_state_file
    fi
    
    # 更新状态文件
    update_state "mihomo_ip" "$MIHOMO_IP"
    echo -e "${GREEN}已将 mihomo_ip 更新为 $MIHOMO_IP${PLAIN}"
    
    # 设置接口IP (mihomo IP + 1)
    local ip_parts=(${MIHOMO_IP//./ })
    local last_octet=$((ip_parts[3] + 1))
    INTERFACE_IP="${ip_parts[0]}.${ip_parts[1]}.${ip_parts[2]}.$last_octet"
    
    # 验证接口IP是否可用
    if ping -c 1 -W 1 "$INTERFACE_IP" &> /dev/null; then
        echo -e "${RED}错误: 计算得出的接口IP ($INTERFACE_IP) 已被占用。请重新设置Mihomo IP。${PLAIN}"
        setup_mihomo_ip
        return
    fi
    
    update_state "interface_ip" "$INTERFACE_IP"
    echo -e "${GREEN}已将 interface_ip 更新为 $INTERFACE_IP${PLAIN}"
    
    update_state "main_interface" "$MAIN_INTERFACE"
    update_state "macvlan_interface" "mihomo_veth"
    
    # 检查状态文件是否已更新
    echo -e "${CYAN}检查状态文件更新...${PLAIN}"
    local check_ip=$(get_state_value "mihomo_ip")
    if [[ "$check_ip" == "$MIHOMO_IP" ]]; then
        echo -e "${GREEN}状态文件更新成功${PLAIN}"
    else
        echo -e "${RED}警告: 状态文件似乎未正确更新，请检查文件权限或路径${PLAIN}"
        echo -e "${YELLOW}状态文件路径: $STATE_FILE${PLAIN}"
        ls -la "$(dirname "$STATE_FILE")" 2>/dev/null || echo "无法访问目录"
    fi
}

# 检查配置文件是否存在
check_config_template() {
    if [[ ! -f "$CONFIG_TEMPLATE" ]]; then
        echo -e "${CYAN}检查配置文件模板...${PLAIN}"
        
        # 尝试在不同位置寻找配置文件
        local config_locations=(
            "$FILES_DIR/config.yaml"
            "$SCRIPT_DIR/config.yaml"
            "$HOME/mihomo-proxy/config.yaml"
        )
        
        local found=0
        for loc in "${config_locations[@]}"; do
            if [[ -f "$loc" ]]; then
                echo -e "${GREEN}使用配置文件: $loc${PLAIN}"
                cp "$loc" "$CONFIG_TEMPLATE"
                found=1
                break
            fi
        done
        
        if [[ $found -eq 0 ]]; then
            echo -e "${RED}错误: 未找到配置模板文件${PLAIN}"
            echo -e "${YELLOW}请在以下位置之一放置config.yaml文件:${PLAIN}"
            for loc in "${config_locations[@]}"; do
                echo -e "  - $loc"
            done
            return 1
        fi
        
        echo -e "${GREEN}配置文件模板已准备: $CONFIG_TEMPLATE${PLAIN}"
    fi
    return 0
}

# 显示主菜单
show_menu() {
    clear
    
    # 获取当前状态
    local mihomo_ip=$(get_state_value "mihomo_ip")
    local stage=$(get_state_value "installation_stage")
    local timestamp=$(get_state_value "timestamp")
    
    # 标题
    echo -e "${CYAN}===========================================================${PLAIN}"
    echo -e "${CYAN}              Mihomo 一键安装引导脚本${PLAIN}"
    echo -e "${CYAN}===========================================================${PLAIN}"
    echo -e "${CYAN}请按步骤完成安装:${PLAIN}"
    echo
    
    # 步骤1: 初始化
    if [[ -n "$mihomo_ip" ]]; then
        echo -e " ${GREEN}[✓] 1. 初始化设置${PLAIN}    - ${GREEN}步骤1完成! Mihomo IP地址: $mihomo_ip${PLAIN}"
    else
        echo -e " ${CYAN}[1] 1. 初始化设置${PLAIN}    - ${YELLOW}设置mihomo的IP地址并检查配置脚本 ${RED}[未完成]${PLAIN}"
    fi
    
    # 步骤2: 代理机配置
    if [[ "$stage" == "Step2_Completed" ]]; then
        echo -e " ${GREEN}[✓] 2. 配置代理机${PLAIN}    - ${GREEN}步骤2完成! Mihomo代理已安装并启动${PLAIN}"
    elif [[ "$stage" == "Step1_Completed" || "$stage" == "Step2_"* ]]; then
        echo -e " ${CYAN}[2] 2. 配置代理机${PLAIN}    - ${YELLOW}安装Docker和Mihomo，配置网络${PLAIN}"
    else
        echo -e " ${GRAY}[2] 2. 配置代理机${PLAIN}    - ${GRAY}请先完成步骤1${PLAIN}"
    fi
    
    # 步骤3: 路由器配置
    if [[ "$stage" == "Step2_Completed" ]]; then
        echo -e " ${CYAN}[3] 3. 路由器配置${PLAIN}    - ${YELLOW}生成路由器配置命令${PLAIN}"
    else
        echo -e " ${GRAY}[3] 3. 路由器配置${PLAIN}    - ${GRAY}请先完成步骤2${PLAIN}"
    fi
    
    echo -e "${CYAN}----------------------------------------------------------${PLAIN}"
    echo -e " ${GREEN}[4] 4. 重启Mihomo服务${PLAIN}  - ${YELLOW}重启Mihomo代理服务${PLAIN}"
    echo -e " ${GREEN}[5] 5. 检查安装状态${PLAIN}  - ${YELLOW}检查Mihomo安装和运行状态${PLAIN}"
    echo -e " ${RED}[6] 6. 卸载Mihomo${PLAIN}  - ${YELLOW}完全卸载Mihomo及其配置${PLAIN}"
    echo -e " ${GREEN}[0] 0. 退出脚本${PLAIN}"
    echo -e "${CYAN}===========================================================${PLAIN}"
    
    # 显示当前状态
    if [[ -n "$mihomo_ip" ]]; then
        echo -e "${YELLOW}系统信息:${PLAIN}"
        echo -e "${YELLOW}• Mihomo IP: ${GREEN}$mihomo_ip${PLAIN}"
        echo -e "${YELLOW}• 安装阶段: ${GREEN}$stage${PLAIN}"
        echo -e "${YELLOW}• 更新时间: ${GREEN}$timestamp${PLAIN}"
        if [[ "$stage" == "Step2_Completed" ]]; then
            echo -e "${YELLOW}• 控制面板: ${GREEN}http://$mihomo_ip:9090/ui${PLAIN}"
        fi
    fi
    echo
    
    read -p "请输入选择 [0-6]: " choice
    
    case $choice in
        1)
            # 初始化设置
            clear
            echo -e "${CYAN}======================================================${PLAIN}"
            echo -e "${CYAN}              步骤1: 初始化设置${PLAIN}"
            echo -e "${CYAN}======================================================${PLAIN}"
            echo -e "${YELLOW}这一步将设置mihomo的IP地址并检查配置脚本${PLAIN}"
            echo
            
            local mihomo_ip=$(get_state_value "mihomo_ip")
            if [[ -n "$mihomo_ip" ]]; then
                echo -e "${YELLOW}检测到已有配置: IP = $mihomo_ip${PLAIN}"
                read -p "是否重新设置IP地址? (y/n): " reset_ip
                if [[ "$reset_ip" == "y" || "$reset_ip" == "Y" ]]; then
                    echo -e "${CYAN}正在重新设置IP地址...${PLAIN}"
                else
                    echo -e "${YELLOW}保留已有配置，返回主菜单...${PLAIN}"
                    sleep 1
                    show_menu
                    return
                fi
            fi
            
            # 设置mihomo IP地址
            setup_mihomo_ip
            
            # 检查配置脚本是否存在
            if ! check_exec_scripts; then
                echo -e "${RED}错误: 缺少执行脚本文件。请确保以下脚本文件存在:${PLAIN}"
                echo -e "${YELLOW}- $PROXY_SCRIPT${PLAIN}"
                echo -e "${YELLOW}- $ROUTER_SCRIPT${PLAIN}"
                echo -e "${YELLOW}- $CHECK_SCRIPT${PLAIN}"
                read -p "按任意键继续..." key
                return 1
            else
                echo -e "${GREEN}所有执行脚本已就绪${PLAIN}"
            fi
            
            mihomo_ip=$(get_state_value "mihomo_ip")
            echo -e "\n${GREEN}======================================================${PLAIN}"
            echo -e "${GREEN}步骤1完成! Mihomo IP地址: ${YELLOW}$mihomo_ip${PLAIN}"
            echo -e "${GREEN}现在您可以进行步骤2: 配置代理机${PLAIN}"
            echo -e "${GREEN}======================================================${PLAIN}"
            
            # 更新安装阶段状态
            update_state "installation_stage" "Step1_Completed"
            
            read -p "按任意键返回主菜单..." key
            show_menu
            ;;
        2)
            # 配置代理机
            local mihomo_ip=$(get_state_value "mihomo_ip")
            local stage=$(get_state_value "installation_stage")
            
            # 检查是否已完成初始化
            if [[ -z "$mihomo_ip" ]]; then
                echo -e "${YELLOW}======================================================${PLAIN}"
                echo -e "${YELLOW}您需要先完成步骤1: 初始化设置${PLAIN}"
                echo -e "${YELLOW}======================================================${PLAIN}"
                read -p "是否立即进行初始化? (y/n): " do_init
                if [[ "$do_init" == "y" || "$do_init" == "Y" ]]; then
                    echo -e "${CYAN}正在跳转到步骤1...${PLAIN}"
                    sleep 1
                    
                    # 调用选项1的逻辑
                    clear
                    echo -e "${CYAN}======================================================${PLAIN}"
                    echo -e "${CYAN}              步骤1: 初始化设置${PLAIN}"
                    echo -e "${CYAN}======================================================${PLAIN}"
                    echo -e "${YELLOW}这一步将设置mihomo的IP地址并检查配置脚本${PLAIN}"
                    echo
                    
                    # 设置mihomo IP地址
                    setup_mihomo_ip
                    
                    # 检查配置脚本是否存在
                    if ! check_exec_scripts; then
                        echo -e "${RED}错误: 缺少执行脚本文件${PLAIN}"
                        read -p "按任意键继续..." key
                        return 1
                    fi
                    
                    mihomo_ip=$(get_state_value "mihomo_ip")
                    echo -e "\n${GREEN}======================================================${PLAIN}"
                    echo -e "${GREEN}步骤1完成! Mihomo IP地址: ${YELLOW}$mihomo_ip${PLAIN}"
                    echo -e "${GREEN}现在继续步骤2: 配置代理机${PLAIN}"
                    echo -e "${GREEN}======================================================${PLAIN}"
                    sleep 1
                else
                    show_menu
                    return
                fi
            fi
            
            # 执行代理机配置
            clear
            echo -e "${CYAN}======================================================${PLAIN}"
            echo -e "${CYAN}              步骤2: 配置代理机${PLAIN}"
            echo -e "${CYAN}======================================================${PLAIN}"
            
            if [[ -f "$PROXY_SCRIPT" ]]; then
                echo -e "${CYAN}正在安装Docker和Mihomo...${PLAIN}"
                echo -e "${YELLOW}此过程可能需要几分钟，请耐心等待...${PLAIN}"
                echo
                bash "$PROXY_SCRIPT"
                
                # 检查是否使用了预设配置
                if [[ "$(get_state_value "config_type")" == "preset" ]]; then
                    echo -e "\n${YELLOW}======================================================${PLAIN}"
                    echo -e "${YELLOW}重要提示${PLAIN}"
                    echo -e "${YELLOW}======================================================${PLAIN}"
                    echo -e "${YELLOW}您正在使用预设配置文件，该配置仅供测试使用。${PLAIN}"
                    echo -e "${YELLOW}请使用以下命令编辑配置文件以添加您自己的订阅：${PLAIN}"
                    echo -e "${YELLOW}nano /etc/mihomo/config.yaml${PLAIN}"
                    echo -e "${YELLOW}======================================================${PLAIN}"
                fi
                
                echo -e "\n${GREEN}======================================================${PLAIN}"
                echo -e "${GREEN}步骤2完成! Mihomo代理已安装并启动${PLAIN}"
                echo -e "${GREEN}您现在可以使用以下地址访问控制面板:${PLAIN}"
                echo -e "${GREEN}控制面板: http://${mihomo_ip}:9090/ui${PLAIN}"
                echo -e "${GREEN}现在请前往步骤3: 配置路由器${PLAIN}"
                echo -e "${GREEN}======================================================${PLAIN}"
            else
                echo -e "${RED}错误: 代理配置脚本不存在${PLAIN}"
                echo -e "${YELLOW}请确保脚本文件存在: $PROXY_SCRIPT${PLAIN}"
            fi
            
            read -p "按任意键返回主菜单..." key
            show_menu
            ;;
        3)
            # 配置路由器
            local mihomo_ip=$(get_state_value "mihomo_ip")
            local stage=$(get_state_value "installation_stage")
            
            # 检查是否已完成初始化
            if [[ -z "$mihomo_ip" ]]; then
                echo -e "${YELLOW}======================================================${PLAIN}"
                echo -e "${YELLOW}您需要先完成步骤1: 初始化设置${PLAIN}"
                echo -e "${YELLOW}======================================================${PLAIN}"
                read -p "是否立即进行初始化? (y/n): " do_init
                if [[ "$do_init" == "y" || "$do_init" == "Y" ]]; then
                    # 选项1的逻辑
                    choice=1
                    continue
                else
                    show_menu
                    return
                fi
            fi
            
            # 检查是否已完成代理机配置
            if [[ "$stage" != "Step2_Completed" ]]; then
                echo -e "${YELLOW}======================================================${PLAIN}"
                echo -e "${YELLOW}建议先完成步骤2: 配置代理机${PLAIN}"
                echo -e "${YELLOW}======================================================${PLAIN}"
                read -p "是否继续生成路由器配置? (y/n): " continue_router
                if [[ "$continue_router" != "y" && "$continue_router" != "Y" ]]; then
                    show_menu
                    return
                fi
            fi
            
            # 执行路由器配置
            clear
            echo -e "${CYAN}======================================================${PLAIN}"
            echo -e "${CYAN}              步骤3: 路由器配置${PLAIN}"
            echo -e "${CYAN}======================================================${PLAIN}"
            
            if [[ -f "$ROUTER_SCRIPT" ]]; then
                echo -e "${CYAN}正在生成路由器配置命令...${PLAIN}"
                bash "$ROUTER_SCRIPT"
                echo -e "\n${GREEN}======================================================${PLAIN}"
                echo -e "${GREEN}步骤3完成! 路由器配置已生成${PLAIN}"
                echo -e "${GREEN}请按照上方指南配置您的路由器，完成后即可使用Mihomo代理服务${PLAIN}"
                echo -e "${GREEN}======================================================${PLAIN}"
            else
                echo -e "${RED}错误: 路由器配置脚本不存在${PLAIN}"
                echo -e "${YELLOW}请确保脚本文件存在: $ROUTER_SCRIPT${PLAIN}"
            fi
            
            read -p "按任意键返回主菜单..." key
            show_menu
            ;;
        4)
            # 重启Mihomo服务
            clear
            echo -e "${CYAN}======================================================${PLAIN}"
            echo -e "${CYAN}              重启Mihomo服务${PLAIN}"
            echo -e "${CYAN}======================================================${PLAIN}"
            
            # 检查Docker服务是否运行
            if ! systemctl is-active --quiet docker; then
                echo -e "${RED}错误: Docker服务未运行${PLAIN}"
                echo -e "${YELLOW}正在启动Docker服务...${PLAIN}"
                systemctl start docker
                if ! systemctl is-active --quiet docker; then
                    echo -e "${RED}Docker服务启动失败${PLAIN}"
                    echo -e "${YELLOW}请检查Docker服务状态并尝试手动启动${PLAIN}"
                    read -p "按任意键返回..." key
                    show_menu
                    return
                fi
                echo -e "${GREEN}Docker服务已成功启动${PLAIN}"
            fi
            
            # 检查mihomo容器状态
            if ! docker ps -a | grep -q mihomo; then
                echo -e "${RED}错误: 未找到mihomo容器${PLAIN}"
                echo -e "${YELLOW}可能的原因:${PLAIN}"
                echo -e "1. 尚未完成步骤2的安装"
                echo -e "2. 容器已被删除"
                echo -e "3. 容器名称不是'mihomo'"
                echo
                echo -e "${CYAN}建议操作:${PLAIN}"
                echo -e "1. 完成步骤2的安装"
                echo -e "2. 检查Docker容器状态: docker ps -a"
                echo -e "3. 如果需要，手动启动容器"
                read -p "按任意键返回..." key
                show_menu
                return
            fi
            
            # 检查容器是否正在运行
            if ! docker ps | grep -q mihomo; then
                echo -e "${YELLOW}警告: mihomo容器未运行${PLAIN}"
                echo -e "${CYAN}尝试启动mihomo容器...${PLAIN}"
                if ! docker start mihomo; then
                    echo -e "${RED}容器启动失败${PLAIN}"
                    echo -e "${YELLOW}请检查Docker日志:${PLAIN}"
                    docker logs mihomo --tail 20
                    read -p "按任意键返回..." key
                    show_menu
                    return
                fi
                echo -e "${GREEN}Mihomo容器已成功启动${PLAIN}"
            else
                echo -e "${CYAN}正在重启Mihomo服务...${PLAIN}"
                if ! docker restart mihomo; then
                    echo -e "${RED}错误: 重启Mihomo服务失败${PLAIN}"
                    echo -e "${YELLOW}请检查Docker日志并尝试手动重启容器${PLAIN}"
                    read -p "按任意键返回..." key
                    show_menu
                    return
                fi
                echo -e "${GREEN}Mihomo服务已成功重启${PLAIN}"
            fi
            
            # 等待几秒让服务启动
            echo -e "${CYAN}正在等待服务启动...${PLAIN}"
            sleep 3
            
            # 验证服务状态
            if docker ps | grep -q mihomo; then
                echo -e "${GREEN}● 容器状态: 运行中${PLAIN}"
                
                # 获取mihomo IP
                local mihomo_ip=$(get_state_value "mihomo_ip")
                echo -e "${CYAN}Mihomo服务信息:${PLAIN}"
                echo -e "${GREEN}● 控制面板地址: http://${mihomo_ip}:9090/ui${PLAIN}"
                echo -e "${GREEN}● 混合代理端口: ${mihomo_ip}:7890${PLAIN}"
                echo -e "${GREEN}● HTTP代理端口: ${mihomo_ip}:7891${PLAIN}"
                echo -e "${GREEN}● SOCKS5代理端口: ${mihomo_ip}:7892${PLAIN}"
                
                # 检查服务是否可访问
                if curl -s -m 3 http://${mihomo_ip}:9090 &> /dev/null; then
                    echo -e "${GREEN}● 服务可访问性: 正常${PLAIN}"
                else
                    echo -e "${YELLOW}● 服务可访问性: 无法访问${PLAIN}"
                    echo -e "${YELLOW}请检查网络配置和防火墙设置，确保服务可访问${PLAIN}"
                fi
            else
                echo -e "${RED}● 容器状态: 未运行${PLAIN}"
                echo -e "${YELLOW}请检查Docker日志以了解问题原因${PLAIN}"
                docker logs mihomo --tail 20
            fi
            
            read -p "按任意键返回主菜单..." key
            show_menu
            ;;
        5)
            # 检查安装状态 - 使用预先创建的检查状态脚本
            clear
            echo -e "${CYAN}======================================================${PLAIN}"
            echo -e "${CYAN}              安装状态检查${PLAIN}"
            echo -e "${CYAN}======================================================${PLAIN}"
            
            # 检查状态脚本是否存在
            if [[ -f "$CHECK_SCRIPT" ]]; then
                echo -e "${CYAN}正在执行状态检查...${PLAIN}"
                bash "$CHECK_SCRIPT"
            else
                echo -e "${RED}错误: 状态检查脚本不存在: $CHECK_SCRIPT${PLAIN}"
                echo -e "${YELLOW}为您显示基本信息:${PLAIN}"
                
                if [[ -f "$STATE_FILE" ]]; then
                    echo -e "${YELLOW}基本系统信息:${PLAIN}"
                    local mihomo_ip=$(get_state_value "mihomo_ip")
                    local stage=$(get_state_value "installation_stage")
                    
                    echo -e "${YELLOW}● 步骤完成情况:${PLAIN}"
                    if [[ -n "$mihomo_ip" ]]; then
                        echo -e "${GREEN}  ✓ 步骤1: 初始化已完成 - IP: $mihomo_ip${PLAIN}"
                    else
                        echo -e "${RED}  ✗ 步骤1: 初始化未完成${PLAIN}"
                    fi
                    
                    if [[ "$stage" == "Step2_Completed" ]]; then
                        echo -e "${GREEN}  ✓ 步骤2: 代理机配置已完成${PLAIN}"
                    else
                        echo -e "${RED}  ✗ 步骤2: 代理机配置未完成${PLAIN}"
                    fi
                    
                    if [[ -n "$mihomo_ip" && "$stage" == "Step2_Completed" ]]; then
                        echo -e "${YELLOW}● 访问信息:${PLAIN}"
                        echo -e "${GREEN}  控制面板: http://$mihomo_ip:9090/ui${PLAIN}"
                        echo -e "${GREEN}  HTTP代理: $mihomo_ip:7891${PLAIN}"
                        echo -e "${GREEN}  SOCKS5代理: $mihomo_ip:7892${PLAIN}"
                        echo -e "${GREEN}  混合端口: $mihomo_ip:7890${PLAIN}"
                    fi
                else
                    echo -e "${RED}错误: 未找到状态文件${PLAIN}"
                    echo -e "${YELLOW}建议重新执行步骤1进行初始化${PLAIN}"
                fi
            fi
            
            echo -e "${CYAN}======================================================${PLAIN}"
            read -p "按任意键返回主菜单..." key
            show_menu
            ;;
        6)
            # 卸载Mihomo服务
            clear
            echo -e "${CYAN}======================================================${PLAIN}"
            echo -e "${CYAN}              卸载Mihomo服务${PLAIN}"
            echo -e "${CYAN}======================================================${PLAIN}"
            
            echo -e "${YELLOW}警告: 此操作将卸载Mihomo服务并删除所有相关配置${PLAIN}"
            echo -e "${RED}卸载后将无法恢复，请谨慎操作${PLAIN}"
            read -p "确定要卸载Mihomo吗? (y/n): " confirm_uninstall
            
            if [[ "$confirm_uninstall" != "y" && "$confirm_uninstall" != "Y" ]]; then
                echo -e "${GREEN}卸载已取消${PLAIN}"
                read -p "按任意键返回..." key
                show_menu
                return
            fi
            
            echo -e "${CYAN}开始卸载Mihomo服务...${PLAIN}"
            
            # 1. 停止并删除mihomo容器
            echo -e "${CYAN}[1/4] 停止并删除mihomo容器${PLAIN}"
            if docker ps -a | grep -q mihomo; then
                echo -e "${YELLOW}● 正在停止mihomo容器...${PLAIN}"
                docker stop mihomo
                echo -e "${YELLOW}● 正在删除mihomo容器...${PLAIN}"
                docker rm mihomo
                if ! docker ps -a | grep -q mihomo; then
                    echo -e "${GREEN}● Mihomo容器已成功删除${PLAIN}"
                else
                    echo -e "${RED}● Mihomo容器删除失败，请尝试手动删除: ${CYAN}docker rm -f mihomo${PLAIN}"
                fi
            else
                echo -e "${YELLOW}● 未找到Mihomo容器${PLAIN}"
            fi
            
            # 2. 备份并删除配置文件和UI文件
            echo -e "${CYAN}[2/4] 备份并删除配置文件${PLAIN}"
            if [[ -d "$CONF_DIR" ]]; then
                # 备份配置文件
                local backup_dir="/root/mihomo_backup_$(date '+%Y%m%d%H%M%S')"
                mkdir -p "$backup_dir"
                
                if [[ -f "$CONF_DIR/config.yaml" ]]; then
                    echo -e "${YELLOW}● 备份配置文件到 $backup_dir/config.yaml${PLAIN}"
                    cp "$CONF_DIR/config.yaml" "$backup_dir/config.yaml"
                fi
                
                echo -e "${YELLOW}● 删除配置目录 $CONF_DIR${PLAIN}"
                rm -rf "$CONF_DIR"
                echo -e "${GREEN}● 配置目录已删除${PLAIN}"
            else
                echo -e "${YELLOW}● 未找到配置目录${PLAIN}"
            fi
            
            # 3. 删除Docker网络
            echo -e "${CYAN}[3/4] 删除Docker网络${PLAIN}"
            if docker network ls | grep -q mnet; then
                echo -e "${YELLOW}● 正在删除Docker macvlan网络...${PLAIN}"
                # 先确保没有容器连接到该网络
                docker network disconnect mnet mihomo 2>/dev/null || true
                # 强制删除网络
                docker network rm mnet || docker network rm mnet -f
                if ! docker network ls | grep -q mnet; then
                    echo -e "${GREEN}● Docker macvlan网络已成功删除${PLAIN}"
                else
                    echo -e "${RED}● Docker macvlan网络删除失败，请尝试手动删除: ${CYAN}docker network rm -f mnet${PLAIN}"
                fi
            else
                echo -e "${YELLOW}● 未找到Docker macvlan网络${PLAIN}"
            fi
            
            # 4. 删除网络接口和安装脚本
            echo -e "${CYAN}[4/4] 删除网络接口${PLAIN}"
            
            # 删除macvlan网络接口
            local macvlan_interface=$(get_state_value "macvlan_interface")
            macvlan_interface=${macvlan_interface:-"mihomo_veth"}
            
            echo -e "${YELLOW}● 检查网络接口 $macvlan_interface...${PLAIN}"
            if ip link show "$macvlan_interface" 2>/dev/null; then
                echo -e "${YELLOW}● 正在删除网络接口 $macvlan_interface...${PLAIN}"
                ip link del "$macvlan_interface"
                if ! ip link show "$macvlan_interface" 2>/dev/null; then
                    echo -e "${GREEN}● Macvlan网络接口已成功删除${PLAIN}"
                else
                    echo -e "${RED}● Macvlan网络接口删除失败，请尝试手动删除: ${CYAN}ip link del $macvlan_interface${PLAIN}"
                fi
            else
                echo -e "${YELLOW}● 未找到macvlan网络接口 $macvlan_interface${PLAIN}"
            fi
            
            # 删除安装脚本和状态文件
            if [[ -d "/etc/mihomo-proxy" ]]; then
                echo -e "${YELLOW}● 删除Mihomo安装脚本和状态文件...${PLAIN}"
                rm -rf /etc/mihomo-proxy
                echo -e "${GREEN}● 安装脚本和状态文件已删除${PLAIN}"
            fi
            
            # 删除状态配置文件
            if [[ -f "$STATE_FILE" ]]; then
                echo -e "${YELLOW}● 删除状态配置文件...${PLAIN}"
                rm -f "$STATE_FILE"
                echo -e "${GREEN}● 状态配置文件已删除${PLAIN}"
            fi
            
            # 兼容性处理：如果存在旧的服务文件，也一并删除
            if [[ -f "/etc/systemd/system/mihomo-network.service" ]]; then
                echo -e "${YELLOW}● 删除旧的mihomo-network服务文件...${PLAIN}"
                rm -f /etc/systemd/system/mihomo-network.service
                echo -e "${GREEN}● 旧服务文件已删除${PLAIN}"
                systemctl daemon-reload
            fi
            
            # 删除网卡混杂模式服务
            local main_interface=$(get_state_value "main_interface")
            if [[ -n "$main_interface" && -f "/etc/systemd/system/promisc-$main_interface.service" ]]; then
                systemctl disable "promisc-$main_interface.service" &>/dev/null
                rm -f "/etc/systemd/system/promisc-$main_interface.service"
                echo -e "${GREEN}● 网卡混杂模式服务已删除${PLAIN}"
                
                # 关闭网卡混杂模式
                if ip link show 2>/dev/null | grep -q "$main_interface"; then
                    ip link set "$main_interface" promisc off &>/dev/null
                    echo -e "${GREEN}● 已关闭网卡混杂模式${PLAIN}"
                fi
            fi
            
            # 重载systemd服务
            systemctl daemon-reload
            
            # 删除后不再重置状态文件，完全卸载
            
            echo -e "\n${GREEN}======================================================${PLAIN}"
            echo -e "${GREEN}Mihomo已成功卸载!${PLAIN}"
            if [[ -d "$backup_dir" ]]; then
                echo -e "${GREEN}配置文件备份已保存至: $backup_dir${PLAIN}"
            fi
            echo -e "${GREEN}======================================================${PLAIN}"
            
            read -p "按任意键返回主菜单..." key
            show_menu
            ;;
        0)
            # 退出
            clear
            echo -e "${GREEN}======================================================${PLAIN}"
            echo -e "${GREEN}感谢使用Mihomo一键安装引导脚本!${PLAIN}"
            echo -e "${GREEN}再见!${PLAIN}"
            echo -e "${GREEN}======================================================${PLAIN}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效的选项，请重新选择${PLAIN}"
            sleep 1
            show_menu
            ;;
    esac
}

# 主函数
main() {
    # 创建日志文件
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    log_message "开始执行安装脚本"
    
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
    
    # 检查root权限
    check_root
    
    # 检查系统
    check_os
    
    # 检测网络环境，初始化网络相关变量
    detect_network
    
    # 初始化状态文件
    init_state_file
    
    # 检查配置文件模板
    check_config_template
    
    # 检查执行脚本是否存在
    check_exec_scripts
    
    # 显示主菜单
    show_menu
}

# 执行主函数
main
