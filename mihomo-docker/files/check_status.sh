#!/bin/bash
#############################################################
# Mihomo 状态检查脚本 (已修改为支持Host网络模式)
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
    value=$(jq -r --arg key_jq "$key" '.[$key_jq] // ""' "$STATE_FILE" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        echo -e "${YELLOW}警告: 无法使用jq从状态文件 $STATE_FILE 中读取 '$key'。${PLAIN}" >&2
        value=$(grep -o "\"$key\": *\"[^\"]*\"" "$STATE_FILE" | grep -o "\"$key\": *\"\([^\"]*\)\"" | sed -E 's/.*"[^\"]+":[[:space:]]*"([^\"]*)".*/\1/')
        echo "$value"
    else
        echo "$value"
    fi
}

# 主机IP (替代原Mihomo IP)
HOST_IP=$(get_state_value "mihomo_ip") # 假设 state 文件中的 mihomo_ip 就是主机IP
MAIN_INTERFACE=$(get_state_value "main_interface")
INSTALL_STAGE=$(get_state_value "installation_stage")

# 检查是否已经设置了Mihomo
if [[ -z "$HOST_IP" ]]; then
    echo -e "${RED}错误: 尚未配置Mihomo${PLAIN}"
    echo -e "${YELLOW}请先运行主脚本设置Mihomo${PLAIN}"
    exit 1
fi

echo -e "${GREEN}=================================================${PLAIN}"
echo -e "${GREEN}       Mihomo 代理状态检查 Host模式${PLAIN}"
echo -e "${GREEN}=================================================${PLAIN}"
echo

# 显示基本配置信息
echo -e "${CYAN}基本配置信息:${PLAIN}"
echo -e "主机 IP: ${GREEN}$HOST_IP${PLAIN}"
echo -e "主网络接口: ${GREEN}$MAIN_INTERFACE${PLAIN}"
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
        sudo systemctl start docker
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
        CONTAINER_ID=$(docker ps | grep mihomo | awk '{print $1}')
        echo -e "Mihomo容器: ${GREEN}运行中${PLAIN}"
        CONTAINER_STATUS=$(docker inspect -f '{{.State.Status}}' $CONTAINER_ID)
        echo -e "容器ID: ${GREEN}$CONTAINER_ID${PLAIN}"
        echo -e "容器状态: ${GREEN}$CONTAINER_STATUS${PLAIN}"

        # 显示运行时间
        STARTED_AT=$(docker inspect -f '{{.State.StartedAt}}' $CONTAINER_ID)
        RUNNING_SECONDS=$(( $(date +%s) - $(date -d "$STARTED_AT" +%s) ))
        RUNNING_DAYS=$(( $RUNNING_SECONDS / 86400 ))
        RUNNING_HOURS=$(( ($RUNNING_SECONDS % 86400) / 3600 ))
        RUNNING_MINUTES=$(( ($RUNNING_SECONDS % 3600) / 60 ))
        echo -e "运行时间: ${GREEN}${RUNNING_DAYS}天 ${RUNNING_HOURS}小时 ${RUNNING_MINUTES}分钟${PLAIN}"
    else
        echo -e "Mihomo容器: ${RED}未运行${PLAIN}"
        if docker ps -a | grep -q mihomo; then
            echo -e "${YELLOW}检测到停止的mihomo容器，尝试启动...${PLAIN}"
            sudo docker start mihomo
            if docker ps | grep -q mihomo; then
                echo -e "${GREEN}Mihomo容器已启动${PLAIN}"
            else
                echo -e "${RED}Mihomo容器启动失败${PLAIN}"
                echo -e "${YELLOW}容器日志:${PLAIN}"
                sudo docker logs mihomo | tail -n 20
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

# 检查Docker网络配置
echo
echo -e "${CYAN}检查Docker网络配置:${PLAIN}"
NETWORK_MODE=$(docker inspect mihomo --format '{{.HostConfig.NetworkMode}}' 2>/dev/null)
if [[ "$NETWORK_MODE" == "host" ]]; then
    echo -e "Docker网络模式: ${GREEN}host 正确${PLAIN}"
