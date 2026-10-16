# Android 代码规范（详细说明）

> 这份文档是**给人看的**：把本目录两份机器/运行级文件——`rule.json`（逐文件判定标准）和 `android-conventions.md`（运行级团队约定）——展开成可读的中文说明，并补上每条规则背后的「为什么」。
>
> **唯一事实来源是 `rule.json` + `android-conventions.md`**。本文档不定义任何新规则，只是它们的忠实解释。改了其中任何一份，必须同步改这里（见文末「如何保持同步」）。

## 这份规范管什么、不管什么

OpenCodeReview（`ocr`）做的是确定性工具做不了的那一层：**语义、意图、跨文件影响、架构与约定的一致性**。它读到的是 `rule.json` 里每条 `rule` 的英文判定标准 + `android-conventions.md` 的团队背景，然后对这次改动给出带 `severity` 和 `category` 两个字段的评论。

凡是有确定性工具能干的活，**都不写进规则**，否则是花 token 还和工具打架：

| 检查 | 归谁 |
|---|---|
| 格式、命名、import 顺序 | ktlint |
| 代码异味、复杂度、未使用资源 | detekt / Android Lint |
| API 级别误用、资源与 Manifest 结构 | Android Lint |
| 已知 `@Deprecated` 符号 | Android Lint + Kotlin 编译警告 → 喂给 `.ocr/deprecated-apis.md` 清单 |
| **语义、意图、跨文件影响、架构一致性** | **本规范（OCR）** |

## 每条判定标准的共同约定

`rule.json` 里九类规则共享同一条结尾约定，这里只写一次：

- **只看这次改动**：审的是增删改的那几行，不审整个文件，也不报 diff 没碰到的既有问题。
- **严重度**（`severity`，固定枚举）：
  - 崩溃、数据丢失、凭据泄露、越权访问 → `critical`
  - 功能性缺陷、生命周期/线程错误、契约或行为变更、Manifest 安全边界被放宽 → `high`
  - 可维护性问题、资源/内存浪费、可访问性与国际化缺失、约定偏离 → `medium`
  - 风格、命名、文案、可读性 → `low`
- **分类**（`category`，固定枚举）：`bug` / `security` / `performance` / `maintainability` / `test` / `style` / `documentation` / `other`，归属约定：
  - 涉及可被外部触达的边界（Manifest、Intent、Provider、网络、存储权限）→ `security`，即使同时是 bug。
  - 崩溃、空指针、并发/生命周期错误 → `bug`。
  - 主线程阻塞、内存泄漏、重组开销 → `performance`。
  - 分层破坏、依赖方向错误、重复实现 → `maintainability`。
  - 同一处属多类时，取**最严重的那个**，不报两条。

`severity` 和 `category` 的取值是固定枚举，CI 分流（GitHub Action 的 `route_severity_below` / `route_categories`）和事后过滤都建立在这套词表上，所以任何规则里都必须让模型用同一套词。

## 全局红线（任何文件里出现都要报）

1. 硬编码的密钥、token、签名密码、私钥。
2. 关闭安全网：`minifyEnabled=false`、`usesCleartextTraffic=true`、`android:debuggable=true`、移除 keep 规则。
3. 让组件可被任意应用触达：导出且无权限守卫的 Activity/Service/Receiver/Provider。
4. 在应用里引入全新技术栈（新框架、新网络库、新 DI）而没有在改动里说明理由。
5. 静默失败：吞掉异常、忽略错误返回值、`catch` 后不处理也不上报。

---

## 逐文件判定标准

### 1. ProGuard/R8 配置（`**/*.pro`）

混淆/裁剪配置的问题只会在 **release 构建**暴露，所以尤其危险。要报的：

- **keep 规则被删除或收窄**。反射可达的类必须保持 keep：Gson、Moshi、kotlinx.serialization、Retrofit、Hilt/Dagger、用于 JSON 的模型类。只有同一改动**同时**删掉了反射访问，删除 keep 才不算问题。
- **`-dontshrink` / `-dontobfuscate` / `-dontoptimize`**：关掉一项 release 安全网，必须有注释说明理由。
- **全量 keep**（`-keep class **`、`-keep class com.example.** { *; }`）：让 shrink 失去意义。
- **新增 `-dontwarn <package>`**：会掩盖一个真正缺失的依赖。

### 2. Gradle 构建脚本（`**/build.gradle*`）

要报的：

