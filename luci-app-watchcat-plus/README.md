# luci-app-watchcat-plus
luci-app-watchcat-plus 由官方js版本的[luci-app-watchcat](https://github.com/openwrt/luci/tree/master/applications/luci-app-watchcat)移植，加入日志查看，适用于luci lua版本的openwrt分支。
需要搭配官方最新版本[watchcat](https://github.com/openwrt/packages/tree/master/utils/watchcat)使用

### 功能
- 定时重启模式
- Ping重启接口模式
- Ping重启系统模式
- Ping运行脚本模式

### 参数使用说明
https://openwrt.org/docs/guide-user/advanced/watchcat

### 编译
```shell
# 删除老版本watchcat
rm -rf feeds/packages/utils/watchcat
svn co https://github.com/openwrt/packages/trunk/utils/watchcat feeds/packages/utils/watchcat

git clone https://github.com/gngpp/luci-app-watchcat-plus.git package/luci-app-watchcat-plus
make menuconfig # choose LUCI -> Applications -> luci-app-watchcat-plus
make V=sc -j1
```
![image](https://user-images.githubusercontent.com/51810656/224473054-920784b1-bb87-4771-bcb5-3dd96d3778be.png)
