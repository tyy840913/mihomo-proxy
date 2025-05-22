#!/bin/bash
#############################################################
# Mihomo 代理机配置脚本
# 此脚本将安装Docker和Mihomo，并配置网络
#############################################################

# 设置颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 日志文件路径
LOG_FILE="/var/log/mihomo-proxy.log"

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
CONF_DIR="/etc/mihomo"

# 获取状态值
get_state_value() {
    local key=$1
    
    # 如果状态文件不存在，返回空值
    if [[ ! -f "$STATE_FILE" ]]; then
        echo -e "${YELLOW}警告: 状态文件不存在${PLAIN}" >&2
        echo ""
        return 1
    fi
    
    local value=$(jq -r ".$key" "$STATE_FILE" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        echo -e "${YELLOW}警告: 无法读取状态文件中的 '$key'${PLAIN}" >&2
        echo ""
        return 1
    fi
    
    echo "$value"
}

# 更新状态值
update_state() {
    local key=$1
    local value=$2
    
    # 如果状态文件不存在，尝试创建它
    if [[ ! -f "$STATE_FILE" ]]; then
        echo -e "${YELLOW}警告: 状态文件不存在，尝试创建...${PLAIN}"
        
        # 确保 FILES_DIR 目录存在
        if [[ ! -d "$FILES_DIR" ]]; then
            mkdir -p "$FILES_DIR"
            if [[ $? -ne 0 ]]; then
                handle_error "错误: 无法创建目录 $FILES_DIR"
            fi
            echo -e "${GREEN}已创建目录: $FILES_DIR${PLAIN}"
        fi
        
        # 创建基本状态文件
        cat > "$STATE_FILE" << EOF
{
  "version": "1.0",
  "mihomo_ip": "",
  "interface_ip": "",
  "main_interface": "$(ip route | grep default | awk '{print $5}' | head -n 1)",
  "macvlan_interface": "mihomo_veth",
  "installation_stage": "初始化",
  "config_type": "",
  "docker_method": "direct_pull",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF
        log_message "信息" "创建了新的状态文件"
    fi
    
    jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$STATE_FILE" > "${STATE_FILE}.tmp"
    if [[ $? -eq 0 ]]; then
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
        log_message "信息" "更新状态: $key = $value"
    else
        handle_error "错误: 无法更新状态文件"
    fi
}

# 检查Docker是否已安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}未检测到Docker，将自动安装...${PLAIN}"
        return 1
    fi
    return 0
}

# 安装Docker
install_docker() {
    echo -e "${CYAN}正在安装Docker...${PLAIN}"
    
    # 安装必要的软件包
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    
    # 添加Docker官方GPG密钥
    curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
    
    # 添加Docker软件源
    echo "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    
    # 更新软件包列表并安装Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # 启动Docker服务
    systemctl start docker
    systemctl enable docker
    
    # 验证安装
    if docker --version &> /dev/null; then
        echo -e "${GREEN}Docker安装完成${PLAIN}"
        return 0
    else
        handle_error "错误: Docker安装失败"
    fi
}

# 创建Docker网络
create_docker_network() {
    local mihomo_ip=$(get_state_value "mihomo_ip")
    local interface_ip=$(get_state_value "interface_ip")
    local main_interface=$(get_state_value "main_interface")
    local macvlan_interface=$(get_state_value "macvlan_interface")
    macvlan_interface=${macvlan_interface:-"mihomo_veth"}
    
    echo -e "${CYAN}正在检查Docker macvlan网络...${PLAIN}"
    
    # 先检查网络是否已存在
    if docker network ls | grep -q mnet; then
        echo -e "${YELLOW}Docker macvlan网络 'mnet' 已存在，跳过创建步骤${PLAIN}"
    else
        echo -e "${CYAN}正在创建Docker macvlan网络...${PLAIN}"
        
        # 创建macvlan网络
        docker network create -d macvlan \
            --subnet=$(ip route | grep default | awk '{print $3}' | cut -d. -f1-3).0/24 \
            --gateway=$(ip route | grep default | awk '{print $3}') \
            -o parent=$main_interface \
            mnet
            
        if [[ $? -ne 0 ]]; then
            handle_error "错误: Docker网络创建失败"
        fi
        
        echo -e "${GREEN}Docker网络已创建${PLAIN}"
    fi
    
    # 确保主机上也有对应的macvlan接口
    echo -e "${CYAN}正在检查主机macvlan接口...${PLAIN}"
    if ip link show | grep -q "$macvlan_interface"; then
        echo -e "${YELLOW}主机macvlan接口 '$macvlan_interface' 已存在，跳过创建步骤${PLAIN}"
    else
        echo -e "${CYAN}正在创建主机macvlan接口...${PLAIN}"
        
        # 创建macvlan接口
        ip link add $macvlan_interface link $main_interface type macvlan mode bridge
        
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}警告: 主机macvlan接口创建失败，将尝试继续${PLAIN}"
        else
            # 配置接口IP并启用
            ip addr add $interface_ip/24 dev $macvlan_interface
            ip link set $macvlan_interface up
            
            # 添加到mihomo_ip的路由
            ip route add $mihomo_ip dev $macvlan_interface
            
            echo -e "${GREEN}主机macvlan接口已创建并配置${PLAIN}"
        fi
    fi
    
    # 设置主接口为混杂模式
    echo -e "${CYAN}正在设置主接口为混杂模式...${PLAIN}"
    ip link set $main_interface promisc on
    
    # 创建持久化的混杂模式服务
    echo -e "${CYAN}正在创建混杂模式持久化服务...${PLAIN}"
    cat > "/etc/systemd/system/promisc-$main_interface.service" << EOF
[Unit]
Description=Set $main_interface interface to promiscuous mode
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/ip link set $main_interface promisc on
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # 启用服务
    systemctl daemon-reload
    systemctl enable "promisc-$main_interface.service"
    
    # 检查接口状态 - 简化接口状态输出
    echo -e "${CYAN}检查网络配置状态...${PLAIN}"
    if ip link show $main_interface | grep -q "PROMISC"; then
        echo -e "${GREEN}主接口已设置为混杂模式${PLAIN}"
    else
        echo -e "${RED}警告: 主接口混杂模式可能未生效${PLAIN}"
    fi
    
    if ip link show $macvlan_interface 2>/dev/null; then
        echo -e "${GREEN}macvlan接口已创建${PLAIN}"
    else
        echo -e "${RED}警告: macvlan接口未找到${PLAIN}"
    fi
}

