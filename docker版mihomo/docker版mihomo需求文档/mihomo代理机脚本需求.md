# Mihomo一键安装脚本需求, debian秒变代理机

## 背景

为了简化小白配置docker版mihomo，我要基于参考脚本和mihomo配置文件模版来生成一个mihomo一键安装脚本，引导用户，以最小的输入，傻瓜化地安装mihomo。

这个一键脚本/引导脚本只可以运行在Debian/Ubuntu系统里，用户只需输入mihomo的IP地址，引导脚本便能生成两个脚本和一个状态记录文件，这两个配置脚本和状态记录文件要放到一个文件夹里，且该文件夹要和引导脚本位于同一个文件路径：
1. 脚本1，是配置代理机的脚本并执行
2. 脚本2，是配置RouterOS的脚本
3. 状态记录文件，记录用户输入的信息，当前配置到那个阶段，以便多次运行引导脚本时，从未完成的地方开始，而不是每次都重头开始。

然后用户可以选择执行哪一个脚本，完成配置。

## 系统与硬件要求

### 支持的系统
- Debian 10/11/12 或 Ubuntu 20.04/22.04/24.04 LTS
- 其他基于 Debian 的发行版可能兼容，但未经测试

## 要求

用户需要输入的信息主要是mihomo的IP地址，是为了防止和区域网其他IP冲突，该IP要和局域网在同一个网段。

- 引导脚本前面要有如何使用的说明，如需将引导脚本放到/opt目录下，开启脚本执行权限，如何运行脚本的说明。

### IP地址分配逻辑

脚本需要智能处理IP分配，遵循以下规则：
1. 自动检测主网卡接口（例如eth0、ens33等）及其IP地址，确定所在局域网网段
2. 基于检测到的网段，向用户建议可用的mihomo IP地址（例如检测到网段为192.168.1.x，则建议192.168.1.x范围内的可用IP）
3. 为macvlan接口自动分配相邻的可用IP（例如如果mihomo IP为192.168.1.10，则接口IP为192.168.1.11）
4. 使用ping和arping测试以确保分配的IP不与网络中的现有设备冲突
5. 如检测到IP冲突，脚本会自动推荐网段内其他可用IP
6. 保存检测到的网卡ID用于后续macvlan配置，确保网络设置正确应用于实际使用的网络接口

### 状态记录文件规范

状态记录文件应为JSON格式，包含以下信息：
- 用户输入的IP地址
- 当前安装阶段（例如："初始化"、"网络配置"、"Docker安装"、"mihomo安装"、"配置完成"）
- 配置选项（如订阅链接类型、镜像拉取方式等）
- 网络接口名称
- macvlan接口名称和IP
- 完成时间戳

示例格式：
```json
{
  "mihomo_ip": "192.168.88.4",
  "interface_ip": "192.168.88.5",
  "main_interface": "eth0",
  "macvlan_interface": "veth5",
  "installation_stage": "Docker安装",
  "config_type": "subscription",
  "subscription_url": "http://example.com/sub",
  "docker_method": "direct_pull",
  "timestamp": "2023-05-15 14:30:22"
}
```

### 代理机脚本

生成的引导脚本负责在代理机里安装docker版的mihomo，安装方法详见 "mihomo参考脚本.md"，该脚本运行后会完成mihomo安装。

- 安装过程中依赖的包，要自动安装
- 由于mihomo相关docker包的下载依赖科学上网环境，安装前需提示用户环境问题
- 安装过程中，要用通俗且清晰的提示语引导用户完成配置
- 引导和配置脚本中要添加通俗清晰的说明
- mihomo安装前先得搞定网络配置和配置文件；网络配置就是要配置macvlan；配置文件包含UI包和config.yaml配置文件

#### 错误处理机制

代理机脚本需要包含以下错误处理机制：
1. 检测并处理网络连接问题
2. 检测Docker安装失败并提供恢复方案
3. 检测mihomo镜像拉取失败，并提供备选方案
4. 检测配置文件格式错误，提供修复建议
5. 记录详细错误日志，便于故障排除
6. 每一步操作添加超时机制，避免长时间卡死

### 网络接口检测

- 自动检测主要网络接口（可能是eth0、ens33、enp0s3等不同命名）
- 不能硬编码使用`enp0s18`这样的固定接口名称
- 使用`ip route | grep default`等命令获取实际使用的出口网卡
- 在创建macvlan接口时使用检测到的实际网卡名称


### docker的macvlan网络配置

这里先要开启主网络接口的混杂模式，再设置一个基于当前网段的macvlan。
- 网卡的混杂模式要防止重启后失效；
- 当前网段和路由是通过主网卡的ip得出的，网段和路由用于构建docker的macvlan

### 配置文件设置

在配置config.yaml时，有两种方式：

1. **机场用户**：
   - 只需要输入订阅链接
   - 配置脚本会取其proxies节点及以下内容，替换 “config配置模版.yaml” 里proxies节点及以下内容，形成新的配置文件
   - 用户可以更新机场clash/mihomo配置文件，逻辑也是仅提供订阅链接;
   - 脚本需验证订阅链接有效性，并处理可能的超时或无效链接情况

