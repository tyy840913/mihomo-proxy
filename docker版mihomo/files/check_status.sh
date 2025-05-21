#!/bin/bash
#############################################################
# Mihomo 状态检查脚本
# 此脚本将检查Mihomo代理的运行状态
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

# Mihomo IP
MIHOMO_IP=$(get_state_value "mihomo_ip")
INTERFACE_IP=$(get_state_value "interface_ip")
MAIN_INTERFACE=$(get_state_value "main_interface")
MACVLAN_INTERFACE=$(get_state_value "macvlan_interface")
INSTALL_STAGE=$(get_state_value "installation_stage")

# 检查是否已经设置了Mihomo
if [[ -z "$MIHOMO_IP" ]]; then
    echo -e "${RED}错误: 尚未配置Mihomo${PLAIN}"
    echo -e "${YELLOW}请先运行主脚本设置Mihomo IP地址${PLAIN}"
    exit 1
fi

echo -e "${GREEN}=================================================${PLAIN}"
echo -e "${GREEN}           Mihomo 代理状态检查${PLAIN}"
echo -e "${GREEN}=================================================${PLAIN}"
echo

# 显示基本配置信息
echo -e "${CYAN}基本配置信息:${PLAIN}"
echo -e "Mihomo IP: ${GREEN}$MIHOMO_IP${PLAIN}"
echo -e "接口IP: ${GREEN}$INTERFACE_IP${PLAIN}"
echo -e "主网络接口: ${GREEN}$MAIN_INTERFACE${PLAIN}"
echo -e "MacVLAN接口: ${GREEN}$MACVLAN_INTERFACE${PLAIN}"
echo -e "安装阶段: ${GREEN}$INSTALL_STAGE${PLAIN}"
echo

# 检查Docker状态
echo -e "${CYAN}检查Docker状态:${PLAIN}"
if command -v docker &> /dev/null; then
    echo -e "Docker安装: ${GREEN}已安装${PLAIN}"
    if systemctl is-active --quiet docker; then
        echo -e "Docker服务: ${GREEN}运行中${PLAIN}"
    else
        echo -e "Docker服务: ${RED}未运行${PLAIN}"
        echo -e "${YELLOW}尝试启动Docker服务...${PLAIN}"
        systemctl start docker
        if systemctl is-active --quiet docker; then
            echo -e "${GREEN}Docker服务已启动${PLAIN}"
        else
            echo -e "${RED}Docker服务启动失败${PLAIN}"
        fi
    fi
    
    # 检查mihomo容器
    echo
    echo -e "${CYAN}检查Mihomo容器:${PLAIN}"
    if docker ps | grep -q mihomo; then
        echo -e "Mihomo容器: ${GREEN}运行中${PLAIN}"
        # 获取容器详细信息
        CONTAINER_ID=$(docker ps | grep mihomo | awk '{print $1}')
        CONTAINER_STATUS=$(docker inspect -f '{{.State.Status}}' $CONTAINER_ID)
        CONTAINER_HEALTH=$(docker inspect -f '{{.State.Health.Status}}' $CONTAINER_ID 2>/dev/null || echo "无健康检查")
        CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_ID)
        
        echo -e "容器ID: ${GREEN}$CONTAINER_ID${PLAIN}"
        echo -e "容器状态: ${GREEN}$CONTAINER_STATUS${PLAIN}"
        echo -e "健康状态: ${GREEN}$CONTAINER_HEALTH${PLAIN}"
        echo -e "容器IP: ${GREEN}$CONTAINER_IP${PLAIN}"
        
        # 显示运行时间
        UPTIME=$(docker inspect -f '{{.State.StartedAt}}' $CONTAINER_ID)
        echo -e "启动时间: ${GREEN}$UPTIME${PLAIN}"
    else
        echo -e "Mihomo容器: ${RED}未运行${PLAIN}"
        
        # 检查是否存在停止的容器
        if docker ps -a | grep -q mihomo; then
            echo -e "${YELLOW}检测到停止的mihomo容器，尝试启动...${PLAIN}"
            docker start mihomo
            if docker ps | grep -q mihomo; then
                echo -e "${GREEN}Mihomo容器已启动${PLAIN}"
            else
                echo -e "${RED}Mihomo容器启动失败${PLAIN}"
                echo -e "${YELLOW}容器日志:${PLAIN}"
                docker logs mihomo | tail -n 20
            fi
        else
            echo -e "${RED}未找到mihomo容器${PLAIN}"
            echo -e "${YELLOW}请运行代理机配置脚本重新配置${PLAIN}"
        fi
    fi
