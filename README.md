# HomeLede Feed - xiaoqingfeng - 说明
本Feed中包含内容：
+ 由HomeLede团队原创的软件包
+ 第三方软件包，由HomeLede团队定制后的版本
+ 第三方软件包，固件BASE代码中不包含或者版本与固件代码库及各个Feed中不同的

## 重点功能说明：
+ 端口转发工具——HomeRedirect（原创）。可以在有Docker环境下支持NAT环回。
+ dnsmasq加速程序——dnsmasq-china-list（原创）。引入Github上同名项目中的代码实现国内域名访问加速。支持自动更新。
+ 支持UPnP。目前Lede代码中集成的mwan3和miniupnpd有冲突，mwan3启动时，miniupnpd会失效，导致BitComet、Emule，PS4等设备无法使用upnp功能。挑选了无冲突的mwan3以及miniupnpd，经过测试，2个软件包可以同时工作。
  
+ 支持去广告套件。采用DNS去广告方案，使用AdGuardHome，chinadns-ng，smart-dns，dnscrypt-proxy组成三级去广告套件。实现去广告+抗污染+优化访问速度。
  + AdGuardHome作为家庭网络路由的主DNS，通过挂载Anti-AD等等脚本实现广告过滤，可实现国内外主流视频网站去播放前广告，网页去广告等功能。
  + chinadns-ng作为AdGuardHome的上游DNS，解决DNS污染，实现国内域名国内解析，国外域名（受干扰域名）国外解析。
  + smartdns作为chinadns-ng的国内上游DNS，维护国内组DNS服务器，对同一个域名解析，通过对多个DNS返回结果进行测速，保证返回最快响应IP。
  + dnscrypt-proxys作为chinadns-ng的可信上游DNS，维护海外组DNS服务器。

  AdGuardHome监听路由127.0.0.1:7913，上游指向 chinadns-ng 127.0.0.1:5053，chinadns-ng 国内DNS指向 smartdns 主DNS 0.0.0.0:6053，chinadns-ng 可信DNS指向 dnscrypt-proxy 0.0.0.0:7053。
  
  去广告使用说明：https://www.cnblogs.com/zlAurora/p/12433266.html
  
+ 提供基于Web的百度网盘下载工具。

+ 提供视觉效果较好的主题。

# HomeLede固件

+ 代码仓库：https://github.com/xiaoqingfengATGH/HomeLede
+ 固件使用说明：https://github.com/xiaoqingfengATGH/HomeLede/wiki
+ 固件下载：https://github.com/xiaoqingfengATGH/HomeLede/wiki/HomeLede%E7%89%88%E6%9C%AC%E5%8F%91%E5%B8%83