- **依赖版本未 pin**：`-SNAPSHOT`、`+`、`latest.release`、`[1.0,)` 区间 → 要求显式版本；版本不在增删改的行上时忽略。
- **`compileSdk` / `targetSdk` 变更**：报并要求给出理由。`minSdk` 调高会丢掉支持的设备，调低则需要兼容性审查。
- **release 构建类型关闭 `minifyEnabled` 或 `shrinkResources`**。
- **签名凭据硬编码**：脚本里的 keystore 密码、或指向仓库外的 `storeFile`。
- **依赖 scope 漂移**：debug 专用库被移到 `implementation`/`api`（现在会跟着进 release），或 release 库被移到 `debugImplementation`。
- **`api()` 用在 `implementation()` 就够的地方**：`api` 会把依赖泄漏给每个消费者。
- **加依赖没写版本**，而同文件里没有应用 BOM/platform。
- **仓库声明散落在构建脚本里**，而不是集中在 `settings.gradle`。
- **`packagingOptions` / `packaging` 静默丢弃 `.so` 文件或资源**。
- **`applicationId`、`versionCode`、`versionName` 变更**。

### 3. Gradle 设置（`**/settings.gradle*`）

- **新增非允许清单仓库**：`pluginManagement` / `dependencyResolutionManagement` 里出现 `google()`、`mavenCentral()`、公司镜像之外的新第三方仓库——这是供应链决策，不是构建细节。
- **`repositoriesMode` 从 `FAIL_ON_PROJECT_REPOS` 放宽**。
- **模块从 `include` 移除**：孤立了源码，还是有意的拆分？
- **模块加入 `include` 但没有对应目录**。

### 4. 版本目录（`**/libs.versions.toml`）

- **`[versions]` 条目被删除或降级，但 `[libraries]` / `[plugins]` 仍引用它**：构建崩溃或静默回退。
- **library/plugin 的 alias 没有对应的版本条目**。
- **两个 alias 解析到同一个 artifact group 的不同版本**。
- **版本未 pin**：`-SNAPSHOT`、`+`、动态区间。
- **版本和 alias 改名但没更新消费者**，或旧名字条目残留。

### 5. gradle.properties（`**/gradle.properties`）

- **`android.enableJetifier=true`**：说明 classpath 上还有旧 support 库依赖——报出这个开关并问是什么需要它。
- **`android.useAndroidX` 或 `android.nonTransitiveRClass` 被关掉**。
- **`org.gradle.parallel`、`org.gradle.caching`、配置缓存被关掉**。
- **`org.gradle.jvmargs` 堆被调小，或提交了机器相关的值**。
- **签名凭据、token、本地文件绝对路径**。

### 6. AndroidManifest（`**/AndroidManifest.xml`）

Manifest 是攻击面，按攻击面审：

- **`android:exported="true"` 且无权限守卫、无说明性的 `intent-filter`**：设备上任何应用都能启动它。反之，从有 intent-filter 的组件上**删掉 `exported`** 在 API 31+ 会崩溃。
- **新增 `<uses-permission>` / `<permission>`**：必须最小化；危险权限要有说明理由；守护组件的自定义权限不能用 `protectionLevel="normal"`。
- **`android:usesCleartextTraffic="true"`**，或 `networkSecurityConfig` 改动新增明文例外/用户添加的 CA。
- **`android:debuggable`、`android:allowBackup`、`android:fullBackupContent` 被放宽**。
- **`<provider>`（FileProvider）导出且 `grantUriPermissions` / path 集合过宽**。
- **deep-link `<data>` 新增或扩宽**：还有谁能到达这个页面？
- **入口 Activity 的 `launchMode`、`taskAffinity`、`excludeFromRecents` 变更**。
- **`versionName` / `applicationId` / 签名 / `platformBuildVersion` 变更**。

### 7. Android 资源（`**/src/main/res/**/*.xml`）

- **用户可见文案硬编码在布局里**（`android:text="Save"`）而不是 `@string/`。
- **硬编码颜色（`#RRGGBB`）或尺寸**，而不是 `@color/` 或 `dimens.xml` 条目。
- **图标/图片没有 `contentDescription`，也没有 `importantForAccessibility="no"`**：屏幕阅读器会撞上一个无名控件。
- **RTL 敌意属性**：`marginLeft` / `paddingLeft` / `gravity="left|right"` / `layout_alignParentLeft` 应换成 Start/End 等价物。
- **`textSize` 没写单位，或文本上 sp/dp 混用**。
- **`values/` 里新增字符串，在应用有翻译时没定 `translatable`**。

### 8. Kotlin 源码（`**/*.{kt,kts}`）

