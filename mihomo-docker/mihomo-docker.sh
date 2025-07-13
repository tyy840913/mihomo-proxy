#!/bin/bash
#############################################################
# Mihomo 一键安装脚本 V1.0
# 支持系统: Debian 10/11/12, Ubuntu 20.04/22.04/24.04
# 功能: 一键安装并配置Mihomo代理服务
#############################################################

# ====================================================================================
# 【使用说明】
# 
# 方法1 - 推荐：下载完整项目目录
#    git clone https://github.com/wallentv/mihomo-proxy.git
#    cd mihomo-proxy/mihomo-docker
#    bash mihomo.sh
#
# 方法2 - 直接下载脚本（支持自动下载依赖文件）:
#    curl -fsSL https://raw.githubusercontent.com/wallentv/mihomo-proxy/master/mihomo-docker/mihomo.sh -o mihomo.sh
#    chmod +x mihomo.sh
#    bash mihomo.sh
#
# 注意：方法2需要网络连接，脚本会自动从GitHub下载必要的执行脚本和配置文件
# 如果自动下载失败，请使用方法1或手动下载files目录下的文件
# 详细说明请参考项目README.md文件
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

# 检查并安装jq
check_and_install_jq() {
    if ! command -v jq &> /dev/null; then
        echo -e "${CYAN}正在安装jq...${PLAIN}"
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y jq
        elif command -v yum &> /dev/null; then
            yum install -y jq
        elif command -v dnf &> /dev/null; then
            dnf install -y jq
        elif command -v apk &> /dev/null; then
            apk add jq
        else
            echo -e "${RED}错误: 无法安装jq，请手动安装后再运行此脚本${PLAIN}"
            exit 1
        fi
        
        # 验证安装
        if command -v jq &> /dev/null; then
            echo -e "${GREEN}jq安装成功${PLAIN}"
        else
            handle_error "jq安装失败"
        fi
    fi
}

# 状态验证函数
validate_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        handle_error "状态文件不存在"
        return 1
    fi

    # 确保jq已安装
    check_and_install_jq

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
    local required_fields=("installation_stage" "timestamp")
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
        echo -e "${YELLOW}files目录不存在，正在创建...${PLAIN}"
        mkdir -p "$FILES_DIR"
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}错误: 无法创建目录 $FILES_DIR${PLAIN}"
            exit 1
        fi
        echo -e "${GREEN}已创建目录: $FILES_DIR${PLAIN}"
    fi
}

