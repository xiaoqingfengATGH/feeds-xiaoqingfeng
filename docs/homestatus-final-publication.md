# HomeStatus r4 配对发布整合

本次以 `origin/master` 为基线，将已验收的应用提交 `4fad6b2a9332c04d84551ff5f964f790a5152ebb` 本地 squash 整合，不创建 PR。

- 保留主线独立新增的 `homelede-keyring` 包及 `docs/packages.md` 登记，不回退并发变更。
- 发布内容包括 phase 1 驾驶舱资源归属迁移、LAN 概览与独立设备面板、同排自然等高及全局语义色协作修正。
- 包版本保持 `1.0.0-r4`；配对主题保持 `2.0-ucode-r12`，主题构建源提交为 `f9ecbac2908f5a409d0de30fa064f8f3d7cea8f9`。
- 应用包全部 24 个跟踪文件与固定构建提交及源归档逐字节一致；实际 IPK 10 个源映射安装文件逐字节一致。主题包 451 个跟踪文件一致，IPK 405 个源映射安装文件一致，6 个模板仅应用真实 SDK SubstituteVersion。
- 整合后应用 Node 测试 27/27 通过；主题 POSIX 回归 6/6 通过；生成器显式使用整合应用 CSS，`--check` 通过；两仓 `git diff --cached --check` 通过。
- 新增行扫描未发现私钥、GitHub/AWS 凭证或长凭据赋值。测试内网 IP/MAC 属合成 fixture；既有审计 JSON 是样式/状态矩阵，不是设备或会话导出。历史验证文档中的工作路径为复现上下文，本发布说明不新增机器路径、设备日志或凭据。

IPK SHA-256：

- 应用：`8695de8b3ea7be69726c78ecd280412d685958491d5362faee68178ec4dce4cc`
- 主题：`51d245a7d8e51e722fcab53fa4adae40b0c3413dc0d4fcfabc76323e23de2697`

最终远端提交 SHA 在发布产物目录的 `PUBLICATION-RECORD.json` / `PUBLICATION-RECORD.md` 记录；本轮不重新构建、不重新部署、不创建 tag 或 GitHub Release，不将 IPK 二进制入仓。
