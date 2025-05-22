#!/bin/bash
#############################################################
# Mihomo 一键安装脚本 V1.0
# 支持系统: Debian 10/11/12, Ubuntu 20.04/22.04/24.04
# 功能: 一键安装并配置Mihomo代理服务
#############################################################

# ====================================================================================
# 【使用说明】
# 
# 如果您已下载mihomo-docker目录:
#    cd mihomo-docker
#    bash mihomo.sh
#
# 或者直接下载脚本:
#    curl -fsSL https://raw.githubusercontent.com/mihomo-proxy/mihomo-docker/main/mihomo.sh -o mihomo.sh
#    chmod +x mihomo.sh
#    bash mihomo.sh
#
# 此脚本会自动加载files文件夹下的执行脚本和配置文件
# 详细说明请参考同目录下的README.md文件
# ====================================================================================

# 版本信息
SCRIPT_VERSION="1.0.0"

# 处理命令行参数
if [[ "$1" == "--version" || "$1" == "-v" ]]; then
    echo "Mihomo 一键安装脚本 v${SCRIPT_VERSION}"
    exit 0
fi

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Mihomo 一键安装脚本 v${SCRIPT_VERSION}"
    echo
    echo "使用方法:"
    echo "  bash mihomo.sh [选项]"
    echo
    echo "选项:"
    echo "  --version, -v     显示版本信息"
    echo "  --help, -h        显示此帮助信息"
    echo "  --auto-install    直接执行一键安装，无需进入菜单"
    echo
    echo "详细说明请参考README.md文件"
    exit 0
fi

# 直接执行一键安装
if [[ "$1" == "--auto-install" ]]; then
    # 跳过菜单直接安装
    one_key_install
    exit 0
fi

# 全局环境变量
script_dir=$(cd "$(dirname "$0")" && pwd)
FILES_DIR="$script_dir/files"
STATE_FILE="$FILES_DIR/mihomo_state.json"
STATE_VERSION="1.0"
LOG_FILE="/var/log/mihomo_install.log"
PROXY_SCRIPT="$FILES_DIR/setup_proxy.sh"
ROUTER_SCRIPT="$FILES_DIR/setup_router.sh"
CHECK_SCRIPT="$FILES_DIR/check_status.sh"
CONFIG_TEMPLATE="$FILES_DIR/config.yaml"
CUSTOM_CONFIG="/etc/mihomo/config.yaml"
MAIN_INTERFACE=""  # 初始为空，会通过detect_network函数设置

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

# 检查files目录是否存在
check_files_dir() {
    if [[ ! -d "$FILES_DIR" ]]; then
        echo -e "${RED}错误: files目录不存在${PLAIN}"
        echo -e "${RED}files目录用于存放执行脚本和相关配置文件，请确保该目录存在${PLAIN}"
        exit 1
    fi
}

