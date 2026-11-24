# 同类客户端调研与许可边界

核查日期：2026-10-29。资料来自 App Store 商品页和源码仓库的 README / 许可证页面，属于开发者自述，没有安装逐项实测。只借鉴通用交互模式，不复制任何代码、图标、截图或文案。

| 应用 | 来源与已声明功能 | Gitlabio 借鉴的交互 | 许可结论 |
| --- | --- | --- | --- |
| GIT-Worker（Jan Hendrik Ellermann，iOS 17+，免费） | [App Store](https://apps.apple.com/us/app/git-worker/id6811055360)：gitlab.com 与自建实例（含自签证书）、项目/组/分支/标签/提交与差异、MR 阅读与讨论、按指派/创建者筛选 Issue、流水线与作业日志、触发流水线、待办、跨项目搜索、推送通知、AI 助手 | 自签实例作为一等场景；Issue 的“指派给我 / 我创建的”筛选；全局搜索入口 | 闭源，未见许可证。不复制 |
| iGit: Git & PRs（Felix Beuving，iOS 26+） | [App Store](https://apps.apple.com/app/id6773623548)：HTTPS 克隆（可取消的进度）、commit / pull / push、分支创建/切换/删除、提交图、编辑工作副本文件、PR 打开/合并/关闭/重开、GitHub / GitLab / Gitea 多账户、令牌存钥匙串 | 克隆进度可取消、提交图（M3 本地 Git 时采用）；多账户切换显示实例域名 | 闭源，未见许可证。不复制。另有用户反映 SHA-256 对象格式兼容问题，M3 测试计划需覆盖 |
| GitSync（ViscousPot） | [源码](https://github.com/ViscousPot/GitSync)：Flutter + Rust（git2-rs），Android 5+ / iOS 13+；clone / fetch / pull / stage / commit / push、文件浏览与编辑、差异、分支、多远端、冲突处理、定时与快捷方式触发同步、断网恢复后自动重试 | 定时 / 快捷指令触发同步，失败后在网络恢复时重试（用于 M3 后台同步设计） | GPL-3.0。Gitlabio 不移植其 Flutter / Rust 代码，只参考行为 |
| GLab: GitLab Code Review（Emil Karimov，iOS 18+） | [App Store](https://apps.apple.com/fr/app/glab-gitlab-code-review/id6772132185)：可定制首页模块（待审查、MR、Issue、待办、流水线）、带语法高亮的 diff、行内讨论、应用建议、批准/合并/变基、Issue 看板、实时流水线、运行/重试/取消、文件 blame、多实例、离线缓存、小组件、Siri 快捷指令、Apple Watch | 首页“待我审查 / 我的 MR / 我的 Issue / 待办”分区；列表滑动操作（完成待办、删除分支）；MR 内批准与合并放在底部操作栏 | 闭源，订阅制，未见许可证。不复制 |
| GLab（GitLab 官方 CLI） | [源码](https://gitlab.com/gitlab-org/cli)、[MIT 许可证](https://gitlab.com/gitlab-org/cli/-/raw/main/LICENSE)：Issue / MR / CI、gitlab.com 与自建实例认证 | 写操作明确区分、分页与错误行为；CI 作业日志按段落折叠 | MIT。仅作行为参考，没有引入源码 |

同名提醒：用户提到的“GLab”可能指 GitLab 官方 CLI，也可能指 App Store 上的 iOS 应用 “GLab: GitLab Code Review”，两者都已列出。

## Gitlabio 的取舍

- **原生优先**：iOS 用 SwiftUI，iOS 26 使用系统 Liquid Glass（`glassEffect`、`GlassEffectContainer`、玻璃按钮、可收起的标签栏），iOS 18–25 回退为材质效果。Android 用 Kotlin + Compose Material 3。不用 Flutter，也不用 KMP 生成界面。
- **远程提交与本地 Git 分开**：M2 的“变更篮”通过 Commits API 把多个文件的增删改一次性提交（真实提交，但不是本地仓库）。本地克隆 / 拉取 / 推送放在 M3：iOS 计划用 libgit2（GPLv2 附 linking exception，允许静态链接），Android 用 JGit（EDL）。
- **自签证书**：按实例信任。用户可以核对指纹后固定服务器证书，或导入组织 CA；仍校验主机名，不提供“忽略证书错误”的开关。
- **通知**：GitLab 不向第三方客户端推送。Gitlabio 用后台刷新轮询待办并发本地通知，运行时间由系统决定。如需真正推送，需要自建中转服务（不在当前范围）。

## 接口依据

- [REST 认证](https://docs.gitlab.com/api/rest/authentication/)、[令牌自检](https://docs.gitlab.com/api/personal_access_tokens/)
- [Commits API（多文件提交）](https://docs.gitlab.com/api/commits/)、[Repository Files](https://docs.gitlab.com/api/repository_files/)、[Branches](https://docs.gitlab.com/api/branches/)
- [Merge requests](https://docs.gitlab.com/api/merge_requests/)、[MR approvals](https://docs.gitlab.com/api/merge_request_approvals/)、[Discussions](https://docs.gitlab.com/api/discussions/)
- [Pipelines](https://docs.gitlab.com/api/pipelines/)、[Jobs](https://docs.gitlab.com/api/jobs/)、[To-do](https://docs.gitlab.com/api/todos/)
- [Apple：在自定义视图中应用 Liquid Glass](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
