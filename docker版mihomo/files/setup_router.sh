#!/bin/bash
#############################################################
# RouterOS 配置脚本
# 此脚本将生成RouterOS配置命令及详细配置指南
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

# 检查是否有Mihomo IP
if [[ -z "$MIHOMO_IP" ]]; then
    echo -e "${RED}错误: 无法读取Mihomo IP地址，请先运行主脚本设置IP地址${PLAIN}"
    exit 1
fi

# RouterOS配置文件名
ROUTER_CONFIG_FILE="$FILES_DIR/routeros_commands.rsc"

echo -e "${CYAN}生成RouterOS配置命令...${PLAIN}"

# 创建RouterOS配置文件
cat > "$ROUTER_CONFIG_FILE" << EOL
# ==== Mihomo RouterOS 配置命令 ====
# 请将以下命令复制到RouterOS的Terminal中执行
# 您可以通过WebFig、WinBox或SSH访问RouterOS的Terminal

# 设置DNS服务器指向Mihomo
/ip dns set servers=$MIHOMO_IP

# 添加fake-ip路由规则
/ip route add dst-address=198.18.0.0/16 gateway=$MIHOMO_IP comment="mihomo fake-ip route"
EOL

echo -e "${GREEN}RouterOS配置命令已生成: $ROUTER_CONFIG_FILE${PLAIN}"
echo
echo -e "${GREEN}=================================================${PLAIN}"
echo -e "${GREEN}           RouterOS 配置详细指南${PLAIN}"
echo -e "${GREEN}=================================================${PLAIN}"
echo

# 创建简洁的RouterOS配置指南
cat > "$FILES_DIR/routeros_guide.txt" << EOL
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
echo -e "${CYAN}===== RouterOS 配置命令与方式 =====${PLAIN}"
echo
echo -e "${YELLOW}/ip dns set servers=$MIHOMO_IP${PLAIN}"
echo -e "${YELLOW}/ip route add dst-address=198.18.0.0/16 gateway=$MIHOMO_IP comment=\"mihomo fake-ip route\"${PLAIN}"
echo
echo -e "【方法一】WebFig界面: IP→DNS→设置服务器为${YELLOW}$MIHOMO_IP${PLAIN}，添加路由${YELLOW}198.18.0.0/16${PLAIN}到${YELLOW}$MIHOMO_IP${PLAIN}"
echo -e "【方法二】WinBox工具: 同上述图形操作"
echo -e "【方法三】Terminal命令: 复制粘贴上方命令执行"
echo
echo -e "${CYAN}===== 其他路由器配置 =====${PLAIN}"
echo
echo -e "1. OpenWrt: DNS设置为${YELLOW}$MIHOMO_IP${PLAIN}，添加静态路由${YELLOW}198.18.0.0/16${PLAIN}到${YELLOW}$MIHOMO_IP${PLAIN}"
echo -e "2. 爱快(iKuai): DNS设置为${YELLOW}$MIHOMO_IP${PLAIN}，添加静态路由${YELLOW}198.18.0.0/16${PLAIN}到${YELLOW}$MIHOMO_IP${PLAIN}"
echo -e "3. 普通路由器: 设置DNS为${YELLOW}$MIHOMO_IP${PLAIN}，支持静态路由则添加${YELLOW}198.18.0.0/16${PLAIN}到${YELLOW}$MIHOMO_IP${PLAIN}"
echo
