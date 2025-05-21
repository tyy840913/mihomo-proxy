#!/bin/bash
#############################################################
# Mihomo 代理机配置脚本
# 此脚本将配置Docker和Mihomo代理环境
#############################################################

# 设置颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 配置信息 - 将从状态文件中读取
SCRIPT_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
FILES_DIR="$SCRIPT_DIR/files"
STATE_FILE="$FILES_DIR/mihomo_state.json"
CONFIG_TEMPLATE="$SCRIPT_DIR/config.yaml"  # 修正配置模板路径为正确的位置
CONF_DIR="/etc/mihomo"

# 从状态文件读取值
get_state_value() {
    local key=$1
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "" && return 1 # File doesn't exist
    fi
    local value
    # Try to read with jq. Suppress jq's stderr for cleaner output if file is not JSON.
    value=$(jq -r --arg key_jq "$key" '.[$key_jq] // ""' "$STATE_FILE" 2>/dev/null)
    # Check jq's exit status.
    if [[ $? -ne 0 ]]; then
        echo -e "${YELLOW}Warning: Could not read '$key' from state file $STATE_FILE using jq. File might be corrupted or not valid JSON.${PLAIN}" >&2
        # Fallback to grep for basic cases if jq fails (e.g. file not JSON yet)
        value=$(grep -o "\"$key\": *\"[^\"]*\"" "$STATE_FILE" | grep -o "\"$key\": *\"\([^\"]*\)\"" | sed -E 's/.*"[^"]+":[[:space:]]*"([^"]*)".*/\1/')
        echo "$value"
    else
        echo "$value"
    fi
}

# 更新状态函数
update_state() {
    local key="$1"
    local value="$2"
    if [[ -f "$STATE_FILE" ]]; then
        sed -i "s|\"$key\": \"[^\"]*\"|\"$key\": \"$value\"|g" "$STATE_FILE"
    fi
}

# 读取必要的配置信息
MIHOMO_IP=$(get_state_value "mihomo_ip")
INTERFACE_IP=$(get_state_value "interface_ip")
MAIN_INTERFACE=$(get_state_value "main_interface")
MACVLAN_INTERFACE=$(get_state_value "macvlan_interface")

# 检查配置是否存在
if [[ -z "$MIHOMO_IP" || -z "$MAIN_INTERFACE" ]]; then
    echo -e "${RED}错误: 无法读取配置信息，请先运行主脚本设置IP地址${PLAIN}"
    exit 1
fi

# 检查是否具有root权限
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

echo -e "${CYAN}开始配置Mihomo代理机...${PLAIN}"
update_state "installation_stage" "网络配置"

# 安装所需依赖
echo -e "${CYAN}更新系统包并安装必要依赖...${PLAIN}"
apt update && apt install -y docker.io curl wget jq iproute2 iputils-ping arping tar gzip

# 检查Docker是否安装成功
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker安装失败，请手动安装后重试${PLAIN}"
    exit 1
fi

echo -e "${GREEN}Docker已安装${PLAIN}"

# 启动Docker服务
systemctl start docker
systemctl enable docker

# 设置网卡混杂模式
echo -e "${CYAN}设置网卡混杂模式...${PLAIN}"
ip link set $MAIN_INTERFACE promisc on

# 创建持久化的promisc设置
cat > /etc/systemd/system/promisc-$MAIN_INTERFACE.service << EOL
[Unit]
Description=Set $MAIN_INTERFACE to promiscuous mode
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/ip link set $MAIN_INTERFACE promisc on
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable promisc-$MAIN_INTERFACE.service

# 创建Docker macvlan网络
echo -e "${CYAN}创建Docker macvlan网络...${PLAIN}"
SUBNET=$(echo $MIHOMO_IP | cut -d '.' -f 1,2,3).0/24
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n 1)

