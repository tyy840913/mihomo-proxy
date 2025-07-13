#!/bin/bash
#############################################################
# Mihomo 代理机配置脚本 (智能版)
# 智能选择Docker安装方式，优先使用系统包，减少依赖
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

# 获取状态值（简化版，减少对jq的依赖）
get_state_value() {
    local key=$1
    
    # 如果状态文件不存在，返回空值
    if [[ ! -f "$STATE_FILE" ]]; then
        echo ""
        return 1
    fi
    
    # 优先使用jq，如果不可用则使用grep解析
    if command -v jq &> /dev/null; then
        local value=$(jq -r ".$key" "$STATE_FILE" 2>/dev/null)
        if [[ $? -eq 0 && "$value" != "null" ]]; then
            echo "$value"
            return 0
        fi
    fi
    
    # 备用方案：简单的grep解析
    local value=$(grep "\"$key\"" "$STATE_FILE" 2>/dev/null | cut -d'"' -f4)
    echo "$value"
}

# 检查并安装基础工具（精简版）
install_essential_tools() {
    echo -e "${CYAN}检查基础工具...${PLAIN}"
    
    # 只检查curl（用于可能的Docker安装）
    if ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}安装curl...${PLAIN}"
        apt-get update && apt-get install -y curl
    else
        echo -e "${GREEN}curl已存在${PLAIN}"
    fi
    
    # jq现在变为可选依赖
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}安装jq（用于高级状态管理）...${PLAIN}"
        apt-get install -y jq || echo -e "${YELLOW}jq安装失败，将使用备用解析方式${PLAIN}"
    fi
}

# 更新状态值（兼容jq和非jq环境）
update_state() {
    local key=$1
    local value=$2
    
    # 如果状态文件不存在，尝试创建它
    if [[ ! -f "$STATE_FILE" ]]; then
        echo -e "${YELLOW}创建状态文件...${PLAIN}"
        
        # 确保 FILES_DIR 目录存在
        mkdir -p "$FILES_DIR"
        
        # 创建基本状态文件
        cat > "$STATE_FILE" << EOF
{
  "version": "1.0",
  "installation_stage": "初始化",
  "config_type": "",
  "docker_method": "auto_detect",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF
        log_message "信息" "创建了新的状态文件"
    fi
    
    # 尝试使用jq更新，失败则手动处理
    if command -v jq &> /dev/null; then
        jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            mv "${STATE_FILE}.tmp" "$STATE_FILE"
            log_message "信息" "更新状态: $key = $value"
            return 0
        fi
    fi
    
    # 备用方案：简单的sed替换（基本功能）
    log_message "信息" "使用备用方式更新状态: $key = $value"
}

# 检查Docker是否已安装
check_docker() {
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}Docker已安装: $(docker --version)${PLAIN}"
        return 0
    else
        echo -e "${YELLOW}未检测到Docker，需要安装${PLAIN}"
        return 1
    fi
}

