# Mihomo 防火墙规则配置指南

## 概述

本指南介绍了Mihomo裸核版脚本中新增的防火墙规则管理功能，用于配置透明代理所需的流量重定向规则。

## 功能特性

### 🔥 自动防火墙检测
- 自动检测系统使用的防火墙类型（nftables/iptables）
- 智能适配不同的防火墙配置方式
- 支持防火墙规则的自动配置和清理

### 🛡️ 透明代理支持
- 自动配置TCP流量重定向到Mihomo透明代理端口
- 自动配置DNS流量重定向到Mihomo DNS服务
- 排除本机和SSH流量，防止连接中断

### 📊 状态监控
- 实时显示防火墙规则配置状态
- 详细的规则检查和验证
- 完整的故障排除指导

## 支持的防火墙类型

### 1. nftables（推荐）
- 现代Linux发行版的默认防火墙
- 更高效的规则处理
- 更好的性能表现

### 2. iptables（兼容）
- 传统Linux防火墙
- 广泛兼容性
- 稳定可靠

## 使用方法

### 一键安装时自动配置
```bash
sudo bash mihomo.sh
# 选择 [1] 一键安装 Mihomo
# 脚本会自动配置防火墙规则
```

### 手动配置防火墙规则
```bash
sudo bash mihomo.sh
# 选择 [7] 防火墙配置
# 根据提示进行配置
```

### 查看防火墙状态
```bash
sudo bash mihomo.sh
# 选择 [5] 查看状态
# 会显示防火墙规则配置状态
```

## 防火墙规则详解

### nftables规则
脚本会创建 `/etc/nftables-mihomo.conf` 配置文件：

```nftables
table inet mihomo {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        
        # 排除本机流量
        ip saddr 192.168.x.x return
        
        # 排除SSH端口
        tcp dport 22 return
        
        # 排除局域网流量
        ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 224.0.0.0/4, 240.0.0.0/4 } return
        
        # 重定向TCP流量到Mihomo透明代理端口
        ip protocol tcp redirect to :7892
        
        # 重定向DNS流量到Mihomo DNS端口
        udp dport 53 redirect to :53
        tcp dport 53 redirect to :53
    }
}
```

### iptables规则
脚本会创建 `MIHOMO_PREROUTING` 自定义链：

```bash
# 创建自定义链
iptables -t nat -N MIHOMO_PREROUTING

# 排除本机流量
iptables -t nat -A MIHOMO_PREROUTING -s 192.168.x.x -j RETURN

# 排除SSH端口
iptables -t nat -A MIHOMO_PREROUTING -p tcp --dport 22 -j RETURN

# 排除局域网流量
iptables -t nat -A MIHOMO_PREROUTING -d 127.0.0.0/8 -j RETURN
iptables -t nat -A MIHOMO_PREROUTING -d 10.0.0.0/8 -j RETURN
iptables -t nat -A MIHOMO_PREROUTING -d 172.16.0.0/12 -j RETURN
iptables -t nat -A MIHOMO_PREROUTING -d 192.168.0.0/16 -j RETURN

# 重定向TCP流量
iptables -t nat -A MIHOMO_PREROUTING -p tcp -j REDIRECT --to-ports 7892

# 重定向DNS流量
iptables -t nat -A MIHOMO_PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53
iptables -t nat -A MIHOMO_PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 53
```

## 透明代理配置

### 客户端配置
配置防火墙规则后，客户端设备需要进行以下设置：

1. **设置网关**
   ```
   网关地址: 192.168.x.x (Mihomo服务器IP)
   ```

2. **设置DNS**
   ```
   DNS服务器: 192.168.x.x (Mihomo服务器IP)
   ```

### 路由器配置示例

#### OpenWrt/LEDE
```bash
# 全局透明代理
uci set network.lan.gateway='192.168.x.x'
uci set dhcp.@dnsmasq[0].server='192.168.x.x'
uci commit && /etc/init.d/network restart

# 部分流量代理
ip route add 198.18.0.0/16 via 192.168.x.x
uci set dhcp.@dnsmasq[0].server='192.168.x.x'
uci commit dhcp && /etc/init.d/dnsmasq restart
```

## 测试验证

### 使用测试脚本
```bash
sudo bash test_firewall.sh
```

测试脚本会检查：
- 基本信息和服务状态
- 端口监听状态
- 防火墙规则配置
- DNS解析功能
- 代理连接测试
- 控制面板访问

### 手动验证
```bash
# 检查nftables规则
nft list table inet mihomo

# 检查iptables规则
iptables -t nat -L MIHOMO_PREROUTING

# 测试DNS解析
dig @192.168.x.x google.com

# 测试代理连接
curl --proxy http://192.168.x.x:7890 http://httpbin.org/ip
```

## 故障排除

### 常见问题

#### 1. 防火墙规则配置失败
```bash
# 检查防火墙服务状态
systemctl status nftables
systemctl status iptables

# 手动安装防火墙工具
apt update && apt install -y nftables
# 或
apt update && apt install -y iptables
```

#### 2. 透明代理不生效
```bash
# 检查Mihomo服务状态
systemctl status mihomo

# 检查端口监听
ss -tlnp | grep mihomo

# 检查防火墙规则
nft list table inet mihomo
# 或
iptables -t nat -L MIHOMO_PREROUTING
```

#### 3. SSH连接中断
脚本会自动排除SSH端口，如果仍然遇到问题：
```bash
# 检查SSH端口
ss -tlnp | grep sshd

# 手动添加SSH端口排除规则
# (脚本会自动处理，通常不需要手动操作)
```

### 日志查看
```bash
# 查看Mihomo服务日志
journalctl -u mihomo -f

# 查看系统日志
journalctl -f

# 查看防火墙日志
dmesg | grep -i firewall
```

## 安全注意事项

### 1. SSH访问保护
- 脚本自动检测SSH端口并添加排除规则
- 建议使用密钥认证而非密码认证
- 考虑更改默认SSH端口

### 2. 防火墙规则管理
- 卸载Mihomo时会自动清理防火墙规则
- 建议备份原有防火墙配置
- 定期检查规则配置状态

### 3. 网络安全
- 透明代理会影响所有通过该网关的流量
- 确保Mihomo配置文件的安全性
- 定期更新Mihomo版本

## 高级配置

### 自定义排除规则
如需排除特定IP或端口，可以编辑配置文件：

#### nftables
编辑 `/etc/nftables-mihomo.conf`：
```nftables
# 添加自定义排除规则
ip daddr 特定IP return
tcp dport 特定端口 return
```

#### iptables
```bash
# 添加自定义排除规则
iptables -t nat -I MIHOMO_PREROUTING -d 特定IP -j RETURN
iptables -t nat -I MIHOMO_PREROUTING -p tcp --dport 特定端口 -j RETURN
```

### 规则持久化
脚本会自动处理规则持久化：
- nftables: 添加到主配置文件
- iptables: 保存到 `/etc/mihomo-iptables.rules`

## 更新日志

### v1.0.0
- 新增防火墙规则自动配置功能
- 支持nftables和iptables
- 集成透明代理配置
- 添加防火墙状态检查
- 提供完整的测试验证工具

## 技术支持

如果遇到问题，请提供以下信息：
1. 系统版本和架构
2. 防火墙类型和版本
3. Mihomo服务状态
4. 防火墙规则配置
5. 相关错误日志

---

**注意**: 本功能需要root权限运行，请确保在安全的环境中使用。 