# Mihomo 一键安装脚本使用说明

## 概述

`mihomo-docker.sh` 是一个专为 Debian/Ubuntu 系统设计的 Mihomo 一键安装和管理脚本。该脚本提供了完整的 Mihomo 生命周期管理功能，包括安装、配置、启停、更新和卸载。

## 特性

- ✅ **一键安装**: 自动下载最新版本的 Mihomo 并完成配置
- ✅ **架构检测**: 自动检测系统架构（amd64/arm64/armv7）
- ✅ **UI界面**: 自动安装 MetaCubeX 管理界面
- ✅ **服务管理**: 完整的 systemd 服务管理功能
- ✅ **网络配置**: 自动开启 IP 转发，提供网络配置指导
- ✅ **配置管理**: 支持配置文件编辑和热重载
- ✅ **状态监控**: 实时查看服务状态和日志
- ✅ **安全卸载**: 完整清理所有相关文件

## 系统要求

- **操作系统**: Debian 9+ 或 Ubuntu 18.04+
- **权限**: 需要 root 权限
- **网络**: 需要互联网连接下载相关文件
- **架构**: 支持 x86_64、aarch64、armv7l

## 快速开始

### 1. 下载脚本

```bash
# 方法一：直接下载
wget https://raw.githubusercontent.com/your-repo/mihomo-proxy/main/mihomo-docker/mihomo-docker.sh

# 方法二：克隆仓库
git clone https://github.com/your-repo/mihomo-proxy.git
cd mihomo-proxy
```

### 2. 运行脚本

```bash
# 给脚本执行权限
chmod +x mihomo-docker.sh

# 运行脚本（需要root权限）
sudo ./mihomo-docker.sh
```

### 3. 选择安装

在菜单中选择 `1` 进行一键安装，脚本将自动完成：
- 系统环境配置
- Mihomo 二进制文件下载
- UI 界面安装
- 配置文件设置
- 系统服务创建
- 服务启动

## 功能详解

### 主菜单选项

```
================================
    Mihomo 一键管理脚本
================================

1. 安装 Mihomo        - 完整安装流程
2. 启动服务          - 启动 Mihomo 服务
3. 停止服务          - 停止 Mihomo 服务
4. 重启服务          - 重启 Mihomo 服务
5. 查看状态          - 查看服务运行状态
6. 查看日志          - 实时查看服务日志
7. 编辑配置          - 编辑配置文件
8. 网络配置指导      - 显示网络配置方法
9. 更新 Mihomo       - 更新到最新版本
10. 卸载 Mihomo      - 完全卸载 Mihomo
0. 退出              - 退出脚本
```

### 安装过程详解

1. **环境检查**: 检查 root 权限、网络连接
2. **系统更新**: 更新软件包，安装必要依赖
3. **IP转发**: 开启 IPv4/IPv6 转发功能
4. **下载安装**: 自动检测架构，下载最新版本
5. **UI安装**: 下载并安装 MetaCubeX 管理界面
6. **配置文件**: 复制或创建默认配置文件
7. **服务创建**: 创建 systemd 服务并设置开机启动
8. **服务启动**: 启动服务并验证运行状态

### 配置文件说明

脚本会优先使用项目中的 `mihomo-docker/files/config.yaml` 配置文件，如果不存在则创建默认配置。

**默认配置特性**:
- 混合端口: 7890 (HTTP + SOCKS5)
- HTTP端口: 7891
- SOCKS5端口: 7892
- 管理界面: 9090端口
- DNS服务: 53端口
- TUN模式: 已启用
- 管理密码: wallentv

## 网络配置

安装完成后，脚本会显示网络配置指导。有两种使用方式：

### 方法一: DNS + 路由设置

适用于部分设备使用代理的场景：

1. 将设备 DNS 设置为代理机 IP
2. 添加路由规则：
   - 目标网段: `198.18.0.0/16`
   - 网关: 代理机 IP

### 方法二: 透明代理（推荐）

适用于全局代理的场景：

1. 将设备网关设置为代理机 IP
2. 将设备 DNS 设置为代理机 IP

## 管理界面

安装完成后可通过浏览器访问管理界面：

- **地址**: `http://代理机IP:9090`
- **密码**: `wallentv`
- **功能**: 节点管理、规则配置、流量监控等

## 文件位置

- **二进制文件**: `/opt/mihomo/mihomo`
- **配置目录**: `/etc/mihomo/`
- **配置文件**: `/etc/mihomo/config.yaml`
- **UI界面**: `/etc/mihomo/ui/`
- **服务文件**: `/etc/systemd/system/mihomo.service`

## 常用命令

```bash
# 查看服务状态
systemctl status mihomo

# 查看实时日志
journalctl -u mihomo -f

# 重启服务
systemctl restart mihomo

# 编辑配置文件
nano /etc/mihomo/config.yaml

# 检查端口监听
netstat -tlnp | grep mihomo
```

## 故障排除

### 1. 服务启动失败

```bash
# 查看详细错误信息
journalctl -u mihomo -n 50

# 检查配置文件语法
/opt/mihomo/mihomo -t -d /etc/mihomo
```

### 2. 网络连接问题

```bash
# 检查IP转发是否开启
cat /proc/sys/net/ipv4/ip_forward

# 检查防火墙设置
ufw status
iptables -L
```

### 3. 权限问题

```bash
# 检查文件权限
ls -la /opt/mihomo/
ls -la /etc/mihomo/

# 修复权限
chmod +x /opt/mihomo/mihomo
chmod 644 /etc/mihomo/config.yaml
```

## 更新和维护

### 更新 Mihomo

使用脚本菜单中的 "更新 Mihomo" 选项，或手动执行：

```bash
# 停止服务
systemctl stop mihomo

# 备份配置
cp /etc/mihomo/config.yaml /tmp/config.backup

# 下载新版本
# ... (参考安装步骤)

# 恢复配置并重启
cp /tmp/config.backup /etc/mihomo/config.yaml
systemctl start mihomo
```

### 配置文件更新

修改配置文件后需要重启服务：

```bash
nano /etc/mihomo/config.yaml
systemctl restart mihomo
```

## 安全建议

1. **修改默认密码**: 更改管理界面默认密码
2. **防火墙配置**: 限制管理端口的访问来源
3. **定期更新**: 保持 Mihomo 版本最新
4. **日志监控**: 定期检查服务日志

## 支持和反馈

如果在使用过程中遇到问题，请：

1. 查看本文档的故障排除部分
2. 检查 GitHub Issues
3. 提交新的 Issue 并附上详细的错误信息

## 许可证

本脚本遵循 MIT 许可证，详见 LICENSE 文件。 