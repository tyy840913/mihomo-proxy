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
PLAIN='\033[0m'

# 主目录设置
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
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
        echo -e "${RED}无法确定操作系统类型${PLAIN}"
        exit 1
    fi

    if [[ $OS != "debian" && $OS != "ubuntu" ]]; then
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
    if [[ ! -f "$STATE_FILE" ]]; then
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
    if [[ -f "$STATE_FILE" ]]; then
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
    if [[ -f "$STATE_FILE" ]]; then
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
        if [[ "$ip" == "$GATEWAY" ]]; then
            continue
        fi
        
        # 跳过当前主机IP
        if [[ "$ip" == "$CURRENT_IP" ]]; then
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
    if [[ ! -f "$CONFIG_TEMPLATE" ]]; then
        echo -e "${CYAN}创建默认配置文件模板...${PLAIN}"
        cat > "$CONFIG_TEMPLATE" << EOF
# ===== Mihomo 配置文件模板 =====
# 此模板由引导脚本自动生成
# 可根据需要修改，或使用机场订阅替换

mixed-port: 7890            # 混合端口，支持 HTTP 和 SOCKS
http-port: 7891             # HTTP 代理端口
socks-port: 7892            # SOCKS 代理端口
redir-port: 7893            # 透明代理端口
tproxy-port: 7894           # tproxy 端口

allow-lan: true             # 允许局域网连接
bind-address: VPS_IP        # 绑定IP地址 (会被脚本自动替换为您选择的mihomo IP)
mode: rule                  # 代理规则模式: rule, global, direct
log-level: info             # 日志级别: info, warning, error, debug, silent

ipv6: false                 # 启用 IPv6
external-controller: VPS_IP:9090  # 外部控制器
external-ui: ui             # 外部控制面板路径

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

# 代理配置，可以通过机场订阅链接自动获取，或手动配置
proxies:
  - name: ExampleProxy
    type: ss
    server: example.com
    port: 443
    cipher: chacha20-ietf-poly1305
    password: password

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - ExampleProxy
      - DIRECT

rules:
  - DOMAIN-SUFFIX,google.com,PROXY
  - DOMAIN-SUFFIX,facebook.com,PROXY
  - DOMAIN-SUFFIX,youtube.com,PROXY
  - DOMAIN-SUFFIX,netflix.com,PROXY
  - DOMAIN-SUFFIX,github.com,PROXY
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
EOF
        echo -e "${GREEN}配置文件模板已创建: $CONFIG_TEMPLATE${PLAIN}"
    fi
}

