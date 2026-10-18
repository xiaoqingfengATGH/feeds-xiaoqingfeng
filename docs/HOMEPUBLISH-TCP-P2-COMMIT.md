# P2 提交边界与父代理最终检查

本次提交配置/UI/迁移公共链路和已部署成果，不表示P3发布数据面完成。不合并、不推送、不启动P3。

## 已验证切片
官方安装菜单首次无配置初始化、能力过滤网络候选（当前只有LAN）、IPv4/IPv6/双栈控件、四种服务原生弹窗、稳定ID、dirty/cancel、迁移预览确认、真实CLI/native私有journal Save/readback、跨页字段保留、并发revision冲突/reset、证书表结构与使用关系、375px布局。具体历史证据见P2-PROGRESS及部署清单。模拟第二网络/库存消失是浏览器响应fixture，不是实际接口变更。

## 父代理提交前复跑的未闭环项
命令：`HP_CASE=extended node luci-app-homepublish/tests/tcp-ingress-device-probe.cjs`
实际 exit 1。前置实机和扩展断言通过，最后 tcp-ingress-device-extended.cjs:59 “空库存 + 无saved_config”fixture断言失败：网络option实际值lan，预期空字符串。之前子任务自报连续两次exit0不能代替本次结果。此项可能涉及route重新渲染/response模拟时序或产品逻辑，尚未定因，必须保留并修复，不能宣称最终全套GREEN。没有为通过而删除断言。

真实无配置官方页面+实际库存的初始化与过滤已有RED/GREEN；本次失败不能直接归因到真实无配置页面，也不能因此忽略。

## P2 回归夹具修复后的父代理复验
最终 harness 改为单一 RPC dispatcher，通过状态切换响应fixture，不再在新视图请求期间反复 unrouteAll/route；同时等待官方 View.__init__ 完整渲染 Promise，并验证唯一新视图及实际完整RPC响应集合。只修复加载等待仍曾失败；失败时新视图已经渲染但fixture变换次数为零，故根因是测试拦截生命周期，不是已证明的业务地址过滤故障。原空选项、禁用、文案及禁止写入断言全部保留。

父代理独立完整运行两次 `HP_CASE=extended node luci-app-homepublish/tests/tcp-ingress-device-probe.cjs`，均实际 exit0；日志为 docs/evidence/p2-dispatcher-final.log 和 p2-dispatcher-repeat.log。本项已按最终修改复验闭环，不改写上文提交时真实失败记录。未修改业务源码或安装UI；P3设备隔离目录未触碰。

## 延后验收边界
受限非root账号ACL隔离未实测。root通配权限成功不等于受限账户ACL通过。下一阶段为P3协议数据面与运行时集成：四方式路由、IPv6→IPv4、未知流量拒绝、受控Start/Apply/Stop与清理；阶段详细范围以原计划为准。公网可达性、发布防火墙/认证/路由修改不在本次提交或既有仅部署授权内。

## 设备保留
新版永久部署，不恢复旧静态资源；live配置未Save/迁移/Start。上次父读回revision0、intent7、disabled/manual_stop_latch=true、stopped/cleanup confirmed。备份 /root/homepublish-backups/20261015-165134。
