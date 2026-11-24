# Gitlabio 开发计划

更新：2026-10-29。目标：功能完整、外观现代的 gitlab.com / 自建 GitLab 原生客户端，iOS 与 Android 双端。

## 架构

- **iOS 18+**：SwiftUI，`@Observable` 状态，每个标签页一个 `NavigationStack`，所有页面通过 `Route` 枚举导航（通知、待办、搜索都能直接跳转）。iOS 26 使用 Liquid Glass，`Design/Glass.swift` 统一处理版本回退和“降低透明度”。
- **GitLabCore**（Swift 包，Swift 6 严格并发）：`GitLabTransport` 抽象（实际网络 / 演示数据 / 测试替身）、类型化接口、`TrustPolicy`、解析器。无第三方依赖。
- **Android 8+**：Kotlin + Compose Material 3，`:core` 为纯 JVM API 客户端（OkHttp + kotlinx.serialization），`:app` 为界面。
- **不用 KMP**：两端界面都必须原生；共享的部分主要是 REST 调用，用 `contracts/` 里的样例保证两端行为一致，比引入 Kotlin/Native 构建链更划算。本地 Git 引擎两端各自有成熟库。

## 分期

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| M1 | 工程、CI、TestFlight 流水线、PAT 登录、基础浏览（Codex 完成） | 完成 |
| M2 iOS | 界面重写；首页、项目、代码、变更篮多文件提交、提交与分支、MR 完整审查（批准、合并、行内评论、解决讨论）、Issue 编辑、流水线图与实时日志、收件箱、搜索、多账户、自签证书、后台通知、演示模式、截图测试 | 已实现，CI 验证中 |
| M2 Android | Compose 重写到与 iOS M2 对齐，动态取色、自适应导航、证书固定、WorkManager 通知、截图测试 | 进行中 |
| M3 | 本地 Git（libgit2 / JGit）：HTTPS 克隆（可取消进度）、拉取、推送、暂存、提交图、冲突处理、SHA-256 仓库；OAuth 2 PKCE；Issue 看板；MR 审查草稿批量提交；文件 blame；离线缓存 | 计划 |
| M4 | 小组件、流水线实时活动、App Intents / 快捷指令、iPad 并排 diff、Android 发布签名与商店上架 | 计划 |

## 验收标准

- 本机：`scripts/check-swift-core.sh` 全部通过；`scripts/typecheck-app-macos.sh` 通过。
- CI：`apple` 与 `android` 任务通过；截图产物覆盖主要页面的深浅色，经人工检查。
- TestFlight：新构建处理为 VALID 并在内部组 `Gitlabio TF` 中可安装。
- 真机：用自己的令牌登录 git.routeforge.zone，完成浏览代码、编辑并提交、查看 MR 差异和评论、重试作业。

## 风险

- 本机没有 Xcode，iOS 编译和截图只能在 CI 上进行。对策：核心逻辑放在本机可测的包里，应用代码先用 macOS SDK 类型检查。
- 自签证书在 ATS 下使用自定义信任，需要在真实自签实例上确认。
- 通知依赖后台刷新，iOS 不保证及时运行；真正的推送需要自建中转服务。
- GitLab 版本差异：`/personal_access_tokens/self`（15.5+）、`detailed_merge_status`（15.6+）等在旧版本上缺失时界面会降级显示。
- libgit2 体积与构建时间较大，M3 单独评估。
