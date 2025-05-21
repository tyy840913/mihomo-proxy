# ==== Mihomo RouterOS 配置命令 ====
# 请将以下命令复制到RouterOS的Terminal中执行
# 您可以通过WebFig、WinBox或SSH访问RouterOS的Terminal

# 设置DNS服务器指向Mihomo
/ip dns set servers=192.168.88.4

# 添加fake-ip路由规则
/ip route add dst-address=198.18.0.0/16 gateway=192.168.88.4 comment="mihomo fake-ip route"