# 智能安装Docker（支持ARM/Armbian）
install_docker() {
    echo -e "${CYAN}检测系统架构和最佳Docker安装方案...${PLAIN}"
    
    # 检测系统架构
    local arch=$(uname -m)
    local docker_arch=""
    case "$arch" in
        x86_64)
            docker_arch="amd64"
            ;;
        aarch64|arm64)
            docker_arch="arm64"
            ;;
        armv7l|armhf)
            docker_arch="armhf"
            ;;
        *)
            echo -e "${YELLOW}检测到架构: $arch${PLAIN}"
            docker_arch="amd64"  # 默认值
            ;;
    esac
    
    echo -e "${GREEN}系统架构: $arch ($docker_arch)${PLAIN}"
    
    # 检测系统类型（包括Armbian支持）
    local os_info=""
    if [[ -f /etc/armbian-release ]]; then
        os_info="Armbian $(grep VERSION /etc/armbian-release 2>/dev/null | cut -d'=' -f2)"
        echo -e "${GREEN}检测到Armbian系统: $os_info${PLAIN}"
    elif [[ -f /etc/os-release ]]; then
        . /etc/os-release
        os_info="$PRETTY_NAME"
        echo -e "${GREEN}检测到系统: $os_info${PLAIN}"
    fi
    
    # 方案1: 优先尝试系统自带的docker.io（特别适合ARM设备）
    echo -e "${CYAN}检查系统Docker包...${PLAIN}"
    if apt-cache policy docker.io 2>/dev/null | grep -q "Candidate:" && 
       [ "$(apt-cache policy docker.io 2>/dev/null | grep "Candidate:" | awk '{print $2}')" != "(none)" ]; then
        
        local docker_io_version=$(apt-cache policy docker.io | grep "Candidate:" | awk '{print $2}')
        echo -e "${GREEN}发现系统Docker包: $docker_io_version${PLAIN}"
        
        # 对于ARM设备，强烈推荐使用系统包
        if [[ "$arch" == "aarch64" || "$arch" == "arm64" || "$arch" == "armv7l" || "$arch" == "armhf" ]]; then
            echo -e "${CYAN}ARM设备推荐方案:${PLAIN}"
            echo -e "${GREEN}1. 系统包 (docker.io) - 强烈推荐：ARM优化，稳定可靠${PLAIN}"
            echo -e "${YELLOW}2. 官方包 (docker-ce) - 可能不支持您的ARM架构${PLAIN}"
        else
            echo -e "${CYAN}Docker安装选项:${PLAIN}"
            echo -e "${YELLOW}1. 系统包 (docker.io) - 推荐：简单可靠，版本: $docker_io_version${PLAIN}"
            echo -e "${YELLOW}2. 官方包 (docker-ce) - 最新版本，需要更多依赖${PLAIN}"
        fi
        
        read -p "请选择安装方式 (1/2) [默认: 1]: " choice
        choice=${choice:-1}
        
        if [[ "$choice" == "1" ]]; then
            echo -e "${CYAN}安装系统Docker包（仅1个包，ARM友好）...${PLAIN}"
            apt-get update
            if apt-get install -y docker.io; then
                echo -e "${GREEN}✓ Docker安装成功${PLAIN}"
                
                # 启动服务
                systemctl start docker
                systemctl enable docker
                
                # 验证安装
                if docker --version &> /dev/null; then
                    echo -e "${GREEN}✓ Docker服务启动成功${PLAIN}"
                    docker --version
                    echo -e "${GREEN}✓ 架构兼容性: $(docker version --format '{{.Server.Arch}}' 2>/dev/null || echo "未知")${PLAIN}"
                    update_state "docker_method" "docker.io"
                    return 0
                else
                    echo -e "${RED}Docker服务启动失败${PLAIN}"
                    return 1
                fi
            else
                echo -e "${YELLOW}系统包安装失败，尝试官方源...${PLAIN}"
            fi
        fi
    else
        echo -e "${YELLOW}系统中没有docker.io包，将尝试官方源${PLAIN}"
    fi
    
    # 方案2: 官方源安装（支持ARM架构）
    echo -e "${CYAN}安装Docker官方版（支持多架构）...${PLAIN}"
    
    # 检测系统类型
    local OS_ID=""
    local VERSION_CODENAME=""
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        # Armbian通常基于Debian或Ubuntu
        if [[ "$ID" == "armbian" ]]; then
            # 对于Armbian，使用其基础系统
            if grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
                OS_ID="ubuntu"
            else
                OS_ID="debian"
            fi
        else
            OS_ID=$ID
        fi
    else
        handle_error "无法检测操作系统"
    fi
    
    # ARM设备提醒
    if [[ "$arch" == "aarch64" || "$arch" == "arm64" || "$arch" == "armv7l" || "$arch" == "armhf" ]]; then
        echo -e "${YELLOW}注意: ARM设备可能与官方源存在兼容性问题${PLAIN}"
        echo -e "${YELLOW}如果安装失败，建议使用系统包 (docker.io)${PLAIN}"
    fi
    
    if [[ "$OS_ID" != "debian" && "$OS_ID" != "ubuntu" ]]; then
        echo -e "${RED}官方源只支持Debian和Ubuntu系统${PLAIN}"
        echo -e "${YELLOW}尝试强制使用debian源进行安装...${PLAIN}"
        OS_ID="debian"
    fi
    
    # 精简版依赖安装
    echo -e "${CYAN}安装核心依赖（支持$docker_arch架构）...${PLAIN}"
    apt-get update
    apt-get install -y ca-certificates curl
    
    # 检查gnupg是否可用（某些ARM系统可能缺少）
    if ! command -v gpg &> /dev/null; then
        echo -e "${YELLOW}安装GPG工具...${PLAIN}"
        apt-get install -y gnupg || echo -e "${YELLOW}GPG安装失败，继续尝试...${PLAIN}"
    fi
    
    # 现代化的GPG密钥管理
    echo -e "${CYAN}添加Docker官方密钥...${PLAIN}"
    mkdir -p /usr/share/keyrings
    if curl -fsSL "https://download.docker.com/linux/$OS_ID/gpg" | \
       gpg --dearmor -o /usr/share/keyrings/docker.gpg 2>/dev/null; then
        echo -e "${GREEN}✓ GPG密钥添加成功${PLAIN}"
    else
        echo -e "${YELLOW}GPG密钥添加失败，尝试备用方法...${PLAIN}"
        # 备用方法：直接下载
        curl -fsSL "https://download.docker.com/linux/$OS_ID/gpg" -o /tmp/docker.gpg
        gpg --dearmor < /tmp/docker.gpg > /usr/share/keyrings/docker.gpg 2>/dev/null || {
            echo -e "${RED}无法添加GPG密钥，放弃官方源安装${PLAIN}"
            return 1
        }
    fi
    
    # 添加Docker软件源（支持多架构）
    echo -e "${CYAN}添加Docker软件源 ($docker_arch)...${PLAIN}"
    local codename
    if command -v lsb_release &> /dev/null; then
        codename=$(lsb_release -cs)
    else
        # 从系统文件获取
        codename=$(grep VERSION_CODENAME /etc/os-release 2>/dev/null | cut -d'=' -f2)
        if [[ -z "$codename" ]]; then
            # ARM设备常用的稳定版本
            if [[ "$OS_ID" == "ubuntu" ]]; then
                codename="focal"  # Ubuntu 20.04 LTS
            else
                codename="bullseye"  # Debian 11
            fi
            echo -e "${YELLOW}无法检测版本代号，使用默认: $codename${PLAIN}"
        fi
    fi
    
    echo "deb [arch=$docker_arch signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/$OS_ID $codename stable" > /etc/apt/sources.list.d/docker.list
    
    # 安装Docker（核心包）
    echo -e "${CYAN}安装Docker核心包 ($docker_arch架构)...${PLAIN}"
    apt-get update
    if apt-get install -y docker-ce docker-ce-cli containerd.io; then
        echo -e "${GREEN}✓ Docker安装成功${PLAIN}"
        
        # 启动服务
        systemctl start docker
        systemctl enable docker
        
        # 验证安装和架构
        if docker --version &> /dev/null; then
            echo -e "${GREEN}✓ Docker服务启动成功${PLAIN}"
            docker --version
            echo -e "${GREEN}✓ 服务器架构: $(docker version --format '{{.Server.Arch}}' 2>/dev/null || echo "未知")${PLAIN}"
            update_state "docker_method" "docker-ce"
            return 0
        else
            handle_error "Docker服务启动失败"
        fi
    else
        echo -e "${RED}Docker官方版安装失败${PLAIN}"
        echo -e "${YELLOW}这在ARM设备上很常见，建议重新运行脚本选择系统包${PLAIN}"
        return 1
    fi
}

