# HomeLede Feed - xiaoqingfeng - 说明
![visits since 2024.07.23](https://views.whatilearened.today/views/github/xiaoqingfengATGH/deplives.svg)


本Feed中包含内容：
+ 由HomeLede团队原创的软件包
+ 第三方软件包，由HomeLede团队定制后的版本
+ 第三方软件包，固件BASE代码中不包含或者版本与固件代码库及各个Feed中不同的

## HomePublish（家庭服务直连）

HomePublish以家庭Web HTTPS服务为中心，最终设计采用独立专用Nginx直接IPv4/IPv6监听，单服务IPv4/IPv6/hostname后端确定IPv4优先、不重放写请求。正常发布持续到停用，临时限时可选，UPnP有限网关租约受控续租。默认未发布、Save不启动；明确开启后精确owned TCP INPUT，独立开机恢复默认关。主/旁IPv4固定转发优先，再授权UPnP/STUN；IPv6路由和入站许可非DNAT。残留unknown不fallback/危险端口复用，HomeTunnel不动，真实ACME/DDNS-Go复用、Cloudflare可选。

## 重点功能说明：
+ 端口转发工具——HomeRedirect（原创）。可以在有Docker环境下支持NAT环回。
+ 家庭VPN接入——HomeConnect（原创）。基于L2TP over IPSec协议，本协议目前被最广泛支持的终端直接支持，Windows、mac、ios、Android都可以在不安装额外软件情况下，直接使用本VPN方案。

# HomeLede固件

+ 代码仓库：https://github.com/xiaoqingfengATGH/HomeLede
+ 固件使用说明：https://github.com/xiaoqingfengATGH/HomeLede/wiki
+ 固件下载：https://github.com/xiaoqingfengATGH/HomeLede/wiki/HomeLede%E7%89%88%E6%9C%AC%E5%8F%91%E5%B8%83