# 检查是否已存在macvlan网络
if docker network ls | grep -q mnet; then
    echo -e "${YELLOW}已存在macvlan网络，将重新创建...${PLAIN}"
    docker network rm mnet &>/dev/null || {
        echo -e "${YELLOW}注意: 无法删除现有网络，可能被容器使用。尝试停止mihomo容器...${PLAIN}"
        docker stop mihomo &>/dev/null
        docker rm mihomo &>/dev/null
        docker network rm mnet &>/dev/null || {
            echo -e "${YELLOW}警告: 无法删除网络，将继续使用现有网络${PLAIN}"
        }
    }
fi

# 确保网络存在，如果不存在或者成功删除了，就创建新网络
if ! docker network ls | grep -q mnet; then
    echo -e "${CYAN}创建Docker macvlan网络...${PLAIN}"
    docker network create -d macvlan --subnet=$SUBNET --gateway=$GATEWAY -o parent=$MAIN_INTERFACE mnet || {
        echo -e "${RED}创建macvlan网络失败，尝试不同方式...${PLAIN}"
        docker network create -d macvlan --subnet=$SUBNET --gateway=$GATEWAY -o parent=$MAIN_INTERFACE:0 mnet || {
            echo -e "${RED}创建macvlan网络失败，请检查网络配置${PLAIN}"
            exit 1
        }
    }
else
    echo -e "${YELLOW}继续使用现有macvlan网络${PLAIN}"
fi

update_state "installation_stage" "准备配置文件"

# 准备Mihomo配置目录
echo -e "${CYAN}准备Mihomo配置目录...${PLAIN}"
mkdir -p $CONF_DIR

# 检查现有配置文件
EXISTING_CONFIG=0
if [[ -f "$CONF_DIR/config.yaml" ]]; then
    echo -e "${YELLOW}检测到现有配置文件: $CONF_DIR/config.yaml${PLAIN}"
    # 自动使用现有配置文件
    echo -e "${GREEN}自动使用现有配置文件${PLAIN}"
    EXISTING_CONFIG=1
    
    # 检查external-controller部分是否需要更新IP地址
    if grep -q "external-controller:" "$CONF_DIR/config.yaml"; then
        CURRENT_CONTROLLER_IP=$(grep "external-controller:" "$CONF_DIR/config.yaml" | awk -F':' '{print $2}' | awk -F':' '{print $1}' | tr -d ' ')
        if [[ "$CURRENT_CONTROLLER_IP" != "$MIHOMO_IP" && "$CURRENT_CONTROLLER_IP" != "0.0.0.0" ]]; then
            echo -e "${YELLOW}配置文件中控制台IP地址($CURRENT_CONTROLLER_IP)与当前设置($MIHOMO_IP)不一致${PLAIN}"
            echo -e "${CYAN}正在更新控制台IP地址...${PLAIN}"
            sed -i "s/external-controller: $CURRENT_CONTROLLER_IP/external-controller: $MIHOMO_IP/g" "$CONF_DIR/config.yaml"
            echo -e "${GREEN}控制台IP地址已更新${PLAIN}"
        fi
    fi
    
    # 检查bind-address是否为"*"，如果不是则提示保持"*"更好
    if grep -q "bind-address:" "$CONF_DIR/config.yaml"; then
        CURRENT_BIND=$(grep "bind-address:" "$CONF_DIR/config.yaml" | awk '{print $2}' | tr -d '"' | tr -d "'")
        if [[ "$CURRENT_BIND" != "*" ]]; then
            echo -e "${YELLOW}注意: 当前bind-address设置为'$CURRENT_BIND'，建议设置为'*'以监听所有地址${PLAIN}"
            read -p "是否将bind-address设置为'*'? (y/n): " change_bind
            if [[ "$change_bind" == "y" || "$change_bind" == "Y" ]]; then
                sed -i "s/bind-address: $CURRENT_BIND/bind-address: \"*\"/g" "$CONF_DIR/config.yaml"
                echo -e "${GREEN}bind-address已设置为'*'${PLAIN}"
            fi
        else
            echo -e "${GREEN}检测到bind-address已设置为'*'，这是推荐的设置${PLAIN}"
        fi
    fi
