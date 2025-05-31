# 代理机里直接跑mihomo，裸核版

## 概述

✅ **已完成** - Mihomo 裸核版一键安装脚本已经开发完成！

这是一个专为 Debian/Ubuntu 系统设计的 Mihomo 原生安装脚本，无需 Docker 环境，直接在系统上运行 Mihomo 二进制文件。

## 主要特性

✅ **完全实现的功能**：

1. ✅ **一键安装** - 自动完成 mihomo 安装和配置
2. ✅ **状态检测** - 实时检查 mihomo 运行状态
3. ✅ **服务管理** - 启动、停止、重启 mihomo 服务
4. ✅ **完整卸载** - 安全卸载 mihomo 及其配置
5. ✅ **使用指南** - 详细的网络配置指导
6. ✅ **架构检测** - 自动检测系统架构并下载对应版本
7. ✅ **配置自动化** - 自动从 GitHub 下载配置文件
8. ✅ **UI 界面** - 自动安装 MetaCubeX 管理界面

## 安装方式

### 方法一：直接下载主脚本（推荐）
```bash
wget https://raw.githubusercontent.com/wallentv/mihomo-proxy/refs/heads/master/mihomo/mihomo.sh
chmod +x mihomo.sh
sudo ./mihomo.sh
```

### 方法二：使用 curl 下载
```bash
curl -fsSL https://raw.githubusercontent.com/wallentv/mihomo-proxy/refs/heads/master/mihomo/mihomo.sh -o mihomo.sh
chmod +x mihomo.sh
sudo ./mihomo.sh
```

### 方法三：一键下载并执行
```bash
wget https://raw.githubusercontent.com/wallentv/mihomo-proxy/refs/heads/master/mihomo/mihomo.sh && chmod +x mihomo.sh && sudo ./mihomo.sh --auto-install
```

## 实现的功能清单

### ✅ 环境配置
- 系统更新和依赖安装
- IP 转发开启（IPv4/IPv6）
- 系统架构自动检测

### ✅ Mihomo 安装
- 自动获取最新版本
- 根据架构下载对应二进制文件
- 安装到 `/opt/mihomo/mihomo`
- 设置正确的文件权限

### ✅ UI 界面安装
- 自动下载 MetaCubeX UI
- 解压到 `/etc/mihomo/ui/`
- 支持 Web 管理界面

### ✅ 配置文件管理
- 优先使用本地配置文件
- 自动从 GitHub 下载配置模板
- 网络失败时创建默认配置
- 配置文件位置：`/etc/mihomo/config.yaml`

### ✅ 系统服务
- 创建 systemd 服务文件
- 设置开机自启动
- 完整的服务生命周期管理

### ✅ 网络配置指导
实现了两种使用方法的详细指导：

**方法一：DNS + 路由设置**
- 设备 DNS 指向代理机 IP
- 添加 198.18.0.0/16 路由规则

**方法二：透明代理**
- 设备网关指向代理机 IP
- 设备 DNS 指向代理机 IP

### ✅ 管理功能
- 服务状态检查
- 端口监听状态显示
- 实时日志查看
- 配置文件编辑指导
- 完整的卸载功能

## 文件结构

```
mihomo/
├── mihomo.sh          # 主安装脚本（唯一需要的文件）
├── config.yaml        # 配置文件模板（自动下载）
├── README.md          # 使用说明
└── doc/
    └── mihomo裸核.md  # 本文档
```

## 安装位置

- **二进制文件**: `/opt/mihomo/mihomo`
- **配置目录**: `/etc/mihomo/`
- **配置文件**: `/etc/mihomo/config.yaml`
- **UI界面**: `/etc/mihomo/ui/`
- **服务文件**: `/etc/systemd/system/mihomo.service`
- **日志文件**: `/var/log/mihomo.log`

## 使用示例