# 检查配置文件模板是否存在
check_config_template() {
    if [[ ! -f "$CONFIG_TEMPLATE" ]]; then
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

docker network create -d macvlan --subnet=\$SUBNET --gateway=\$GATEWAY -o parent=\$MAIN_INTERFACE mnet

update_state "installation_stage" "准备配置文件"

# 准备Mihomo配置目录
echo -e "\${CYAN}准备Mihomo配置目录...\${PLAIN}"
mkdir -p \$CONF_DIR

# 选择配置方式
echo -e "\${CYAN}请选择配置方式:\${PLAIN}"
echo -e "  1) 使用机场订阅链接"
echo -e "  2) 使用自定义配置文件"
read -p "请选择 [1-2]: " config_choice

if [[ "\$config_choice" == "1" ]]; then
    update_state "config_type" "subscription"
    echo -e "\${CYAN}请输入您的机场订阅链接:\${PLAIN}"
    read -p "订阅链接: " sub_url
    
    update_state "subscription_url" "\$sub_url"
    
    echo -e "\${CYAN}正在获取订阅配置...\${PLAIN}"
    
    # 尝试获取订阅内容
    if ! curl -s -o /tmp/subscription.yaml "\$sub_url"; then
        echo -e "\${RED}无法获取订阅内容，请检查链接是否正确或网络连接\${PLAIN}"
        exit 1
    fi
    
    # 检查是否为有效的clash/mihomo配置
    if ! grep -q "^proxies:" /tmp/subscription.yaml; then
        echo -e "\${RED}订阅内容不是有效的clash/mihomo配置文件\${PLAIN}"
        exit 1
    fi
    
    echo -e "\${GREEN}成功获取订阅配置\${PLAIN}"
    
    # 提取并合并配置
    
    # 获取模板中的proxies部分之前的内容
    sed -n '1,/^proxies:/p' "\$CONFIG_TEMPLATE" > \$CONF_DIR/config.yaml
    
    # 获取订阅中的proxies及之后的内容
    sed -n '/^proxies:/,$p' /tmp/subscription.yaml >> \$CONF_DIR/config.yaml
    
    # 替换配置文件中的VPS_IP
    sed -i "s/VPS_IP/\$MIHOMO_IP/g" \$CONF_DIR/config.yaml
    
    echo -e "\${GREEN}已生成配置文件\${PLAIN}"
else
    update_state "config_type" "custom"
    echo -e "\${CYAN}将使用自定义配置文件\${PLAIN}"
    
    # 复制配置模板
    cp "\$CONFIG_TEMPLATE" \$CONF_DIR/config.yaml
    
    # 替换配置文件中的VPS_IP
    sed -i "s/VPS_IP/\$MIHOMO_IP/g" \$CONF_DIR/config.yaml
    
    echo -e "\${YELLOW}注意: 您需要手动编辑配置文件以设置您的代理节点\${PLAIN}"
    echo -e "\${YELLOW}配置文件路径: \$CONF_DIR/config.yaml\${PLAIN}"
    echo -e "\${YELLOW}您可以使用nano或vim进行编辑:\${PLAIN}"
    echo -e "\${YELLOW}  nano \$CONF_DIR/config.yaml\${PLAIN}"
    echo -e "\${YELLOW}或者\${PLAIN}"
    echo -e "\${YELLOW}  vim \$CONF_DIR/config.yaml\${PLAIN}"
    
    read -p "是否立即编辑配置文件? (y/n): " edit_now
    if [[ "\$edit_now" == "y" || "\$edit_now" == "Y" ]]; then
        if command -v nano &> /dev/null; then
            nano \$CONF_DIR/config.yaml
        elif command -v vim &> /dev/null; then
            vim \$CONF_DIR/config.yaml
        else
            echo -e "\${RED}未找到编辑器(nano/vim)，请安装后手动编辑配置文件\${PLAIN}"
        fi
    fi
fi

# 下载UI文件
update_state "installation_stage" "下载UI文件"
echo -e "\${CYAN}下载Mihomo UI界面...\${PLAIN}"

mkdir -p \$CONF_DIR/ui

# 尝试获取最新版本
echo -e "\${CYAN}正在检查最新版本...\${PLAIN}"
LATEST_VERSION=\$(curl -s https://api.github.com/repos/MetaCubeX/metacubexd/releases/latest | grep "tag_name" | cut -d '"' -f 4)

if [[ -z "\$LATEST_VERSION" ]]; then
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

# 安装mihomo
update_state "installation_stage" "安装Mihomo"
echo -e "\${CYAN}开始安装Mihomo...\${PLAIN}"

# 检查是否有现有的mihomo容器
if docker ps -a | grep -q mihomo; then
    echo -e "\${YELLOW}检测到已有mihomo容器，将先移除...\${PLAIN}"
    docker stop mihomo &>/dev/null
    docker rm mihomo &>/dev/null
fi

# 选择安装方式
echo -e "\${CYAN}请选择安装方式:\${PLAIN}"
echo -e "  1) 直接从Docker Hub拉取镜像 (需要网络环境良好)"
echo -e "  2) 使用本地镜像文件 (适用于无法直接拉取镜像的环境)"
read -p "请选择 [1-2]: " install_choice

if [[ "\$install_choice" == "1" ]]; then
    update_state "docker_method" "direct_pull"
    echo -e "\${CYAN}正在从Docker Hub拉取镜像...\${PLAIN}"
    
    if ! docker pull metacubex/mihomo:latest; then
        echo -e "\${RED}拉取镜像失败，可能是网络问题\${PLAIN}"
        echo -e "\${YELLOW}请选择使用本地镜像文件安装\${PLAIN}"
        update_state "docker_method" "local_image"
        exit 1
    fi
else
    update_state "docker_method" "local_image"
    echo -e "\${CYAN}使用本地镜像文件安装\${PLAIN}"
    
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
    echo -e "\${YELLOW}接口 \$MACVLAN_INTERFACE 已存在，将先移除\${PLAIN}"
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
# 此脚本将生成RouterOS配置命令
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
echo -e "\${CYAN}=== 使用说明 ===\${PLAIN}"
echo -e "\${CYAN}1. 通过WebFig界面操作:\${PLAIN}"
echo -e "\${CYAN}   - 登录RouterOS的WebFig界面\${PLAIN}"
echo -e "\${CYAN}   - 打开"Terminal"选项\${PLAIN}"
echo -e "\${CYAN}   - 复制并粘贴以下命令\${PLAIN}"
echo -e "\${CYAN}   - 按Enter执行\${PLAIN}"
echo
echo -e "\${CYAN}2. 通过WinBox操作:\${PLAIN}"
echo -e "\${CYAN}   - 打开WinBox连接到RouterOS\${PLAIN}"
echo -e "\${CYAN}   - 点击"New Terminal"按钮\${PLAIN}"
echo -e "\${CYAN}   - 复制并粘贴以下命令\${PLAIN}"
echo -e "\${CYAN}   - 按Enter执行\${PLAIN}"
echo
echo -e "\${CYAN}3. 通过SSH终端操作:\${PLAIN}"
echo -e "\${CYAN}   - 使用SSH连接到RouterOS\${PLAIN}"
echo -e "\${CYAN}   - 复制并粘贴以下命令\${PLAIN}"
echo -e "\${CYAN}   - 按Enter执行\${PLAIN}"
echo
echo -e "\${YELLOW}=== RouterOS配置命令 ===\${PLAIN}"
cat "\$ROUTER_CONFIG_FILE" | grep -v "^#"
echo
echo -e "\${CYAN}=== 非RouterOS路由器配置 ===\${PLAIN}"
echo -e "\${CYAN}如果您使用其他路由器系统:\${PLAIN}"
echo
echo -e "\${CYAN}1. OpenWrt路由器:\${PLAIN}"
echo -e "\${CYAN}   - 通过LuCI界面设置DNS服务器指向 \$MIHOMO_IP\${PLAIN}"
echo -e "\${CYAN}   - 添加静态路由，将198.18.0.0/16网段指向 \$MIHOMO_IP\${PLAIN}"
echo
echo -e "\${CYAN}2. 普通家用路由器:\${PLAIN}"
echo -e "\${CYAN}   - 通过DHCP设置自定义DNS服务器为 \$MIHOMO_IP\${PLAIN}"
echo -e "\${CYAN}   - 如果支持静态路由，添加198.18.0.0/16网段路由指向 \$MIHOMO_IP\${PLAIN}"
echo -e "\${CYAN}   - 如不支持，建议用户直接在电脑上手动设置代理\${PLAIN}"
echo

exit 0
EOF
    
    chmod +x "$ROUTER_SCRIPT"
    echo -e "${GREEN}RouterOS配置脚本生成完成: $ROUTER_SCRIPT${PLAIN}"
}

# 显示主菜单
show_menu() {
    echo -e "${CYAN}===========================================================${PLAIN}"
    echo -e "${CYAN}              Mihomo 一键安装引导脚本${PLAIN}"
    echo -e "${CYAN}===========================================================${PLAIN}"
    echo -e "${CYAN}  1. 配置代理机${PLAIN}"
    echo -e "${CYAN}  2. 配置RouterOS${PLAIN}"
    echo -e "${CYAN}  3. 检查安装状态${PLAIN}"
    echo -e "${CYAN}  4. 重新设置mihomo IP地址${PLAIN}"
    echo -e "${CYAN}  0. 退出${PLAIN}"
    echo -e "${CYAN}===========================================================${PLAIN}"
    
    # 显示当前状态
    if [[ -f "$STATE_FILE" ]]; then
        local mihomo_ip=$(get_state_value "mihomo_ip")
        local stage=$(get_state_value "installation_stage")
        local timestamp=$(get_state_value "timestamp")
        
        echo -e "${YELLOW}当前状态:${PLAIN}"
        [[ -n "$mihomo_ip" ]] && echo -e "${YELLOW}- Mihomo IP: $mihomo_ip${PLAIN}"
        [[ -n "$stage" ]] && echo -e "${YELLOW}- 安装阶段: $stage${PLAIN}"
        [[ -n "$timestamp" ]] && echo -e "${YELLOW}- 最后更新: $timestamp${PLAIN}"
        echo
    fi
    
    read -p "请选择 [0-4]: " choice
    
    case $choice in
        1)
            if [[ -f "$PROXY_SCRIPT" ]]; then
                echo -e "${CYAN}执行代理机配置脚本...${PLAIN}"
                bash "$PROXY_SCRIPT"
            else
                echo -e "${RED}代理机配置脚本不存在，请先设置IP地址${PLAIN}"
            fi
            read -p "按任意键继续..." key
            show_menu
            ;;
        2)
            if [[ -f "$ROUTER_SCRIPT" ]]; then
                echo -e "${CYAN}执行RouterOS配置脚本...${PLAIN}"
                bash "$ROUTER_SCRIPT"
            else
                echo -e "${RED}RouterOS配置脚本不存在，请先设置IP地址${PLAIN}"
            fi
            read -p "按任意键继续..." key
            show_menu
            ;;
        3)
            if [[ -f "$STATE_FILE" ]]; then
                echo -e "${CYAN}当前安装状态:${PLAIN}"
                cat "$STATE_FILE" | jq .
            else
                echo -e "${RED}状态文件不存在${PLAIN}"
            fi
            read -p "按任意键继续..." key
            show_menu
            ;;
        4)
            setup_mihomo_ip
            generate_proxy_script
            generate_router_script
            show_menu
            ;;
        0)
            echo -e "${GREEN}感谢使用！再见！${PLAIN}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效的选项，请重新选择${PLAIN}"
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
    if [[ ! -x "$SCRIPT_PATH" ]]; then
        echo -e "${YELLOW}检测到脚本没有执行权限，尝试添加执行权限...${PLAIN}"
        chmod +x "$SCRIPT_PATH"
        if [[ $? -eq 0 ]]; then
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
    
    echo -e "${CYAN}第一步: 设置mihomo IP地址...${PLAIN}"
    
    # 直接设置mihomo IP地址
    setup_mihomo_ip
    
    # 生成配置脚本
    generate_proxy_script
    generate_router_script
    
    echo -e "${GREEN}第一步完成: IP地址已设置为 ${MIHOMO_IP}${PLAIN}"
    echo -e "${CYAN}接下来您可以:${PLAIN}"
    echo -e "${CYAN}1. 配置代理机 - 安装Docker和mihomo${PLAIN}"
    echo -e "${CYAN}2. 配置RouterOS - 设置路由器指向mihomo${PLAIN}"
    echo -e "${CYAN}请按任意键进入菜单...${PLAIN}"
    read -n 1
    
    # 显示菜单
    show_menu
}

main