fi

# 如果不使用现有配置，则创建新配置
if [[ $EXISTING_CONFIG -eq 0 ]]; then
    update_state "config_type" "preset"
    echo -e "${CYAN}使用预设配置文件...${PLAIN}"
    
    # 复制配置模板
    cp "$CONFIG_TEMPLATE" $CONF_DIR/config.yaml
    
    # 替换配置文件中的VPS_IP（但不替换bind-address的值）
    sed -i "/bind-address:/! s/VPS_IP/$MIHOMO_IP/g" $CONF_DIR/config.yaml
    
    # 配置文件说明
    echo -e "${YELLOW}已使用预设配置文件。您需要根据自己的代理服务器信息修改配置文件中的关键参数：${PLAIN}"
    echo -e "${YELLOW}配置文件路径: $CONF_DIR/config.yaml${PLAIN}"
    echo -e "${YELLOW}- 编辑配置文件，找到proxies部分${PLAIN}"
    echo -e "${YELLOW}- 将VPS_IP替换为您的服务器IP地址${PLAIN}"
    echo -e "${YELLOW}- 替换your_password为您设置的密码${PLAIN}"
    echo -e "${YELLOW}- 根据您的网络情况调整上传/下载速度参数${PLAIN}"
    echo -e "${YELLOW}您可以使用以下命令编辑配置文件:${PLAIN}"
    echo -e "${YELLOW}  nano $CONF_DIR/config.yaml${PLAIN}"
    echo -e "${YELLOW}或者${PLAIN}"
    echo -e "${YELLOW}  vim $CONF_DIR/config.yaml${PLAIN}"
fi

# 下载UI文件
update_state "installation_stage" "下载UI文件"
echo -e "${CYAN}下载Mihomo UI界面...${PLAIN}"

# 检查是否已有UI文件
EXISTING_UI=0
if [[ -d "$CONF_DIR/ui" ]] && ls -A "$CONF_DIR/ui" &> /dev/null; then
    echo -e "${YELLOW}检测到现有UI文件，自动使用现有UI文件${PLAIN}"
    EXISTING_UI=1
else
    mkdir -p $CONF_DIR/ui
fi

if [[ $EXISTING_UI -eq 0 ]]; then
    # 尝试获取最新版本
    echo -e "${CYAN}正在检查最新版本...${PLAIN}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/MetaCubeX/metacubexd/releases/latest | grep "tag_name" | cut -d '"' -f 4)

    if [[ -z "$LATEST_VERSION" ]]; then
        echo -e "${YELLOW}警告: 无法获取最新版本信息，使用默认版本v1.187.1${PLAIN}"
        LATEST_VERSION="v1.187.1"
    fi

    echo -e "${GREEN}检测到最新版本: $LATEST_VERSION${PLAIN}"

    # 下载UI文件
    download_ui() {
        echo -e "${CYAN}正在下载UI包...${PLAIN}"
        if curl -L -o /tmp/compressed-dist.tgz "https://github.com/MetaCubeX/metacubexd/releases/download/$LATEST_VERSION/compressed-dist.tgz"; then
            echo -e "${GREEN}UI包下载成功${PLAIN}"
            
            # 解压UI文件
            if tar -xzf /tmp/compressed-dist.tgz -C $CONF_DIR/ui; then
                echo -e "${GREEN}UI文件解压成功${PLAIN}"
                return 0
            else
                echo -e "${RED}UI文件解压失败${PLAIN}"
                return 1
            fi
        else
            echo -e "${RED}UI包下载失败${PLAIN}"
            return 1
        fi
    }

    # 尝试下载UI包
    if ! download_ui; then
        echo -e "${YELLOW}尝试备选下载方式...${PLAIN}"
        if ! download_ui; then
            echo -e "${RED}UI下载失败，请手动下载UI文件${PLAIN}"
            echo -e "${YELLOW}您可以稍后手动执行以下命令:${PLAIN}"
            echo -e "${YELLOW}  wget https://github.com/MetaCubeX/metacubexd/releases/download/$LATEST_VERSION/compressed-dist.tgz${PLAIN}"
            echo -e "${YELLOW}  tar -xzf compressed-dist.tgz -C $CONF_DIR/ui${PLAIN}"
        fi
    fi
