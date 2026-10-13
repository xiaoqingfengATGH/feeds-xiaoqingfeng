# HomeLede Feed - xiaoqingfeng - 说明
![visits since 2024.07.23](https://views.whatilearened.today/views/github/xiaoqingfengATGH/deplives.svg)


本Feed中包含内容：
+ 由HomeLede团队原创的软件包
+ 第三方软件包，由HomeLede团队定制后的版本
+ 第三方软件包，固件BASE代码中不包含或者版本与固件代码库及各个Feed中不同的

## HomeDirect（家庭服务直连）

HomeDirect以家庭Web HTTPS服务为中心，最终设计采用独立专用Nginx直接IPv4/IPv6监听，单服务IPv4/IPv6/hostname后端确定IPv4优先、不重放写请求。正常发布持续到停用，临时限时可选，UPnP有限网关租约受控续租。默认未发布、Save不启动；明确开启后精确owned TCP INPUT，独立开机恢复默认关。主/旁IPv4固定转发优先，再授权UPnP/STUN；IPv6路由和入站许可非DNAT。残留unknown不fallback/危险端口复用，HomeTunnel不动，真实ACME/DDNS-Go复用、Cloudflare可选。

本轮只最终完整设计，尚未实现新双栈/生命周期/adapter或生产集成。旧120秒仅实验引擎约束非产品上限，IPv6首版本地功能必验、真实外网可后验且标未验证。见[需求](REQUIREMENTS.md)、[完整设计](docs/homedirect-product-design.md)、[审查清单](docs/homedirect-design-review-checklist.md)、[续跑历史证据](docs/HOMESTUN-RESUME.md)。无代码/设备操作或提交。

## 重点功能说明：
+ 端口转发工具——HomeRedirect（原创）。可以在有Docker环境下支持NAT环回。
+ 家庭VPN接入——HomeConnect（原创）。基于L2TP over IPSec协议，本协议目前被最广泛支持的终端直接支持，Windows、mac、ios、Android都可以在不安装额外软件情况下，直接使用本VPN方案。
+ dnsmasq加速程序——dnsmasq-china-list（原创）。引入Github上同名项目中的代码实现国内域名访问加速。支持自动更新。
+ DNS方案，使用AdGuardHome，mosdns实现去广告+抗污染+优化访问速度。
  + AdGuardHome作为家庭网络路由的主DNS，通过挂载Anti-AD等等脚本实现广告过滤，可实现国内外主流视频网站去播放前广告，网页去广告等功能。
  + dnsmasq作为AdGuardHome上游，完成host解析，以及兼容多种其他插件功能
  + mosdns作为dnsmasq的上游DNS，解决DNS污染，实现国内域名国内解析，国外域名（受干扰域名）国外解析。
  
  去广告使用说明：https://www.cnblogs.com/zlAurora/p/12433266.html
  
+ 提供基于Web的百度网盘下载工具。

+ 提供视觉效果较好的主题。

+ 支持UPnP。目前Lede代码中集成的mwan3和miniupnpd有冲突，mwan3启动时，miniupnpd会失效，导致BitComet、Emule，PS4等设备无法使用upnp功能。挑选了无冲突的mwan3以及miniupnpd，经过测试，2个软件包可以同时工作。

+ Beam（Docker版本）的Luci程序。

# HomeLede固件

+ 代码仓库：https://github.com/xiaoqingfengATGH/HomeLede
+ 固件使用说明：https://github.com/xiaoqingfengATGH/HomeLede/wiki
+ 固件下载：https://github.com/xiaoqingfengATGH/HomeLede/wiki/HomeLede%E7%89%88%E6%9C%AC%E5%8F%91%E5%B8%83