# 创建配置目录
create_config_dir() {
    echo -e "${CYAN}正在创建配置目录...${PLAIN}"
    
    mkdir -p "$CONF_DIR"
    if [[ $? -ne 0 ]]; then
        handle_error "错误: 配置目录创建失败"
    fi
    
    echo -e "${GREEN}配置目录已创建${PLAIN}"
}

# 复制配置文件
copy_config_file() {
    # 直接从files目录中获取配置文件
    local config_template="$FILES_DIR/config.yaml"
    
    echo -e "${CYAN}正在复制配置文件...${PLAIN}"
    
    # 创建配置目录
    mkdir -p "$CONF_DIR"
    
    # 检查配置文件是否存在
    if [[ ! -f "$config_template" ]]; then
        handle_error "错误: 配置文件不存在($config_template)"
    else
        echo -e "${GREEN}找到配置文件: $config_template${PLAIN}"
    fi
    
    # 复制配置文件
    cp "$config_template" "$CONF_DIR/config.yaml"
    if [[ $? -ne 0 ]]; then
        handle_error "错误: 配置文件复制失败"
    fi
    
    # 设置配置文件权限
    chmod 644 "$CONF_DIR/config.yaml"
    echo -e "${GREEN}配置文件已复制到 $CONF_DIR/config.yaml${PLAIN}"
    
    # 下载和设置UI包
    echo -e "${CYAN}正在设置UI界面...${PLAIN}"
    mkdir -p "$CONF_DIR/ui"
    
    # 检查是否已存在UI文件
    if [[ -f "$CONF_DIR/ui/index.html" ]]; then
        echo -e "${YELLOW}UI文件已存在，跳过下载${PLAIN}"
    else
        echo -e "${CYAN}正在下载最新版metacubexd界面...${PLAIN}"
        
        # 下载UI包
        if ! command -v wget &> /dev/null; then
            echo -e "${YELLOW}未安装wget，正在安装...${PLAIN}"
            apt-get update && apt-get install -y wget
        fi
        
        # 创建临时目录
        local tmp_dir=$(mktemp -d)
        cd "$tmp_dir"
        
        # 下载并解压UI包
        if ! wget https://github.com/MetaCubeX/metacubexd/releases/download/v1.187.1/compressed-dist.tgz; then
            echo -e "${RED}警告: UI包下载失败，将使用无UI模式${PLAIN}"
        else
            tar -xzf compressed-dist.tgz -C "$CONF_DIR/ui"
            echo -e "${GREEN}UI界面已设置${PLAIN}"
        fi
        
        # 清理临时文件
        cd - > /dev/null
        rm -rf "$tmp_dir"
    fi
    
    echo -e "${GREEN}配置设置完成${PLAIN}"
    echo -e "${YELLOW}如需修改配置，请使用文本编辑器编辑 $CONF_DIR/config.yaml 文件${PLAIN}"
    echo -e "${YELLOW}建议使用第三方工具修改yaml配置文件，确保格式正确${PLAIN}"
}

# 启动Mihomo容器
start_mihomo_container() {
    local mihomo_ip=$(get_state_value "mihomo_ip")
    local interface_ip=$(get_state_value "interface_ip")
    
    echo -e "${CYAN}正在启动Mihomo容器...${PLAIN}"
    
    # 停止并删除已存在的容器
    docker stop mihomo 2>/dev/null
    docker rm mihomo 2>/dev/null
    
    # 启动新容器 - 按照参考脚本的格式
    docker run -d --privileged \
        --name=mihomo --restart=always \
        --network mnet --ip "$mihomo_ip" \
        -v "$CONF_DIR:/root/.config/mihomo/" \
        metacubex/mihomo:latest
        
    if [[ $? -ne 0 ]]; then
        handle_error "错误: 容器启动失败"
    fi
    
    echo -e "${GREEN}Mihomo容器已启动${PLAIN}"
}

# 主函数
main() {
    # 创建日志文件
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    log_message "信息" "开始执行代理机配置脚本"
    
    # 检查Docker
    if ! check_docker; then
        install_docker
    fi
    
    # 创建Docker网络
    create_docker_network
    
    # 创建配置目录
    create_config_dir
    
    # 复制配置文件
    copy_config_file
    
    # 启动Mihomo容器
    start_mihomo_container
    
    # 更新安装状态
    update_state "installation_stage" "Step2_Completed"
    update_state "config_type" "preset"
    update_state "timestamp" "$(date '+%Y-%m-%d %H:%M:%S')"
    
    # 显示完成信息
    local mihomo_ip=$(get_state_value "mihomo_ip")
    echo -e "\n${GREEN}======================================================${PLAIN}"
    echo -e "${GREEN}代理机配置完成！${PLAIN}"
    echo -e "${GREEN}控制面板地址: http://${mihomo_ip}:9090/ui${PLAIN}"
    echo -e "${GREEN}======================================================${PLAIN}"
    
    log_message "信息" "代理机配置脚本执行完成"
}

# 执行主函数
main