2. **VPS用户**：
   - 需要用户参考配置模版，自行修改代理部份，一般仅proxies节点以下才需要修改
   - 需引导用户用什么工具，如何手动编辑和更新mihomo配置文件
   - 提供nano/vim基本操作指南，或推荐使用WinSCP等工具远程编辑

#### 配置文件模板位置

配置模板应位于与引导脚本同目录的`config配置模版.yaml`文件中。脚本需验证该文件存在，如不存在则从备用位置下载或提示用户。

### UI包设置

UI包需要从 https://github.com/MetaCubeX/metacubexd/releases 中获取最新版本并下载解压到 `/etc/mihomo/ui`：

1. 脚本应动态检测最新版本号，而不是硬编码`v1.187.1`
2. 使用`curl -s https://api.github.com/repos/MetaCubeX/metacubexd/releases/latest`获取最新版本
3. 下载最新版本的`compressed-dist.tgz`文件
4. 提供下载失败的备选方案（如本地上传）

### 安装docker版mihomo

通过docker方式拉取mihomo镜像即可完成，但这里需要依赖科学上网环境，如果拉取不到，要告知用户通过手动方式上传mihomo镜像文件后再安装。如何通过电脑拉取和保存对应的镜像包要告知用户，如何在代理机里通过上传的镜像包也要告知用户。
- 如果用户选择了手动上传镜像包的方式，则状态要被记录下来，以便与再次运行引导脚本时，引导用户完成基于镜像文件方式进行mihomo安装。

#### 离线安装指导

对于无法直接拉取镜像的情况，提供以下离线安装步骤：

1. **在有科学上网环境的电脑上拉取并保存镜像**：
   ```bash
   docker pull metacubex/mihomo:latest
   docker save metacubex/mihomo:latest -o mihomo-image.tar
   ```
   - 确保文件名为`mihomo-image.tar`以便脚本识别
   - 文件大小约为30-40MB，请确认保存成功

2. **将镜像传输到代理机器**：
   - 使用SCP方式（Linux/Mac用户）：
   ```bash
      # 确保目标目录存在
      ssh user@代理机IP "mkdir -p /opt/mihomo"
      
      # 上传镜像文件
      scp mihomo-image.tar user@代理机IP:/opt/mihomo/
      ```
   - 如果显示"no space left on device"，清理磁盘空间：`docker system prune -a`
   - 确保Docker服务正常运行：`systemctl status docker`

### 打通宿主机和docker的网络

docker版的mihomo安装完成后，还有个常遇到的问题要解决，docker和宿主机网络不通的问题，这个要解决掉，并告知用户如何相互访问。

核心原理是通过macvlan上一个接口桥接docker和宿主机。例如，假设mihomo的ip是192.168.88.4，设置一个名为veth5 的macvlan接口， 并分配一个接口ip 192.168.88.5， 然后让宿主机以veth5接口为路由访问docker版本mihomo; 其实就是搞一个内奸veth5，他和物理网卡是配对的，门外和门里的关系，猫和咪咪的关系；通过他来脚踩两只船，让宿主机能访问到mihomo，反过来他又代表着宿主机，从而mihomo也能通过这个ip连接到宿主机上；

详细参考 https://rehtt.com/index.php/archives/236/

脚本参考（需根据实际网络接口动态调整）：

```bash
# 检测主网络接口名称
MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)

# 创建macvlan接口
ip link add veth5 link $MAIN_INTERFACE type macvlan mode bridge

# 为接口分配IP地址
ip addr add 192.168.88.5 dev veth5

# 启用接口
ip link set veth5 up

# 添加路由规则
ip route add 192.168.88.4 dev veth5
```

#### 持久化网络配置

为确保系统重启后网络配置依然有效，添加以下功能：
- 在`/etc/network/interfaces.d/`或`/etc/systemd/network/`中添加永久配置
- 创建systemd服务确保启动时配置macvlan接口
- 添加网络检测功能，定期验证连通性并自动修复

**重要IP地址说明：**
- 宿主机访问mihomo的IP： 用户指定的IP（例如192.168.88.4）
- mihomo访问宿主机的IP： 自动分配的接口IP（例如192.168.88.5）

### RouterOS配置脚本

生成的RouterOS配置脚本包含必要RouterOS命令的纯文本文件，用户可以手动复制粘贴这些命令到RouterOS终端执行。

- 输出为标准的RouterOS命令格式(.rsc)，方便用户直接复制
- 不依赖SSH连接，避免额外的连接复杂性和安装sshpass等依赖
- 提供详细的说明，告知用户如何在RouterOS的Terminal或WebFig终端中执行这些命令
- 核心功能保持不变：配置DNS指向mihomo的IP，以及设置198.18.0.0/16 fake-ip网段的路由指向mihomo

脚本应生成如下格式的命令文本，保存为易于识别的文件（如`routeros_commands.rsc`）：

