#!/bin/bash

# 检查并安装jq
check_and_install_jq() {
    if ! command -v jq &> /dev/null; then
        echo "正在安装jq..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y jq
        elif command -v yum &> /dev/null; then
            yum install -y jq
        elif command -v dnf &> /dev/null; then
            dnf install -y jq
        elif command -v apk &> /dev/null; then
            apk add jq
        else
            echo "错误: 无法安装jq，请手动安装后再运行此脚本"
            exit 1
        fi
    fi
}

# 检查并创建macvlan网络
setup_macvlan_network() {
    local main_interface=$1
    local macvlan_interface=$2
    
    echo "正在检查Docker macvlan网络..."
    if ! docker network ls | grep -q "mnet"; then
        echo "创建Docker macvlan网络..."
        docker network create -d macvlan \
            --subnet=$(ip -o -4 addr show dev $main_interface | awk '{print $4}' | cut -d/ -f1 | head -n1 | cut -d. -f1-3).0/24 \
            --gateway=$(ip route | grep default | awk '{print $3}') \
            -o parent=$main_interface mnet
    else
        echo "Docker macvlan网络 'mnet' 已存在，跳过创建步骤"
    fi
    
    echo "正在检查主机macvlan接口..."
    if ! ip link show $macvlan_interface &>/dev/null; then
        echo "正在创建主机macvlan接口..."
        # 获取主接口的MAC地址
        local mac_address=$(ip link show $main_interface | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n1)
        if [ -z "$mac_address" ]; then
            echo "警告: 无法获取MAC地址，使用随机MAC地址"
            mac_address="02:00:00:$(openssl rand -hex 3 | sed 's/\(..\)/\1:/g; s/.$//')"
        fi
        
        # 创建macvlan接口
        ip link add $macvlan_interface link $main_interface type macvlan mode bridge
        if [ $? -eq 0 ]; then
            ip link set dev $macvlan_interface address $mac_address
            ip link set $macvlan_interface up
            echo "主机macvlan接口创建成功"
        else
            echo "警告: 主机macvlan接口创建失败，将尝试继续"
        fi
    else
        echo "主机macvlan接口已存在"
    fi
    
    echo "正在设置主接口为混杂模式..."
    ip link set $main_interface promisc on
    
    # 创建持久化服务
    echo "正在创建混杂模式持久化服务..."
    cat > /etc/systemd/system/promisc.service << EOF
[Unit]
Description=Enable promiscuous mode for $main_interface
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/ip link set $main_interface promisc on
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable promisc.service
    systemctl start promisc.service
}

# 主函数
main() {
    # 检查jq
    check_and_install_jq
    
    # 获取主网络接口
    local main_interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    local macvlan_interface="mihomo_veth"
    
    # 设置macvlan网络
    setup_macvlan_network $main_interface $macvlan_interface
    
    # 检查网络配置状态
    echo "检查网络配置状态..."
    if ! ip link show $main_interface | grep -q "PROMISC"; then
        echo "警告: 主接口混杂模式可能未生效"
    fi
    
    if ! ip link show $macvlan_interface &>/dev/null; then
        echo "警告: macvlan接口未找到"
    fi
    
    # 创建配置目录
    echo "正在创建配置目录..."
    mkdir -p /etc/mihomo
    echo "配置目录已创建"
    
    # 复制配置文件
    echo "正在复制配置文件..."
    if [ -f "/root/files/config.yaml" ]; then
        echo "找到配置文件: /root/files/config.yaml"
        cp /root/files/config.yaml /etc/mihomo/config.yaml
        echo "配置文件已复制到 /etc/mihomo/config.yaml"
    else
        echo "错误: 未找到配置文件"
        exit 1
    fi
    
    # 设置UI界面
    echo "正在设置UI界面..."
    echo "正在下载最新版metacubexd界面..."
    wget -q https://github.com/MetaCubeX/metacubexd/releases/download/v1.187.1/compressed-dist.tgz
    tar xzf compressed-dist.tgz -C /etc/mihomo/
    rm compressed-dist.tgz
    echo "UI界面已设置"
    
    echo "配置设置完成"
    echo "如需修改配置，请使用文本编辑器编辑 /etc/mihomo/config.yaml 文件"
    echo "建议使用第三方工具修改yaml配置文件，确保格式正确"
    
    # 启动Mihomo容器
    echo "正在启动Mihomo容器..."
    docker run -d --name mihomo \
        --network mnet \
        --ip $(jq -r '.mihomo_ip' /root/files/mihomo_state.json) \
        -v /etc/mihomo:/root/.config/mihomo \
        -p 9090:9090 \
        -p 7890:7890 \
        -p 7891:7891 \
        -p 7892:7892 \
        --restart unless-stopped \
        metacubexd/mihomo:latest
    
    if [ $? -eq 0 ]; then
        echo "Mihomo容器已启动"
    else
        echo "错误: Mihomo容器启动失败"
        exit 1
    fi
}

# 执行主函数
main 