# 检查执行脚本是否存在
check_exec_scripts() {
    # 检查files目录是否存在
    check_files_dir
    
    # 检查所需的执行脚本
    local scripts=("$PROXY_SCRIPT" "$ROUTER_SCRIPT" "$CHECK_SCRIPT")
    local script_names=("setup_proxy.sh" "setup_router.sh" "check_status.sh")
    local missing=0
    
    for i in "${!scripts[@]}"; do
        local script="${scripts[$i]}"
        local script_name="${script_names[$i]}"
        
        if [[ ! -f "$script" ]]; then
            echo -e "${YELLOW}未找到脚本: $script_name，尝试从当前目录加载${PLAIN}"
            
            # 尝试从当前目录加载
            if [[ -f "$script_dir/$script_name" ]]; then
                cp "$script_dir/$script_name" "$script"
                chmod +x "$script"
                echo -e "${GREEN}已加载脚本: $script_name${PLAIN}"
            else
                echo -e "${RED}错误: 找不到脚本: $script_name${PLAIN}"
                missing=1
            fi
        else
            # 确保脚本可执行
            chmod +x "$script"
        fi
    done
    
    # 检查配置文件
    if [[ ! -f "$CONFIG_TEMPLATE" ]]; then
        echo -e "${YELLOW}未找到配置文件: config.yaml，尝试从当前目录加载${PLAIN}"
        
        # 尝试从当前目录加载
        if [[ -f "$script_dir/config.yaml" ]]; then
            cp "$script_dir/config.yaml" "$CONFIG_TEMPLATE"
            echo -e "${GREEN}已加载配置文件: config.yaml${PLAIN}"
        else
            echo -e "${RED}错误: 找不到配置文件: config.yaml${PLAIN}"
            missing=1
        fi
    fi
    
    if [[ $missing -eq 1 ]]; then
        echo -e "${RED}错误: 缺少必要的文件。请确保以下文件存在于 $FILES_DIR 目录或当前目录:${PLAIN}"
        echo -e "${YELLOW}- setup_proxy.sh${PLAIN}"
        echo -e "${YELLOW}- setup_router.sh${PLAIN}"
        echo -e "${YELLOW}- check_status.sh${PLAIN}"
        echo -e "${YELLOW}- config.yaml${PLAIN}"
        return 1
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
    if [[ -z "$MAIN_INTERFACE" ]]; then
        # 获取默认路由的网络接口
        MAIN_INTERFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
        
        # 如果还是为空，尝试其他方法
        if [[ -z "$MAIN_INTERFACE" ]]; then
            # 尝试从IP地址获取
            MAIN_INTERFACE=$(ip -o -4 addr | grep -v "127.0.0.1" | awk '{print $2}' | head -n1)
            
            # 如果还是为空，使用eth0作为默认
            if [[ -z "$MAIN_INTERFACE" ]]; then
                MAIN_INTERFACE="eth0"
                echo -e "${YELLOW}警告: 无法检测到默认网络接口，使用eth0作为默认值${PLAIN}"
            fi
        fi
    fi
    
    if ! ip link show dev "$MAIN_INTERFACE" &>/dev/null; then
        echo -e "${RED}错误: 网络接口 $MAIN_INTERFACE 不存在${PLAIN}"
        read -p "请输入正确的网络接口名称: " MAIN_INTERFACE
        if ! ip link show dev "$MAIN_INTERFACE" &>/dev/null; then
            echo -e "${RED}错误: 网络接口 $MAIN_INTERFACE 不存在，退出安装${PLAIN}"
            exit 1
        fi
    fi
    
    # 获取接口IP地址
    INTERFACE_IP=$(ip -o -4 addr show dev "$MAIN_INTERFACE" | awk '{print $4}' | cut -d/ -f1 | head -n1)
    if [[ -z "$INTERFACE_IP" ]]; then
        echo -e "${RED}错误: 无法获取网络接口 $MAIN_INTERFACE 的IP地址${PLAIN}"
        exit 1
    fi
    
    # 检测局域网网段
    local ip_parts=(${INTERFACE_IP//./ })
    local subnet_prefix="${ip_parts[0]}.${ip_parts[1]}.${ip_parts[2]}"
    
    # 仅显示基本网络信息
    echo -e "${GREEN}网络接口: ${CYAN}$MAIN_INTERFACE${PLAIN}"
    echo -e "${GREEN}接口IP地址: ${CYAN}$INTERFACE_IP${PLAIN}"
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
    
    # 获取网络环境信息，用于初始化配置
    detect_network 2>/dev/null || true
    
    if [[ ! -f "$STATE_FILE" ]]; then
        # 如果没有获取到网络信息，尝试再次检测
        if [[ -z "$MAIN_INTERFACE" || -z "$INTERFACE_IP" ]]; then
            detect_network
        fi
        
        # 确保网络变量已设置
        MAIN_INTERFACE=${MAIN_INTERFACE:-$(ip route | grep default | awk '{print $5}' | head -n 1)}
        INTERFACE_IP=$(ip -o -4 addr show dev "$MAIN_INTERFACE" | awk '{print $4}' | cut -d/ -f1 | head -n1)
        
        # 创建新的状态文件
        cat > "$STATE_FILE" << EOF
{
  "version": "$STATE_VERSION",
  "mihomo_ip": "$INTERFACE_IP",
  "interface_ip": "$INTERFACE_IP",
  "main_interface": "$MAIN_INTERFACE",
  "macvlan_interface": "mihomo_veth",
  "installation_stage": "初始化",
  "config_type": "preset",
  "docker_method": "direct_pull",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF
        log_message "创建本地状态文件: $STATE_FILE"
        echo -e "${GREEN}已创建状态文件，默认Mihomo IP: $INTERFACE_IP${PLAIN}"
    else
        log_message "使用现有状态文件"
        echo -e "${GREEN}使用现有状态文件${PLAIN}"
        if ! validate_state; then
            handle_error "状态文件验证失败"
            return 1
        fi
    fi
    
    chmod 644 "$STATE_FILE"
    return 0
}

# 获取状态值
get_state_value() {
    local key="$1"
    local value=""
    
    # 检查状态文件是否存在
    if [[ ! -f "$STATE_FILE" ]]; then
        return
    fi
    
    value=$(grep -o "\"$key\": *\"[^\"]*\"" "$STATE_FILE" | cut -d'"' -f4)
    echo "$value"
}

# 更新状态
update_state() {
    local key="$1"
    local value="$2"
    
    # 检查状态文件是否存在
    if [[ ! -f "$STATE_FILE" ]]; then
        echo -e "${YELLOW}警告: 状态文件不存在，无法更新状态${PLAIN}"
        return 1
    fi
    
    # 使用sed更新状态值
    sed -i "s|\"$key\": *\"[^\"]*\"|\"$key\": \"$value\"|g" "$STATE_FILE"
    
    # 更新时间戳
    sed -i "s|\"timestamp\": *\"[^\"]*\"|\"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\"|g" "$STATE_FILE"
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

# 设置Mihomo IP
setup_mihomo_ip() {
    # 确定默认的网络接口
    local interface_ip=""
    
    # 如果网络接口已检测
    if [[ -n "$MAIN_INTERFACE" ]]; then
        interface_ip=$(ip -o -4 addr show dev "$MAIN_INTERFACE" | awk '{print $4}' | cut -d/ -f1 | head -n1)
    else
        # 重新进行网络检测
        detect_network
        interface_ip="$INTERFACE_IP"
    fi
    
    # 将IP拆分为段
    local ip_parts=(${interface_ip//./ })
    local subnet_prefix="${ip_parts[0]}.${ip_parts[1]}.${ip_parts[2]}"
    
    # 建议的IP地址
    local suggested_ip="${subnet_prefix}.4"
    
    # 显示当前检测到的网络信息
    echo -e "${CYAN}当前网络信息:${PLAIN}"
    echo -e "${YELLOW}• 网络接口: ${GREEN}$MAIN_INTERFACE${PLAIN}"
    echo -e "${YELLOW}• 接口IP地址: ${GREEN}$interface_ip${PLAIN}"
    echo -e "${YELLOW}• 默认子网: ${GREEN}${subnet_prefix}.0/24${PLAIN}"
    echo
    
    # 提示用户设置IP
    echo -e "${CYAN}请为Mihomo设置一个静态IP地址:${PLAIN}"
    echo -e "${YELLOW}推荐使用子网内未使用的IP: ${GREEN}${suggested_ip}${PLAIN}"
    echo -e "${YELLOW}注意: IP地址必须与您当前设备在同一子网内${PLAIN}"
    echo -e "${YELLOW}建议使用${subnet_prefix}.X形式的地址 (X为2-254之间的数字)${PLAIN}"
    
    # 用户输入
    local mihomo_ip=""
    read -p "请输入Mihomo IP地址 [$suggested_ip]: " mihomo_ip
    mihomo_ip=${mihomo_ip:-$suggested_ip}
    
    # 验证IP格式
    if ! [[ $mihomo_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}IP地址格式不正确${PLAIN}"
        read -p "重新输入IP地址: " mihomo_ip
        if ! [[ $mihomo_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${RED}IP地址格式不正确，使用默认值${PLAIN}"
            mihomo_ip="$suggested_ip"
        fi
    fi
    
    # 检查IP是否已被占用
    if ping -c 1 -W 1 "$mihomo_ip" &>/dev/null; then
        echo -e "${YELLOW}警告: IP地址 $mihomo_ip 可能已被占用${PLAIN}"
        read -p "是否继续使用此IP? (y/n): " continue_ip
        if [[ "$continue_ip" != "y" && "$continue_ip" != "Y" ]]; then
            setup_mihomo_ip
            return
        fi
    fi
    
    # 更新状态文件
    if update_state "mihomo_ip" "$mihomo_ip"; then
        echo -e "${GREEN}Mihomo IP地址已设置为: $mihomo_ip${PLAIN}"
    else
        echo -e "${RED}设置IP地址失败${PLAIN}"
    fi
}

# 检查配置文件是否存在
check_config_template() {
    if [[ ! -f "$CONFIG_TEMPLATE" ]]; then
        echo -e "${CYAN}检查配置文件模板...${PLAIN}"
        
        # 尝试在不同位置寻找配置文件
        local config_locations=(
            "$FILES_DIR/config.yaml"
            "$script_dir/config.yaml"
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

# 显示分步安装菜单
show_step_menu() {
    clear
    
    # 获取当前状态（如果状态文件存在）
    local mihomo_ip=""
    local stage=""
    
    if [[ -f "$STATE_FILE" ]]; then
        mihomo_ip=$(get_state_value "mihomo_ip")
        stage=$(get_state_value "installation_stage")
    else
        # 如果状态文件不存在，则视为未初始化
        stage="未初始化"
    fi
    
    # 标题
    echo -e "${CYAN}===========================================================${PLAIN}"
    echo -e "${CYAN}              Mihomo 分步安装向导${PLAIN}"
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
    echo -e " ${GREEN}[0] 0. 返回主菜单${PLAIN}"
    echo -e "${CYAN}===========================================================${PLAIN}"
    
    # 显示当前状态
    if [[ -n "$mihomo_ip" && "$stage" == "Step2_Completed" ]]; then
        echo -e "${YELLOW}系统信息:${PLAIN}"
        echo -e "${YELLOW}• 控制面板: ${GREEN}http://$mihomo_ip:9090/ui${PLAIN}"
        echo -e "${YELLOW}• HTTP代理: ${GREEN}$mihomo_ip:7891${PLAIN}"
        echo -e "${YELLOW}• SOCKS5代理: ${GREEN}$mihomo_ip:7892${PLAIN}"
    fi
    echo
    
    read -p "请输入选择 [0-3]: " choice
    
    case $choice in
        1)
            # 初始化设置
            init_setup
            ;;
        2)
            # 配置代理机
            setup_proxy
            ;;
        3)
            # 配置路由器
            configure_router
            ;;
        0)
            # 返回主菜单
            show_menu
            ;;
        *)
            echo -e "${RED}无效的选项，请重新选择${PLAIN}"
            sleep 1
            show_step_menu
            ;;
    esac
}

# 显示主菜单
show_menu() {
    clear
    
    # 获取当前状态（如果状态文件存在）
    local mihomo_ip=""
    local stage=""
    local timestamp=""
    
    if [[ -f "$STATE_FILE" ]]; then
        mihomo_ip=$(get_state_value "mihomo_ip")
        stage=$(get_state_value "installation_stage")
        timestamp=$(get_state_value "timestamp")
    fi
    
    # 标题
    echo -e "${CYAN}===========================================================${PLAIN}"
    echo -e "${CYAN}              Mihomo 一键安装引导脚本${PLAIN}"
    echo -e "${CYAN}===========================================================${PLAIN}"
    echo
    
    echo -e "${CYAN}菜单选项:${PLAIN}"
    echo -e " ${GREEN}[1] 1. 分步安装${PLAIN}      - ${YELLOW}按步骤引导完成安装${PLAIN}"
    echo -e " ${GREEN}[2] 2. 一键安装${PLAIN}      - ${YELLOW}自动完成所有安装步骤${PLAIN}"
    echo -e " ${GREEN}[3] 3. 检查状态${PLAIN}      - ${YELLOW}检查Mihomo安装和运行状态${PLAIN}"
    echo -e " ${GREEN}[4] 4. 重启服务${PLAIN}      - ${YELLOW}重启Mihomo代理服务${PLAIN}"
    echo -e " ${GREEN}[5] 5. 配置路由器${PLAIN}    - ${YELLOW}生成路由器配置命令${PLAIN}"
    echo -e " ${RED}[6] 6. 卸载Mihomo${PLAIN}    - ${YELLOW}完全卸载Mihomo及其配置${PLAIN}"
    echo -e " ${GREEN}[0] 0. 退出脚本${PLAIN}"
    echo -e "${CYAN}===========================================================${PLAIN}"
    
    # 显示当前状态（如果有）
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
            # 显示分步安装菜单
            show_step_menu
            ;;
        2)
            # 执行一键安装
            one_key_install
            ;;
        3)
            # 检查安装状态
            check_installation_status
            ;;
        4)
            # 重启Mihomo服务
            restart_mihomo_service
            ;;
        5)
            # 配置路由器
            configure_router
            ;;
        6)
            # 卸载Mihomo
            uninstall_mihomo
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

# 初始化设置
init_setup() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}              步骤1: 初始化设置${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${YELLOW}这一步将设置mihomo的IP地址并检查配置脚本${PLAIN}"
    echo
    
    # 检查状态文件是否已存在
    local mihomo_ip=""
    if [[ -f "$STATE_FILE" ]]; then
        mihomo_ip=$(get_state_value "mihomo_ip")
    else
        # 如果状态文件不存在，创建一个初始的空状态文件
        echo -e "${CYAN}创建初始状态文件...${PLAIN}"
        # 确保files目录存在
        if [[ ! -d "$FILES_DIR" ]]; then
            mkdir -p "$FILES_DIR"
        fi
        
        # 创建基本状态文件
        cat > "$STATE_FILE" << EOF
{
  "version": "$STATE_VERSION",
  "mihomo_ip": "",
  "interface_ip": "",
  "main_interface": "$MAIN_INTERFACE",
  "macvlan_interface": "mihomo_veth",
  "installation_stage": "初始化",
  "config_type": "preset",
  "docker_method": "direct_pull",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF
        chmod 644 "$STATE_FILE"
        echo -e "${GREEN}初始状态文件已创建${PLAIN}"
    fi
    
    if [[ -n "$mihomo_ip" ]]; then
        echo -e "${YELLOW}检测到已有配置: IP = $mihomo_ip${PLAIN}"
        read -p "是否重新设置IP地址? (y/n): " reset_ip
        if [[ "$reset_ip" == "y" || "$reset_ip" == "Y" ]]; then
            echo -e "${CYAN}正在重新设置IP地址...${PLAIN}"
        else
            echo -e "${YELLOW}保留已有配置，返回菜单...${PLAIN}"
            sleep 1
            show_step_menu
            return
        fi
    fi
    
    # 设置mihomo IP地址
    setup_mihomo_ip
    
    # 检查配置脚本是否存在
    if ! check_exec_scripts; then
        echo -e "${RED}错误: 缺少执行脚本文件。请确保所需文件存在${PLAIN}"
        read -p "按任意键继续..." key
        show_step_menu
        return 1
    else
        echo -e "${GREEN}所有执行脚本已就绪${PLAIN}"
    fi
    
    # 检查配置文件模板是否存在
    check_config_template
    
    # 获取设置完成后的mihomo IP
    mihomo_ip=$(get_state_value "mihomo_ip")
    echo -e "\n${GREEN}======================================================${PLAIN}"
    echo -e "${GREEN}步骤1完成! Mihomo IP地址: ${YELLOW}$mihomo_ip${PLAIN}"
    echo -e "${GREEN}现在您可以进行步骤2: 配置代理机${PLAIN}"
    echo -e "${GREEN}======================================================${PLAIN}"
    
    # 更新安装阶段状态
    update_state "installation_stage" "Step1_Completed"
    
    read -p "按任意键返回菜单..." key
    show_step_menu
}

# 配置代理机
setup_proxy() {
    # 检查状态文件是否存在
    local mihomo_ip=""
    local stage=""
    
    if [[ -f "$STATE_FILE" ]]; then
        mihomo_ip=$(get_state_value "mihomo_ip")
        stage=$(get_state_value "installation_stage")
    fi
    
    # 检查是否已完成初始化
    if [[ -z "$mihomo_ip" ]]; then
        echo -e "${YELLOW}======================================================${PLAIN}"
        echo -e "${YELLOW}您需要先完成步骤1: 初始化设置${PLAIN}"
        echo -e "${YELLOW}======================================================${PLAIN}"
        read -p "是否立即进行初始化? (y/n): " do_init
        if [[ "$do_init" == "y" || "$do_init" == "Y" ]]; then
            init_setup
            return
        else
            show_step_menu
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
        if [[ -f "$STATE_FILE" ]] && [[ "$(get_state_value "config_type")" == "preset" ]]; then
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
    
    read -p "按任意键返回菜单..." key
    show_step_menu
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
    
    # 0. 检查执行环境
    echo -e "${CYAN}[1/5] 检查执行环境...${PLAIN}"
    check_root
    check_os
    
    # 1. 初始化设置
    echo -e "${CYAN}[2/5] 初始化配置...${PLAIN}"
    # 这里首先检测网络并初始化状态文件
    detect_network
    init_state_file
    
    # 确认脚本和配置文件存在
    if ! check_exec_scripts; then
        echo -e "${RED}错误: 必要的执行脚本或配置文件缺失，无法继续安装${PLAIN}"
        read -p "按任意键返回主菜单..." key
        show_menu
        return 1
    fi
    
    # 2. 安装依赖
    echo -e "${CYAN}[3/5] 安装依赖和配置环境...${PLAIN}"
    
    # 3. 安装和配置Mihomo
    echo -e "${CYAN}[4/5] 安装和配置Mihomo...${PLAIN}"
    if [[ -f "$PROXY_SCRIPT" ]]; then
        bash "$PROXY_SCRIPT"
    else
        echo -e "${RED}错误: 代理配置脚本不存在 ($PROXY_SCRIPT)${PLAIN}"
        read -p "按任意键返回主菜单..." key
        show_menu
        return 1
    fi
    
    # 4. 检查安装结果
    echo -e "${CYAN}[5/5] 检查安装结果...${PLAIN}"
    local mihomo_ip=$(get_state_value "mihomo_ip")
    local stage=$(get_state_value "installation_stage")
    
    if [[ "$stage" == "Step2_Completed" ]]; then
        echo -e "${GREEN}安装成功!${PLAIN}"
        echo -e "\n${GREEN}======================================================${PLAIN}"
        echo -e "${GREEN}Mihomo 代理已成功安装!${PLAIN}"
        echo -e "${GREEN}======================================================${PLAIN}"
        echo -e "${YELLOW}控制面板: ${GREEN}http://${mihomo_ip}:9090/ui${PLAIN}"
        echo -e "${YELLOW}混合代理: ${GREEN}${mihomo_ip}:7890${PLAIN}"
        echo -e "${YELLOW}HTTP代理: ${GREEN}${mihomo_ip}:7891${PLAIN}"
        echo -e "${YELLOW}SOCKS代理: ${GREEN}${mihomo_ip}:7892${PLAIN}"
        echo -e "${GREEN}======================================================${PLAIN}"
        echo -e "${YELLOW}推荐下一步:${PLAIN}"
        echo -e "${YELLOW}1. 检查Mihomo服务状态${PLAIN}"
        echo -e "${YELLOW}2. 配置您的路由器使用Mihomo代理${PLAIN}"
        echo -e "${YELLOW}3. 根据需要自定义配置文件${PLAIN}"
        echo -e "${GREEN}======================================================${PLAIN}"
    else
        echo -e "${RED}安装可能未完全成功，请检查安装状态${PLAIN}"
    fi
    
    read -p "按任意键返回主菜单..." key
    show_menu
}

# 检查安装状态
check_installation_status() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}              安装状态检查${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    # 检查状态文件是否存在
    if [[ ! -f "$STATE_FILE" ]]; then
        echo -e "${YELLOW}未检测到安装状态。目前尚未初始化安装。${PLAIN}"
        echo -e "${YELLOW}请先运行初始化安装。${PLAIN}"
        read -p "按任意键返回主菜单..." key
        show_menu
        return
    fi
    
    # 系统信息
    local system_info=$(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)
    local kernel_info=$(uname -r)
    echo -e "${CYAN}系统信息:${PLAIN}"
    echo -e "${YELLOW}• 系统: ${GREEN}$system_info${PLAIN}"
    echo -e "${YELLOW}• 内核: ${GREEN}$kernel_info${PLAIN}"
    echo
    
    # Mihomo配置信息
    local mihomo_ip=$(get_state_value "mihomo_ip")
    local stage=$(get_state_value "installation_stage")
    local timestamp=$(get_state_value "timestamp")
    
    echo -e "${CYAN}Mihomo配置:${PLAIN}"
    echo -e "${YELLOW}• Mihomo IP: ${GREEN}$mihomo_ip${PLAIN}"
    echo -e "${YELLOW}• 安装阶段: ${GREEN}$stage${PLAIN}"
    echo -e "${YELLOW}• 更新时间: ${GREEN}$timestamp${PLAIN}"
    
    # 检查服务运行状态
    echo
    echo -e "${CYAN}服务状态:${PLAIN}"
    
    # 检查Docker运行状态
    if command -v docker &> /dev/null; then
        if systemctl is-active --quiet docker; then
            echo -e "${YELLOW}• Docker服务: ${GREEN}运行中${PLAIN}"
        else
            echo -e "${YELLOW}• Docker服务: ${RED}未运行${PLAIN}"
        fi
    else
        echo -e "${YELLOW}• Docker服务: ${RED}未安装${PLAIN}"
    fi
    
    # 检查Mihomo容器状态
    if command -v docker &> /dev/null; then
        local container_status=$(docker ps -a --filter "name=mihomo" --format "{{.Status}}")
        if [[ -n "$container_status" ]]; then
            if [[ "$container_status" == *"Up"* ]]; then
                echo -e "${YELLOW}• Mihomo容器: ${GREEN}运行中${PLAIN}"
                echo -e "${YELLOW}• 状态详情: ${GREEN}$container_status${PLAIN}"
                
                # 如果容器正在运行，显示可用端口
                echo
                echo -e "${CYAN}代理端口:${PLAIN}"
                echo -e "${YELLOW}• 控制面板: ${GREEN}http://$mihomo_ip:9090/ui${PLAIN}"
                echo -e "${YELLOW}• HTTP代理: ${GREEN}$mihomo_ip:7891${PLAIN}"
                echo -e "${YELLOW}• SOCKS代理: ${GREEN}$mihomo_ip:7892${PLAIN}"
            else
                echo -e "${YELLOW}• Mihomo容器: ${RED}已停止${PLAIN}"
                echo -e "${YELLOW}• 状态详情: ${YELLOW}$container_status${PLAIN}"
            fi
        else
            echo -e "${YELLOW}• Mihomo容器: ${RED}未创建${PLAIN}"
        fi
    fi
    
    # 检查网络配置
    echo
    echo -e "${CYAN}网络配置:${PLAIN}"
    local macvlan_interface=$(get_state_value "macvlan_interface")
    
    # 检查主接口
    if ip link show dev $MAIN_INTERFACE &>/dev/null; then
        echo -e "${YELLOW}• 主接口: ${GREEN}$MAIN_INTERFACE - 已识别${PLAIN}"
    else
        echo -e "${YELLOW}• 主接口: ${RED}$MAIN_INTERFACE - 未找到${PLAIN}"
    fi
    
    # 检查macvlan接口
    if [[ -n "$macvlan_interface" ]]; then
        if ip link show dev $macvlan_interface &>/dev/null; then
            echo -e "${YELLOW}• macvlan接口: ${GREEN}$macvlan_interface - 已创建${PLAIN}"
        else
            echo -e "${YELLOW}• macvlan接口: ${RED}$macvlan_interface - 未找到${PLAIN}"
        fi
    fi
    
    echo -e "${CYAN}======================================================${PLAIN}"
    
    # 根据安装状态给出建议
    echo
    echo -e "${CYAN}建议操作:${PLAIN}"
    if [[ "$stage" == "Step2_Completed" ]]; then
        if [[ $(docker ps -q -f name=mihomo) ]]; then
            echo -e "${GREEN}• Mihomo正常运行中，可以使用代理服务${PLAIN}"
            echo -e "${GREEN}• 您可以通过控制面板管理Mihomo: http://$mihomo_ip:9090/ui${PLAIN}"
        else
            echo -e "${YELLOW}• Mihomo容器未运行，建议重启服务${PLAIN}"
            echo -e "${YELLOW}• 返回主菜单选择'重启服务'选项${PLAIN}"
        fi
    else
        echo -e "${YELLOW}• 您的安装尚未完成，建议完成完整安装${PLAIN}"
        echo -e "${YELLOW}• 返回主菜单选择'一键安装'或'分步安装'选项${PLAIN}"
    fi
    
    echo
    read -p "按任意键返回主菜单..." key
    show_menu
}

# 重启mihomo服务
restart_mihomo_service() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}              重启Mihomo服务${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    # 检查状态文件是否存在
    if [[ ! -f "$STATE_FILE" ]]; then
        echo -e "${YELLOW}未检测到Mihomo安装状态，请先完成安装。${PLAIN}"
        read -p "按任意键返回主菜单..." key
        show_menu
        return
    fi
    
    # 检查docker是否已安装
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker未安装，无法重启Mihomo服务${PLAIN}"
        echo -e "${YELLOW}请先完成Mihomo的安装${PLAIN}"
        read -p "按任意键返回主菜单..." key
        show_menu
        return
    fi
    
    # 重启mihomo容器
    echo -e "${CYAN}正在重启Mihomo容器...${PLAIN}"
    
    # 获取mihomo IP和接口信息
    local mihomo_ip=$(get_state_value "mihomo_ip")
    local stage=$(get_state_value "installation_stage")
    
    if [[ -z "$mihomo_ip" || "$stage" != "Step2_Completed" ]]; then
        echo -e "${YELLOW}警告: Mihomo似乎未完成安装。${PLAIN}"
        read -p "是否仍要尝试重启服务? (y/n): " continue_restart
        if [[ "$continue_restart" != "y" && "$continue_restart" != "Y" ]]; then
            show_menu
            return
        fi
    fi
    
    # 停止并删除已存在的容器
    docker stop mihomo 2>/dev/null
    docker rm mihomo 2>/dev/null
    
    # 重新启动代理配置
    if [[ -f "$PROXY_SCRIPT" ]]; then
        echo -e "${CYAN}正在重新启动Mihomo容器...${PLAIN}"
        if bash "$PROXY_SCRIPT" restart; then
            echo -e "${GREEN}Mihomo服务已成功重启!${PLAIN}"
            if [[ -n "$mihomo_ip" ]]; then
                echo -e "\n${GREEN}======================================================${PLAIN}"
                echo -e "${GREEN}访问信息:${PLAIN}"
                echo -e "${GREEN}• 控制面板: http://$mihomo_ip:9090/ui${PLAIN}"
                echo -e "${GREEN}• HTTP代理: $mihomo_ip:7891${PLAIN}"
                echo -e "${GREEN}• SOCKS代理: $mihomo_ip:7892${PLAIN}"
                echo -e "${GREEN}• 混合代理: $mihomo_ip:7890${PLAIN}"
                echo -e "${GREEN}======================================================${PLAIN}"
            fi
        else
            echo -e "${RED}重启Mihomo服务失败${PLAIN}"
        fi
    else
        echo -e "${RED}错误: 代理配置脚本不存在 ($PROXY_SCRIPT)${PLAIN}"
        echo -e "${YELLOW}请确保安装文件完整${PLAIN}"
    fi
    
    read -p "按任意键返回主菜单..." key
    show_menu
}

