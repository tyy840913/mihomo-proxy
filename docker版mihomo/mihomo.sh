#!/bin/bash
#############################################################
# Mihomo 一键安装引导脚本 V1.0
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
#    如果无法自动获取权限，您可以手动执行:
#    sudo bash /opt/mihomo.sh
#    或者:
#    chmod +x /opt/mihomo.sh
#    sudo ./opt/mihomo.sh
#    
# 3. 查看使用帮助:
#    bash /opt/mihomo.sh -h
#    或者
#    bash /opt/mihomo.sh --help
# ====================================================================================

# 使用说明
# ====================================================================================
# 1. 请先确保以root用户运行此脚本: sudo bash mihomo.sh
# 2. 脚本将自动引导您设置mihomo IP地址，这是最重要的第一步
# 3. 安装流程:
#    - 第一步: 设置代理机IP地址 (自动执行)
#    - 第二步: 配置代理机 (选项1)
#    - 第三步: 配置RouterOS或其他路由器 (选项2)
# 4. 脚本会自动检测网络环境并生成配置，用户只需进行简单选择
# 5. 配置完成后可以使用选项3检查安装状态
# 6. 如需查看此使用说明，请使用 bash mihomo.sh -h 或 bash mihomo.sh --help
# ====================================================================================

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

# 设置颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
PLAIN='\033[0m'

# 主目录设置
SCRIPT_DIR="/root/mihomo-proxy/docker版mihomo"
FILES_DIR="$SCRIPT_DIR/files"
CONF_DIR="/etc/mihomo"

# 创建文件存放目录
mkdir -p "$FILES_DIR"

# 文件路径设置
STATE_FILE="$FILES_DIR/mihomo_state.json"
PROXY_SCRIPT="$FILES_DIR/setup_proxy.sh"
ROUTER_SCRIPT="$FILES_DIR/setup_router.sh"
CONFIG_TEMPLATE="$FILES_DIR/config.yaml"

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
                if ([[ ! -x "$SCRIPT_PATH" ]]); then
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
    if ([[ -f /etc/os-release ]]); then
        . /etc/os-release
        OS=$ID
        VERSION_ID=$VERSION_ID
    else
        echo -e "${RED}无法确定操作系统类型${PLAIN}"
        exit 1
    fi
    
    if ([[ $OS != "debian" && $OS != "ubuntu" ]]); then
        echo -e "${RED}错误: 此脚本只支持 Debian 或 Ubuntu 系统${PLAIN}"
        exit 1
    fi
    
    echo -e "${GREEN}检测到 $OS $VERSION_ID 系统${PLAIN}"
}

