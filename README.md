# OpenWrt Feed 包说明
+ 基于家庭网络使用场景维护的软件包集合
+ 包含如下包：去广告套件，多拨，UPnP，皮肤等
+ 基于现有开源包，为改善集成使用便利性，对现有开源包做了一定的调整

## 功能说明：
+ 支持UPnP。目前Lede代码中集成的mwan3和miniupnpd有冲突，mwan3启动时，miniupnpd会失效，导致BitComet、Emule，PS4等设备无法使用upnp功能。挑选了无冲突的mwan3以及miniupnpd，经过测试，2个软件包可以同时工作。
  
+ 支持去广告套件。采用DNS去广告方案，使用AdGuardHome，chinadns-ng，smart-dns组成三级去广告套件。实现去广告+抗污染+优化访问速度。
  + AdGuardHome作为家庭网络路由的主DNS，通过挂载Anti-AD等等脚本实现广告过滤，可实现国内外主流视频网站去播放前广告，网页去广告等功能。
  + chinadns-ng作为AdGuardHome的上游DNS，解决DNS污染，实现国内域名国内解析，国外域名（受干扰域名）国外解析。
  + smartdns作为chinadns-ng的上游DNS，维护国内及国外两组DNS服务器，对同一个域名解析，通过对多个DNS返回结果进行测速，保证返回最快响应IP。

  AdGuardHome监听路由127.0.0.1:7913，上游-> chinadns-ng 127.0.0.1:5053，chinadns-ng 国内DNS指向 Smart DNS 主DNS 0.0.0.0:6053，chinadns-ng 可信DNS指向 Smart DNS 第二DNS 0.0.0.0:7053
  
  去广告套件三个组件已经全部升级最新版本。
  
+ 提供基于Web的百度网盘下载工具。

+ 提供视觉效果较好的opentomcat及opentomato皮肤。