# 卸载mihomo
uninstall_mihomo() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${RED}              卸载Mihomo${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    echo -e "${YELLOW}警告: 此操作将完全卸载Mihomo及其配置${PLAIN}"
    echo -e "${YELLOW}包括：${PLAIN}"
    echo -e "${YELLOW}• 删除Mihomo容器${PLAIN}"
    echo -e "${YELLOW}• 删除网络配置${PLAIN}"
    echo -e "${YELLOW}• 删除配置文件${PLAIN}"
    echo
    
    read -p "是否确认卸载? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${GREEN}已取消卸载操作${PLAIN}"
        read -p "按任意键返回主菜单..." key
        show_menu
        return
    fi
    
    echo -e "${CYAN}开始卸载Mihomo...${PLAIN}"
    
    # 1. 停止和删除Docker容器
    if command -v docker &> /dev/null; then
        echo -e "${CYAN}正在停止并删除Mihomo容器...${PLAIN}"
        docker stop mihomo 2>/dev/null
        docker rm mihomo 2>/dev/null
        echo -e "${GREEN}Mihomo容器已删除${PLAIN}"
    fi
    
    # 2. 删除网络配置
    local macvlan_interface="mihomo_veth"
    if [[ -f "$STATE_FILE" ]]; then
        macvlan_interface=$(get_state_value "macvlan_interface")
    fi
    
    echo -e "${CYAN}正在删除网络配置...${PLAIN}"
    if ip link show $macvlan_interface &>/dev/null; then
        ip link delete $macvlan_interface 2>/dev/null
        echo -e "${GREEN}已删除macvlan接口: $macvlan_interface${PLAIN}"
    fi
    
    # 3. 删除配置文件
    echo -e "${CYAN}正在删除配置文件...${PLAIN}"
    rm -rf /etc/mihomo 2>/dev/null
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE" 2>/dev/null
        echo -e "${GREEN}已删除状态文件: $STATE_FILE${PLAIN}"
    fi
    
    echo -e "\n${GREEN}======================================================${PLAIN}"
    echo -e "${GREEN}Mihomo卸载完成!${PLAIN}"
    echo -e "${GREEN}======================================================${PLAIN}"
    
    read -p "按任意键返回主菜单..." key
    show_menu
}

