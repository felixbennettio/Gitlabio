# 跨端 API 契约

Swift XCTest 与 Kotlin JVM 测试共同读取 fixtures/projects.json。其值均为合成数据，不含真实账户或凭证。

| 场景 | 双端要求 |
| --- | --- |
| 实例 | 仅 HTTPS；拒绝 URL 内账户、密码、query、fragment 和路径穿越；保留部署子路径 |
| 编码 | 项目路径与文件完整路径分别作为单个 URL 路径组件；分支作为 query 值单独编码 |
| 凭证 | PRIVATE-TOKEN 请求头；禁止写入 URL；禁用自动重定向 |
| 分页 | per_page=50；只接受大于当前页的 X-Next-Page；最后一页 next=null |
| 文件 | Base64，编辑仅接受不含 NUL 的 UTF-8 且 size≤1 MiB |
| 写入 | PUT Repository Files，携带 branch、content、encoding、commit_message、last_commit_id |
| 错误 | 400/409 不当成成功；不自动重试写入；不向界面透传任意服务端错误正文 |
| CI 控制 | Pipeline / Job 的 retry / cancel 均用 POST；触发用 POST /projects/:id/pipeline |

M1 仅开放状态 Issue / MR；讨论与差异分页；日志只显示首 1 MiB。客户端当前未对所有响应实施流式网络体积限制，这是进入大仓库支持阶段前必须解决的事项。