# 自动下载缺失的文件
download_missing_files() {
    local github_base_url="https://raw.githubusercontent.com/wallentv/mihomo-proxy/master/mihomo-docker/files"
    local required_files=("setup_proxy.sh" "setup_router.sh" "check_status.sh" "config.yaml")
    local download_needed=0
    
    echo -e "${CYAN}检查必要文件...${PLAIN}"
    
    # 检查哪些文件缺失
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
    
    # 检查网络连接和下载工具
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        echo -e "${RED}错误: 系统中没有找到curl或wget，无法下载文件${PLAIN}"
        echo -e "${YELLOW}请手动下载以下文件到 $FILES_DIR 目录:${PLAIN}"
        for file in "${required_files[@]}"; do
            echo -e "  - $github_base_url/$file"
        done
        return 1
    fi
    
    # 测试网络连接
    echo -e "${CYAN}测试网络连接...${PLAIN}"
    if command -v curl &> /dev/null; then
        if ! curl -fsSL --connect-timeout 10 "https://raw.githubusercontent.com" &> /dev/null; then
            echo -e "${RED}网络连接失败，无法访问GitHub${PLAIN}"
            echo -e "${YELLOW}请检查网络连接或手动下载文件${PLAIN}"
            return 1
        fi
    elif command -v wget &> /dev/null; then
        if ! wget -q --timeout=10 --spider "https://raw.githubusercontent.com" &> /dev/null; then
            echo -e "${RED}网络连接失败，无法访问GitHub${PLAIN}"
            echo -e "${YELLOW}请检查网络连接或手动下载文件${PLAIN}"
            return 1
        fi
    fi
    echo -e "${GREEN}网络连接正常${PLAIN}"
    
    echo -e "${CYAN}正在从GitHub下载缺失的文件...${PLAIN}"
    
    # 下载缺失的文件
    for file in "${required_files[@]}"; do
        if [[ ! -f "$FILES_DIR/$file" ]]; then
            echo -e "${CYAN}下载: $file${PLAIN}"
            
            local download_success=0
            
            # 尝试使用curl下载
            if command -v curl &> /dev/null; then
                if curl -fsSL "$github_base_url/$file" -o "$FILES_DIR/$file"; then
                    download_success=1
                fi
            # 尝试使用wget下载
            elif command -v wget &> /dev/null; then
                if wget -q "$github_base_url/$file" -O "$FILES_DIR/$file"; then
                    download_success=1
                fi
            fi
            
            if [[ $download_success -eq 1 ]]; then
                # 为脚本文件添加执行权限
                if [[ "$file" == *.sh ]]; then
                    chmod +x "$FILES_DIR/$file"
                fi
                echo -e "${GREEN}✓ 下载成功: $file${PLAIN}"
            else
                echo -e "${RED}✗ 下载失败: $file${PLAIN}"
                echo -e "${YELLOW}请手动下载: $github_base_url/$file${PLAIN}"
                return 1
            fi
        fi
    done
    
    echo -e "${GREEN}所有文件下载完成!${PLAIN}"
    return 0
}