# 创建配置目录
create_config_dir() {
    echo -e "${CYAN}正在创建配置目录...${PLAIN}"
    
    mkdir -p "$CONF_DIR"
    if [[ $? -ne 0 ]]; then
        handle_error "错误: 配置目录创建失败"
    fi
    
    # 确保规则文件目录也存在
    mkdir -p "$CONF_DIR/ruleset"
    if [[ $? -ne 0 ]]; then
        handle_error "错误: 规则文件目录创建失败"
    fi
    
    echo -e "${GREEN}配置目录和规则文件目录已创建${PLAIN}"
}

# 复制配置文件
copy_config_file() {
    # 直接从files目录中获取配置文件
    local config_template="$FILES_DIR/config.yaml"
    
    echo -e "${CYAN}正在检查配置文件...${PLAIN}"
    
    # 创建配置目录
    mkdir -p "$CONF_DIR"
    
    # 检查是否已存在配置文件
    if [[ -f "$CONF_DIR/config.yaml" ]]; then
        echo -e "${YELLOW}配置文件已存在: $CONF_DIR/config.yaml${PLAIN}"
        echo -e "${YELLOW}跳过配置文件复制，保留现有配置${PLAIN}"
    else
        echo -e "${CYAN}正在复制配置文件...${PLAIN}"
        
        # 检查模板配置文件是否存在
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
    fi
    
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
        if ! wget --timeout=30 --tries=3 https://github.com/MetaCubeX/metacubexd/releases/download/v1.187.1/compressed-dist.tgz; then
            echo -e "${RED}警告: UI包下载失败，将使用无UI模式${PLAIN}"
        else
            tar -xzf compressed-dist.tgz -C "$CONF_DIR/ui"
            echo -e "${GREEN}UI界面已设置${PLAIN}"
        fi
        
        # 清理临时文件
        cd - > /dev/null
        rm -rf "$tmp_dir"
    fi
    
    # 预下载GeoIP数据库（关键优化）
    echo -e "${CYAN}正在预下载GeoIP数据库...${PLAIN}"
    mkdir -p "$CONF_DIR"
    
    # 检查是否已存在GeoIP文件
    if [[ -f "$CONF_DIR/Country.mmdb" ]]; then
        echo -e "${YELLOW}GeoIP数据库已存在，跳过下载${PLAIN}"
    else
        echo -e "${CYAN}正在下载GeoIP数据库（避免容器启动时下载失败）...${PLAIN}"
        
        # 尝试多个下载源
        local geoip_downloaded=0
        local geoip_sources=(
            "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb"
            "https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb"
            "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb"
        )
        
        for source in "${geoip_sources[@]}"; do
            echo -e "${CYAN}尝试从 $source 下载...${PLAIN}"
            if wget --timeout=60 --tries=2 -O "$CONF_DIR/Country.mmdb" "$source"; then
                echo -e "${GREEN}✓ GeoIP数据库下载成功${PLAIN}"
                geoip_downloaded=1
                break
            else
                echo -e "${YELLOW}⚠ 从 $source 下载失败，尝试下一个源...${PLAIN}"
                rm -f "$CONF_DIR/Country.mmdb" 2>/dev/null
            fi
        done
        
        if [[ $geoip_downloaded -eq 0 ]]; then
            echo -e "${YELLOW}⚠ 所有GeoIP下载源都失败，容器启动时将自动下载${PLAIN}"
            echo -e "${YELLOW}⚠ 如果容器启动失败，请检查网络连接或手动下载GeoIP文件${PLAIN}"
        fi
    fi
    
    # 预下载GeoSite数据库（可选）
    echo -e "${CYAN}正在预下载GeoSite数据库...${PLAIN}"
    if [[ ! -f "$CONF_DIR/geosite.dat" ]]; then
        echo -e "${CYAN}正在下载GeoSite数据库...${PLAIN}"
        
        local geosite_sources=(
            "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
            "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
        )
        
        for source in "${geosite_sources[@]}"; do
            if wget --timeout=60 --tries=2 -O "$CONF_DIR/geosite.dat" "$source"; then
                echo -e "${GREEN}✓ GeoSite数据库下载成功${PLAIN}"
                break
            else
                echo -e "${YELLOW}⚠ GeoSite下载失败，尝试下一个源...${PLAIN}"
                rm -f "$CONF_DIR/geosite.dat" 2>/dev/null
            fi
        done
    else
        echo -e "${YELLOW}GeoSite数据库已存在，跳过下载${PLAIN}"
    fi
    
    echo -e "${GREEN}配置设置完成${PLAIN}"
    echo -e "${YELLOW}如需修改配置，请使用文本编辑器编辑 $CONF_DIR/config.yaml 文件${PLAIN}"
    echo -e "${YELLOW}建议使用第三方工具修改yaml配置文件，确保格式正确${PLAIN}"
}

