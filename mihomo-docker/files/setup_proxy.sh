#!/bin/bash
#############################################################
# Mihomo 代理机配置脚本 (精简版)
# 不安装Docker但检查Docker状态，优先host网络，其次桥接
#############################################################

# 设置颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 配置信息
SCRIPT_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
FILES_DIR="$SCRIPT_DIR/files"
CONF_DIR="/etc/mihomo"
CONFIG_URL="https://route.luxxk.dpdns.org/raw.githubusercontent.com/tyy840913/mihomo-proxy/refs/heads/master/mihomo-docker/files/config.yaml"

# 错误处理函数
handle_error() {
    local error_msg=$1
    echo -e "${RED}$error_msg${PLAIN}"
    exit 1
}

# 检查操作系统
check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION_ID=$VERSION_ID
    else
        handle_error "无法检测操作系统"
    fi
    
    if [[ $OS != "debian" && $OS != "ubuntu" ]]; then
        handle_error "此脚本只支持 Debian 或 Ubuntu 系统"
    fi
    
    echo -e "${GREEN}检测到系统: $OS $VERSION_ID${PLAIN}"
}

# 检查并安装基础工具（精简版）
install_essential_tools() {
    echo -e "${CYAN}检查基础工具...${PLAIN}"
    
    if ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}安装curl...${PLAIN}"
        apt-get update && apt-get install -y curl || echo -e "${YELLOW}curl安装失败，继续尝试...${PLAIN}"
    fi
    
    if ! command -v wget &> /dev/null; then
        echo -e "${YELLOW}安装wget...${PLAIN}"
        apt-get install -y wget || echo -e "${YELLOW}wget安装失败，继续尝试...${PLAIN}"
    fi
}

# 检查Docker是否已安装
check_docker() {
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}Docker已安装: $(docker --version)${PLAIN}"
        return 0
    else
        echo -e "${RED}未检测到Docker，请先安装Docker${PLAIN}"
        echo -e "${YELLOW}可以参考以下命令安装Docker:${PLAIN}"
        echo -e "${CYAN}curl -fsSL https://get.docker.com | sh${PLAIN}"
        return 1
    fi
}

# 创建配置目录
create_config_dir() {
    echo -e "${CYAN}正在创建配置目录...${PLAIN}"
    
    mkdir -p "$CONF_DIR" || handle_error "错误: 配置目录创建失败"
    mkdir -p "$CONF_DIR/ruleset" || echo -e "${YELLOW}警告: 规则文件目录创建失败${PLAIN}"
    
    echo -e "${GREEN}配置目录和规则文件目录已创建${PLAIN}"
}

# 下载配置文件
download_config_file() {
    echo -e "${CYAN}正在检查配置文件...${PLAIN}"
    
    if [[ -f "$CONF_DIR/config.yaml" ]]; then
        echo -e "${YELLOW}配置文件已存在: $CONF_DIR/config.yaml${PLAIN}"
        echo -e "${YELLOW}跳过配置文件下载，保留现有配置${PLAIN}"
        return
    fi

    echo -e "${CYAN}从远程下载配置文件...${PLAIN}"
    if ! wget --timeout=30 --tries=3 -O "$CONF_DIR/config.yaml" "$CONFIG_URL"; then
        handle_error "错误: 配置文件下载失败"
    fi
    
    chmod 644 "$CONF_DIR/config.yaml"
    echo -e "${GREEN}配置文件已下载到 $CONF_DIR/config.yaml${PLAIN}"
}

# 下载UI界面
download_ui() {
    echo -e "${CYAN}正在设置UI界面...${PLAIN}"
    mkdir -p "$CONF_DIR/ui"
    
    if [[ -f "$CONF_DIR/ui/index.html" ]]; then
        echo -e "${YELLOW}UI文件已存在，跳过下载${PLAIN}"
        return
    fi

    if ! command -v wget &> /dev/null; then
        echo -e "${YELLOW}未安装wget，跳过UI下载${PLAIN}"
        return
    fi

    local tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || return
    
    if wget --timeout=30 --tries=3 https://route.luxxk.dpdns.org/github.com/MetaCubeX/metacubexd/releases/download/v1.187.1/compressed-dist.tgz; then
        tar -xzf compressed-dist.tgz -C "$CONF_DIR/ui"
        echo -e "${GREEN}UI界面已设置${PLAIN}"
    else
        echo -e "${RED}警告: UI包下载失败，将使用无UI模式${PLAIN}"
    fi
    
    cd - > /dev/null || return
    rm -rf "$tmp_dir"
}

# 下载GeoIP数据库
download_geoip() {
    echo -e "${CYAN}正在预下载GeoIP数据库...${PLAIN}"
    
    if [[ -f "$CONF_DIR/Country.mmdb" ]]; then
        echo -e "${YELLOW}GeoIP数据库已存在，跳过下载${PLAIN}"
        return
    fi

    local geoip_sources=(
        "https://route.woskee.dpdns.org/github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb"
        "https://route.woskee.dpdns.org/github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb"
        "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb"
    )
    
    for source in "${geoip_sources[@]}"; do
        echo -e "${CYAN}尝试从 $source 下载...${PLAIN}"
        if wget --timeout=60 --tries=2 -O "$CONF_DIR/Country.mmdb" "$source"; then
            echo -e "${GREEN}✓ GeoIP数据库下载成功${PLAIN}"
            return
        else
            echo -e "${YELLOW}⚠ 从 $source 下载失败，尝试下一个源...${PLAIN}"
            rm -f "$CONF_DIR/Country.mmdb" 2>/dev/null
        fi
    done
    
    echo -e "${YELLOW}⚠ 所有GeoIP下载源都失败，容器启动时将自动下载${PLAIN}"
}