# 检查执行脚本是否存在
check_exec_scripts() {
    # 检查files目录是否存在
    check_files_dir
    
    # 首先尝试自动下载缺失的文件
    if ! download_missing_files; then
        echo -e "${YELLOW}自动下载失败，尝试从当前目录加载文件...${PLAIN}"
    fi
    
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
        echo -e "${RED}错误: 缺少必要的文件。${PLAIN}"
        echo -e "${YELLOW}解决方案:${PLAIN}"
        echo -e "${YELLOW}1. 确保网络连接正常，脚本会自动从GitHub下载${PLAIN}"
        echo -e "${YELLOW}2. 手动下载完整的mihomo-proxy目录:${PLAIN}"
        echo -e "   git clone https://github.com/wallentv/mihomo-proxy.git${PLAIN}"
        echo -e "   cd mihomo-proxy/mihomo-docker${PLAIN}"
        echo -e "   bash mihomo.sh${PLAIN}"
        echo -e "${YELLOW}3. 手动下载以下文件到 $FILES_DIR 目录:${PLAIN}"
        echo -e "   - setup_proxy.sh${PLAIN}"
        echo -e "   - setup_router.sh${PLAIN}"
        echo -e "   - check_status.sh${PLAIN}"
        echo -e "   - config.yaml${PLAIN}"
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
    
    if [[ ! -f "$STATE_FILE" ]]; then
        # 创建新的状态文件
        cat > "$STATE_FILE" << EOF
{
  "version": "$STATE_VERSION",
  "installation_stage": "初始化",
  "config_type": "preset",
  "docker_method": "direct_pull",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF
        log_message "创建本地状态文件: $STATE_FILE"
        echo -e "${GREEN}已创建状态文件${PLAIN}"
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
    
    # 确保jq已安装
    check_and_install_jq
    
    value=$(jq -r ".$key // \"\"" "$STATE_FILE" 2>/dev/null)
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
    
    # 确保jq已安装
    check_and_install_jq
    
    # 使用jq更新状态值
    jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$STATE_FILE" > "${STATE_FILE}.tmp"
    if [[ $? -eq 0 ]]; then
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
        
        # 更新时间戳
        jq --arg ts "$(date '+%Y-%m-%d %H:%M:%S')" '.timestamp = $ts' "$STATE_FILE" > "${STATE_FILE}.tmp"
        if [[ $? -eq 0 ]]; then
            mv "${STATE_FILE}.tmp" "$STATE_FILE"
        fi
    else
        echo -e "${YELLOW}警告: 状态更新失败${PLAIN}"
        rm -f "${STATE_FILE}.tmp"
        return 1
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
    local stage=""
    
    if [[ -f "$STATE_FILE" ]]; then
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
    if [[ "$stage" == "Step1_Completed" || "$stage" == "Step2_Completed" ]]; then
        echo -e " ${GREEN}[✓] 1. 初始化设置${PLAIN}    - ${GREEN}步骤1完成!${PLAIN}"
    else
        echo -e " ${CYAN}[1] 1. 初始化设置${PLAIN}    - ${YELLOW}检查配置脚本 ${RED}[未完成]${PLAIN}"
    fi
    
    # 步骤2: 代理机配置
    if [[ "$stage" == "Step2_Completed" ]]; then
        echo -e " ${GREEN}[✓] 2. 配置代理机${PLAIN}    - ${GREEN}步骤2完成! Mihomo代理已安装并启动${PLAIN}"
    elif [[ "$stage" == "Step1_Completed" || "$stage" == "Step2_"* ]]; then
        echo -e " ${CYAN}[2] 2. 配置代理机${PLAIN}    - ${YELLOW}安装Docker和Mihomo${PLAIN}"
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
    if [[ "$stage" == "Step2_Completed" ]]; then
        echo -e "${YELLOW}系统信息:${PLAIN}"
        echo -e "${YELLOW}• 控制面板: ${GREEN}http://<宿主机IP>:9090/ui${PLAIN}"
        echo -e "${YELLOW}• HTTP代理: ${GREEN}<宿主机IP>:7891${PLAIN}"
        echo -e "${YELLOW}• SOCKS5代理: ${GREEN}<宿主机IP>:7892${PLAIN}"
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
    local stage=""
    local timestamp=""
    
    if [[ -f "$STATE_FILE" ]]; then
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
    echo -e " ${PURPLE}[6] 6. 重置配置${PLAIN}      - ${YELLOW}重置配置文件并重启服务${PLAIN}"
    echo -e " ${RED}[7] 7. 卸载Mihomo${PLAIN}    - ${YELLOW}完全卸载Mihomo及其配置${PLAIN}"
    echo -e " ${GREEN}[0] 0. 退出脚本${PLAIN}"
    echo -e "${CYAN}===========================================================${PLAIN}"
    
    # 显示当前状态（如果有）
    if [[ -n "$stage" ]]; then
        echo -e "${YELLOW}系统信息:${PLAIN}"
        echo -e "${YELLOW}• 安装阶段: ${GREEN}$stage${PLAIN}"
        echo -e "${YELLOW}• 更新时间: ${GREEN}$timestamp${PLAIN}"
        if [[ "$stage" == "Step2_Completed" ]]; then
            echo -e "${YELLOW}• 控制面板: ${GREEN}http://<宿主机IP>:9090/ui${PLAIN}"
        fi
    fi
    echo
    
    read -p "请输入选择 [0-7]: " choice
    
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
            # 重置配置文件
            reset_config_file
            ;;
        7)
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
    echo -e "${YELLOW}这一步将检查配置脚本${PLAIN}"
    echo
    
    # 检查状态文件是否已存在
    if [[ ! -f "$STATE_FILE" ]]; then
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
  "installation_stage": "初始化",
  "config_type": "preset",
  "docker_method": "direct_pull",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF
        chmod 644 "$STATE_FILE"
        echo -e "${GREEN}初始状态文件已创建${PLAIN}"
    fi
    
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
    
    echo -e "\n${GREEN}======================================================${PLAIN}"
    echo -e "${GREEN}步骤1完成!${PLAIN}"
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
    local stage=""
    
    if [[ -f "$STATE_FILE" ]]; then
        stage=$(get_state_value "installation_stage")
    fi
    
    # 检查是否已完成初始化
    if [[ -z "$stage" || "$stage" == "未初始化" ]]; then
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
        echo -e "${GREEN}控制面板: http://<宿主机IP>:9090/ui${PLAIN}"
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
    local stage=$(get_state_value "installation_stage")
    
    if [[ "$stage" == "Step2_Completed" ]]; then
        echo -e "${GREEN}安装成功!${PLAIN}"
        echo -e "\n${GREEN}======================================================${PLAIN}"
        echo -e "${GREEN}Mihomo 代理已成功安装!${PLAIN}"
        echo -e "${GREEN}======================================================${PLAIN}"
        echo -e "${YELLOW}控制面板: ${GREEN}http://<宿主机IP>:9090/ui${PLAIN}"
        echo -e "${YELLOW}混合代理: ${GREEN}<宿主机IP>:7890${PLAIN}"
        echo -e "${YELLOW}HTTP代理: ${GREEN}<宿主机IP>:7891${PLAIN}"
        echo -e "${YELLOW}SOCKS代理: ${GREEN}<宿主机IP>:7892${PLAIN}"
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
    
    # 调用专门的状态检查脚本
    if [[ -f "$CHECK_SCRIPT" ]]; then
        echo -e "${CYAN}正在执行详细状态检查...${PLAIN}"
        echo
        bash "$CHECK_SCRIPT"
        
        # 检查脚本执行结果
        if [[ $? -eq 0 ]]; then
            echo -e "\n${GREEN}状态检查完成${PLAIN}"
        else
            echo -e "\n${YELLOW}状态检查可能遇到问题，请查看上方详细信息${PLAIN}"
        fi
    else
        echo -e "${RED}错误: 状态检查脚本不存在${PLAIN}"
        echo -e "${YELLOW}请确保脚本文件存在: $CHECK_SCRIPT${PLAIN}"
        
        # 提供基本的状态信息作为备用
        local stage=$(get_state_value "installation_stage")
        
        echo -e "\n${CYAN}基本状态信息:${PLAIN}"
        echo -e "${YELLOW}• 安装阶段: ${GREEN}$stage${PLAIN}"
        
        if command -v docker &> /dev/null && docker ps --filter "name=mihomo" --format "{{.Status}}" | grep -q "Up"; then
            echo -e "${YELLOW}• 容器状态: ${GREEN}运行中${PLAIN}"
            echo -e "${YELLOW}• 控制面板: ${GREEN}http://<宿主机IP>:9090/ui${PLAIN}"
        else
            echo -e "${YELLOW}• 容器状态: ${RED}未运行或未安装${PLAIN}"
        fi
    fi
    
    echo
    read -p "按任意键返回主菜单..." key
    show_menu
}