# 网络接口检测
detect_network() {
    echo -e "${CYAN}正在检测网络环境...${PLAIN}"
    # 检测主网络接口
    MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
    if ([[ -z "$MAIN_INTERFACE" ]]); then
        echo -e "${RED}错误: 无法检测到默认网络接口${PLAIN}"
        exit 1
    fi
    
    # 获取当前IP和网段
    CURRENT_IP=$(ip -4 addr show $MAIN_INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
    if ([[ -z "$CURRENT_IP" ]]); then
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
    if ([[ ! -f "$STATE_FILE" ]]); then
        cat > "$STATE_FILE" << EOF
{
  "mihomo_ip": "",
  "interface_ip": "",
  "main_interface": "$MAIN_INTERFACE",
  "macvlan_interface": "mihomo_veth",
  "installation_stage": "初始化",
  "config_type": "",
  "subscription_url": "",
  "docker_method": "direct_pull",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF
    else
        echo -e "${YELLOW}发现现有配置状态文件，将从上次中断的地方继续${PLAIN}"
    fi
}

# 从状态文件读取值
get_state_value() {
    local key=$1
    if ([[ -f "$STATE_FILE" ]]); then
        value=$(grep -o "\"$key\": \"[^\"]*\"" "$STATE_FILE" | cut -d '"' -f 4)
        echo "$value"
    else
        echo ""
    fi
}

# 更新状态文件中的值
update_state() {
    local key=$1
    local value=$2
    if ([[ -f "$STATE_FILE" ]]); then
        sed -i "s|\"$key\": \"[^\"]*\"|\"$key\": \"$value\"|g" "$STATE_FILE"
    fi
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
        if ([[ "$ip" == "$GATEWAY" ]]); then
            continue
        fi
        
        # 跳过当前主机IP
        if ([[ "$ip" == "$CURRENT_IP" ]]); then
            continue
        fi
        
        # 检查IP是否已被使用
        if ping -c 1 -W 1 "$ip" &> /dev/null; then
            echo -e "${YELLOW}IP $ip 已被使用${PLAIN}"
            continue
        fi
        
        # 进一步用arping确认IP未被使用
        if command -v arping &> /dev/null; then
            if arping -c 2 -w 2 -I "$MAIN_INTERFACE" "$ip" &> /dev/null; then
                echo -e "${YELLOW}IP $ip 已被使用 (arping检测)${PLAIN}"
                continue
            fi
        fi
        
        echo -e "${GREEN}找到可用IP: $ip${PLAIN}"
        return 0
    done
    
    echo -e "${RED}在指定范围内没有找到可用IP${PLAIN}"
    return 1
}

# 交互式设置mihomo IP
setup_mihomo_ip() {
    local stored_ip=$(get_state_value "mihomo_ip")
    
    if ([[ -n "$stored_ip" ]]); then
        read -p "检测到之前配置的mihomo IP: $stored_ip, 是否使用此IP? (y/n): " use_stored
        if ([[ "$use_stored" == "y" || "$use_stored" == "Y" ]]); then
            MIHOMO_IP=$stored_ip
            return 0
        fi
    fi
    
    # 自动检测合适的IP
    local suggested_ip="${SUBNET_PREFIX}.4"
    if ping -c 1 -W 1 "$suggested_ip" &> /dev/null; then
        # 如果默认IP已使用，寻找可用IP
        for i in {5..20}; do
            suggested_ip="${SUBNET_PREFIX}.${i}"
            if ! ping -c 1 -W 1 "$suggested_ip" &> /dev/null; then
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
    if ! ([[ $MIHOMO_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]); then
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
    update_state "mihomo_ip" "$MIHOMO_IP"
    
    # 设置接口IP (mihomo IP + 1)
    local ip_parts=(${MIHOMO_IP//./ })
    local last_octet=$((ip_parts[3] + 1))
    INTERFACE_IP="${ip_parts[0]}.${ip_parts[1]}.${ip_parts[2]}.$last_octet"
    
    # 验证接口IP是否可用
    if ping -c 1 -W 1 "$INTERFACE_IP" &> /dev/null; then
        echo -e "${YELLOW}警告: IP $INTERFACE_IP 已被使用，将寻找其他可用IP作为接口IP${PLAIN}"
        for i in $(seq $((last_octet+1)) 254); do
            INTERFACE_IP="${ip_parts[0]}.${ip_parts[1]}.${ip_parts[2]}.$i"
            if ! ping -c 1 -W 1 "$INTERFACE_IP" &> /dev/null; then
                echo -e "${GREEN}将使用 $INTERFACE_IP 作为接口IP${PLAIN}"
                break
            fi
        done
    fi
    
    update_state "interface_ip" "$INTERFACE_IP"
}

# 创建默认配置文件模板
create_config_template() {
    if ([[ ! -f "$CONFIG_TEMPLATE" ]]); then
        echo -e "${CYAN}创建默认配置文件模板...${PLAIN}"
        
        # 获取脚本所在目录
        SCRIPT_DIR_PATH=$(dirname "$(readlink -f "$0")")
        
        # 使用用户原有的配置文件作为模板 - 优先使用同目录下的config.yaml
        if [[ -f "$SCRIPT_DIR_PATH/config.yaml" ]]; then
            echo -e "${GREEN}使用脚本目录中的配置文件作为模板${PLAIN}"
            cp "$SCRIPT_DIR_PATH/config.yaml" "$CONFIG_TEMPLATE"
        elif [[ -f "/root/mihomo-proxy/docker版mihomo/config.yaml" ]]; then
            echo -e "${GREEN}使用备用路径中的配置文件作为模板${PLAIN}"
            cp "/root/mihomo-proxy/docker版mihomo/config.yaml" "$CONFIG_TEMPLATE"
        else
            # 如果没有找到现有配置文件，创建基本模板
            echo -e "${YELLOW}未找到配置模板文件，创建默认配置...${PLAIN}"
            cat > "$CONFIG_TEMPLATE" << EOF
#---------------------------------------------------#
## 预设配置文件 - 无需选择机场或自定义
## 
## 此配置文件已经预先设置好，用户只需根据个人需求修改几个关键参数即可使用
## 
## 当前配置包含:
## - Hysteria2 代理协议（高性能抗干扰）
## - Vmess 代理协议（备用协议）
## - TUN 模式（全局透明代理，无需单独配置应用）
## - 优化 DNS 解析（防污染、加速访问）
## - 自动分流规则（国内直连、国外代理）
## - 自动测速选择（自动选择最佳节点）
## - 面板远程管理（支持通过浏览器控制）
##
## 【使用方法】: 
## 1. 将此文件放置在容器内的 /etc/mihomo/config.yaml 路径
## 2. 编辑 proxies 部分，替换以下关键信息:
##    - 将 VPS_IP 替换为你的服务器 IP 地址
##    - 将 your_password 替换为你设置的密码
##    - 根据你的网络情况调整上传下载速度(up/down参数)
## 3. 如果你有多个代理节点，可在 proxies 部分添加更多节点配置
## 4. 如需自定义分流规则，请修改 rules 部分
## 5. 控制面板默认地址: http://设备IP:9090，密码: wallentv
#---------------------------------------------------#

# 通用代理端口：同时支持HTTP和SOCKS5协议，一般软件都可以使用这个端口
mixed-port: 7890

# 仅HTTP协议专用端口（如果你的软件只支持HTTP代理，用这个）
port: 7891

# 仅SOCKS5协议专用端口（如果你的软件只支持SOCKS5代理，用这个）
socks-port: 7892

# 允许局域网的连接（开启后，其他设备可以通过你的电脑上网）
allow-lan: true

# 绑定IP地址 (会被脚本自动替换为您选择的mihomo IP)
bind-address: VPS_IP

# 代理规则模式: rule(规则), global(全局), direct(直连)
mode: rule                  

# 日志级别: info, warning, error, debug, silent(无日志)
log-level: info             

# 启用 IPv6
ipv6: false                 

# 外部控制器
external-controller: VPS_IP:9090  

# 外部控制面板路径
external-ui: ui             

# DNS配置
dns:
  enable: true
  listen: 0.0.0.0:53
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  nameserver:
    - tls://223.5.5.5:853
    - https://doh.pub/dns-query
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - '*.lan'
    - localhost.ptlogin2.qq.com

# 代理配置 - 请替换以下示例配置为您自己的服务器信息
proxies:
  # Hysteria2代理（高性能抗干扰协议）
  - name: "dmit-hy2"
    type: hysteria2
    server: VPS_IP # 替换为你的VPS IP地址
    port: 443
    password: "your_password" # 替换为你的Hysteria2密码
    # 根据你的实际网速调整，单位是Mbps
    up: 100  # 上传速度
    down: 1000  # 下载速度
    sni: cn.bing.com # 伪装成访问必应
    skip-cert-verify: true # 跳过证书验证

  # Vmess代理配置示例
  - name: "dmit-vmess"
    type: vmess
    server: VPS_IP # 替换为你的VPS IP地址
    port: 80
    uuid: "12345678-1234-1234-1234-123456789012" # 替换为你的UUID
    alterId: 0
    cipher: auto

# 代理分组
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - dmit-hy2
      - dmit-vmess
      - DIRECT

# 分流规则
rules:
  - DOMAIN-SUFFIX,google.com,PROXY
  - DOMAIN-SUFFIX,facebook.com,PROXY
  - DOMAIN-SUFFIX,youtube.com,PROXY
  - DOMAIN-SUFFIX,netflix.com,PROXY
  - DOMAIN-SUFFIX,github.com,PROXY
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
EOF
        fi
        echo -e "${GREEN}配置文件模板已创建: $CONFIG_TEMPLATE${PLAIN}"
    fi
}

# 检查配置文件模板是否存在
check_config_template() {
    if ([[ ! -f "$CONFIG_TEMPLATE" ]]); then
        create_config_template
    fi
}

# 生成代理机配置脚本
generate_proxy_script() {
    echo -e "${CYAN}正在生成代理机配置脚本...${PLAIN}"
    
    MIHOMO_IP=$(get_state_value "mihomo_ip")
    INTERFACE_IP=$(get_state_value "interface_ip")
    
    cat > "$PROXY_SCRIPT" << EOF
#!/bin/bash
#############################################################
# Mihomo 代理机配置脚本 (由引导脚本自动生成)
# 此脚本将配置Docker和Mihomo代理环境
#############################################################

# 设置颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 配置信息
MIHOMO_IP="$MIHOMO_IP"
INTERFACE_IP="$INTERFACE_IP"
MAIN_INTERFACE="$MAIN_INTERFACE"
MACVLAN_INTERFACE="mihomo_veth"
CONF_DIR="/etc/mihomo"
STATE_FILE="$STATE_FILE"
CONFIG_TEMPLATE="$CONFIG_TEMPLATE"

# 检查是否具有root权限
if [[ \$EUID -ne 0 ]]; then
    echo -e "\${YELLOW}警告: 当前非root用户，需要root权限才能继续安装\${PLAIN}"
    echo -e "\${CYAN}尝试获取root权限...\${PLAIN}"
    
    # 检查是否有sudo命令
    if command -v sudo &> /dev/null; then
        echo -e "\${CYAN}已检测到sudo命令，尝试使用sudo执行脚本...\${PLAIN}"
        
        # 询问用户是否自动提权
        read -p "是否自动使用sudo重新执行此脚本? (y/n): " auto_sudo
        if [[ "\$auto_sudo" == "y" || "\$auto_sudo" == "Y" ]]; then
            echo -e "\${GREEN}正在使用sudo重新执行脚本...\${PLAIN}"
            
            # 获取当前脚本的绝对路径
            SCRIPT_PATH=\$(readlink -f "\$0")
            
            # 如果脚本没有执行权限，自动添加
            if [[ ! -x "\$SCRIPT_PATH" ]]; then
                echo -e "\${CYAN}脚本没有执行权限，正在添加...\${PLAIN}"
                sudo chmod +x "\$SCRIPT_PATH"
            fi
            
            # 使用sudo重新执行脚本，保持原始参数
            exec sudo bash "\$SCRIPT_PATH" "\$@"
        else
            echo -e "\${YELLOW}请以root权限运行此脚本:\${PLAIN}"
            echo -e "\${CYAN}方法1: \${GREEN}sudo bash \$0\${PLAIN}"
            echo -e "\${CYAN}方法2: \${GREEN}sudo su\${PLAIN} 然后 \${GREEN}bash \$0\${PLAIN}"
            exit 1
        fi
    else
        echo -e "\${YELLOW}系统中没有发现sudo命令，请尝试以下方法获取root权限:\${PLAIN}"
        echo -e "\${CYAN}方法1: \${GREEN}su -\${PLAIN} 输入root密码后执行 \${GREEN}bash \$0\${PLAIN}"
        echo -e "\${CYAN}方法2: 重新登录为root用户后执行脚本\${PLAIN}"
        echo -e "\${CYAN}方法3: \${GREEN}chmod +x \$0\${PLAIN} 然后以root用户执行 \${GREEN}./\$0\${PLAIN}"
        exit 1
    fi
fi

# 更新状态函数
update_state() {
    local key=\$1
    local value=\$2
    if [[ -f "\$STATE_FILE" ]]; then
        sed -i "s|\\"\$key\\": \\"[^\\"]*\\"|\\"\$key\\": \\"\$value\\"|g" "\$STATE_FILE"
    fi
}

echo -e "\${CYAN}开始配置Mihomo代理机...\${PLAIN}"
update_state "installation_stage" "网络配置"

# 安装所需依赖
echo -e "\${CYAN}更新系统包并安装必要依赖...\${PLAIN}"
apt update && apt install -y docker.io curl wget jq iproute2 iputils-ping arping tar gzip

# 检查Docker是否安装成功
if ! command -v docker &> /dev/null; then
    echo -e "\${RED}Docker安装失败，请手动安装后重试\${PLAIN}"
    exit 1
fi

echo -e "\${GREEN}Docker已安装\${PLAIN}"

# 启动Docker服务
systemctl start docker
systemctl enable docker

# 设置网卡混杂模式
echo -e "\${CYAN}设置网卡混杂模式...\${PLAIN}"
ip link set \$MAIN_INTERFACE promisc on

# 创建持久化的promisc设置
cat > /etc/systemd/system/promisc-\$MAIN_INTERFACE.service << EOL
[Unit]
Description=Set \$MAIN_INTERFACE to promiscuous mode
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/ip link set \$MAIN_INTERFACE promisc on
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable promisc-\$MAIN_INTERFACE.service

# 创建Docker macvlan网络
echo -e "\${CYAN}创建Docker macvlan网络...\${PLAIN}"
SUBNET=\$(echo \$MIHOMO_IP | cut -d '.' -f 1,2,3).0/24
GATEWAY=\$(ip route | grep default | awk '{print \$3}' | head -n 1)

# 检查是否已存在macvlan网络
if docker network ls | grep -q mnet; then
    echo -e "\${YELLOW}已存在macvlan网络，将重新创建...\${PLAIN}"
    docker network rm mnet &>/dev/null
fi

docker network create -d macvlan --subnet=\$SUBNET --gateway=\$GATEWAY -o parent=\$MAIN_INTERFACE mnet

update_state "installation_stage" "准备配置文件"

# 准备Mihomo配置目录
echo -e "\${CYAN}准备Mihomo配置目录...\${PLAIN}"
mkdir -p \$CONF_DIR

# 检查现有配置文件
EXISTING_CONFIG=0
if [[ -f "\$CONF_DIR/config.yaml" ]]; then
    echo -e "\${YELLOW}检测到现有配置文件: \$CONF_DIR/config.yaml\${PLAIN}"
    # 自动使用现有配置文件
    echo -e "\${GREEN}自动使用现有配置文件\${PLAIN}"
    EXISTING_CONFIG=1
    
    # 检查是否需要更新IP地址
    if grep -q "bind-address:" "\$CONF_DIR/config.yaml"; then
        CURRENT_IP=\$(grep "bind-address:" "\$CONF_DIR/config.yaml" | awk '{print \$2}')
        if [[ "\$CURRENT_IP" != "\$MIHOMO_IP" ]]; then
            echo -e "\${YELLOW}配置文件中IP地址(\$CURRENT_IP)与当前设置(\$MIHOMO_IP)不一致\${PLAIN}"
            echo -e "\${CYAN}正在更新配置文件中的IP地址...\${PLAIN}"
            sed -i "s/bind-address: \$CURRENT_IP/bind-address: \$MIHOMO_IP/g" "\$CONF_DIR/config.yaml"
            sed -i "s/external-controller: \$CURRENT_IP/external-controller: \$MIHOMO_IP/g" "\$CONF_DIR/config.yaml"
            echo -e "\${GREEN}配置文件已更新\${PLAIN}"
        fi
    fi
fi

# 如果不使用现有配置，则创建新配置
if [[ \$EXISTING_CONFIG -eq 0 ]]; then
    update_state "config_type" "preset"
    echo -e "\${CYAN}使用预设配置文件...\${PLAIN}"
    
    # 复制配置模板
    cp "\$CONFIG_TEMPLATE" \$CONF_DIR/config.yaml
    
    # 替换配置文件中的VPS_IP
    sed -i "s/VPS_IP/\$MIHOMO_IP/g" \$CONF_DIR/config.yaml
    
    # 配置文件说明
    echo -e "\${YELLOW}已使用预设配置文件。您需要根据自己的代理服务器信息修改配置文件中的关键参数：\${PLAIN}"
    echo -e "\${YELLOW}配置文件路径: \$CONF_DIR/config.yaml\${PLAIN}"
    echo -e "\${YELLOW}- 编辑配置文件，找到proxies部分\${PLAIN}"
    echo -e "\${YELLOW}- 将VPS_IP替换为您的服务器IP地址\${PLAIN}"
    echo -e "\${YELLOW}- 替换your_password为您设置的密码\${PLAIN}"
    echo -e "\${YELLOW}- 根据您的网络情况调整上传/下载速度参数\${PLAIN}"
    echo -e "\${YELLOW}您可以使用以下命令编辑配置文件:\${PLAIN}"
    echo -e "\${YELLOW}  nano \$CONF_DIR/config.yaml\${PLAIN}"
    echo -e "\${YELLOW}或者\${PLAIN}"
    echo -e "\${YELLOW}  vim \$CONF_DIR/config.yaml\${PLAIN}"
fi

# 下载UI文件
update_state "installation_stage" "下载UI文件"
echo -e "\${CYAN}下载Mihomo UI界面...\${PLAIN}"

# 检查是否已有UI文件
EXISTING_UI=0
if [[ -d "\$CONF_DIR/ui" ]] && ls -A "\$CONF_DIR/ui" &> /dev/null; then
    echo -e "\${YELLOW}检测到现有UI文件，自动使用现有UI文件\${PLAIN}"
    EXISTING_UI=1
else
    mkdir -p \$CONF_DIR/ui
fi

if [[ \$EXISTING_UI -eq 0 ]]; then
    # 尝试获取最新版本
    echo -e "\${CYAN}正在检查最新版本...\${PLAIN}"
    LATEST_VERSION=\$(curl -s https://api.github.com/repos/MetaCubeX/metacubexd/releases/latest | grep "tag_name" | cut -d '"' -f 4)

    if ([[ -z "\$LATEST_VERSION" ]]); then
        echo -e "\${YELLOW}警告: 无法获取最新版本信息，使用默认版本v1.187.1\${PLAIN}"
        LATEST_VERSION="v1.187.1"
    fi

    echo -e "\${GREEN}检测到最新版本: \$LATEST_VERSION\${PLAIN}"

    # 下载UI文件
    download_ui() {
        echo -e "\${CYAN}正在下载UI包...\${PLAIN}"
        if curl -L -o /tmp/compressed-dist.tgz "https://github.com/MetaCubeX/metacubexd/releases/download/\$LATEST_VERSION/compressed-dist.tgz"; then
            echo -e "\${GREEN}UI包下载成功\${PLAIN}"
            
            # 解压UI文件
            if tar -xzf /tmp/compressed-dist.tgz -C \$CONF_DIR/ui; then
                echo -e "\${GREEN}UI文件解压成功\${PLAIN}"
                return 0
            else
                echo -e "\${RED}UI文件解压失败\${PLAIN}"
                return 1
            fi
        else
            echo -e "\${RED}UI包下载失败\${PLAIN}"
            return 1
        fi
    }

    # 尝试下载UI包
    if ! download_ui; then
        echo -e "\${YELLOW}尝试备选下载方式...\${PLAIN}"
        if ! download_ui; then
            echo -e "\${RED}UI下载失败，请手动下载UI文件\${PLAIN}"
            echo -e "\${YELLOW}您可以稍后手动执行以下命令:\${PLAIN}"
            echo -e "\${YELLOW}  wget https://github.com/MetaCubeX/metacubexd/releases/download/\$LATEST_VERSION/compressed-dist.tgz\${PLAIN}"
            echo -e "\${YELLOW}  tar -xzf compressed-dist.tgz -C \$CONF_DIR/ui\${PLAIN}"
        fi
    fi
else
    echo -e "\${GREEN}使用现有UI文件，跳过UI下载步骤\${PLAIN}"
fi

# 安装mihomo
update_state "installation_stage" "安装Mihomo"
echo -e "\${CYAN}开始安装Mihomo...\${PLAIN}"

# 检查是否有现有的mihomo容器
if docker ps -a | grep -q mihomo; then
    echo -e "\${YELLOW}检测到系统中已安装mihomo容器，将自动删除并重新安装\${PLAIN}"
    echo -e "\${CYAN}正在停止并移除现有mihomo容器...\${PLAIN}"
    docker stop mihomo &>/dev/null
    docker rm mihomo &>/dev/null
fi

# 从Docker Hub拉取镜像
update_state "docker_method" "direct_pull"
echo -e "\${CYAN}正在从Docker Hub拉取镜像...\${PLAIN}"

# 尝试从Docker Hub拉取镜像
if ! docker pull metacubex/mihomo:latest; then
    echo -e "\${RED}拉取镜像失败，尝试使用本地镜像\${PLAIN}"
    update_state "docker_method" "local_image"
    
    # 检查是否有本地镜像文件
    if [[ ! -f "./mihomo-image.tar" ]]; then
        echo -e "\${RED}未找到本地镜像文件: ./mihomo-image.tar\${PLAIN}"
        echo -e "\${YELLOW}请先在有科学上网环境的电脑上执行以下命令:\${PLAIN}"
        echo -e "\${YELLOW}  docker pull metacubex/mihomo:latest\${PLAIN}"
        echo -e "\${YELLOW}  docker save metacubex/mihomo:latest -o mihomo-image.tar\${PLAIN}"
        echo -e "\${YELLOW}然后将mihomo-image.tar文件上传到当前目录\${PLAIN}"
        exit 1
    fi
    
    echo -e "\${CYAN}正在导入本地镜像文件...\${PLAIN}"
    if ! docker load -i ./mihomo-image.tar; then
        echo -e "\${RED}导入镜像文件失败\${PLAIN}"
        exit 1
    fi
fi

# 启动mihomo容器
echo -e "\${CYAN}启动Mihomo容器...\${PLAIN}"
if ! docker run -d --privileged \
  --name=mihomo --restart=always \
  --network mnet --ip \$MIHOMO_IP \
  -v \$CONF_DIR:/root/.config/mihomo/ \
  metacubex/mihomo:latest; then
    
    echo -e "\${RED}启动Mihomo容器失败\${PLAIN}"
    exit 1
fi

# 检查容器是否成功运行
if ! docker ps | grep -q mihomo; then
    echo -e "\${RED}Mihomo容器未能成功运行\${PLAIN}"
    echo -e "\${YELLOW}查看容器日志:\${PLAIN}"
    docker logs mihomo
    exit 1
fi

update_state "installation_stage" "配置网络"

# 设置宿主机和容器通信
echo -e "\${CYAN}配置宿主机与容器通信...\${PLAIN}"

# 检查是否已存在接口
if ip link show | grep -q \$MACVLAN_INTERFACE; then
    # 静默移除已存在的接口，无需提示
    ip link del \$MACVLAN_INTERFACE &>/dev/null
fi

# 创建macvlan接口
ip link add \$MACVLAN_INTERFACE link \$MAIN_INTERFACE type macvlan mode bridge

# 为接口分配IP地址
ip addr add \$INTERFACE_IP/24 dev \$MACVLAN_INTERFACE

# 启用接口
ip link set \$MACVLAN_INTERFACE up

# 添加路由规则
ip route add \$MIHOMO_IP dev \$MACVLAN_INTERFACE

# 创建持久化配置
cat > /etc/systemd/system/mihomo-network.service << EOL
[Unit]
Description=Setup Mihomo Network
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c "ip link add \$MACVLAN_INTERFACE link \$MAIN_INTERFACE type macvlan mode bridge && ip addr add \$INTERFACE_IP/24 dev \$MACVLAN_INTERFACE && ip link set \$MACVLAN_INTERFACE up && ip route add \$MIHOMO_IP dev \$MACVLAN_INTERFACE"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable mihomo-network.service

update_state "installation_stage" "配置完成"
update_state "timestamp" "\$(date '+%Y-%m-%d %H:%M:%S')"

# 验证安装
echo -e "\${CYAN}验证mihomo安装...\${PLAIN}"

# 检查Docker容器状态
if docker ps | grep -q mihomo; then
    echo -e "\${GREEN}Mihomo容器运行正常\${PLAIN}"
else
    echo -e "\${RED}Mihomo容器未运行\${PLAIN}"
fi

# 测试网络连通性
if ping -c 3 \$MIHOMO_IP &> /dev/null; then
    echo -e "\${GREEN}网络连通性测试成功\${PLAIN}"
else
    echo -e "\${RED}网络连通性测试失败\${PLAIN}"
fi

# 测试DNS解析
if command -v dig &> /dev/null; then
    if dig @\$MIHOMO_IP google.com +short &> /dev/null; then
        echo -e "\${GREEN}DNS解析测试成功\${PLAIN}"
    else
        echo -e "\${YELLOW}DNS解析测试未成功\${PLAIN}"
    fi
fi

# 检查控制面板
if curl -s -o /dev/null -w "%{http_code}" http://\$MIHOMO_IP:9090/ | grep -q "200"; then
    echo -e "\${GREEN}控制面板访问正常\${PLAIN}"
else
    echo -e "\${YELLOW}控制面板访问测试未成功\${PLAIN}"
fi

echo
echo -e "\${GREEN}======================================\${PLAIN}"
echo -e "\${GREEN}        Mihomo 配置完成!\${PLAIN}"
echo -e "\${GREEN}======================================\${PLAIN}"
echo
echo -e "\${CYAN}Mihomo IP: \$MIHOMO_IP\${PLAIN}"
echo -e "\${CYAN}控制面板: http://\$MIHOMO_IP:9090/ui\${PLAIN}"
echo -e "\${CYAN}控制面板密码: wallentv\${PLAIN}"
echo
echo -e "\${CYAN}代理端口:\${PLAIN}"
echo -e "\${CYAN}  混合端口(HTTP/SOCKS5): \$MIHOMO_IP:7890\${PLAIN}"
echo -e "\${CYAN}  HTTP端口: \$MIHOMO_IP:7891\${PLAIN}"
echo -e "\${CYAN}  SOCKS5端口: \$MIHOMO_IP:7892\${PLAIN}"
echo
echo -e "\${CYAN}现在您需要配置路由器指向Mihomo,\${PLAIN}"
echo -e "\${CYAN}请运行引导脚本并选择'配置RouterOS'选项\${PLAIN}"
echo

exit 0
EOF

    chmod +x "$PROXY_SCRIPT"
    echo -e "${GREEN}代理机配置脚本生成完成: $PROXY_SCRIPT${PLAIN}"
}

# 生成RouterOS配置脚本
generate_router_script() {
    echo -e "${CYAN}正在生成RouterOS配置脚本...${PLAIN}"
    
    MIHOMO_IP=$(get_state_value "mihomo_ip")
    
    cat > "$ROUTER_SCRIPT" << EOF
#!/bin/bash
#############################################################
# RouterOS 配置脚本 (由引导脚本自动生成)
# 此脚本将生成RouterOS配置命令及详细配置指南
#############################################################

# 设置颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# Mihomo IP
MIHOMO_IP="$MIHOMO_IP"

# RouterOS配置文件名
ROUTER_CONFIG_FILE="$FILES_DIR/routeros_commands.rsc"

echo -e "\${CYAN}生成RouterOS配置命令...\${PLAIN}"

# 创建RouterOS配置文件
cat > "\$ROUTER_CONFIG_FILE" << EOL
# ==== Mihomo RouterOS 配置命令 ====
# 请将以下命令复制到RouterOS的Terminal中执行
# 您可以通过WebFig、WinBox或SSH访问RouterOS的Terminal

# 设置DNS服务器指向Mihomo
/ip dns set servers=\$MIHOMO_IP

# 添加fake-ip路由规则
/ip route add dst-address=198.18.0.0/16 gateway=\$MIHOMO_IP comment="mihomo fake-ip route"
EOL

echo -e "\${GREEN}RouterOS配置命令已生成: \$ROUTER_CONFIG_FILE\${PLAIN}"
echo
echo -e "\${GREEN}=================================================\${PLAIN}"
echo -e "\${GREEN}           RouterOS 配置详细指南\${PLAIN}"
echo -e "\${GREEN}=================================================\${PLAIN}"
echo

# 创建简洁的RouterOS配置指南
cat > "\$FILES_DIR/routeros_guide.txt" << EOL
===================================
      RouterOS 配置简易指南
===================================

----- 配置命令 -----

/ip dns set servers=$MIHOMO_IP
/ip route add dst-address=198.18.0.0/16 gateway=$MIHOMO_IP comment="mihomo fake-ip route"

----- 配置方法 -----

【WebFig/WinBox配置】
1. DNS配置: IP → DNS → 设置Servers为$MIHOMO_IP
2. 路由配置: IP → Routes → 添加路由198.18.0.0/16指向$MIHOMO_IP

【Terminal命令配置】
复制粘贴上方命令到RouterOS Terminal中执行即可

----- 验证配置 -----

1. 尝试访问google.com等网站
2. 运行nslookup google.com检查DNS解析
3. 访问http://$MIHOMO_IP:9090/ui查看连接状态

----- 其他路由器配置 -----

1. OpenWrt: 网络→DHCP/DNS→设置DNS为$MIHOMO_IP，添加静态路由
2. 爱快: DNS设置为$MIHOMO_IP，添加静态路由
3. 普通路由器: 设置DNS服务器为$MIHOMO_IP
===================================
EOL

# 打印RouterOS配置指南的摘要
echo -e "\${CYAN}===== RouterOS 配置命令与方式 =====\${PLAIN}"
echo
echo -e "\${YELLOW}/ip dns set servers=$MIHOMO_IP\${PLAIN}"
echo -e "\${YELLOW}/ip route add dst-address=198.18.0.0/16 gateway=$MIHOMO_IP comment="mihomo fake-ip route"\${PLAIN}"
echo
echo -e "【方法一】WebFig界面: IP→DNS→设置服务器为\${YELLOW}$MIHOMO_IP\${PLAIN}，添加路由\${YELLOW}198.18.0.0/16\${PLAIN}到\${YELLOW}$MIHOMO_IP\${PLAIN}"
echo -e "【方法二】WinBox工具: 同上述图形操作"
echo -e "【方法三】Terminal命令: 复制粘贴上方命令执行"
echo
echo -e "\${CYAN}===== 其他路由器配置 =====\${PLAIN}"
echo
echo -e "1. OpenWrt: DNS设置为\${YELLOW}$MIHOMO_IP\${PLAIN}，添加静态路由\${YELLOW}198.18.0.0/16\${PLAIN}到\${YELLOW}$MIHOMO_IP\${PLAIN}"
echo -e "2. 爱快(iKuai): DNS设置为\${YELLOW}$MIHOMO_IP\${PLAIN}，添加静态路由\${YELLOW}198.18.0.0/16\${PLAIN}到\${YELLOW}$MIHOMO_IP\${PLAIN}"
echo -e "3. 普通路由器: 设置DNS为\${YELLOW}$MIHOMO_IP\${PLAIN}，支持静态路由则添加\${YELLOW}198.18.0.0/16\${PLAIN}到\${YELLOW}$MIHOMO_IP\${PLAIN}"
echo

echo -e "\${CYAN}===== 验证配置 =====\${PLAIN}"
echo
echo -e "验证方法: 访问\${YELLOW}google.com\${PLAIN}，运行\${YELLOW}nslookup google.com\${PLAIN}，查看面板\${YELLOW}http://$MIHOMO_IP:9090/ui\${PLAIN}"
echo

echo -e "\${GREEN}RouterOS配置脚本执行完成\${PLAIN}"
echo

exit 0
EOF
    
    chmod +x "$ROUTER_SCRIPT"
    echo -e "${GREEN}RouterOS配置脚本生成完成: $ROUTER_SCRIPT${PLAIN}"
}

# 重新生成配置文件
regenerate_config() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}              Mihomo配置文件管理${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    # 检查mihomo是否已安装
    if ([[ ! -d "$CONF_DIR" ]]); then
        echo -e "${YELLOW}Mihomo配置目录不存在，将创建目录${PLAIN}"
        mkdir -p "$CONF_DIR"
    fi
    
    # 获取mihomo IP
    local mihomo_ip=$(get_state_value "mihomo_ip")
    if ([[ -z "$mihomo_ip" ]]); then
        echo -e "${RED}错误: 未找到mihomo IP地址配置${PLAIN}"
        echo -e "${YELLOW}将为您设置Mihomo IP地址...${PLAIN}"
        setup_mihomo_ip
        mihomo_ip=$(get_state_value "mihomo_ip")
    fi
    
    echo -e "${YELLOW}配置文件管理选项:${PLAIN}"
    echo -e "${CYAN}1. 查看当前配置文件${PLAIN}"
    echo -e "${CYAN}2. 编辑配置文件${PLAIN}" 
    echo -e "${CYAN}3. 重置为默认配置模板${PLAIN}"
    echo -e "${CYAN}0. 返回主菜单${PLAIN}"
    read -p "请选择 [0-3]: " config_choice
    
    case $config_choice in
        1)
            # 查看当前配置
            if [[ -f "$CONF_DIR/config.yaml" ]]; then
                echo -e "${GREEN}当前配置文件内容:${PLAIN}"
                echo -e "${CYAN}----------------------------------------${PLAIN}"
                cat "$CONF_DIR/config.yaml"
                echo -e "${CYAN}----------------------------------------${PLAIN}"
            else
                echo -e "${YELLOW}配置文件不存在，请使用选项3创建默认配置模板${PLAIN}"
            fi
            ;;
        2)
            # 编辑配置文件
            if ([[ ! -f "$CONF_DIR/config.yaml" ]]); then
                echo -e "${YELLOW}配置文件不存在，将创建默认配置模板...${PLAIN}"
                create_config_template
                cp "$CONFIG_TEMPLATE" "$CONF_DIR/config.yaml"
                sed -i "s/VPS_IP/$mihomo_ip/g" "$CONF_DIR/config.yaml"
            fi
            
            echo -e "${CYAN}选择编辑器:${PLAIN}"
            echo -e "1. nano (简单易用)"
            echo -e "2. vim (高级功能)"
            read -p "请选择 [1-2]: " editor_choice
            
            if ([[ "$editor_choice" == "1" ]]); then
                if ! command -v nano &> /dev/null; then
                    echo -e "${YELLOW}未安装nano编辑器，正在安装...${PLAIN}"
                    apt update && apt install -y nano
                fi
                nano "$CONF_DIR/config.yaml"
            else
                if ! command -v vim &> /dev/null; then
                    echo -e "${YELLOW}未安装vim编辑器，正在安装...${PLAIN}"
                    apt update && apt install -y vim
                fi
                vim "$CONF_DIR/config.yaml"
            fi
            
            # 检查配置文件语法
            echo -e "${CYAN}检查配置文件语法...${PLAIN}"
            if command -v yq &> /dev/null; then
                if yq eval . "$CONF_DIR/config.yaml" &>/dev/null; then
                    echo -e "${GREEN}配置文件语法正确${PLAIN}"
                else
                    echo -e "${RED}配置文件语法错误，请检查YAML格式${PLAIN}"
                fi
            else
                echo -e "${YELLOW}未安装yq工具，无法验证YAML语法${PLAIN}"
                echo -e "${YELLOW}请确保您的配置文件格式正确${PLAIN}"
            fi
            ;;
        3)
            # 重置为默认配置
            if ([[ -f "$CONF_DIR/config.yaml" ]]); then
                local backup_file="$CONF_DIR/config.yaml.backup.$(date '+%Y%m%d%H%M%S')"
                echo -e "${YELLOW}备份现有配置文件到: $backup_file${PLAIN}"
                cp "$CONF_DIR/config.yaml" "$backup_file"
            fi
            
            echo -e "${CYAN}创建默认配置模板...${PLAIN}"
            create_config_template
            cp "$CONFIG_TEMPLATE" "$CONF_DIR/config.yaml"
            
            # 替换配置文件中的VPS_IP
            sed -i "s/VPS_IP/$mihomo_ip/g" "$CONF_DIR/config.yaml"
            
            echo -e "${GREEN}已重置为默认配置模板${PLAIN}"
            echo -e "${YELLOW}注意: 默认模板仅包含基本设置，您需要自行编辑添加代理节点${PLAIN}"
            echo -e "${YELLOW}配置文件路径: $CONF_DIR/config.yaml${PLAIN}"
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}无效的选择${PLAIN}"
            ;;
    esac
    
    read -p "按任意键返回..." key
    regenerate_config
}

# 重启mihomo服务
restart_mihomo_service() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}              重启Mihomo服务${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    # 检查mihomo容器是否存在
    if ! docker ps -a | grep -q mihomo; then
        echo -e "${RED}错误: 未找到mihomo容器${PLAIN}"
        echo -e "${YELLOW}请先进行步骤2: 配置代理机${PLAIN}"
        read -p "按任意键返回..." key
        return
    fi
    
    echo -e "${CYAN}正在重启mihomo服务...${PLAIN}"
    if docker restart mihomo; then
        echo -e "${GREEN}mihomo服务已成功重启${PLAIN}"
        
        # 等待几秒让服务启动
        echo -e "${CYAN}等待服务启动...${PLAIN}"
        sleep 3
        
        # 获取mihomo IP
        local mihomo_ip=$(get_state_value "mihomo_ip")
        
        # 验证服务状态
        echo -e "${CYAN}检查服务状态...${PLAIN}"
        
        # 检查容器是否运行
        if docker ps | grep -q mihomo; then
            echo -e "${GREEN}● 容器状态: 运行中${PLAIN}"
        else
            echo -e "${RED}● 容器状态: 未运行${PLAIN}"
            echo -e "${YELLOW}查看错误日志:${PLAIN}"
            docker logs mihomo --tail 20
            read -p "按任意键返回..." key
            return
        fi
        
        # 检查配置文件问题
        echo -e "${CYAN}检查配置文件日志...${PLAIN}"
        local config_errors=$(docker logs mihomo 2>&1 | grep -i "error\|fail\|invalid" | tail -10)
        
        if ([[ -n "$config_errors" ]]); then
            echo -e "${RED}● 检测到配置文件可能存在问题:${PLAIN}"
            echo -e "${YELLOW}$config_errors${PLAIN}"
            echo
            echo -e "${YELLOW}常见配置问题解决方案:${PLAIN}"
            echo -e "1. 代理节点格式错误: 检查proxies部分语法"
            echo -e "2. DNS配置有误: 检查dns部分配置"
            echo -e "3. 端口冲突: 更改mixed-port/http-port/socks-port端口值"
            echo -e "4. 规则格式错误: 检查rules部分语法"
            echo -e "5. 缩进错误: 确保使用空格而非Tab进行缩进"
        else
            echo -e "${GREEN}● 未发现明显配置错误${PLAIN}"
        fi
        
        # 检查网络连通性
        echo -e "${CYAN}检查网络连通性...${PLAIN}"
        if ping -c 2 $mihomo_ip &>/dev/null; then
            echo -e "${GREEN}● 网络连通性: 正常${PLAIN}"
        else
            echo -e "${RED}● 网络连通性: 异常${PLAIN}"
            echo -e "${YELLOW}请检查网络配置${PLAIN}"
        fi
        
        # 检查代理端口
        if ! command -v nc &>/dev/null; then
            echo -e "${YELLOW}未安装nc工具，正在自动安装...${PLAIN}"
            apt update >/dev/null 2>&1 && apt install -y netcat-openbsd >/dev/null 2>&1
            
            if ! command -v nc &>/dev/null; then
                echo -e "${RED}nc工具安装失败，无法检查端口${PLAIN}"
            else
                echo -e "${GREEN}nc工具安装成功，继续检查端口...${PLAIN}"
            fi
        fi
        
        # 再次检查nc命令是否可用，然后执行端口检查
        if command -v nc &>/dev/null; then
            echo -e "${CYAN}检查代理端口...${PLAIN}"
            if nc -z -w2 $mihomo_ip 7890; then
                echo -e "${GREEN}● 混合端口(7890): 开放${PLAIN}"
            else
                echo -e "${RED}● 混合端口(7890): 未开放${PLAIN}"
            fi
            
            if nc -z -w2 $mihomo_ip 9090; then
                echo -e "${GREEN}● 控制面板(9090): 开放${PLAIN}"
                echo -e "${GREEN}● 控制面板地址: http://${mihomo_ip}:9090/ui${PLAIN}"
            else
                echo -e "${RED}● 控制面板(9090): 未开放${PLAIN}"
            fi
        else
            echo -e "${YELLOW}无法使用nc工具，跳过端口检查${PLAIN}"
        fi
    else
        echo -e "${RED}mihomo服务重启失败${PLAIN}"
        echo -e "${YELLOW}请检查Docker服务状态${PLAIN}"
    fi
    
    read -p "按任意键返回..." key
}

# 卸载mihomo及相关配置
uninstall_mihomo() {
    clear
    echo -e "${CYAN}======================================================${PLAIN}"
    echo -e "${CYAN}              卸载Mihomo服务${PLAIN}"
    echo -e "${CYAN}======================================================${PLAIN}"
    
    echo -e "${YELLOW}警告: 此操作将完全删除Mihomo容器、配置文件和网络设置${PLAIN}"
    echo -e "${RED}此操作不可恢复，所有配置信息都将丢失!${PLAIN}"
    read -p "确定要卸载Mihomo吗? (y/n): " confirm_uninstall
    
    if ([[ "$confirm_uninstall" != "y" && "$confirm_uninstall" != "Y" ]]); then
        echo -e "${GREEN}已取消卸载操作${PLAIN}"
        read -p "按任意键返回..." key
        return
    fi
    
    echo -e "${CYAN}开始卸载Mihomo...${PLAIN}"
    
    # 步骤1: 停止并删除mihomo容器
    echo -e "${CYAN}[1/6] 停止并删除Mihomo容器...${PLAIN}"
    if docker ps -a | grep -q mihomo; then
        docker stop mihomo &>/dev/null
        docker rm mihomo &>/dev/null
        echo -e "${GREEN}● Mihomo容器已删除${PLAIN}"
    else
        echo -e "${YELLOW}● 未找到Mihomo容器${PLAIN}"
    fi
    
    # 步骤2: 删除配置文件和UI文件
    echo -e "${CYAN}[2/6] 删除配置文件和UI文件...${PLAIN}"
    if ([[ -d "$CONF_DIR" ]]); then
        # 备份配置文件
        local backup_dir="/root/mihomo_backup_$(date '+%Y%m%d%H%M%S')"
        mkdir -p "$backup_dir"
        
        if ([[ -f "$CONF_DIR/config.yaml" ]]); then
            echo -e "${YELLOW}● 备份配置文件到 $backup_dir/config.yaml${PLAIN}"
            cp "$CONF_DIR/config.yaml" "$backup_dir/config.yaml"
        fi
        
        echo -e "${CYAN}● 删除配置目录 $CONF_DIR${PLAIN}"
        rm -rf "$CONF_DIR"
        echo -e "${GREEN}● 配置目录已删除${PLAIN}"
    else
        echo -e "${YELLOW}● 未找到配置目录${PLAIN}"
    fi
    
    # 步骤3: 删除Docker网络
    echo -e "${CYAN}[3/6] 删除Docker macvlan网络...${PLAIN}"
    if docker network ls | grep -q mnet; then
        docker network rm mnet &>/dev/null
        echo -e "${GREEN}● Docker macvlan网络已删除${PLAIN}"
    else
        echo -e "${YELLOW}● 未找到Docker macvlan网络${PLAIN}"
    fi
    
    # 步骤4: 删除网络接口
    local macvlan_interface=$(get_state_value "macvlan_interface")
    macvlan_interface=${macvlan_interface:-"mihomo_veth"}
    
    echo -e "${CYAN}[4/6] 删除macvlan网络接口...${PLAIN}"
    if ip link show | grep -q "$macvlan_interface"; then
        ip link del "$macvlan_interface" &>/dev/null
        echo -e "${GREEN}● Macvlan网络接口已删除${PLAIN}"
    else
        echo -e "${YELLOW}● 未找到macvlan网络接口${PLAIN}"
    fi
    
    # 步骤5: 删除系统服务
    echo -e "${CYAN}[5/6] 删除系统服务...${PLAIN}"
    # 删除mihomo网络服务
    if ([[ -f "/etc/systemd/system/mihomo-network.service" ]]); then
        systemctl disable mihomo-network.service &>/dev/null
        rm -f /etc/systemd/system/mihomo-network.service
        echo -e "${GREEN}● Mihomo网络服务已删除${PLAIN}"
    else
        echo -e "${YELLOW}● 未找到Mihomo网络服务${PLAIN}"
    fi
    
    # 删除网卡混杂模式服务
    local main_interface=$(get_state_value "main_interface")
    if ([[ -n "$main_interface" && -f "/etc/systemd/system/promisc-$main_interface.service" ]]); then
        systemctl disable "promisc-$main_interface.service" &>/dev/null
        rm -f "/etc/systemd/system/promisc-$main_interface.service"
        echo -e "${GREEN}● 网卡混杂模式服务已删除${PLAIN}"
        
        # 关闭网卡混杂模式
        if ip link show | grep -q "$main_interface"; then
            ip link set "$main_interface" promisc off &>/dev/null
            echo -e "${GREEN}● 已关闭网卡混杂模式${PLAIN}"
        fi
    else
        echo -e "${YELLOW}● 未找到网卡混杂模式服务${PLAIN}"
    fi
    
    # 重载systemd服务
    systemctl daemon-reload
    
    # 步骤6: 重置状态文件
    echo -e "${CYAN}[6/6] 重置状态信息...${PLAIN}"
    local mihomo_ip=$(get_state_value "mihomo_ip")
    local main_interface=$(get_state_value "main_interface")
    local macvlan_interface=$(get_state_value "macvlan_interface")
    
    # 保留网络接口信息，但清除安装状态
    update_state "mihomo_ip" ""
    update_state "interface_ip" ""
    # 保留main_interface和macvlan_interface
    update_state "installation_stage" "初始化"
    update_state "config_type" ""
    update_state "subscription_url" ""
    update_state "docker_method" ""
    update_state "timestamp" "$(date '+%Y-%m-%d %H:%M:%S')"
    
    echo -e "\n${GREEN}======================================================${PLAIN}"
    echo -e "${GREEN}Mihomo已成功卸载!${PLAIN}"
    echo -e "${GREEN}配置文件备份已保存至: $backup_dir${PLAIN}"
    echo -e "${GREEN}======================================================${PLAIN}"
    echo -e "${YELLOW}提示: 如果您需要彻底卸载Docker，可以执行以下命令:${PLAIN}"
    echo -e "${CYAN}  apt purge docker.io -y${PLAIN}"
    echo -e "${CYAN}  apt autoremove -y${PLAIN}"
    
    read -p "按任意键返回主菜单..." key
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
    
    # 整合安装步骤和操作选项
    # 步骤1: 初始化
    if ([[ -n "$mihomo_ip" ]]); then
        echo -e " ${GREEN}[✓] 1. 初始化设置${PLAIN}    - ${GREEN}已完成 - IP: $mihomo_ip${PLAIN}"
    else
        echo -e " ${CYAN}[1] 1. 初始化设置${PLAIN}    - ${YELLOW}配置mihomo IP地址 ${RED}[未完成]${PLAIN}"
    fi
    
    # 步骤2: 代理机配置
    if ([[ "$stage" == "配置完成" ]]); then
        echo -e " ${GREEN}[✓] 2. 配置代理机${PLAIN}    - ${GREEN}已完成 - mihomo已安装并运行${PLAIN}"
    elif ([[ -n "$mihomo_ip" ]]); then
        echo -e " ${CYAN}[2] 2. 配置代理机${PLAIN}    - ${YELLOW}安装Docker和mihomo${PLAIN}"
    else
        echo -e " ${GRAY}[2] 2. 配置代理机${PLAIN}    - ${GRAY}请先完成步骤1${PLAIN}"
    fi
    
    # 步骤3: 路由器配置
    if ([[ "$stage" == "配置完成" ]]); then
        echo -e " ${CYAN}[3] 3. 配置路由器${PLAIN}    - ${YELLOW}生成RouterOS配置命令${PLAIN}"
    else
        echo -e " ${GRAY}[3] 3. 配置路由器${PLAIN}    - ${GRAY}请先完成步骤2${PLAIN}"
    fi
    
    echo -e "${CYAN}----------------------------------------------------------${PLAIN}"
    echo -e " ${GREEN}[4] 4. 配置文件管理${PLAIN}  - ${YELLOW}查看/编辑/重置配置文件${PLAIN}"
    echo -e " ${GREEN}[5] 5. 重启Mihomo服务${PLAIN}  - ${YELLOW}重启并检测服务状态${PLAIN}"
    echo -e " ${GREEN}[6] 6. 检查安装状态${PLAIN}  - ${YELLOW}查看服务运行情况${PLAIN}"
    echo -e " ${RED}[7] 7. 卸载Mihomo${PLAIN}  - ${YELLOW}卸载Mihomo及相关配置${PLAIN}"
    echo -e " ${GREEN}[0] 0. 退出脚本${PLAIN}"
    echo -e "${CYAN}===========================================================${PLAIN}"
    
    # 显示当前状态
    if ([[ -n "$mihomo_ip" ]]); then
        echo -e "${YELLOW}系统信息:${PLAIN}"
        echo -e "${YELLOW}• Mihomo IP: ${GREEN}$mihomo_ip${PLAIN}"
        echo -e "${YELLOW}• 安装阶段: ${GREEN}$stage${PLAIN}"
        echo -e "${YELLOW}• 更新时间: ${GREEN}$timestamp${PLAIN}"
        if ([[ "$stage" == "配置完成" ]]); then
            echo -e "${YELLOW}• 控制面板: ${GREEN}http://$mihomo_ip:9090/ui${PLAIN}"
        fi
    fi
    echo
    
    read -p "请输入选择 [0-7]: " choice
    
    case $choice in
        1)
            # 初始化设置
            clear
            echo -e "${CYAN}======================================================${PLAIN}"
            echo -e "${CYAN}              步骤1: 初始化设置${PLAIN}"
            echo -e "${CYAN}======================================================${PLAIN}"
            echo -e "${YELLOW}这一步将设置mihomo的IP地址并生成配置脚本${PLAIN}"
            echo
            
            local mihomo_ip=$(get_state_value "mihomo_ip")
            if ([[ -n "$mihomo_ip" ]]); then
                echo -e "${YELLOW}检测到已有配置: IP = $mihomo_ip${PLAIN}"
                read -p "是否重新设置IP地址? (y/n): " reset_ip
                if ([[ "$reset_ip" == "y" || "$reset_ip" == "Y" ]]); then
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
            
            # 生成配置脚本
            echo -e "${CYAN}正在生成配置脚本...${PLAIN}"
            generate_proxy_script
            generate_router_script
            
            mihomo_ip=$(get_state_value "mihomo_ip")
            echo -e "\n${GREEN}======================================================${PLAIN}"
            echo -e "${GREEN}步骤1完成! Mihomo IP地址: ${YELLOW}$mihomo_ip${PLAIN}"
            echo -e "${GREEN}现在您可以进行步骤2: 配置代理机${PLAIN}"
            echo -e "${GREEN}======================================================${PLAIN}"
            
            read -p "按任意键返回主菜单..." key
            show_menu
            ;;
        2)
            # 配置代理机
            local mihomo_ip=$(get_state_value "mihomo_ip")
            local stage=$(get_state_value "installation_stage")
            
            # 检查是否已完成初始化
            if ([[ -z "$mihomo_ip" ]]); then
                echo -e "${YELLOW}======================================================${PLAIN}"
                echo -e "${YELLOW}您需要先完成步骤1: 初始化设置${PLAIN}"
                echo -e "${YELLOW}======================================================${PLAIN}"
                read -p "是否立即进行初始化? (y/n): " do_init
                if ([[ "$do_init" == "y" || "$do_init" == "Y" ]]); then
                    echo -e "${CYAN}正在跳转到步骤1...${PLAIN}"
                    sleep 1
                    
                    # 调用选项1的逻辑
                    clear
                    echo -e "${CYAN}======================================================${PLAIN}"
                    echo -e "${CYAN}              步骤1: 初始化设置${PLAIN}"
                    echo -e "${CYAN}======================================================${PLAIN}"
                    echo -e "${YELLOW}这一步将设置mihomo的IP地址并生成配置脚本${PLAIN}"
                    echo
                    
                    # 设置mihomo IP地址
                    setup_mihomo_ip
                    
                    # 生成配置脚本
                    echo -e "${CYAN}正在生成配置脚本...${PLAIN}"
                    generate_proxy_script
                    generate_router_script
                    
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
            
            # 检查是否已经安装了mihomo
            if docker ps -a | grep -q mihomo && ([[ "$stage" == "配置完成" ]]); then
                echo -e "${YELLOW}检测到mihomo已经安装，继续操作将重新安装${PLAIN}"
                echo -e "${YELLOW}原配置文件将保留在 /etc/mihomo 目录下${PLAIN}"
                read -p "是否继续重新安装？ (y/n): " confirm
                if ([[ "$confirm" != "y" && "$confirm" != "Y" ]]); then
                    show_menu
                    return
                fi
            fi
            
            if ([[ -f "$PROXY_SCRIPT" ]]); then
                echo -e "${CYAN}正在安装Docker和Mihomo...${PLAIN}"
                echo -e "${YELLOW}此过程可能需要几分钟，请耐心等待...${PLAIN}"
                echo
                bash "$PROXY_SCRIPT"
                echo -e "\n${GREEN}======================================================${PLAIN}"
                echo -e "${GREEN}步骤2完成! Mihomo代理已安装并启动${PLAIN}"
                echo -e "${GREEN}您现在可以使用以下地址访问控制面板:${PLAIN}"
                echo -e "${GREEN}控制面板: http://${mihomo_ip}:9090/ui${PLAIN}"
                echo -e "${GREEN}现在请前往步骤3: 配置路由器${PLAIN}"
                echo -e "${GREEN}======================================================${PLAIN}"
            else
                echo -e "${RED}错误: 配置脚本不存在${PLAIN}"
                echo -e "${YELLOW}请返回主菜单重新执行步骤1: 初始化设置${PLAIN}"
            fi
            
            read -p "按任意键返回主菜单..." key
            show_menu
            ;;
        3)
            # 配置路由器
            local mihomo_ip=$(get_state_value "mihomo_ip")
            local stage=$(get_state_value "installation_stage")
            
            # 检查是否已完成初始化
            if ([[ -z "$mihomo_ip" ]]); then
                echo -e "${YELLOW}======================================================${PLAIN}"
                echo -e "${YELLOW}您需要先完成步骤1: 初始化设置${PLAIN}"
                echo -e "${YELLOW}======================================================${PLAIN}"
                read -p "是否立即进行初始化? (y/n): " do_init
                if ([[ "$do_init" == "y" || "$do_init" == "Y" ]]); then
                    # 选项1的逻辑
                    choice=1
                    continue
                else
                    show_menu
                    return
                fi
            fi
            
            # 检查是否已完成代理机配置
            if ([[ "$stage" != "配置完成" ]]); then
                echo -e "${YELLOW}======================================================${PLAIN}"
                echo -e "${YELLOW}建议先完成步骤2: 配置代理机${PLAIN}"
                echo -e "${YELLOW}否则Mihomo可能无法正常工作${PLAIN}"
                echo -e "${YELLOW}======================================================${PLAIN}"
                read -p "是否继续生成路由器配置? (y/n): " continue_router
                if ([[ "$continue_router" != "y" && "$continue_router" != "Y" ]]); then
                    show_menu
                    return
                fi
            fi
            
            # 执行路由器配置
            clear
            echo -e "${CYAN}======================================================${PLAIN}"
            echo -e "${CYAN}              步骤3: 配置路由器${PLAIN}"
            echo -e "${CYAN}======================================================${PLAIN}"
            
            if ([[ -f "$ROUTER_SCRIPT" ]]); then
                echo -e "${CYAN}生成RouterOS配置命令...${PLAIN}"
                bash "$ROUTER_SCRIPT"
                echo -e "\n${GREEN}======================================================${PLAIN}"
                echo -e "${GREEN}步骤3完成! 路由器配置指南已生成${PLAIN}"
                echo -e "${GREEN}请按照指南配置您的路由器，完成后即可使用Mihomo代理服务${PLAIN}"
                echo -e "${GREEN}======================================================${PLAIN}"
            else
                echo -e "${RED}错误: 路由器配置脚本不存在${PLAIN}"
                echo -e "${YELLOW}请返回主菜单重新执行步骤1: 初始化设置${PLAIN}"
            fi
            
            read -p "按任意键返回主菜单..." key
            show_menu
            ;;
        4)
            # 配置文件管理
            regenerate_config
            show_menu
            ;;
        5)
            # 重启Mihomo服务
            restart_mihomo_service
            show_menu
            ;;
        6)
            # 检查安装状态
            clear
            echo -e "${CYAN}======================================================${PLAIN}"
            echo -e "${CYAN}              Mihomo 安装状态检查${PLAIN}"
            echo -e "${CYAN}======================================================${PLAIN}"
            
            if ([[ -f "$STATE_FILE" ]]); then
                local mihomo_ip=$(get_state_value "mihomo_ip")
                local stage=$(get_state_value "installation_stage")
                local timestamp=$(get_state_value "timestamp")
                
                echo -e "${YELLOW}● 步骤完成情况:${PLAIN}"
                if ([[ -n "$mihomo_ip" ]]); then
                    echo -e "${GREEN}  ✓ 步骤1: 初始化已完成 - IP: $mihomo_ip${PLAIN}"
                else
                    echo -e "${RED}  ✗ 步骤1: 初始化未完成${PLAIN}"
                fi
                
                if ([[ "$stage" == "配置完成" ]]); then
                    echo -e "${GREEN}  ✓ 步骤2: 代理机配置已完成${PLAIN}"
                else
                    echo -e "${RED}  ✗ 步骤2: 代理机配置未完成${PLAIN}"
                fi
                echo
                
                echo -e "${YELLOW}● 状态文件详情:${PLAIN}"
                if command -v jq &> /dev/null; then
                    cat "$STATE_FILE" | jq
                else
                    cat "$STATE_FILE"
                fi
                echo
                
                echo -e "${YELLOW}● Docker容器状态:${PLAIN}"
                if command -v docker &> /dev/null; then
                    if docker ps | grep -q mihomo; then
                        echo -e "${GREEN}  ✓ Mihomo 容器正在运行${PLAIN}"
                        docker ps | grep mihomo
                    elif docker ps -a | grep -q mihomo; then
                        echo -e "${RED}  ✗ Mihomo 容器存在但未运行${PLAIN}"
                        docker ps -a | grep mihomo
                        echo -e "${YELLOW}  提示: 可以使用以下命令启动容器:${PLAIN}"
                        echo -e "${YELLOW}  docker start mihomo${PLAIN}"
                    else
                        echo -e "${RED}  ✗ 未检测到Mihomo容器${PLAIN}"
                        echo -e "${YELLOW}  提示: 请执行步骤2安装Mihomo${PLAIN}"
                    fi
                else
                    echo -e "${RED}  ✗ Docker未安装${PLAIN}"
                    echo -e "${YELLOW}  提示: 请执行步骤2安装Docker${PLAIN}"
                fi
                echo
                
                echo -e "${YELLOW}● 网络连通性测试:${PLAIN}"
                if ([[ -n "$mihomo_ip" ]]); then
                    if ping -c 2 $mihomo_ip &> /dev/null; then
                        echo -e "${GREEN}  ✓ 成功连接到Mihomo IP ($mihomo_ip)${PLAIN}"
                    else
                        echo -e "${RED}  ✗ 无法连接到Mihomo IP ($mihomo_ip)${PLAIN}"
                        echo -e "${YELLOW}  提示: 请检查网络配置或重新执行步骤2${PLAIN}"
                    fi
                else
                    echo -e "${RED}  ✗ 未设置Mihomo IP${PLAIN}"
                fi
                echo
                
                echo -e "${YELLOW}● 配置文件检查:${PLAIN}"
                if ([[ -d "/etc/mihomo" ]]); then
                    echo -e "${GREEN}  ✓ 配置目录存在: /etc/mihomo${PLAIN}"
                    
                    if ([[ -f "/etc/mihomo/config.yaml" ]]); then
                        echo -e "${GREEN}  ✓ 配置文件存在: /etc/mihomo/config.yaml${PLAIN}"
                        echo -e "${CYAN}    最后修改时间: $(stat -c %y /etc/mihomo/config.yaml)${PLAIN}"
                        
                        # 检查配置文件是否有效
                        if grep -q "^proxies:" "/etc/mihomo/config.yaml"; then
                            echo -e "${GREEN}  ✓ 配置文件包含代理节点${PLAIN}"
                        else
                            echo -e "${YELLOW}  ! 配置文件可能缺少代理节点${PLAIN}"
                            echo -e "${YELLOW}    提示: 使用选项4更新配置文件${PLAIN}"
                        fi
                    else
                        echo -e "${RED}  ✗ 配置文件不存在${PLAIN}"
                        echo -e "${YELLOW}    提示: 使用选项4生成配置文件${PLAIN}"
                    fi
                    
                    if ([[ -d "/etc/mihomo/ui" ]]); then
                        echo -e "${GREEN}  ✓ UI文件存在: /etc/mihomo/ui${PLAIN}"
                    else
                        echo -e "${RED}  ✗ UI文件不存在${PLAIN}"
                        echo -e "${YELLOW}    提示: 重新执行步骤2安装UI文件${PLAIN}"
                    fi
                else
                    echo -e "${RED}  ✗ 配置目录不存在${PLAIN}"
                    echo -e "${YELLOW}    提示: 执行步骤2创建配置目录${PLAIN}"
                fi
                
                if ([[ -n "$mihomo_ip" && "$stage" == "配置完成" ]]); then
                    echo
                    echo -e "${YELLOW}● 访问信息:${PLAIN}"
                    echo -e "${GREEN}  控制面板: http://$mihomo_ip:9090/ui${PLAIN}"
                    echo -e "${GREEN}  HTTP代理: $mihomo_ip:7891${PLAIN}"
                    echo -e "${GREEN}  SOCKS5代理: $mihomo_ip:7892${PLAIN}"
                    echo -e "${GREEN}  混合端口: $mihomo_ip:7890${PLAIN}"
                fi
            else
                echo -e "${RED}状态文件不存在，无法获取安装信息${PLAIN}"
                echo -e "${YELLOW}请执行步骤1初始化设置${PLAIN}"
            fi
            
            echo -e "${CYAN}======================================================${PLAIN}"
            read -p "按任意键返回主菜单..." key
            show_menu
            ;;
        7)
            # 卸载Mihomo服务
            uninstall_mihomo
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
    clear
    echo -e "${CYAN}===========================================================${PLAIN}"
    echo -e "${CYAN}  Mihomo 一键安装引导脚本 V1.0${PLAIN}"
    echo -e "${CYAN}  系统要求: Debian/Ubuntu${PLAIN}"
    echo -e "${CYAN}===========================================================${PLAIN}"
    
    # 检查脚本是否有执行权限
    SCRIPT_PATH=$(readlink -f "$0")
    if ([[ ! -x "$SCRIPT_PATH" ]]); then
        echo -e "${YELLOW}检测到脚本没有执行权限，尝试添加执行权限...${PLAIN}"
        chmod +x "$SCRIPT_PATH"
        if ([[ $? -eq 0 ]]); then
            echo -e "${GREEN}已成功添加执行权限${PLAIN}"
        else
            echo -e "${YELLOW}无法自动添加执行权限，建议手动执行: ${GREEN}chmod +x $SCRIPT_PATH${PLAIN}"
        fi
    fi
    
    # 检查root权限
    check_root
    
    # 检查操作系统
    check_os
    
    # 检测网络环境
    detect_network
    
    # 初始化状态文件
    init_state_file

    # 检查配置文件模板
    check_config_template
    
    # 检查是否需要设置IP地址
    local mihomo_ip=$(get_state_value "mihomo_ip")
    if ([[ -z "$mihomo_ip" ]]); then
        echo -e "${CYAN}初始化: 设置mihomo IP地址...${PLAIN}"
        
        # 设置mihomo IP地址
        setup_mihomo_ip
        
        # 生成配置脚本
        generate_proxy_script
        generate_router_script
    fi
    
    # 直接进入菜单，无需中间等待
    show_menu
}

main