# 启动Mihomo容器（优先host网络，失败则尝试桥接）
start_mihomo_container() {
    echo -e "${CYAN}正在启动Mihomo容器...${PLAIN}"
    
    # 停止并删除已存在的容器
    docker stop mihomo 2>/dev/null
    docker rm mihomo 2>/dev/null
    
    local host_ip=$(hostname -I | awk '{print $1}')
    local container_started=0
    local access_url=""
    
    # 优先尝试host网络模式
    echo -e "${CYAN}尝试使用host网络模式启动容器...${PLAIN}"
    echo -e "${YELLOW}• 网络: host${PLAIN}"
    echo -e "${YELLOW}• 主机IP: $host_ip${PLAIN}"
    
    if docker run -d \
        --name=mihomo \
        --restart=unless-stopped \
        --network=host \
        -v "$CONF_DIR:/root/.config/mihomo" \
        metacubex/mihomo:latest >/dev/null 2>&1; then
        
        sleep 5
        if docker ps --filter "name=mihomo" --format "{{.Status}}" | grep -q "Up"; then
            container_started=1
            access_url="http://$host_ip:9090/ui"
            echo -e "${GREEN}✓ host网络启动成功${PLAIN}"
        fi
    fi
    
    # 如果host模式失败，尝试桥接模式
    if [[ $container_started -eq 0 ]]; then
        echo -e "${YELLOW}host网络启动失败，尝试桥接模式...${PLAIN}"
        
        if docker run -d \
            --name=mihomo \
            --restart=unless-stopped \
            -p 7890:7890 \
            -p 7891:7891 \
            -p 7892:7892 \
            -p 9090:9090 \
            -v "$CONF_DIR:/root/.config/mihomo" \
            metacubex/mihomo:latest >/dev/null 2>&1; then
            
            sleep 5
            if docker ps --filter "name=mihomo" --format "{{.Status}}" | grep -q "Up"; then
                container_started=1
                access_url="http://$host_ip:9090/ui"
                echo -e "${GREEN}✓ 桥接模式启动成功${PLAIN}"
            fi
        fi
    fi
    
    # 检查最终结果
    if [[ $container_started -eq 1 ]]; then
        echo -e "${GREEN}✓ Mihomo容器启动成功${PLAIN}"
        sleep 3
        
        local container_status=$(docker ps --filter "name=mihomo" --format "{{.Status}}")
        if [[ -n "$container_status" && "$container_status" == *"Up"* ]]; then
            echo -e "${GREEN}✓ 服务运行正常${PLAIN}"
            echo -e "${GREEN}✓ 控制面板: $access_url${PLAIN}"
            echo -e "${GREEN}✓ HTTP代理: $host_ip:7891${PLAIN}"
            echo -e "${GREEN}✓ SOCKS代理: $host_ip:7892${PLAIN}"
            echo -e "${GREEN}✓ 混合代理: $host_ip:7890${PLAIN}"
        else
            echo -e "${YELLOW}⚠ 容器状态异常，请检查日志${PLAIN}"
            docker logs mihomo --tail 10 2>/dev/null
        fi
    else
        echo -e "${RED}✗ 容器启动失败${PLAIN}"
        echo -e "${YELLOW}正在显示错误日志...${PLAIN}"
        docker logs mihomo --tail 20 2>/dev/null
        
        echo -e "${YELLOW}可能的解决方案:${PLAIN}"
        echo -e "${YELLOW}1. 检查配置文件: nano /etc/mihomo/config.yaml${PLAIN}"
        echo -e "${YELLOW}2. 检查Docker是否正常运行: systemctl status docker${PLAIN}"
        echo -e "${YELLOW}3. 查看完整日志: docker logs mihomo${PLAIN}"
    fi
}

# 重启Mihomo服务
restart_mihomo() {
    echo -e "${CYAN}正在重启Mihomo服务...${PLAIN}"
    start_mihomo_container
    echo -e "${GREEN}Mihomo服务重启完成！${PLAIN}"
}

# 重置Mihomo配置
reset_config() {
    echo -e "${CYAN}正在重置Mihomo配置...${PLAIN}"
    
    echo -e "${CYAN}正在删除当前配置文件...${PLAIN}"
    rm -f "/etc/mihomo/config.yaml" 2>/dev/null
    
    download_config_file
    start_mihomo_container
    
    echo -e "${GREEN}配置重置完成！${PLAIN}"
}

# 主函数
main() {
    local mode="${1:-install}"  # 默认为install模式
    
    case "$mode" in
        "restart")
            restart_mihomo
            return 0
            ;;
        "reset")
            reset_config
            return 0
            ;;
        *)
            ;;
    esac
    
    # 系统信息显示
    local arch=$(uname -m)
    echo -e "${CYAN}系统架构: $arch${PLAIN}"

    # 检查操作系统
    check_os
    
    # 安装基础工具
    install_essential_tools
    
    # 检查Docker但不安装
    if ! check_docker; then
        handle_error "请先安装Docker后再运行此脚本"
    fi
    
    # 创建配置目录
    create_config_dir
    
    # 下载配置文件
    download_config_file
    
    # 下载UI
    download_ui
    
    # 下载GeoIP
    download_geoip
    
    # 启动容器
    start_mihomo_container
    
    # 显示完成信息
    local host_ip=$(hostname -I | awk '{print $1}')
    echo -e "\n${GREEN}======================================================${PLAIN}"
    echo -e "${GREEN}代理机配置完成！${PLAIN}"
    echo -e "${GREEN}控制面板地址: http://${host_ip}:9090/ui${PLAIN}"
    echo -e "${GREEN}======================================================${PLAIN}"
}

# 执行主函数，传递命令行参数
main "$@"