else
    echo -e "${GREEN}使用现有UI文件，跳过UI下载步骤${PLAIN}"
fi

# 安装mihomo
update_state "installation_stage" "安装Mihomo"
echo -e "${CYAN}开始安装Mihomo...${PLAIN}"

# 检查是否有现有的mihomo容器
if docker ps -a | grep -q mihomo; then
    echo -e "${YELLOW}检测到系统中已安装mihomo容器，将自动删除并重新安装${PLAIN}"
    echo -e "${CYAN}正在停止并移除现有mihomo容器...${PLAIN}"
    docker stop mihomo &>/dev/null
    docker rm mihomo &>/dev/null
fi

# 从Docker Hub拉取镜像
update_state "docker_method" "direct_pull"
echo -e "${CYAN}正在从Docker Hub拉取镜像...${PLAIN}"

# 尝试从Docker Hub拉取镜像
if ! docker pull metacubex/mihomo:latest; then
    echo -e "${RED}拉取镜像失败，尝试使用本地镜像${PLAIN}"
    update_state "docker_method" "local_image"
    
    # 检查是否有本地镜像文件
    if [[ ! -f "./mihomo-image.tar" ]]; then
        echo -e "${RED}未找到本地镜像文件: ./mihomo-image.tar${PLAIN}"
        echo -e "${YELLOW}请先在有科学上网环境的电脑上执行以下命令:${PLAIN}"
        echo -e "${YELLOW}  docker pull metacubex/mihomo:latest${PLAIN}"
        echo -e "${YELLOW}  docker save metacubex/mihomo:latest -o mihomo-image.tar${PLAIN}"
        echo -e "${YELLOW}然后将mihomo-image.tar文件上传到当前目录${PLAIN}"
        exit 1
    fi
    
    echo -e "${CYAN}正在导入本地镜像文件...${PLAIN}"
    if ! docker load -i ./mihomo-image.tar; then
        echo -e "${RED}导入镜像文件失败${PLAIN}"
        exit 1
    fi
fi

# 启动mihomo容器
echo -e "${CYAN}启动Mihomo容器...${PLAIN}"
if ! docker run -d --privileged \
  --name=mihomo --restart=always \
  --network mnet --ip $MIHOMO_IP \
  -v $CONF_DIR:/root/.config/mihomo/ \
  metacubex/mihomo:latest; then
    
    echo -e "${RED}启动Mihomo容器失败${PLAIN}"
    exit 1
fi

# 检查容器是否成功运行
if ! docker ps | grep -q mihomo; then
    echo -e "${RED}Mihomo容器未能成功运行${PLAIN}"
    echo -e "${YELLOW}查看容器日志:${PLAIN}"
    docker logs mihomo
    exit 1
fi

update_state "installation_stage" "配置网络"

# 设置宿主机和容器通信
echo -e "${CYAN}配置宿主机与容器通信...${PLAIN}"

# 检查是否已存在接口
if ip link show | grep -q $MACVLAN_INTERFACE; then
    echo -e "${YELLOW}检测到已存在的macvlan接口，尝试删除...${PLAIN}"
    ip link del $MACVLAN_INTERFACE &>/dev/null
fi