- **主线程阻塞**：磁盘/网络 I/O、`Thread.sleep`、UI 或生命周期回调里的 `runBlocking`。
- **Context / Activity / View / Fragment 泄漏进更长生命周期**：`static`/`companion object` 字段、单例、或比屏幕活得更久的协程。
- **`GlobalScope` 启动协程**，或作用域不绑定调用方的生命周期。
- **UI 代码收集 Flow/StateFlow 没用 `repeatOnLifecycle` 或 `flowWithLifecycle`**。
- **Compose**：composable 函数体重活/分配、`remember`/`key` 缺失或错误、热列表里的不稳定 lambda、`LaunchedEffect(Unit)` 但效果实际依赖参数。
- **Java 互操作平台类型上的 `!!`**，或未检查的强转。
- **吞掉失败**：空 `catch`、忽略 `Result`、没人观察异常的协程。
- **废弃 API**：对照团队废弃清单（`.ocr/deprecated-apis.md`），不要凭记忆声称某个 API 废弃。

### 9. Java 源码（`**/*.java`）

- **公开 API 缺 `@NonNull`/`@Nullable`**：调用方无从判断，Kotlin 互操作会把它变成平台类型。
- **`AsyncTask` 或裸 `Thread`**，而项目已经用协程。
- **`static` 字段持有 Context、View、Activity 或资源对象**。
- **回调/监听器注册了，但从不在生命周期 teardown 里反注册**。
- **废弃 API**：同样对照团队废弃清单。

---

## 运行级团队约定（`android-conventions.md`）

这部分不是逐文件规则，而是注入到每次审查 prompt 里的团队背景。其中**技术栈基线**是唯一必须按你们项目改的地方（以 `<!-- TODO(team) -->` 标出）：语言 Kotlin 优先、UI Compose 优先、异步 Coroutines + Flow、以及 DI / 网络序列化 / 架构分层 / 模块边界四项，要写出「是什么」，模型才能判断「什么算偏离」。

它还包括**交付质量的最低要求**：

- 新增或修改的公开行为要有对应测试；测试缺失时按 `medium` 报一条，不要每个文件都报。
- 同一个问题在一个文件里只报一次，不要对同一处重复刷屏。
- 报问题必须给出可以照着改的具体建议；拿不准就写「需要确认」并说明依据，不要编造替代 API 或不存在的 API。

## 四个 Android 特有的默认行为

这些不是本规范的设定，而是 `ocr` 的默认过滤行为，但会直接影响结果，落地时必须在 `rule.json` 里应对：

1. **`**/build/**` 默认不排除**（只排 `**/.gradle/**`）。所以 `rule.json` 里必须有 `**/build/**`，否则 AGP 生成的 `BuildConfig.java`、`R.java` 会被送审。
2. **`**/src/androidTest/**` 默认不排除**（默认只排 `**/src/test/**`）。本规范选择两个都排除；要审测试代码就用 `include` 拉回。
3. **`build.gradle.kts` 会落到 Kotlin 源码规则上**（内置只有 `**/build.gradle` 精确匹配）。所以 `**/build.gradle*` 必须排在 `**/*.{kt,kts}` **前面**，否则 Gradle 规则永远不触发。
4. **`.pro` 不在扩展名白名单里**，默认按 `unsupported_ext` 丢弃，规则写了也没用，必须靠 `include` 拉回。而 `include` 会一并绕过白名单和测试目录排除，所以只加确实要审的路径。

## 落地与验收

完整命令见同目录 `README.md` 的「三步采纳」和「验收」。要点：拷 `rule.json` → `<repo>/.opencodereview/rule.json`、`android-conventions.md` → `<repo>/.ocr/`、`scripts/` → `<repo>/scripts/`；填完所有 `<!-- TODO(team) -->`；跑 `refresh-deprecated-apis.sh`（自动执行 `./gradlew lint` 并读取各模块报告，传报告路径则跳过 lint）生成废弃清单；上线前务必用 `ocr rules check <file>` 看 Source/Pattern 两行、用 `ocr review --preview --format json` 确认过滤生效。

## 如何保持同步

- 本文档与 `rule.json`、`android-conventions.md` 是同一套规范的三份：**改规范只改 `rule.json` 或 `android-conventions.md`，然后同步更新本文档**，不要让它们各自演化。
- 改完用 `ocr rules check` 确认命中，跑一次真实 PR 看是否误报。加规则容易，去掉噪声难。
- 规则里**不要写「注意性能」这类写不出判定标准的话**——那会变成模型的自由发挥。
