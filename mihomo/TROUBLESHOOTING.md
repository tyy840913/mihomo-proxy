# Mihomo 安装故障排除指南

## 常见问题解决方案

### 1. dpkg 错误 (Sub-process /usr/bin/dpkg returned an error code (1))

这是最常见的安装问题，通常由包管理器状态异常引起。

#### 解决方法一：使用脚本内置修复功能

```bash
# 重新下载最新脚本
wget https://raw.githubusercontent.com/wallentv/mihomo-proxy/refs/heads/master/mihomo/mihomo.sh
chmod +x mihomo.sh

# 运行脚本并选择系统修复
sudo ./mihomo.sh
# 在菜单中选择 "7. 系统修复"
```

#### 解决方法二：手动修复系统

```bash
# 1. 修复中断的包安装
sudo dpkg --configure -a

# 2. 修复损坏的依赖关系
sudo apt-get -f install -y

# 3. 清理包缓存
sudo apt-get clean
sudo apt-get autoclean

# 4. 更新包列表
sudo apt-get update --fix-missing

# 5. 重新运行安装脚本
sudo ./mihomo.sh --auto-install
```

### 2. 网络下载失败

```bash
# 检查网络连接
ping -c 3 github.com

# 如果网络正常但下载失败，可能是 DNS 问题
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

### 3. 权限问题

```bash
# 确保以 root 权限运行
sudo ./mihomo.sh

# 检查脚本权限
chmod +x mihomo.sh
```

### 4. 服务启动失败

```bash
# 查看详细错误日志
sudo journalctl -u mihomo -n 20

# 检查配置文件
sudo /opt/mihomo -t -d /etc/mihomo

# 检查端口是否被占用
sudo netstat -tlnp | grep -E "(7890|7891|7892|9090|53)"
```

### 5. 完全重新安装

如果以上方法都无效，可以完全重新安装：

```bash
# 1. 卸载现有安装
sudo ./mihomo.sh
# 选择 "8. 卸载 Mihomo"

# 2. 系统修复
# 选择 "7. 系统修复"

# 3. 重新安装
# 选择 "1. 一键安装 Mihomo"
```

## 预防措施

1. **定期更新系统**：`sudo apt update && sudo apt upgrade`
2. **避免强制中断安装过程**
3. **确保有足够的磁盘空间**：`df -h`
4. **检查系统时间是否正确**：`date`

## 获取帮助

如果问题仍然存在，请提供以下信息：

```bash
# 系统信息
cat /etc/os-release
uname -a

# 错误日志
sudo journalctl -u mihomo -n 50

# 包管理器状态
sudo dpkg --audit
sudo apt-get check
``` 