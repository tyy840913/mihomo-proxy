# Mihomo 裸核版一键安装脚本

## 简介

Mihomo 裸核版一键安装脚本是一个专为 Debian/Ubuntu 系统设计的 Mihomo 原生安装和管理工具。与 Docker 版本不同，此脚本直接在系统上安装 Mihomo 二进制文件，无需 Docker 环境，更加轻量化。

### 🚀 快速开始（一键安装）

```bash
# 下载并执行一键安装
wget https://raw.githubusercontent.com/wallentv/mihomo-proxy/refs/heads/master/mihomo/mihomo.sh && chmod +x mihomo.sh && sudo ./mihomo.sh --auto-install
```

## 特性

- ✅ **无需 Docker**: 直接在系统上运行 Mihomo，减少资源占用
- ✅ **一键安装**: 自动下载最新版本的 Mihomo 并完成配置
- ✅ **架构检测**: 自动检测系统架构（amd64/arm64/armv7）
- ✅ **UI界面**: 自动安装 MetaCubeX 管理界面
- ✅ **systemd 服务**: 完整的系统服务管理功能
- ✅ **网络配置**: 自动开启 IP 转发，提供网络配置指导
- ✅ **配置管理**: 使用项目中的配置文件模板
- ✅ **状态监控**: 实时查看服务状态和日志
- ✅ **安全卸载**: 完整清理所有相关文件

## 系统要求

- **操作系统**: Debian 10+ 或 Ubuntu 20.04+
- **权限**: 需要 root 权限
- **网络**: 需要互联网连接下载相关文件
- **架构**: 支持 x86_64、aarch64、armv7l

## 快速开始

### 1. 下载脚本

```bash
# 方法一：直接下载主脚本（推荐）
wget https://raw.githubusercontent.com/wallentv/mihomo-proxy/refs/heads/master/mihomo/mihomo.sh
chmod +x mihomo.sh

# 方法二：使用 curl 下载
curl -fsSL https://raw.githubusercontent.com/wallentv/mihomo-proxy/refs/heads/master/mihomo/mihomo.sh -o mihomo.sh
chmod +x mihomo.sh

# 方法三：克隆整个仓库
git clone https://github.com/wallentv/mihomo-proxy.git
cd mihomo-proxy/mihomo
```

**注意**: 配置文件会在安装过程中自动从 GitHub 下载，无需手动下载。

### 2. 运行脚本

```bash
# 给脚本执行权限
chmod +x mihomo.sh

# 运行脚本（需要root权限）
sudo ./mihomo.sh
```

### 3. 一键安装

在菜单中选择 `1` 进行一键安装，脚本将自动完成：
- 系统环境配置
- Mihomo 二进制文件下载
- UI 界面安装
- 配置文件设置
- systemd 服务创建
- 服务启动

## 功能菜单

```
======================================================
              Mihomo 裸核版管理脚本
======================================================
 [1] 一键安装 Mihomo
 [2] 启动服务
 [3] 停止服务
 [4] 重启服务
 [5] 查看状态
 [6] 使用指南
 [7] 卸载 Mihomo
 [0] 退出脚本
======================================================
```

## 命令行参数

```bash
# 显示版本信息
./mihomo.sh --version

# 显示帮助信息
./mihomo.sh --help

# 直接执行一键安装（无需进入菜单）
./mihomo.sh --auto-install
```

## 安装位置

- **二进制文件**: `/opt/mihomo`
- **配置目录**: `/etc/mihomo/`
- **配置文件**: `/etc/mihomo/config.yaml`
- **UI界面**: `/etc/mihomo/ui/`
- **服务文件**: `/etc/systemd/system/mihomo.service`
- **日志文件**: `/var/log/mihomo.log`

## 网络配置

安装完成后，有两种使用方式：

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
- **密码**: 根据配置文件中的设置
- **功能**: 节点管理、规则配置、流量监控等

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
/opt/mihomo -t -d /etc/mihomo
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
ls -la /opt/mihomo
ls -la /etc/mihomo/

# 修复权限
chmod +x /opt/mihomo
chmod 644 /etc/mihomo/config.yaml
```

## 与 Docker 版本的区别

| 特性 | 裸核版 | Docker版 |
|------|--------|----------|
| 资源占用 | 更低 | 较高 |
| 安装复杂度 | 简单 | 需要Docker |
| 系统集成 | 更好 | 容器化 |
| 网络配置 | 直接 | 需要网络映射 |
| 维护难度 | 简单 | 中等 |

## 更新和维护

### 更新 Mihomo

使用脚本菜单中的 "一键安装" 选项重新安装即可更新到最新版本。

### 配置文件更新

修改配置文件后需要重启服务：

```bash
nano /etc/mihomo/config.yaml
systemctl restart mihomo
```

## 注意事项

1. **配置文件**: 脚本会自动从 GitHub 下载最新的配置文件模板，如果下载失败会创建基本的默认配置
2. **权限要求**: 安装和管理需要 root 权限
3. **网络要求**: 安装过程需要互联网连接下载二进制文件、UI界面和配置文件
4. **端口冲突**: 确保配置文件中的端口没有被其他服务占用
5. **防火墙**: 可能需要开放相应端口的防火墙规则

## 配置文件说明

脚本会按以下优先级获取配置文件：

1. **本地配置**: 如果脚本同目录下存在 `config.yaml`，优先使用本地文件
2. **GitHub 下载**: 自动从项目仓库下载最新的配置文件模板
3. **默认配置**: 如果网络下载失败，创建基本的默认配置文件

安装完成后，可以根据需要编辑 `/etc/mihomo/config.yaml` 文件来自定义配置。

## 许可证

本脚本遵循 MIT 许可证，详见 LICENSE 文件。 