else
    echo -e "Docker安装: ${RED}未安装${PLAIN}"
    echo -e "${YELLOW}请运行代理机配置脚本安装Docker${PLAIN}"
fi

# 检查网络接口
echo
echo -e "${CYAN}检查网络接口:${PLAIN}"
if ip link show | grep -q $MACVLAN_INTERFACE; then
    echo -e "MacVLAN接口: ${GREEN}已创建${PLAIN}"
    IP_ADDR=$(ip -4 addr show $MACVLAN_INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    echo -e "接口IP地址: ${GREEN}$IP_ADDR${PLAIN}"
    
    if [[ "$IP_ADDR" != "$INTERFACE_IP" ]]; then
        echo -e "${YELLOW}警告: 接口IP地址与配置不一致${PLAIN}"
    fi
    
    # 检查接口是否启用
    if ip link show $MACVLAN_INTERFACE | grep -q "state UP"; then
        echo -e "接口状态: ${GREEN}已启用${PLAIN}"
    else
        echo -e "接口状态: ${RED}未启用${PLAIN}"
        echo -e "${YELLOW}尝试启用接口...${PLAIN}"
        ip link set $MACVLAN_INTERFACE up
    fi
else
    echo -e "MacVLAN接口: ${RED}未创建${PLAIN}"
    echo -e "${YELLOW}尝试创建接口...${PLAIN}"
    ip link add $MACVLAN_INTERFACE link $MAIN_INTERFACE type macvlan mode bridge
    ip addr add $INTERFACE_IP/24 dev $MACVLAN_INTERFACE
    ip link set $MACVLAN_INTERFACE up
    ip route add $MIHOMO_IP dev $MACVLAN_INTERFACE
    
    if ip link show | grep -q $MACVLAN_INTERFACE; then
        echo -e "${GREEN}MacVLAN接口创建成功${PLAIN}"
    else
        echo -e "${RED}MacVLAN接口创建失败${PLAIN}"
    fi
fi

# 检查主网卡是否处于混杂模式
echo
echo -e "${CYAN}检查主网卡混杂模式:${PLAIN}"
if ip link show $MAIN_INTERFACE | grep -q "PROMISC"; then
    echo -e "混杂模式: ${GREEN}已启用${PLAIN}"
else
    echo -e "混杂模式: ${RED}未启用${PLAIN}"
    echo -e "${YELLOW}尝试启用混杂模式...${PLAIN}"
    ip link set $MAIN_INTERFACE promisc on
    
    if ip link show $MAIN_INTERFACE | grep -q "PROMISC"; then
        echo -e "${GREEN}混杂模式已启用${PLAIN}"
    else
        echo -e "${RED}混杂模式启用失败${PLAIN}"
    fi
fi

# 检查系统服务
echo
echo -e "${CYAN}检查系统服务:${PLAIN}"
if systemctl list-unit-files | grep -q "promisc-$MAIN_INTERFACE"; then
    if systemctl is-enabled --quiet promisc-$MAIN_INTERFACE; then
        echo -e "混杂模式服务: ${GREEN}已启用${PLAIN}"
    else
        echo -e "混杂模式服务: ${RED}未启用${PLAIN}"
        systemctl enable promisc-$MAIN_INTERFACE
    fi
else
    echo -e "混杂模式服务: ${RED}未创建${PLAIN}"
fi

# 检查是否正确配置网络接口（而不是检查系统服务）
if ip link show | grep -q "$MACVLAN_INTERFACE"; then
    echo -e "网络接口: ${GREEN}已配置${PLAIN}"
    
    # 检查网络接口是否启用
    if ip link show "$MACVLAN_INTERFACE" | grep -q "state UP"; then
        echo -e "网络接口状态: ${GREEN}已启用${PLAIN}"
    else
        echo -e "网络接口状态: ${RED}未启用${PLAIN}"
        echo -e "${YELLOW}正在尝试启用接口...${PLAIN}"
        ip link set "$MACVLAN_INTERFACE" up
    fi

    # 检查路由是否存在
    if ip route | grep -q "$MIHOMO_IP.*$MACVLAN_INTERFACE"; then
        echo -e "路由配置: ${GREEN}已配置${PLAIN}"
    else
        echo -e "路由配置: ${RED}未配置${PLAIN}"
        echo -e "${YELLOW}正在添加路由...${PLAIN}"
        ip route add $MIHOMO_IP dev $MACVLAN_INTERFACE
    fi
else
    echo -e "网络接口: ${RED}未配置${PLAIN}"
    echo -e "${YELLOW}网络接口可能需要重新配置，请手动执行以下命令:${PLAIN}"
    echo -e "${YELLOW}ip link add $MACVLAN_INTERFACE link $MAIN_INTERFACE type macvlan mode bridge${PLAIN}"
    echo -e "${YELLOW}ip addr add $INTERFACE_IP/24 dev $MACVLAN_INTERFACE${PLAIN}"
    echo -e "${YELLOW}ip link set $MACVLAN_INTERFACE up${PLAIN}"
    echo -e "${YELLOW}ip route add $MIHOMO_IP dev $MACVLAN_INTERFACE${PLAIN}"
fi

# 检查连接性
echo
echo -e "${CYAN}检查连接性:${PLAIN}"
if ping -c 1 -W 1 $MIHOMO_IP &> /dev/null; then
    echo -e "Mihomo IP可访问性: ${GREEN}可访问${PLAIN}"
    
    # 检查控制面板
    if curl -s -m 3 http://$MIHOMO_IP:9090 &> /dev/null; then
        echo -e "控制面板: ${GREEN}可访问${PLAIN}"
        echo -e "控制面板地址: ${GREEN}http://$MIHOMO_IP:9090/ui${PLAIN}"
    else
        echo -e "控制面板: ${RED}无法访问${PLAIN}"
        echo -e "${YELLOW}请检查Mihomo容器是否正常启动${PLAIN}"
    fi
else
    echo -e "Mihomo IP可访问性: ${RED}无法访问${PLAIN}"
    echo -e "${YELLOW}请检查网络配置${PLAIN}"
fi

# 检查配置文件
echo
echo -e "${CYAN}检查配置文件:${PLAIN}"
if [[ -f "/etc/mihomo/config.yaml" ]]; then
    echo -e "配置文件: ${GREEN}已存在${PLAIN}"
    # 检查关键配置项
    if grep -q "external-controller:" "/etc/mihomo/config.yaml"; then
        CONTROLLER_IP=$(grep "external-controller:" "/etc/mihomo/config.yaml" | awk -F':' '{print $2}' | awk -F':' '{print $1}' | tr -d ' ')
        if [[ "$CONTROLLER_IP" == "$MIHOMO_IP" || "$CONTROLLER_IP" == "0.0.0.0" ]]; then
            echo -e "控制面板IP: ${GREEN}配置正确${PLAIN}"
        else
            echo -e "控制面板IP: ${YELLOW}$CONTROLLER_IP (与Mihomo IP不一致)${PLAIN}"
        fi
    else
        echo -e "控制面板配置: ${RED}未找到${PLAIN}"
    fi
    
    if grep -q "bind-address:" "/etc/mihomo/config.yaml"; then
        BIND_ADDR=$(grep "bind-address:" "/etc/mihomo/config.yaml" | awk '{print $2}' | tr -d '"' | tr -d "'")
        if [[ "$BIND_ADDR" == "*" ]]; then
            echo -e "绑定地址: ${GREEN}* (推荐设置)${PLAIN}"
        else
            echo -e "绑定地址: ${YELLOW}$BIND_ADDR (建议设置为*)${PLAIN}"
        fi
    else
        echo -e "绑定地址配置: ${RED}未找到${PLAIN}"
    fi
else
    echo -e "配置文件: ${RED}不存在${PLAIN}"
    echo -e "${YELLOW}请运行代理机配置脚本创建配置文件${PLAIN}"
fi

# 总结
echo
echo -e "${GREEN}=================================================${PLAIN}"
echo -e "${GREEN}           Mihomo 状态检查完成${PLAIN}"
echo -e "${GREEN}=================================================${PLAIN}"

if docker ps | grep -q mihomo && ip link show | grep -q $MACVLAN_INTERFACE && curl -s -m 3 http://$MIHOMO_IP:9090 &> /dev/null; then
    echo -e "${GREEN}Mihomo代理运行正常!${PLAIN}"
    echo -e "${GREEN}控制面板地址: http://$MIHOMO_IP:9090/ui${PLAIN}"
    echo -e "${YELLOW}请确保您的路由器已正确配置指向此代理机${PLAIN}"
else
    echo -e "${RED}Mihomo代理存在问题!${PLAIN}"
    echo -e "${YELLOW}请根据以上检查结果修复问题${PLAIN}"
    echo -e "${YELLOW}如需重新配置，请运行代理机配置脚本${PLAIN}"
fi
