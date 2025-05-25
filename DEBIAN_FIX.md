# Debian系统运行修复说明

## 问题描述

在Debian系统上运行mihomo.sh脚本时遇到以下问题：

1. **jq命令未找到** - 脚本依赖jq处理JSON文件，但Debian系统默认未安装
2. **macvlan接口创建失败** - 网络命令语法问题导致macvlan接口创建失败
3. **容器重启循环** - 容器配置或网络问题导致容器不断重启

## 修复内容

### 1. 自动安装jq工具

在所有需要使用jq的函数中添加了自动安装检查：

```bash
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
```

### 2. 修复macvlan网络配置

修复了网络接口创建命令的语法问题：

```bash
# 修复前（有问题的命令）
ip link add $macvlan_interface link $main_interface type macvlan mode bridge

# 修复后（正确的命令）
ip link add "$macvlan_interface" link "$main_interface" type macvlan mode bridge
```

### 3. 改进容器启动配置

修复了Docker容器的启动参数：

```bash
# 添加端口映射和改进重启策略
docker run -d --privileged \
    --name=mihomo --restart=unless-stopped \
    --network mnet --ip "$mihomo_ip" \
    -v "$CONF_DIR:/root/.config/mihomo/" \
    -p 9090:9090 \
    -p 7890:7890 \
    -p 7891:7891 \
    -p 7892:7892 \
    metacubex/mihomo:latest
```

### 4. 改进状态文件处理

将原来基于sed的JSON处理改为使用jq：

```bash
# 修复前
sed -i "s|\"$key\": *\"[^\"]*\"|\"$key\": \"$value\"|g" "$STATE_FILE"

# 修复后
jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$STATE_FILE" > "${STATE_FILE}.tmp"
mv "${STATE_FILE}.tmp" "$STATE_FILE"
```

## 使用方法

### 方法1：直接使用修复后的脚本

1. 确保您有root权限
2. 运行修复后的脚本：
   ```bash
   sudo bash mihomo.sh
   ```

### 方法2：先运行测试脚本

1. 运行测试脚本验证环境：
   ```bash
   sudo bash test_fix.sh
   ```

2. 如果测试通过，再运行主脚本：
   ```bash
   sudo bash mihomo.sh
   ```

## 修复的文件

- `mihomo-docker/mihomo.sh` - 主安装脚本
- `mihomo-docker/files/setup_proxy.sh` - 代理配置脚本
- `mihomo-docker/test_fix.sh` - 测试脚本（新增）

## 验证修复

运行测试脚本后，您应该看到类似以下输出：

```
=== Mihomo 修复测试脚本 ===
开始测试修复...
✓ jq已安装
=== 测试网络接口检测 ===
主网络接口: eth0
接口IP地址: 192.168.1.100
网关地址: 192.168.1.1
子网: 192.168.1.0/24
✓ 网络检测正常
=== 测试Docker ===
✓ Docker已安装
✓ Docker服务运行中
=== 测试JSON操作 ===
✓ JSON读取测试通过
✓ JSON更新测试通过
=== 测试完成 ===
如果所有测试都通过，您可以重新运行mihomo.sh脚本
```

## 注意事项

1. **系统要求**：Debian 10/11/12 或 Ubuntu 20.04/22.04/24.04
2. **权限要求**：必须以root权限运行
3. **网络要求**：需要互联网连接以下载Docker镜像和UI文件
4. **依赖安装**：脚本会自动安装必要的依赖包（jq、wget等）

## 故障排除

如果仍然遇到问题：

1. **检查系统日志**：
   ```bash
   tail -f /var/log/mihomo_install.log
   ```

2. **检查Docker日志**：
   ```bash
   docker logs mihomo
   ```

3. **检查容器状态**：
   ```bash
   docker ps -a
   ```

4. **手动安装jq**（如果自动安装失败）：
   ```bash
   apt-get update && apt-get install -y jq
   ```

## 开发环境差异

此修复主要解决了macOS开发环境与Debian运行环境之间的差异：

- **包管理器差异**：macOS使用Homebrew，Debian使用apt-get
- **命令语法差异**：某些网络命令在不同系统上的语法略有不同
- **默认软件包差异**：Debian默认不包含jq等工具

修复后的脚本现在可以在Debian系统上正常运行。 