```
# 添加DNS设置
/ip dns set servers=192.168.88.4

# 添加fake-ip路由
/ip route add dst-address=198.18.0.0/16 gateway=192.168.88.4 comment="mihomo fake-ip route"
```

#### 使用指南提示

脚本应提供以下几种使用指南：

1. **通过WebFig界面执行**：
   - 登录RouterOS的WebFig界面
   - 打开"Terminal"选项
   - 复制并粘贴所有命令
   - 按Enter执行

2. **通过WinBox执行**：
   - 打开WinBox连接到RouterOS
   - 点击"New Terminal"按钮
   - 复制并粘贴所有命令
   - 按Enter执行
   
3. **通过SSH终端执行**（可选）：
   - 在命令行中使用`ssh user@router_ip`连接到RouterOS
   - 粘贴所有命令并按Enter执行

#### 非RouterOS路由器配置指南

对于使用其他路由器系统的用户，脚本需提供通用配置指导：

1. **OpenWrt路由器**：
   - 通过LuCI界面设置DNS服务器指向mihomo的IP
   - 添加静态路由，将198.18.0.0/16网段指向mihomo
   
2. **普通家用路由器**：
   - 通过DHCP设置自定义DNS服务器为mihomo的IP
   - 如果支持静态路由，添加198.18.0.0/16网段路由
   - 如不支持，建议用户直接在电脑上手动设置代理

3. **软路由/其他系统**：
   - 提供详细的命令行或GUI操作步骤

### 安装成功验证

脚本需要在安装完成后进行以下验证：

1. 检查Docker和mihomo服务状态
   ```bash
   docker ps | grep mihomo
   ```

2. 验证网络连通性
   ```bash
   ping -c 3 $MIHOMO_IP
   ```

3. 测试DNS解析
   ```bash
   dig @$MIHOMO_IP google.com
   ```

4. 检查mihomo配置有效性
   ```bash
   curl -s -o /dev/null -w "%{http_code}" http://$MIHOMO_IP:9090/
   ```

5. 提供故障排除指南与常见问题解答

### 更新机制

脚本需要包含更新机制，使用户可以：

1. 更新mihomo本身：
   ```bash
   docker pull metacubex/mihomo:latest
   # 重启服务
   docker stop mihomo
   docker rm mihomo
   # 使用新的镜像启动服务
   ```

2. 更新UI界面：
   - 自动检测最新UI版本
   - 提供一键更新选项

3. 更新配置文件：
   - 对于使用订阅的用户，提供重新获取最新订阅配置选项
   - 对于自定义配置的用户，提供配置文件备份恢复功能

### 特别要求

1. 严格遵从需求说明，修改时不要把以有的功能改没了，确保代码质量和稳定性。
2. 脚本应具备良好的兼容性，以适应不同的网络环境和系统配置。
3. 提供清晰的日志和调试信息，便于排查问题。
4. 所有敏感操作前提供确认步骤，防止误操作导致系统问题。
5. 性能优化：确保脚本执行高效，避免不必要的系统资源消耗。
6. 基于以上需求，生成引导脚本，名称为 "mihomo.sh", 注意其他脚本是通过引导脚本运行期间生成的，只需要生成引导脚本即可。
6. 生成的脚本和配置文件要放到引导脚本同目录下的独立文件夹里，而不是和引导脚本放到一个跟目录里。
7. 如果用户磁盘不足导致无法安装mihomo，则要检测和提醒用户。
8. 不要安装一些用不到的依赖包，参考脚本例子，只安装必要的包；
9. 新生成的配置文件必须严格按照config.yaml配置模版来，不要随意修改内容，特别是 “proxies” 节点以上的部份。


### 优化点
1. 第一步完成后的引导脚本有点重复，整合为一套引导界面，而且表述要更加清晰易懂；
2. 如果重新运行脚本来配置代理机，如果已经安装了mihomo，则提示用户已配置，如继续则会删除原有的安装新的mihomo。但挂载沿用 "/etc/mihomno" 下的，无需重新配置。
3. 通过订阅连接生成配置文件时需要先对订阅连接做解码，在转化为配置文件，并与配置文件模版对照，用机场配置文件 “proxies” 节点及以下部分替换配置模版 “proxies” 及以下部分。
4. 不要试图通过修改配置脚本来解决问题，而是去修改引导脚本，这才是根本。
5. 重复安装mihomo时，静默使用原来的配置文件，静默重新安装ui包，静默卸载和重新安装mihomo，不要再提示用户了，直接执行即可。静默直接从docker拉取镜像，只有拉取不成功时再提示使用本地镜像。
6. yaml配置文件这里简化一下算了，仅提供配置文件的模版，用户需自行修改配置文件。引导脚本不区分机场还是VPS类型，告知用户如何修改和更新配置文件即可，主菜单里提供一个重启mihomo服务的功能即可，便于修改配置文件后重启mihomo服务，使得配置生效，但要根据日志信息，告知用户配置子文件那里不对，应该如何修改，要检测mihomo有没有正常运行。原来的更新配置文件的功能删掉。