# 重启Mihomo服务
restart_mihomo_service() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${PURPLE}              重启Mihomo服务${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    # 检查Mihomo是否已安装
    if [[ ! -f "$STATE_FILE" ]]; then
        echo -e "${YELLOW}未检测到Mihomo安装状态，请先完成安装。${PLAIN}"
        read -p "按任意键返回主菜单..." key
        show_menu
        return
    fi
    
    local stage=$(get_state_value "installation_stage")
    
    if [[ "$stage" != "Step2_Completed" ]]; then
        echo -e "${YELLOW}Mihomo似乎未完成安装，请先完成安装。${PLAIN}"
        read -p "按任意键返回主菜单..." key
        show_menu
        return
    fi
    
    echo -e "${CYAN}当前配置信息:${PLAIN}"
    echo -e "${YELLOW}• 安装阶段: $stage${PLAIN}"
    
    # 检查配置文件是否存在
    if [[ ! -f "/etc/mihomo/config.yaml" ]]; then
        echo -e "${RED}错误: 配置文件不存在 (/etc/mihomo/config.yaml)${PLAIN}"
        echo -e "${YELLOW}请先完成完整安装或手动创建配置文件${PLAIN}"
        read -p "按任意键返回主菜单..." key
        show_menu
        return
    fi
    
    echo -e "${CYAN}正在调用执行脚本重启服务...${PLAIN}"
    
    # 调用setup_proxy.sh脚本的重启模式
    if [[ -f "$FILES_DIR/setup_proxy.sh" ]]; then
        bash "$FILES_DIR/setup_proxy.sh" restart
        
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}✓ Mihomo服务重启完成${PLAIN}"
        else
            echo -e "${RED}✗ Mihomo服务重启失败${PLAIN}"
            echo -e "${YELLOW}请检查错误信息或尝试手动重启${PLAIN}"
        fi
    else
        echo -e "${RED}错误: 执行脚本不存在 ($FILES_DIR/setup_proxy.sh)${PLAIN}"
        echo -e "${YELLOW}请确保files目录下有setup_proxy.sh文件${PLAIN}"
    fi
    
    read -p "按任意键返回主菜单..." key
    show_menu
}

