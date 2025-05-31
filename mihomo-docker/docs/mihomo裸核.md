# PVE下，代理机里直接跑mihomo


1. 新建一个mihomo-setup.sh的脚本，引导用户完成debian/ubuntun代理机中直接安装mihomo。这种方式无需docker，直接跑原生mihomo服务。
   1. 能一键完成mihomo安装
   2. 能检测mihomo运行状态
   3. 能重启mihomo
   4. 能关停mihomo服务
   5. 能启动mihomo服务
   6. 引导用户如何使用mihomo
      1. 方法1，DNS设置为代理机ip，198.18.0.1/16 的路由指向代理机ip  
      2. 方法2，讲代理机设置为网关，实现透明代理；
   7. 能卸载mihomo
2. 这个脚本主要是给小白用，傻瓜化菜单操作就能搞定。运行在代理机里，代理机一般是安装了debian/ubuntu的虚拟机。
   1. 用户通过从github上下载这个脚本，在代理机里执行；
   2. mihomo的yaml配置模版需要先下载到mihomo运行目录；
3. 安装步骤如下
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
   4. 复制files/config.yaml 到 /etc/mihomo，搞定配置文件
   5. 设置开机mihomo自动启动；
   6. 引导用户下一步操作，依据主网卡获得代理机ip，配置路由和dns。
   
   


