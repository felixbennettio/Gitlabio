# 第三方依赖与构建工具

应用从空仓库独立编写。此为直接依赖初始清单；正式分发前需生成传递依赖清单与完整许可证包。

| 组件 | 固定版本 / 来源 | 上游许可 |
| --- | --- | --- |
| Gradle Wrapper | [v8.9.0](https://github.com/gradle/gradle/tree/v8.9.0/gradle/wrapper) | Apache-2.0；JAR 内含 META-INF/LICENSE，gradlew 保留原始许可头 |
| Android Gradle Plugin | 8.7.2，Google Maven | Apache-2.0 |
| Kotlin 与 Compose compiler plugin | 2.1.21，JetBrains | Apache-2.0 |
| AndroidX Compose / Material 3 / Activity / Lifecycle | 见 android/app/build.gradle.kts | Apache-2.0 |
| OkHttp / MockWebServer / okhttp-tls | 4.12.0，Square | Apache-2.0 |
| kotlinx.serialization | 1.8.1，JetBrains | Apache-2.0 |
| kotlinx.coroutines | 1.10.2，JetBrains | Apache-2.0 |
| Kotlin test / JUnit（仅测试） | Kotlin 2.1.21 / 传递依赖 JUnit 4 | Apache-2.0 / EPL-1.0 |
| Foundation / Security / SwiftUI / XCTest | Apple SDK | Apple SDK 条款 |

Gradle Wrapper JAR SHA-256：`498495120a03b9a6ab5d155f5de3c8f0d986a449153702fb80fc80e134484f17`。
Gradle 8.9 binary ZIP SHA-256：`d725d707bfabd4dfdc958c624003b3c80accc03f7037b5122c4b1d0ef15cecab`。
核查依据：[Gradle 官方校验和](https://gradle.org/release-checksums/)。

GLab、GitSync、GIT-Worker、iGit 未作为运行时依赖引入，参考边界见 docs/RESEARCH.md。