# 按照参考脚本直接创建网络配置（不使用系统服务）
echo -e "${CYAN}创建macvlan接口: $MACVLAN_INTERFACE${PLAIN}"
ip link add $MACVLAN_INTERFACE link $MAIN_INTERFACE type macvlan mode bridge
if [ $? -ne 0 ]; then
    echo -e "${RED}创建macvlan接口失败${PLAIN}"
    echo -e "${YELLOW}请检查网络接口名称是否正确: $MAIN_INTERFACE${PLAIN}"
    # 尝试使用其他方式创建
    echo -e "${CYAN}尝试使用替代方法创建接口...${PLAIN}"
    ip link add $MACVLAN_INTERFACE link $MAIN_INTERFACE type macvlan mode bridge || true
fi

echo -e "${CYAN}为接口分配IP地址: $INTERFACE_IP/24${PLAIN}"
ip addr add $INTERFACE_IP/24 dev $MACVLAN_INTERFACE
if [ $? -ne 0 ]; then
    echo -e "${RED}分配IP地址失败${PLAIN}"
    # 尝试先清除接口再添加
    ip addr flush dev $MACVLAN_INTERFACE 2>/dev/null
    ip addr add $INTERFACE_IP/24 dev $MACVLAN_INTERFACE || true
fi

echo -e "${CYAN}启用接口...${PLAIN}"
ip link set $MACVLAN_INTERFACE up

echo -e "${CYAN}添加路由规则: $MIHOMO_IP${PLAIN}"
ip route add $MIHOMO_IP dev $MACVLAN_INTERFACE 2>/dev/null || true

# 验证配置是否生效
if ip link show $MACVLAN_INTERFACE 2>/dev/null | grep -q "UP"; then
    echo -e "${GREEN}网络接口配置成功!${PLAIN}"
    echo -e "${GREEN}• Mihomo IP: $MIHOMO_IP${PLAIN}"
    echo -e "${GREEN}• 接口 IP: $INTERFACE_IP${PLAIN}"
else
    echo -e "${RED}网络接口配置失败${PLAIN}"
    echo -e "${YELLOW}请尝试手动执行以下命令:${PLAIN}"
    echo -e "${YELLOW}ip link add $MACVLAN_INTERFACE link $MAIN_INTERFACE type macvlan mode bridge${PLAIN}"
    echo -e "${YELLOW}ip addr add $INTERFACE_IP/24 dev $MACVLAN_INTERFACE${PLAIN}"
    echo -e "${YELLOW}ip link set $MACVLAN_INTERFACE up${PLAIN}"
    echo -e "${YELLOW}ip route add $MIHOMO_IP dev $MACVLAN_INTERFACE${PLAIN}"
fi

# 不创建网络重建脚本，避免依赖于系统服务
# 注意：网络配置已直接在上面通过命令行操作完成

# 显示网络重建命令（供用户在需要时手动执行）
echo -e "${YELLOW}如果网络配置丢失，可以执行以下命令重建网络：${PLAIN}"
echo -e "${CYAN}ip link add $MACVLAN_INTERFACE link $MAIN_INTERFACE type macvlan mode bridge${PLAIN}"
echo -e "${CYAN}ip addr add $INTERFACE_IP/24 dev $MACVLAN_INTERFACE${PLAIN}"
echo -e "${CYAN}ip link set $MACVLAN_INTERFACE up${PLAIN}"
echo -e "${CYAN}ip route add $MIHOMO_IP dev $MACVLAN_INTERFACE${PLAIN}"

update_state "installation_stage" "安装完成"
echo -e "${GREEN}Mihomo代理机配置完成!${PLAIN}"
echo -e "${GREEN}Mihomo IP: $MIHOMO_IP${PLAIN}"
echo -e "${GREEN}控制台地址: http://$MIHOMO_IP:9090/ui${PLAIN}"
echo -e "${YELLOW}注意: 您需要在路由器上配置以使用此代理${PLAIN}"
echo
echo -e "${CYAN}请在其他设备上访问控制面板检查状态${PLAIN}"
echo -e "${CYAN}http://$MIHOMO_IP:9090/ui${PLAIN}"
