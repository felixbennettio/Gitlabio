# 验证记录

日期：2026-10-28。此记录区分代码实现、实际验证和外部阻塞。

## 已完成的实际检查

- 仓库已从指定 GitLab 克隆，基线为 `53411eb`，原有内容只有初始 README；未覆盖用户工作。
- 在 `feat/native-foundation` 分支分阶段提交计划、Swift 核心、SwiftUI 和 Compose 实现。
- 本机 Swift 6.4 / macOS Command Line Tools 编译并运行 CoreChecks，全部通过：不安全实例拒绝、根实例与子路径 API 地址、特殊字符与嵌套文件编码、分支 query、项目解码、正向与无效分页、401 / 403 / 409 / 429 / 302 错误、文件更新 last_commit_id / Base64 / branch、并发冲突可见、二进制与大小限制。
- SwiftUI 源文件语法解析通过（此项不是 iOS SDK 类型检查或应用构建）。
- Xcode 工程文件通过 plutil 检查；CI shell 和 Gradle Wrapper shell 语法检查通过。
- Gradle Wrapper JAR SHA-256 与官方校验和一致；发行包 SHA-256 已固定。
- Android API 核心在本机 JDK 17 / Gradle 8.9 下编译，两轮 Kotlin JVM 测试通过。最终轮包含令牌控制字符测试及 IO 线程修正，共 10 个测试，结果 BUILD SUCCESSFUL（1m 5s）。包含 TLS MockWebServer、根地址 / 子路径、分页、重定向不跟随、HTTP 错误、last_commit_id 冲突与文本限制。
- 最终修改后的 Swift CoreChecks 再次编译并全部通过（包含令牌控制字符拒绝）。
- GitLab 连接恢复后，分支已推送并创建[合并请求 !1](https://git.routeforge.zone/FelixBennett/gitlabio/-/merge_requests/1)。
- [Apple 任务 159](https://git.routeforge.zone/FelixBennett/gitlabio/-/jobs/159)：Xcode 26.6，9 个 XCTest 全部通过，模拟器与 arm64 iOS 设备完整构建成功。
- [Apple 任务 163](https://git.routeforge.zone/FelixBennett/gitlabio/-/jobs/163)：方向声明修正后再次通过 9 个 XCTest、双目标构建，JUnit 报告已保留。
- 原创 1024px RGB 无透明度应用图标已生成并检查；App Store Connect 发布助手已在本机编译通过。
- 已临时下载任务 163 的真实构建产物检查：Bundle ID 为 io.routeforge.gitlabio，版本 0.1.0，iPad 四个方向、加密声明、图标目录、隐私清单和 9 个通过的 JUnit 结果均正确；检查后下载已清理。
- [流水线 56](https://git.routeforge.zone/FelixBennett/gitlabio/-/pipelines/56)：Apple 任务 167 成功；Android 任务 166 完成 10 个核心测试、Compose 应用编译、unsigned APK 和 Lint，BUILD SUCCESSFUL（6m 20s）。
- [流水线 65](https://git.routeforge.zone/FelixBennett/gitlabio/-/pipelines/65)：缓存修复分支验证通过，正式报告共 19 个测试（Apple 9、Android 10），无失败、错误或跳过；Apple 模拟器与设备构建、Android APK 与 Lint 全部成功。
- [主分支流水线 66](https://git.routeforge.zone/FelixBennett/gitlabio/-/pipelines/66)：提交 `a1a8fdfcd15315f3543dd69f9bb4c3fc367e98ea` 的 Apple 任务 189（98 秒）与 Android 任务 188（176 秒）均成功。Android 任务直接保留 2,693 个有效缓存文件，0 个损坏项，验证了依赖跨任务复用。
- 已下载并检查主分支任务 188 的 Android 交付产物，ZIP 完整性与 10 个正式测试结果均通过；unsigned APK 为 16,578,488 字节，SHA-256 `1a70e24910d9cc35f472948fb761ac98c7c27b5a6940c89c412b451fc980ba05`。下载的临时压缩包已删除。
- [TestFlight 任务 190](https://git.routeforge.zone/FelixBennett/gitlabio/-/jobs/190) 成功：现有 App Store Connect 应用 `6827831053` / `io.routeforge.gitlabio`，版本 0.1.0、构建号 2190。发布归档及上传成功，2026-10-28 20:26（Asia/Singapore）Apple 接收上传，20:29 Apple API 确认 `processingState=VALID`。现有内部测试组为 0，尚未向测试账户分配；不将 VALID 等同于已有测试者可安装。

CoreChecks 使用 URLProtocol 合成响应，不使用真实令牌或 GitLab。Kotlin 正式测试使用 TLS MockWebServer；其中重定向测试检查没有发出第二次请求。Swift 正式 XCTest 与 Kotlin 测试共同读取 contracts/fixtures/projects.json。

## 尚未验证

- 本机未安装完整 Xcode，`swift test` 的 XCTest 目标因缺少 XCTest 框架无法运行；核心代码本身可通过 CoreChecks 编译执行。
- Liquid Glass 真机视觉效果、VoiceOver、实际钥匙串生命周期（完整构建已通过）。
- Android 设备交互、Keystore 生命周期（应用完整编译与 Lint 已通过）。
- 用应用自身登录官方 / 自建实例，完成文件提交、Issue / MR 评论和 CI 控制的真实端到端操作。
- 设备重启 / 应用进程被终止后的草稿恢复、后台刷新、通知、巨型日志与大仓库。
- TestFlight 的实际设备安装与测试者分配：构建已签名上传且 Apple 处理通过，但应用当前没有内部测试组，仍需指定接收测试的团队账户。

## 连接与 CI 修复记录

初次读取项目 API 与克隆成功。之后 SSH 推送因 `xubuntu.local` 无法解析失败；使用既有钥匙串凭证的 HTTPS 推送返回 HTTP 521。只读 HEAD 请求也观察到 HTTP 521。没有修改 SSH 配置、服务器、GitLab、runner 或虚拟机。

2026-10-28 12:12（Asia/Singapore）复查仍为 HTTP 521；12:48 后 API 与推送恢复，开始真实 CI 验证。

Android 最初在共享 `/opt/gradle/caches/8.9/kotlin-dsl/` 元数据读取时失败，尚未进入应用编译。本项目改用 mktemp 下独立可写 Gradle 状态，读取既有镜像配置。新目录首次下载 Gradle 发行包超时后，脚本增加只读复用构建机已有的 Gradle 8.9 安装与既有 gradle.properties。

主分支早期复验又遇到 Maven TLS 下载中断。将整个 Gradle 用户目录放在 mktemp 会丢失跨任务依赖，因此改为只隔离版本相关的脚本生成状态，将 modules-2 指向 Runner 已有的约 1.4 GB 依赖缓存。缓存完整性检查仅隔离内容校验失败、POM 无法解析或模块 JSON 无效的文件，不清空正常依赖；任务结束清理隔离临时目录。Gradle 自己管理二进制索引。任务 184 发现 48 个损坏 POM；任务 186 保留 2,294 个有效文件并隔离 16 个损坏模块文件，缺失项重新获取后成功构建。后续主分支任务 188 保留 2,693 个有效文件、无损坏项。

只对明确的 TLS / 超时 / 连接重置等依赖下载失败在同一任务缓存内最多尝试三次；源码编译或测试失败不通过此机制重试。没有降低 TLS 安全要求、添加镜像 / 代理或修改 runner、虚拟机、GitLab、服务器配置。[缓存修复合并请求 !3](https://git.routeforge.zone/FelixBennett/gitlabio/-/merge_requests/3) 在双端流水线 65 成功后合并。

任务 164 发现 core 公开的 OkHttp 类型未传递到 app 编译类路径；通过 java-library 的 api 配置显式导出后，任务 166 完整验证通过。返回导航也改用带空栈保护的索引移除，避免依赖 Android 15 新增 List API。

所有本次下载与本地构建均使用 mktemp 临时目录，退出时清理。未在 .git 中手工写入文件。签名材料仅在受保护的发布任务中按用户指定位置使用；源码与 Git 历史不包含凭证。