# 重置配置文件
reset_config_file() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${PURPLE}              重置Mihomo配置文件${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    # 检查Mihomo是否已安装
    if [[ ! -f "$STATE_FILE" ]]; then
        echo -e "${YELLOW}未检测到Mihomo安装状态，请先完成安装。${PLAIN}"
        read -p "按任意键返回主菜单..." key
        show_menu
        return
    fi
    
    local stage=$(get_state_value "installation_stage")
    
    if [[ "$stage" != "Step2_Completed" ]]; then
        echo -e "${YELLOW}Mihomo似乎未完成安装，请先完成安装。${PLAIN}"
        read -p "按任意键返回主菜单..." key
        show_menu
        return
    fi
    
    echo -e "${YELLOW}警告: 此操作将重置Mihomo配置文件${PLAIN}"
    echo -e "${YELLOW}包括：${PLAIN}"
    echo -e "${YELLOW}• 删除当前的config.yaml配置文件${PLAIN}"
    echo -e "${YELLOW}• 恢复为默认模板配置${PLAIN}"
    echo -e "${YELLOW}• 重启Mihomo服务${PLAIN}"
    echo -e "${RED}• 您的自定义配置将会丢失！${PLAIN}"
    echo
    
    # 显示当前配置文件信息
    if [[ -f "/etc/mihomo/config.yaml" ]]; then
        echo -e "${CYAN}当前配置文件信息:${PLAIN}"
        echo -e "${YELLOW}• 文件路径: /etc/mihomo/config.yaml${PLAIN}"
        echo -e "${YELLOW}• 文件大小: $(du -h /etc/mihomo/config.yaml | cut -f1)${PLAIN}"
        echo -e "${YELLOW}• 修改时间: $(stat -c %y /etc/mihomo/config.yaml 2>/dev/null || stat -f %Sm /etc/mihomo/config.yaml)${PLAIN}"
        echo
    fi
    
    read -p "是否确认重置配置文件? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${GREEN}已取消重置操作${PLAIN}"
        read -p "按任意键返回主菜单..." key
        show_menu
        return
    fi
    
    echo -e "${CYAN}正在调用执行脚本重置配置...${PLAIN}"
    
    # 调用setup_proxy.sh脚本的重置模式
    if [[ -f "$FILES_DIR/setup_proxy.sh" ]]; then
        bash "$FILES_DIR/setup_proxy.sh" reset
        
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}✓ 配置重置完成${PLAIN}"
            echo -e "\n${YELLOW}重要提示:${PLAIN}"
            echo -e "${YELLOW}• 配置文件已重置为默认模板${PLAIN}"
            echo -e "${YELLOW}• 请编辑 /etc/mihomo/config.yaml 添加您的代理服务器${PLAIN}"
            echo -e "${YELLOW}• 修改配置后需要重启服务才能生效${PLAIN}"
        else
            echo -e "${RED}✗ 配置重置失败${PLAIN}"
            echo -e "${YELLOW}请检查错误信息或尝试手动重置${PLAIN}"
        fi
    else
        echo -e "${RED}错误: 执行脚本不存在 ($FILES_DIR/setup_proxy.sh)${PLAIN}"
        echo -e "${YELLOW}请确保files目录下有setup_proxy.sh文件${PLAIN}"
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
    echo -e "${YELLOW}• 删除Mihomo容器和镜像${PLAIN}"
    echo -e "${YELLOW}• 删除配置文件和状态文件${PLAIN}"
    echo
    
    read -p "是否确认卸载? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${GREEN}已取消卸载操作${PLAIN}"
        read -p "按任意键返回主菜单..." key
        show_menu
        return
    fi
    
    echo -e "${CYAN}开始彻底卸载Mihomo...${PLAIN}"
    
    # 1. 停止和删除Docker容器
    if command -v docker &> /dev/null; then
        echo -e "${CYAN}正在停止并删除Mihomo容器...${PLAIN}"
        docker stop mihomo 2>/dev/null
        docker rm mihomo 2>/dev/null
        echo -e "${GREEN}✓ Mihomo容器已删除${PLAIN}"
        
        # 可选：删除Mihomo镜像
        echo -e "${CYAN}检查Mihomo镜像...${PLAIN}"
        if docker images | grep -q metacubex/mihomo; then
            read -p "是否同时删除Mihomo镜像? (y/n): " remove_image
            if [[ "$remove_image" == "y" || "$remove_image" == "Y" ]]; then
                docker rmi metacubex/mihomo:latest 2>/dev/null
                echo -e "${GREEN}✓ Mihomo镜像已删除${PLAIN}"
            else
                echo -e "${YELLOW}⚠ 保留Mihomo镜像${PLAIN}"
            fi
        fi
    fi
    
    # 2. 删除配置文件和目录
    echo -e "${CYAN}正在删除配置文件...${PLAIN}"
    if [[ -d "/etc/mihomo" ]]; then
        rm -rf /etc/mihomo 2>/dev/null
        echo -e "${GREEN}✓ 已删除配置目录: /etc/mihomo${PLAIN}"
    else
        echo -e "${YELLOW}⚠ 配置目录不存在: /etc/mihomo${PLAIN}"
    fi
    
    # 删除状态文件
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE" 2>/dev/null
        echo -e "${GREEN}✓ 已删除状态文件: $STATE_FILE${PLAIN}"
    else
        echo -e "${YELLOW}⚠ 状态文件不存在: $STATE_FILE${PLAIN}"
    fi
    
    # 删除日志文件
    if [[ -f "$LOG_FILE" ]]; then
        rm -f "$LOG_FILE" 2>/dev/null
        echo -e "${GREEN}✓ 已删除日志文件: $LOG_FILE${PLAIN}"
    fi
    
    echo -e "\n${GREEN}======================================================${PLAIN}"
    echo -e "${GREEN}Mihomo彻底卸载完成!${PLAIN}"
    echo -e "${GREEN}======================================================${PLAIN}"
    echo -e "${GREEN}已清理的项目:${PLAIN}"
    echo -e "${GREEN}• Docker容器${PLAIN}"
    echo -e "${GREEN}• 配置文件和状态文件${PLAIN}"
    echo -e "${GREEN}======================================================${PLAIN}"
    
    read -p "按任意键返回主菜单..." key
    show_menu
}

# 配置路由器
configure_router() {
    # 检查状态文件是否存在
    local stage=""
    
    if [[ -f "$STATE_FILE" ]]; then
        stage=$(get_state_value "installation_stage")
    fi
    
    # 检查是否已配置IP
    if [[ -z "$stage" || "$stage" != "Step2_Completed" ]]; then
        clear
        echo -e "${CYAN}======================================================${PLAIN}"
        echo -e "${CYAN}              路由器配置${PLAIN}"
        echo -e "${CYAN}======================================================${PLAIN}"
        echo -e "${YELLOW}请先完成Mihomo的安装${PLAIN}"
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