# 配置路由器
configure_router() {
    # 检查状态文件是否存在
    local mihomo_ip=""
    local stage=""
    
    if [[ -f "$STATE_FILE" ]]; then
        mihomo_ip=$(get_state_value "mihomo_ip")
        stage=$(get_state_value "installation_stage")
    fi
    
    # 检查是否已配置IP
    if [[ -z "$mihomo_ip" ]]; then
        clear
        echo -e "${CYAN}======================================================${PLAIN}"
        echo -e "${CYAN}              路由器配置${PLAIN}"
        echo -e "${CYAN}======================================================${PLAIN}"
        echo -e "${YELLOW}未检测到Mihomo IP地址配置${PLAIN}"
        echo -e "${YELLOW}请先完成Mihomo的安装并配置IP地址${PLAIN}"
        echo -e "${YELLOW}建议选择'分步安装'或'一键安装'选项${PLAIN}"
        echo -e "${CYAN}======================================================${PLAIN}"
        read -p "按任意键返回主菜单..." key
        show_menu
        return
    fi
    
    # 执行路由器配置
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}              路由器配置${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    if [[ -f "$ROUTER_SCRIPT" ]]; then
        echo -e "${CYAN}正在生成路由器配置命令...${PLAIN}"
        bash "$ROUTER_SCRIPT"
        
        # 检查脚本执行结果
        if [[ $? -eq 0 ]]; then
            echo -e "\n${GREEN}======================================================${PLAIN}"
            echo -e "${GREEN}路由器配置已生成${PLAIN}"
            echo -e "${GREEN}请按照上方指南配置您的路由器，完成后即可使用Mihomo代理服务${PLAIN}"
            echo -e "${GREEN}======================================================${PLAIN}"
        else
            echo -e "\n${YELLOW}路由器配置生成可能未完成，请检查上方提示信息${PLAIN}"
        fi
    else
        echo -e "${RED}错误: 路由器配置脚本不存在${PLAIN}"
        echo -e "${YELLOW}请确保脚本文件存在: $ROUTER_SCRIPT${PLAIN}"
    fi
    
    read -p "按任意键返回主菜单..." key
    show_menu
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
    
    # 检测网络环境初始化网络相关变量 - 但不自动创建状态文件
    detect_network
    
    # 确保files目录存在
    if [[ ! -d "$FILES_DIR" ]]; then
        mkdir -p "$FILES_DIR"
        echo -e "${GREEN}已创建files目录: $FILES_DIR${PLAIN}"
    fi
    
    # 检查执行脚本是否存在
    check_exec_scripts
    
    # 显示主菜单
    show_menu
}

# 执行主函数
main