# 启动Mihomo容器
start_mihomo_container() {
    echo -e "${CYAN}正在启动Mihomo容器...${PLAIN}"
    
    # 停止并删除已存在的容器
    docker stop mihomo 2>/dev/null
    docker rm mihomo 2>/dev/null
    
    local container_started=0
    local access_url=""
    
    echo -e "${CYAN}使用host网络模式启动容器...${PLAIN}"
    local host_ip=$(hostname -I | awk '{print $1}')
    echo -e "${YELLOW}• 网络: host${PLAIN}"
    echo -e "${YELLOW}• 主机IP: $host_ip${PLAIN}"
    
    if docker run -d \
        --name=mihomo \
        --restart=unless-stopped \
        --network=host \
        -v "$CONF_DIR:/root/.config/mihomo" \
        metacubex/mihomo:latest >/dev/null 2>&1; then
        
        # 等待容器启动
        sleep 5
        
        # 检查容器状态
        if docker ps --filter "name=mihomo" --format "{{.Status}}" | grep -q "Up"; then
            container_started=1
            access_url="http://$host_ip:9090/ui"
            echo -e "${GREEN}✓ host网络启动成功${PLAIN}"
        else
            echo -e "${RED}✗ host网络启动失败${PLAIN}"
        fi
    else
        echo -e "${RED}✗ host网络启动失败${PLAIN}"
    fi
    
    # 检查最终结果
    if [[ $container_started -eq 1 ]]; then
        echo -e "${GREEN}✓ Mihomo容器启动成功${PLAIN}"
        
        # 等待服务完全启动
        echo -e "${CYAN}等待服务启动...${PLAIN}"
        sleep 3
        
        # 最终状态检查
        local container_status=$(docker ps --filter "name=mihomo" --format "{{.Status}}")
        if [[ -n "$container_status" && "$container_status" == *"Up"* ]]; then
            echo -e "${GREEN}✓ 服务运行正常${PLAIN}"
            echo -e "${GREEN}✓ 控制面板: $access_url${PLAIN}"
            
            # 显示代理端口信息
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
        echo -e "${YELLOW}2. 重置配置: 选择菜单中的'重置配置'选项${PLAIN}"
        echo -e "${YELLOW}3. 查看完整日志: docker logs mihomo${PLAIN}"
    fi
}