else
    echo -e "Docker网络模式: ${RED}$NETWORK_MODE 错误${PLAIN}"
    echo -e "${YELLOW}网络模式应为 'host'，请检查您的docker run/compose配置。${PLAIN}"
fi

# 检查连接性
echo
echo -e "${CYAN}检查连接性:${PLAIN}"
# 在host模式下，服务监听在主机的端口上
if curl -s -m 3 http://127.0.0.1:9090/ui &> /dev/null; then
    echo -e "控制面板: ${GREEN}可访问${PLAIN}"
    echo -e "控制面板地址: ${GREEN}http://$HOST_IP:9090/ui${PLAIN}"
else
    echo -e "控制面板: ${RED}无法访问${PLAIN}"
    echo -e "${YELLOW}请检查Mihomo容器是否正常启动，以及防火墙是否开放了9090端口。${PLAIN}"
fi

# 检查配置文件
echo
echo -e "${CYAN}检查配置文件:${PLAIN}"
if [[ -f "/etc/mihomo/config.yaml" ]]; then
    echo -e "配置文件: ${GREEN}已存在${PLAIN}"
    # 检查关键配置项
    if grep -q "external-controller:" "/etc/mihomo/config.yaml"; then
        CONTROLLER_IP=$(grep "external-controller:" "/etc/mihomo/config.yaml" | awk -F':' '{print $2}' | awk -F':' '{print $1}' | tr -d ' ')
        if [[ "$CONTROLLER_IP" == "127.0.0.1" || "$CONTROLLER_IP" == "0.0.0.0" ]]; then
            echo -e "控制面板IP: ${GREEN}配置正确 ${CONTROLLER_IP}${PLAIN}"
        else
            echo -e "控制面板IP: ${YELLOW}$CONTROLLER_IP 建议为 127.0.0.1 或 0.0.0.0${PLAIN}"
        fi
    else
        echo -e "控制面板配置: ${RED}未找到${PLAIN}"
    fi

    if grep -q "bind-address:" "/etc/mihomo/config.yaml"; then
        BIND_ADDR=$(grep "bind-address:" "/etc/mihomo/config.yaml" | awk '{print $2}' | tr -d '"' | tr -d "'")
        if [[ "$BIND_ADDR" == "*" ]]; then
            echo -e "绑定地址: ${GREEN}* 推荐设置${PLAIN}"
        else
            echo -e "绑定地址: ${YELLOW}$BIND_ADDR 建议设置为*${PLAIN}"
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

# 最终状态判断
CONTAINER_RUNNING=$(docker ps | grep -q mihomo && echo "true" || echo "false")
CONTROL_PANEL_OK=$(curl -s -m 3 http://127.0.0.1:9090/ui &> /dev/null && echo "true" || echo "false")

if [[ "$CONTAINER_RUNNING" == "true" && "$NETWORK_MODE" == "host" && "$CONTROL_PANEL_OK" == "true" ]]; then
    echo -e "${GREEN}Mihomo代理运行正常! host网络模式${PLAIN}"
    echo -e "${GREEN}控制面板地址: http://$HOST_IP:9090/ui${PLAIN}"
    echo -e "${YELLOW}请确保您的路由器已正确配置指向此代理机 ${HOST_IP}${PLAIN}"
elif [[ "$CONTAINER_RUNNING" == "true" ]]; then
    echo -e "${RED}Mihomo代理存在问题!${PLAIN}"
    echo -e "${YELLOW}容器正在运行，但网络模式或控制面板存在问题。请根据以上检查结果修复。${PLAIN}"
else
    echo -e "${RED}Mihomo代理未运行!${PLAIN}"
    echo -e "${YELLOW}请根据以上检查结果修复问题。${PLAIN}"
fi
