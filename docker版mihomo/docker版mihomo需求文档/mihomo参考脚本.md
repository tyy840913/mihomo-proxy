# 一键安装Mihomo（docker版），debian秒变代理机

## 在Debian里安装Docker

后面用到的包可以在这里一并安装，包含但不限于docker包，如unzip，但不要装一些没用的包：

```bash
apt update && upgrade && apt install docker.io
```

## 配置Docker网络

设置网卡混杂模式：

```bash
# 设置网卡混杂模式，需要先识别物理且有链接的网卡，然后基于该网卡
ip link set enp0s18 promisc on
```

## Docker Macvlan设置

创建桥接网络：

```bash
# 先基于网卡的ip，得到局域网网段和网关，然后基于这两个信息来设置用于docker的桥接网络
docker network create -d macvlan --subnet=192.168.88.0/24 --gateway=192.168.88.1 -o parent=enp0s18 mnet
```

## 准备Mihomo配置文件

1. 创建用来存放Mihomo相关配置文件的目录：
   ```bash
   mkdir -p /etc/mihomo
   ```

2. 准备Mihomo配置文件：
   - 如果是基于机场，用户需要提供订阅链接，且后继也能通过链接更新订阅
   - 如果基于VPS的用户需要基于模版自己修改配置文件
   - 配置文件模版的 "proxies" 节点以上的部份不要动，不管是机场还是VPS用户，只需要修改代理节点以下部份即可

3. 下载UI包到挂载目录：
   ```bash
   mkdir -p /etc/mihomo/ui
   wget https://github.com/MetaCubeX/metacubexd/releases/download/v1.187.1/compressed-dist.tgz
   tar -xzf compressed-dist.tgz -C /etc/mihomo/ui
   ```

## 拉取Mihomo镜像并运行容器

```bash
docker run -d --privileged \
  --name=mihomo --restart=always \
  --network mnet --ip 192.168.88.4 \
  -v /etc/mihomo:/root/.config/mihomo/ \
  metacubex/mihomo:latest
```

## 容器网络配置，解决容器访问宿主机的问题

配置宿主机和容器间的通信：

```bash
# 创建macvlan接口
ip link add veth5 link enp0s18 type macvlan mode bridge

# 为接口分配IP地址
ip addr add 192.168.88.7 dev veth5

# 启用接口
ip link set veth5 up

# 添加路由规则
ip route add 192.168.88.4 dev veth5
```

**重要IP地址说明：**
- 宿主机访问mihomo的IP： 192.168.88.4
- mihomo访问宿主机的IP： 192.168.88.7

## 设置RouterOS里的DNS和路由

需要通过SSH登录RouterOS，然后通过脚本设置这两项：

1. DNS设置为Mihomo
2. 198.18.0.1/16 的路由指向Mihomo
