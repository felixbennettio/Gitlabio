# TestFlight 发布

用户于 2026-10-28 明确授权直接发布到已创建的 TestFlight 应用。iOS Bundle ID 为 `io.routeforge.gitlabio`。

## 发布门槛

- 在开发分支完成修改，通过合并请求进入受保护分支，不强推 main。
- `apple`、`android` 验证成功后，`testflight` 才可执行。
- 只有在受保护分支上显式设置 `UPLOAD_TESTFLIGHT=true`，或主动执行受保护 main 上的手动发布任务，才上传；普通提交不自动发布。
- 使用现有实例级受保护、掩码变量：APPLE_TEAM_ID、APP_STORE_CONNECT_ISSUER_ID、APP_STORE_CONNECT_KEY_ID、APP_STORE_CONNECT_PRIVATE_KEY。

## 私钥位置

用户已确认允许 macOS CI 构建机使用 `$HOME/Library/Application Support/Gitlabio/Signing/` 专用目录。私钥文件以权限 0600、独占新建方式写入，发布结束（成功或失败）后清理。不在仓库、.git、mktemp 目录或构建产物中保存私钥。

归档、构建依赖和其他中间文件仍使用 mktemp 并结束清理。Xcode 自动签名使用构建机钥匙串与 App Store Connect API，不复制或导出证书私钥，不改 runner / VM / GitLab 配置。

Xcode 会额外在系统用户临时目录生成 `.xcdistributionlogs`。发布脚本从本次导出日志中读取它实际生成的路径，仅清理用户临时目录内、当前用户所有且名称匹配 Gitlabio 的分发日志，拒绝符号链接；不会遍历删除其他项目日志。`release-cleanup` 是受保护 main 上的手动清理核验任务，必须提供已核实的 `GITLABIO_RELEASE_JOB_ID`、`GITLABIO_DISTRIBUTION_LOG_BASENAME`、`GITLABIO_RELEASE_TEMP_BASENAME`，用于首次发布遗留文件的清理和私钥缺失核验，不会签名、构建或上传应用。若发布临时目录仍存在，必须包含准确匹配 Gitlabio Bundle ID 的预检文件才允许清理。

## 发布步骤

1. 验证已存在的 App Store Connect 应用准确匹配 Bundle ID，不创建新应用。
2. 从已有构建号与 CI Job ID 计算递增构建号。
3. Xcode 归档、自动签名、上传 App Store Connect。
4. 最多等待 20 分钟，确认 Apple 的 processingState 为 VALID。
5. 将有效构建关联到已有内部测试组；没有内部组时明确报告，不擅自创建测试者或外部测试组。
6. 保留不含凭证的 dist/testflight/upload.json（上传接收凭据）与 result.json（Apple 处理状态和内部组数量），区分上传成功和可供测试。

用户指定收件邮箱后，可通过受保护 main 上的 `testflight-invite` 手动任务，提供 `GITLABIO_TESTER_EMAIL` 和已上传的 `GITLABIO_BUILD_NUMBER`。此任务只分配已有且 Apple 确认 VALID 的构建，因此独立于本次构建队列；上传新安装包的 `testflight` 仍必须等待双端验证通过。先核验邮箱属于有应用访问权的现有团队成员，再创建或复用 `Gitlabio TF` 内部组。组内已有该邮箱时直接核验；否则以创建测试者并同时关联内部组的操作完成分配，避免把全局外部测试者记录直接转成内部成员的状态冲突。核实 Apple 的 INVITED / ACCEPTED / INSTALLED 状态；若确认仍为 NOT_INVITED / REVOKED，只向该测试者请求一次邀请。邮箱通过任务变量传入，不写入源码；不提升团队角色、不启用公开链接。结果保存为 `dist/testflight/distribution.json`，并核实任务使用的 API 私钥文件已删除。

App Store Connect API 认证助手使用 CryptoKit 生成短期 ES256 JWT，密钥和 JWT 不写日志。

## 平台依据

- [Xcode 云签名与 API Key 参数](https://developer.apple.com/videos/play/wwdc2021/10204/)
- [上传构建与 Apple 处理阶段](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [UserDefaults 的隐私用途声明](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)

2026-10-28 首次实际发布：[主分支流水线 66](https://git.routeforge.zone/FelixBennett/gitlabio/-/pipelines/66) 双端验证通过后，[发布任务 190](https://git.routeforge.zone/FelixBennett/gitlabio/-/jobs/190) 已上传 **0.1.0（2190）**，Apple API 返回 `VALID`。现有内部测试组数量为 0，构建已在 TestFlight 就绪，测试账户分配尚待指定。没有发出测试者邀请，也没有创建外部公开链接。