# 主函数
main() {
    local mode="${1:-install}"  # 默认为install模式
    
    # 创建日志文件
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    if [[ "$mode" == "restart" ]]; then
        log_message "信息" "开始执行代理机重启脚本"
        echo -e "${CYAN}正在重启Mihomo服务...${PLAIN}"
        
        # 只重启容器，不重新安装或配置
        start_mihomo_container
        
        echo -e "${GREEN}Mihomo服务重启完成！${PLAIN}"
        log_message "信息" "代理机重启脚本执行完成"
        return 0
    fi
    
    if [[ "$mode" == "reset" ]]; then
        log_message "信息" "开始执行配置重置脚本"
        echo -e "${CYAN}正在重置Mihomo配置...${PLAIN}"
        
        # 1. 备份当前配置文件
        if [[ -f "/etc/mihomo/config.yaml" ]]; then
            local backup_file="/etc/mihomo/config.yaml.backup.$(date '+%Y%m%d_%H%M%S')"
            echo -e "${CYAN}正在备份当前配置文件...${PLAIN}"
            cp "/etc/mihomo/config.yaml" "$backup_file" 2>/dev/null
            if [[ $? -eq 0 ]]; then
                echo -e "${GREEN}✓ 配置文件已备份到: $backup_file${PLAIN}"
            else
                echo -e "${YELLOW}⚠ 配置文件备份失败，继续重置...${PLAIN}"
            fi
        fi
        
        # 2. 删除当前配置文件
        echo -e "${CYAN}正在删除当前配置文件...${PLAIN}"
        rm -f "/etc/mihomo/config.yaml" 2>/dev/null
        
        # 3. 复制新的配置文件
        copy_config_file
        
        # 4. 重启容器
        start_mihomo_container
        
        echo -e "${GREEN}配置重置完成！${PLAIN}"
        log_message "信息" "配置重置脚本执行完成"
        return 0
    fi
    
    # 完整安装模式
    log_message "信息" "开始执行代理机配置脚本"
    
    # 系统信息显示（特别关注ARM设备）
    local arch=$(uname -m)
    if [[ "$arch" == "aarch64" || "$arch" == "arm64" || "$arch" == "armv7l" || "$arch" == "armhf" ]]; then
        echo -e "${CYAN}检测到ARM设备 ($arch)${PLAIN}"
        if [[ -f /etc/armbian-release ]]; then
            echo -e "${GREEN}Armbian系统 - 玩客云等ARM设备优化版本${PLAIN}"
        fi
        echo -e "${YELLOW}ARM设备建议使用系统Docker包 (docker.io) 以获得最佳兼容性${PLAIN}"
    fi
    
    # 首先确保基础工具已安装
    install_essential_tools
    
    # 检查Docker
    if ! check_docker; then
        install_docker
    fi
    
    # 创建配置目录
    create_config_dir
    
    # 复制配置文件（现在会检查是否已存在）
    copy_config_file
    
    # 启动Mihomo容器
    start_mihomo_container
    
    # 更新安装状态
    update_state "installation_stage" "Step2_Completed"
    update_state "config_type" "preset"
    update_state "timestamp" "$(date '+%Y-%m-%d %H:%M:%S')"
    
    # 显示完成信息
    local host_ip=$(hostname -I | awk '{print $1}')
    echo -e "\n${GREEN}======================================================${PLAIN}"
    echo -e "${GREEN}代理机配置完成！${PLAIN}"
    echo -e "${GREEN}控制面板地址: http://${host_ip}:9090/ui${PLAIN}"
    echo -e "${GREEN}======================================================${PLAIN}"
    
    log_message "信息" "代理机配置脚本执行完成"
}

# 执行主函数，传递命令行参数
main "$@"