### 安装完成后的信息显示
```
======================================================
Mihomo 安装完成!
======================================================
控制面板: http://192.168.1.100:9090
管理密码: wallentv
混合代理: 192.168.1.100:7890
HTTP代理: 192.168.1.100:7891
SOCKS代理: 192.168.1.100:7892
DNS服务: 192.168.1.100:53
======================================================
```

### 常用管理命令
```bash
# 查看服务状态
systemctl status mihomo

# 查看实时日志
journalctl -u mihomo -f

# 重启服务
systemctl restart mihomo

# 编辑配置
nano /etc/mihomo/config.yaml
```

## 与需求对比

| 需求项目 | 实现状态 | 说明 |
|---------|---------|------|
| 一键安装 | ✅ 完成 | 支持菜单和命令行参数 |
| 状态检测 | ✅ 完成 | 详细的状态信息显示 |
| 服务管理 | ✅ 完成 | 启动/停止/重启功能 |
| 使用指南 | ✅ 完成 | 两种网络配置方法 |
| 卸载功能 | ✅ 完成 | 安全完整卸载 |
| 小白友好 | ✅ 完成 | 傻瓜化菜单操作 |
| 架构支持 | ✅ 完成 | amd64/arm64/armv7 |
| 配置自动化 | ✅ 完成 | 自动下载配置文件 |

## 总结

Mihomo 裸核版一键安装脚本已经完全实现了需求文档中的所有功能，并且增加了许多实用的特性：

- 🎯 **用户友好**: 提供交互式菜单和一键安装选项
- 🔧 **自动化程度高**: 自动检测架构、下载文件、配置服务
- 📱 **管理便捷**: 完整的服务管理和状态监控
- 🌐 **网络配置**: 详细的使用指导和配置示例
- 🛡️ **安全可靠**: 完整的错误处理和日志记录

用户只需要一条命令即可完成整个安装过程，真正实现了"小白友好"的目标。


1. 新建一个mihomo.sh的脚本，引导用户完成debian/ubuntun代理机中直接安装mihomo。
2. 这个脚本位于mihomo文件夹跟目录下，是核版的mihomo，这种方式无需docker，直接跑原生mihomo服务。
3. 这个脚本主要是给小白用，傻瓜化菜单操作就能搞定。运行在代理机里，代理机一般是安装了debian/ubuntu的虚拟机。
   1. 用户通过从github上下载这个脚本，在代理机里执行；
   2. mihomo的yaml配置模版需要先下载到mihomo运行目录；
4. 功能清单
   1. 能一键完成mihomo安装
   2. 能检测mihomo运行状态
   3. 能重启mihomo
   4. 能关停mihomo服务
   5. 能启动mihomo服务
   6. 引导用户如何使用mihomo
      1. 方法1，DNS设置为代理机ip，198.18.0.1/16 的路由指向代理机ip  
      2. 方法2，讲代理机设置为网关，实现透明代理；
   7. 能卸载mihomo
5. 安装步骤如下
   1. 环境配置
      1. apt update && aptupgrade
      2. apt install wget
      3. 开启ipv4和ipv6转发
   2. 根据系统的架构，下载对应最新的Clash安装包。
      1. 下载地址 https://github.com/MetaCubeX/mihomo/releases 
      2. 将下载压缩包解压得到二进制文件重名名为 mihomo 并移动到 /opt/mihomo
      3. 给予执行文件755权限
   3. 下载UI包到挂载目录：/etc/mihomo
   ```bash
   mkdir -p /etc/mihomo/ui
   wget https://github.com/MetaCubeX/metacubexd/releases/download/v1.187.1/compressed-dist.tgz
   tar -xzf compressed-dist.tgz -C /etc/mihomo/ui
   ```
   4. 复制config.yaml 到 /etc/mihomo，搞定配置文件
   5. 设置开机mihomo自动启动；
   6. 引导用户下一步操作，依据主网卡获得代理机ip，配置路由和dns。
   
   


