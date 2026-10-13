# LuCI 24.10 fixture 来源

`luci-24.10.mk` 是 LuCI `openwrt-24.10` 分支 `luci.mk` 的原版宏快照；本地文件 SHA-256（原始字节，Python hashlib 计算）：

`bc1a97fb6c3b4fef065227c6d1530ee580f0af3966d36a967fbca2da1c7000ac`

来源：https://raw.githubusercontent.com/openwrt/luci/openwrt-24.10/luci.mk

保留原始 The LuCI Team 2008–2015 版权与 Apache-2.0 头。许可证正文：https://www.apache.org/licenses/LICENSE-2.0 。仅作测试第三方宏 fixture，不将其许可证改写为应用许可证；无源码修改。来源是可变分支 URL，未记录上游 commit，复现以本地快照和 SHA-256 为准；本次收尾网络抓取连接 reset，未重新确认当前远端字节相同。

测试在 Linux/WSL 运行真实 LuCI prepare/install 宏，周边 buildroot 仍为最小桩；不是 SDK/IPK 构建或目标运行验收。应用设置禁用 minify，全局启用时以失败替身检查压缩器未被调用，并逐字节比较安装资源。
