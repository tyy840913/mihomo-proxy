#!/bin/bash

echo "=== Mihomo 修复测试脚本 ==="

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
        
        # 验证安装
        if command -v jq &> /dev/null; then
            echo "✓ jq安装成功"
        else
            echo "✗ jq安装失败"
            exit 1
        fi
    else
        echo "✓ jq已安装"
    fi
}

# 测试网络接口检测
test_network_detection() {
    echo "=== 测试网络接口检测 ==="
    
    local main_interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    echo "主网络接口: $main_interface"
    
    if [[ -n "$main_interface" ]]; then
        local interface_ip=$(ip -o -4 addr show dev "$main_interface" | awk '{print $4}' | cut -d/ -f1 | head -n1)
        echo "接口IP地址: $interface_ip"
        
        local gateway=$(ip route | grep default | awk '{print $3}')
        echo "网关地址: $gateway"
        
        local subnet=$(echo "$interface_ip" | cut -d. -f1-3).0/24
        echo "子网: $subnet"
        
        echo "✓ 网络检测正常"
    else
        echo "✗ 无法检测到网络接口"
        return 1
    fi
}

# 测试Docker
test_docker() {
    echo "=== 测试Docker ==="
    
    if command -v docker &> /dev/null; then
        echo "✓ Docker已安装"
        
        if systemctl is-active --quiet docker; then
            echo "✓ Docker服务运行中"
        else
            echo "! Docker服务未运行，尝试启动..."
            systemctl start docker
            if systemctl is-active --quiet docker; then
                echo "✓ Docker服务已启动"
            else
                echo "✗ Docker服务启动失败"
                return 1
            fi
        fi
    else
        echo "✗ Docker未安装"
        return 1
    fi
}

# 测试JSON操作
test_json_operations() {
    echo "=== 测试JSON操作 ==="
    
    local test_file="/tmp/test_state.json"
    
    # 创建测试JSON文件
    cat > "$test_file" << EOF
{
  "version": "1.0",
  "mihomo_ip": "192.168.1.100",
  "installation_stage": "测试",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF
    
    # 测试读取
    local mihomo_ip=$(jq -r '.mihomo_ip' "$test_file")
    if [[ "$mihomo_ip" == "192.168.1.100" ]]; then
        echo "✓ JSON读取测试通过"
    else
        echo "✗ JSON读取测试失败"
        return 1
    fi
    
    # 测试更新
    jq --arg stage "测试完成" '.installation_stage = $stage' "$test_file" > "${test_file}.tmp"
    if [[ $? -eq 0 ]]; then
        mv "${test_file}.tmp" "$test_file"
        local new_stage=$(jq -r '.installation_stage' "$test_file")
        if [[ "$new_stage" == "测试完成" ]]; then
            echo "✓ JSON更新测试通过"
        else
            echo "✗ JSON更新测试失败"
            return 1
        fi
    else
        echo "✗ JSON更新操作失败"
        return 1
    fi
    
    # 清理测试文件
    rm -f "$test_file" "${test_file}.tmp"
}

# 主函数
main() {
    echo "开始测试修复..."
    
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        echo "此测试需要root权限"
        exit 1
    fi
    
    # 运行测试
    check_and_install_jq
    test_network_detection
    test_docker
    test_json_operations
    
    echo "=== 测试完成 ==="
    echo "如果所有测试都通过，您可以重新运行mihomo.sh脚本"
}

# 执行主函数
main 