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
| 已知 `@Deprecated` 符号 | Android Lint + Kotlin 编译警告 → 喂给 `.ocr/lint-report.md` 全量报告 |
| 固定符号的静态匹配（`Runtime.exec`、`ProcessBuilder`、`DexClassLoader`、`getExternalStorageDirectory`、`/sdcard` 字面量） | 自定义 Android Lint 规则 / Semgrep 兜底 |
| **语义、意图、跨文件影响、架构一致性** | **本规范（OCR）** |

敏感 API 这条规则落在两边：**确定性工具做符号级兜底**（自定义 Lint / Semgrep 把明文符号和字面量全扫一遍，零成本、零漏报），**OCR 补语义那半**（反射与字符串拼出的调用、import 别名、封装多层的工具类、第三方接口背后的 `exec`）。OCR 的 `rule.json` 里写得再全也只是给模型的提示词，覆盖不了全仓扫描，所以这条不能只靠 OCR。两边同时报同一处是允许的。

## 每条判定标准的共同约定

`rule.json` 里十类规则共享同一条结尾约定，这里只写一次（团队统一口径的版本基线与安全基线是例外，见第 2–5 节与第 9、10 节的敏感 API 条目）：

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
2. 关闭安全网：`minifyEnabled=false`、`isShrinkResources=false`、`getDefaultProguardFile("proguard-android.txt")`、`android.enableR8.fullMode=false`、库模块 `consumer-rules.pro` 里的全局选项、`usesCleartextTraffic=true`、`android:debuggable=true`、移除 keep 规则；`networkSecurityConfig` 放行明文同理——debug/test 源集里报 `medium`，其它源集报 `high`。
3. 让组件可被任意应用触达：导出且无权限守卫的 Activity/Service/Receiver/Provider。
4. 在应用里引入全新技术栈（新框架、新网络库、新 DI）而没有在改动里说明理由。
5. 静默失败：吞掉异常、忽略错误返回值、`catch` 后不处理也不上报。
6. 运行外部命令或加载 APK 之外的代码：`Runtime.exec`、`ProcessBuilder`、`DexClassLoader`/`PathClassLoader`/`InMemoryDexClassLoader`/`ClassLoader.defineClass`/`DexFile.loadDex`；`AndroidManifest.xml` 里的 `android:requestLegacyExternalStorage="true"`（legacy 存储退出开关）同样按此报；用反射绕到这些 API 同样按此报。
7. 声明团队禁止的权限：`READ_EXTERNAL_STORAGE`、`WRITE_EXTERNAL_STORAGE`、`READ_MEDIA_IMAGES`（照片）、`READ_MEDIA_VIDEOS`（视频）、`READ_CONTACTS`、`ACCESS_FINE_LOCATION`、`READ_PHONE_NUMBERS`、`QUERY_ALL_PACKAGES`——隐私合规与应用商店的发版红线，写成什么形式、加不加理由都不放行。代码里引用这些权限名（常量、字面量、别名、当字符串传递）或发起申请，同样按这条报。

---

## 逐文件判定标准

下表按文件类型逐类列出判定标准，每条对应 `rule.json` 里的一条规则，并遵循上面的「共同约定」（只看这次改动 + severity/category 词表）。

### 1. ProGuard/R8 配置（`**/*.pro`）

混淆/裁剪配置的问题只会在 **release 构建**暴露，所以尤其危险。

| 检查点 | 判定标准 |
|---|---|
| keep 规则被删除或收窄 | 反射可达的类必须保持 keep：Gson、Moshi、kotlinx.serialization、Retrofit、Hilt/Dagger、用于 JSON 的模型类。只有同一改动**同时**删掉了反射访问，删除 keep 才不算问题。 |
| `-dontshrink` / `-dontobfuscate` / `-dontoptimize` | 关掉一项 release 安全网，必须有注释说明理由。 |
| 全量 keep | `-keep class **`、`-keep class com.example.** { *; }` 会让 shrink 失去意义。 |
| 新增 `-dontwarn <package>` | 会掩盖一个真正缺失的依赖。 |
| consumer rules 里的全局选项 | 库模块 `consumer-rules.pro` 里的 `-dontoptimize` / `-dontshrink` / `-dontobfuscate` / 全量 `-keep class **` 会连带作用于每个消费它的 App，等于从模块外面关掉宿主的安全网。AGP 9.4 已把这类写法报成构建错误（`android.r8.globalOptionsInConsumerRules.disallowed`）。报出并指向模块自己的规则文件。`high`。 |

### 2. Gradle 构建脚本（`**/build.gradle*`）

| 检查点 | 判定标准 |
|---|---|
| 依赖版本未 pin | `-SNAPSHOT`、`+`、`latest.release`、`[1.0,)` 区间 → 要求显式版本；版本不在增删改的行上时忽略。 |
| **团队版本基线** | `minSdk` 必须是 23、`targetSdk` 必须 ≥ 36（Groovy `minSdkVersion 23` / Kotlin DSL `minSdk = 23`，或本文件从版本目录读到的值）。这是**团队统一规则**，不是"这次改动才好"的选择题：只要这个文件在审查范围里，取值落在基线之外就报，哪怕 diff 没碰那一行。基线外 = `medium`；把原本合规的值降到基线以下 = `high`。 |
| **团队版本基线：AGP ≥ 9.0.0** | 本文件声明的每个 `com.android.*` 插件（`com.android.application`、`com.android.library`、`com.android.legacy-kapt`）都适用，写法不限：`id 'com.android.application' version '9.4.0'`、`classpath 'com.android.tools.build:gradle:9.4.0'`，或经版本目录 alias 解析。AGP 低于 9.0.0 也和 Gradle 9.x wrapper 基线对不上。同样是**团队统一规则**：只要文件在审查范围里就报，不限于 diff 碰到的行。基线外 = `medium`；把合规版本降下去 = `high`。 |
| **团队版本基线：Adjust SDK ≥ 5.5.0** | 本文件带的每个 `com.adjust.sdk:*` 依赖（`com.adjust.sdk:adjust-android` 及其配套 artifact，inline 版本或经版本目录 alias）都适用这条下限。同样是**团队统一规则**：只要文件在审查范围里就报，不限于 diff 碰到的行。基线外 = `medium`；把合规版本降下去 = `high`。 |
| `compileSdk` 变更 | 报并要求给出理由。 |
| **团队 release 安全网基线** | release 构建类型必须同时写 `isMinifyEnabled = true`（`minifyEnabled true`）和 `isShrinkResources = true`（`shrinkResources true`）。关掉压缩会连裁剪、混淆、优化一起没了，而 `shrinkResources` 没有 minify 根本不生效；不开资源压缩则留下一批只被死代码引用的资源。**团队统一规则**：只要这个文件在审查范围里就报，哪怕 diff 没碰那一行。关闭或从 `true` 改成 `false` = `high`。 |
| 用了 `proguard-android.txt` | `getDefaultProguardFile("proguard-android.txt")` 带 `-dontoptimize`，R8 完全不优化，Play 后台的优化百分比就是 0。必须用 `proguard-android-optimize.txt`；确实要临时 `-dontoptimize` 就放进自定义规则文件并写明原因。AGP 9.4 已直接报构建错误，更早的 AGP 不会。`high`。 |
| release 的 `postProcessing` | 把 `isOptimizationsEnabled` / `isObfuscationEnabled` / `isShrinkingEnabled` 设成 `false` 等于关掉同一道安全网，要求改动里说明理由。`high`。 |
| 签名凭据硬编码 | 脚本里的 keystore 密码，或指向仓库外的 `storeFile`。 |
| 依赖 scope 漂移 | debug 专用库被移到 `implementation`/`api`（会跟着进 release），或 release 库被移到 `debugImplementation`。 |
| `api()` 用在 `implementation()` 就够的地方 | `api` 会把依赖泄漏给每个消费者。 |
| 加依赖没写版本 | 而同文件里没有应用 BOM/platform。 |
| 仓库声明散落在构建脚本里 | 而不是集中在 `settings.gradle`。 |
| 打包选项 | `packagingOptions` / `packaging` 静默丢弃 `.so` 文件或资源。 |
| 应用身份变更 | `applicationId` / `versionCode` / `versionName` 变更。 |

### 3. Gradle 设置（`**/settings.gradle*`）

| 检查点 | 判定标准 |
|---|---|
| 新增非允许清单仓库 | `pluginManagement` / `dependencyResolutionManagement` 里出现 `google()`、`mavenCentral()`、公司镜像之外的新第三方仓库——这是供应链决策，不是构建细节。 |
| 仓库模式放宽 | `repositoriesMode` 从 `FAIL_ON_PROJECT_REPOS` 放宽。 |
| 模块从 `include` 移除 | 孤立了源码，还是有意的拆分？ |
| 模块加入 `include` 但没有对应目录 | 报。 |
| **团队版本基线：AGP ≥ 9.0.0** | 在这里固定插件版本（`pluginManagement { plugins { id 'com.android.application' version '...' } }`）时同样适用这条下限，和别处一致。团队统一规则，不限于 diff 碰到的行。基线外 = `medium`；降下去 = `high`。 |

### 4. 版本目录（`**/libs.versions.toml`）

| 检查点 | 判定标准 |
|---|---|
| `[versions]` 条目被删除或降级，但 `[libraries]` / `[plugins]` 仍引用它 | 构建崩溃或静默回退。 |
| alias 没有对应的版本条目 | library/plugin 的 alias 没有对应的版本条目。 |
| 同 group 多版本 | 两个 alias 解析到同一个 artifact group 的不同版本。 |
| 版本未 pin | `-SNAPSHOT`、`+`、动态区间。 |
| 改名未同步消费者 | 版本和 alias 改名但没更新消费者，或旧名字条目残留。 |
| **团队版本基线** | `minSdk` 不是 23、`targetSdk` 低于 36、Android Gradle Plugin 的版本条目（`com.android.application` / `com.android.library` 背后的 alias，通常叫 `agp`）低于 9.0.0，或 Adjust SDK 的版本条目（`com.adjust.sdk:*` 背后的 alias，通常叫 `adjust`）低于 5.5.0。同样是**团队统一规则**：只要这个文件在审查范围里就报，不限于 diff 碰到的行。基线外 = `medium`；把原本合规的条目降到基线以下 = `high`。 |

### 5. Gradle wrapper（`**/gradle/wrapper/gradle-wrapper.properties`）

| 检查点 | 判定标准 |
|---|---|
| **团队版本基线：Gradle ≥ 9.0.0** | wrapper 的分发版本，和构建脚本里的 AGP 9.0.0 下限配套。版本取 `distributionUrl` 里的 `gradle-x.y.z` 片段（`gradle-9.6.0-bin.zip` 即 9.6.0，写 `9.0` 等同 9.0.0）。**团队统一规则**：只要这个文件在审查范围里，`distributionUrl` 低于 9.0.0 就报并要求理由，不限于 diff 碰到的行。`-SNAPSHOT` / `-rc` / `-milestone` 是预发布版，也不算达标。原本就在基线以下 = `medium`；把合规版本降到基线以下 = `high`。 |

> 为什么单独一条规则：Gradle 版本只在 wrapper 属性文件里，不在构建脚本里；`.properties` 在扩展名白名单内（系统层有 `**/*.properties` 规则，靠 `merge_system_rule` 合并），所以这条规则能直接命中，不需要 `include`。

### 6. gradle.properties（`**/gradle.properties`）

| 检查点 | 判定标准 |
|---|---|
| `android.enableJetifier=true` | 说明 classpath 上还有旧 support 库依赖——报出这个开关并问是什么需要它。 |
| AndroidX 开关被关 | `android.useAndroidX` 或 `android.nonTransitiveRClass` 被关掉。 |
| **R8 全模式被关** | `android.enableR8.fullMode=false` 关掉 R8 全模式。全模式是 AGP 8.0+ 的默认值，类重打包与更强的优化都靠它，关掉后 Play 后台的优化百分比会掉。AGP 至今仍在读这个开关（9.4 上核对过），不要写成「已被忽略」。报出开关并问是什么需要它。**团队统一规则**：文件进了审查范围就判。`medium`。 |
| 构建缓存开关被关 | `org.gradle.parallel`、`org.gradle.caching`、配置缓存被关掉。 |
| JVM 参数 | `org.gradle.jvmargs` 堆被调小，或提交了机器相关的值。 |
| 凭据 | 签名凭据、token、本地文件绝对路径。 |

### 7. AndroidManifest（`**/AndroidManifest.xml`）

Manifest 是攻击面，按攻击面审：

| 检查点 | 判定标准 |
|---|---|
| 组件导出 | `android:exported="true"` 且无权限守卫、无说明性的 `intent-filter`，设备上任何应用都能启动它；反之，从有 intent-filter 的组件上**删掉 `exported`** 在 API 31+ 会崩溃。 |
| 新增权限 | `<uses-permission>` / `<permission>` 必须最小化；危险权限要有说明理由；守护组件的自定义权限不能用 `protectionLevel="normal"`。 |
| **团队权限基线：禁止的权限（发版红线）** | 这 9 个权限一个都不能声明，按权限名匹配（`android.permission.X` 与 `android:name="android.permission.X"` 是同一种写法）：`READ_EXTERNAL_STORAGE`、`WRITE_EXTERNAL_STORAGE`、`MANAGE_EXTERNAL_STORAGE`、`READ_MEDIA_IMAGES`（照片）、`READ_MEDIA_VIDEOS`（视频）、`READ_CONTACTS`、`ACCESS_FINE_LOCATION`、`READ_PHONE_NUMBERS`、`QUERY_ALL_PACKAGES`。替代做法：取媒体走系统照片选择器（Photo Picker）或 `MediaStore` 作用域存储；定位用用户自己填写/选择的位置；查已安装应用走 `Intent` 解析或 `<queries>`（`<queries>` 是 `QUERY_ALL_PACKAGES` 的官方替代，不算违规）。`<uses-permission-sdk-23>` 一样处罚；`tools:node="remove"` 摘掉不算违规。**团队统一规则**：只要这个文件在审查范围里就报，不限于 diff 碰到的行。`critical` / `security`。代码里出现这些权限名（常量、字面量、别名、当字符串传递）或发起申请的动作，按同一条红线的第 9、10 节处理。 |
| **团队安全基线：只走 HTTPS** | 应用只支持 HTTPS。`android:usesCleartextTraffic="true"`，或允许明文的 `networkSecurityConfig`（base-config 或任一 `<domain-config>` 的 `cleartextTrafficPermitted="true"`）、信任用户安装的 CA，都是违规。**团队统一规则**：只要这个文件在审查范围里就报，不限于 diff 碰到的行。`android:networkSecurityConfig` 只是引用一个文件名——要打开它指的那个 `@xml/...`（名字可能是混淆过的）核对，那个配置里的明文开关同样算违规：只在 debug/test 源集生效报 `medium`（不得带进 release），其它源集报 `high`。`high` / `security`（debug 源集 `medium`）。 |
| **团队安全基线：`allowBackup` 必须 `false`** | `<application>` 的 `android:allowBackup` 必须显式设为 `false`。设为 `true`、或干脆不写（平台默认就是 `true`），应用的文件/数据库/SharedPreferences 都能被 `adb backup` 拉走；`android:fullBackupContent`/`dataExtractionRules` 不能替代。**团队统一规则**：只要这个文件在审查范围里就报，不限于 diff 碰到的行。`high` / `security`。 |
| **团队安全基线：不得声明 legacy 存储退出开关** | `<application>` 上不得有 `android:requestLegacyExternalStorage="true"`。应用 target 到 API 30 及以上之后，系统就忽略这个 scoped storage 退出开关（官方原话：target 到 Android 11 后系统忽略该标志），而团队基线是 `targetSdk ≥ 36`，所以它是一份**死配置**：不改运行时行为，却仍在声明"本应用要 legacy 共享外部存储"，`targetSdk` 一旦降回 29 还会立刻生效。移除即可，不需要替代写法。**团队统一规则**：只要这个文件在审查范围里就报，不限于 diff 碰到的行。`medium` / `security`。 |
| 调试/备份开关 | `android:debuggable`、`android:fullBackupContent` 被放宽。 |
| Provider 授权 | `<provider>`（FileProvider）导出且 `grantUriPermissions` / path 集合过宽。 |
| deep-link 扩宽 | deep-link `<data>` 新增或扩宽——还有谁能到达这个页面？ |
| 入口 Activity | 入口 Activity 的 `launchMode`、`taskAffinity`、`excludeFromRecents` 变更。 |
| 应用身份变更 | `versionName` / `applicationId` / 签名 / `platformBuildVersion` 变更。 |

### 8. Android 资源（`**/res/**/*.xml`，含 `src/main`、`src/debug`、`src/release` 与 flavour 源集）

| 检查点 | 判定标准 |
|---|---|
| 用户可见文案硬编码 | 硬编码在布局里（`android:text="Save"`）而不是 `@string/`。 |
| 硬编码颜色/尺寸 | `#RRGGBB` 或数值，而不是 `@color/` 或 `dimens.xml` 条目。 |
| 无障碍缺失 | 图标/图片没有 `contentDescription`，也没有 `importantForAccessibility="no"`——屏幕阅读器会撞上一个无名控件。 |
| RTL 敌意属性 | `marginLeft` / `paddingLeft` / `gravity="left\|right"` / `layout_alignParentLeft` 应换成 Start/End 等价物。 |
| 字号单位 | `textSize` 没写单位，或文本上 sp/dp 混用。 |
| 翻译标注 | `values/` 里新增字符串，在应用有翻译时没定 `translatable`。 |
| `android:angle` 不是 45 的倍数 | `<gradient android:angle="...">`（drawable 的 shape）取值必须是 45 的倍数：0/45/90/135/180/225/270/315。线性渐变只画这八个方向，平台会把其它值**静默吸附**到最近的一个，渲染出来的方向和写的值不一致（`android:angle="30"` 实际按 45 渲染）。报出并给出最近的有效角度。角度超出 0–360 由平台取模，本身不算违规。 |
| **只走 HTTPS** | 值里的明文 `http://` 端点（`strings.xml` 的 API base URL、配置/flavours XML、deeplink）按 diff 判，新增即报；XML 命名空间 URI（`http://schemas.android.com/apk/res/android`）不是流量，不报。 |
| **只走 HTTPS：网络配置文件** | 根元素是 `<network-security-config>` 的资源 XML——**文件名任意**，包括被混淆的名字（`android:networkSecurityConfig="@xml/hofeuzirufea_vagepawudusi"` 指到的那个）；base-config 或任一 `<domain-config>` 的 `cleartextTrafficPermitted="true"`、以及为「用户安装的证书」放行的 `<trust-anchors>`，**整份文件**都算违规。**按源集判**：只在 `src/debug/res`、`src/androidTest/res` 里放行明文报 `medium`（不得带进 release，release 侧必须仍是 `false`）；在 `src/main/res`、`src/release/res`、flavour 的 `res/` 里报 `high`。都是 `security`。 |

### 9. Kotlin 源码（`**/*.{kt,kts}`）

| 检查点 | 判定标准 |
|---|---|
| 主线程阻塞 | 磁盘/网络 I/O、`Thread.sleep`、UI 或生命周期回调里的 `runBlocking`。 |
| 对象泄漏 | Context / Activity / View / Fragment 泄漏进更长生命周期：`static`/`companion object` 字段、单例、或比屏幕活得更久的协程。 |
| 协程作用域 | `GlobalScope` 启动协程，或作用域不绑定调用方的生命周期。 |
| Flow 收集 | UI 代码收集 Flow/StateFlow 没用 `repeatOnLifecycle` 或 `flowWithLifecycle`。 |
| Compose | composable 函数体重活/分配、`remember`/`key` 缺失或错误、热列表里的不稳定 lambda、`LaunchedEffect(Unit)` 但效果实际依赖参数。 |
| 平台类型强转 | Java 互操作平台类型上的 `!!`，或未检查的强转。 |
| 吞掉失败 | 空 `catch`、忽略 `Result`、没人观察异常的协程。 |
| 废弃 API | 对照团队 lint 报告（`.ocr/lint-report.md`），不要凭记忆声称某个 API 废弃。 |
| **禁止反射** | 新增的 `java.lang.reflect`（`Class.forName`、`getDeclaredMethod`/`getDeclaredField`、`Method.invoke`、`setAccessible(true)`）、Kotlin 反射（`kotlin.reflect.full.*`、`::class.members`、`KClass.memberProperties`、`isAccessible = true`），或只为把反射结果转成类型的强转，一律报。反射把依赖藏在字符串里、让 R8 裁剪失效、只在 release 构建暴露问题，团队选择禁止而不是补 keep 规则。例外只有一个：第三方只提供反射入口（SDK 工厂、序列化库自己生成的 adapter、插件公开 API），此时改动必须写明理由，没写理由就是违规（`medium`）；用反射绕过访问限制或触达隐藏的平台 API 按 `high`。判定范围是**这次改动引入的反射**，不是把文件里既有的反射翻出来。 |
| **只走 HTTPS** | 应用不支持明文 HTTP：新增的 `http://` 网络目标（OkHttp/Retrofit 的 `baseUrl`、`URL`/`HttpURLConnection`、`WebView.loadUrl`、硬编码端点或 deeplink）一律报。XML 命名空间 / schema URI 里的 `http://` 不是流量，不报。本地开发地址（`localhost`、`127.0.0.1`、`10.0.2.2`）只允许出现在 debug-only 且改动里写明的情况。显式的明文开关（`ConnectionSpec.CLEARTEXT`、信任一切的 `X509TrustManager`、恒返回 true 的 `HostnameVerifier`）**整份文件**都算违规。URL 按 diff 判，明文开关按整份文件判。`high` / `security`。 |
| **禁止的权限（9 项，代码侧，整份文件判）** | 这 9 个权限名不许出现在代码里：`READ_EXTERNAL_STORAGE`、`WRITE_EXTERNAL_STORAGE`、`MANAGE_EXTERNAL_STORAGE`、`READ_MEDIA_IMAGES`、`READ_MEDIA_VIDEOS`、`READ_CONTACTS`、`ACCESS_FINE_LOCATION`、`READ_PHONE_NUMBERS`、`QUERY_ALL_PACKAGES`。`Manifest.permission.X` 常量、`"android.permission.X"` 字面量、本地别名、当字符串传出去（权限映射表、权限数组）都算；发起申请的写法（`checkSelfPermission`、`requestPermissions`、`ActivityResultContracts.RequestPermission()`、`requestPermissionLauncher.launch(...)`、`shouldShowRequestPermissionRationale`、`AppOpsManager`、`PackageManager.checkPermission`，以及 `MANAGE_EXTERNAL_STORAGE` 的申请入口 `Environment.isExternalStorageManager()`、`Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION`、`Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`）一并报。替代做法：照片选择器（`PickVisualMedia`/`PickMultipleVisualMedia`）或 `MediaStore` 作用域存储、用户自己填写/选择的位置、`<queries>` 或 Intent 解析。注释 / KDoc 里的提及不算。**文件进了审查范围就判**，不看 diff 是否碰到那一行。`critical` / `security`。 |
| **禁止的敏感 API**（整份文件判） | 团队禁止的合规红线，**文件进了审查范围就判，不看 diff 是否碰到那一行**：运行外部命令 `Runtime.getRuntime().exec(...)`、`ProcessBuilder(...).command(...)`/`.start()`（`critical`——没有任何正当理由，要做的事用 SDK：`ConnectivityManager`、`InetAddress.isReachable()`）；加载 APK 之外的代码 `DexClassLoader`、`PathClassLoader`、`InMemoryDexClassLoader`、`ClassLoader.defineClass(...)`、`DexFile.loadDex`（`critical`——热修复、插件、加固壳都算隐藏动态代码，应编译进 APK 或独立模块）；共享外部存储 `Environment.getExternalStorageDirectory()`、`getExternalStoragePublicDirectory(...)`、手写 `/sdcard` 或 `/storage/emulated/0` 路径（`medium`——改用 `filesDir` / `getExternalFilesDir(null)`）。三条都归 `security`。用反射绕到这些 API（`Class.forName("java.lang.Runtime")` 加 `getDeclaredMethod("exec")`、按名字取类加载器）算蓄意规避，按 `critical` 报，不按普通反射条处理。 |

### 10. Java 源码（`**/*.java`）

| 检查点 | 判定标准 |
|---|---|
| 可空性标注 | 公开 API 缺 `@NonNull`/`@Nullable`——调用方无从判断，Kotlin 互操作会把它变成平台类型。 |
| 裸线程 | `AsyncTask` 或裸 `Thread`，而项目已经用协程。 |
| 静态引用泄漏 | `static` 字段持有 Context、View、Activity 或资源对象。 |
| 监听器反注册 | 回调/监听器注册了，但从不在生命周期 teardown 里反注册。 |
| 废弃 API | 同样对照团队 lint 报告。 |
| **禁止反射** | 与第 9 节同一条规则：新增的 `java.lang.reflect`（`Class.forName`、`getDeclaredMethod`/`getDeclaredField`、`Method.invoke`、`Field.setAccessible(true)`）、只为转型存在的强转、或用 `@SuppressWarnings` 压住的反射，一律报；第三方只提供反射入口且改动写明理由时除外。判定范围同样是这次改动引入的反射。 |
| **只走 HTTPS** | 与第 9 节同一条规则：新增的明文 `http://` 目标（`OkHttp`/`Retrofit` base URL、`URL`/`HttpURLConnection`、`WebView.loadUrl`、硬编码端点）报；`ConnectionSpec.CLEARTEXT`、信任一切的 `X509TrustManager`、恒返回 true 的 `HostnameVerifier` 按整份文件报。XML 命名空间 URI 不算流量。`high` / `security`。 |
| **禁止的权限（9 项，代码侧，整份文件判）** | 与第 9 节同一条规则：`Manifest.permission.READ_EXTERNAL_STORAGE`、`.WRITE_EXTERNAL_STORAGE`、`.MANAGE_EXTERNAL_STORAGE`、`.READ_MEDIA_IMAGES`、`.READ_MEDIA_VIDEOS`、`.READ_CONTACTS`、`.ACCESS_FINE_LOCATION`、`.READ_PHONE_NUMBERS`、`.QUERY_ALL_PACKAGES`，以及 `"android.permission.X"` 字面量，都不许出现；把它们交给 `checkSelfPermission`、`requestPermissions`、`PackageManager.checkPermission`、`AppOpsManager`、`shouldShowRequestPermissionRationale`，以及 `MANAGE_EXTERNAL_STORAGE` 的申请入口 `Environment.isExternalStorageManager()`、`Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION`、`Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` 同样报。媒体走照片选择器或 `MediaStore` 作用域存储，位置用用户输入，查应用用 `<queries>`/Intent。注释 / javadoc 里的提及不算。**文件进了审查范围就判**，不看 diff 是否碰到那一行。`critical` / `security`。 |
| **禁止的敏感 API**（整份文件判） | 与第 9 节同一条规则：`Runtime.getRuntime().exec(...)`、`new ProcessBuilder(...).start()`（`critical`）；`DexClassLoader`、`PathClassLoader`、`InMemoryDexClassLoader`、`ClassLoader.defineClass(...)`、`DexFile.loadDex`（`critical`）；`Environment.getExternalStorageDirectory()`、`getExternalStoragePublicDirectory(...)`、手写 `/sdcard` 路径（`medium`）。只要这个 Java 文件因任何改动进入审查范围就判，不看违规那行是否被改动。反射绕到这些 API 按 `critical` 报。三条都归 `security`。 |

---

## 运行级团队约定（`android-conventions.md`）

这部分不是逐文件规则，而是注入到每次审查 prompt 里的团队背景。其中**技术栈基线**是唯一必须按你们项目改的地方（以 `<!-- TODO(team) -->` 标出）：语言 Kotlin 优先、UI Compose 优先、异步 Coroutines + Flow、以及 DI / 网络序列化 / 架构分层 / 模块边界四项，要写出「是什么」，模型才能判断「什么算偏离」。

**版本基线**（团队统一，已写进第 1 节，不需要按项目改）：Gradle（wrapper 分发版本）≥ 9.0.0、AGP（`com.android.*`）≥ 9.0.0、Adjust SDK（`com.adjust.sdk:*`）≥ 5.5.0、`minSdk` = 23、`targetSdk` ≥ 36。它同时出现在逐文件规则（`**/build.gradle*`、`**/settings.gradle*`、`**/libs.versions.toml`、`**/gradle/wrapper/gradle-wrapper.properties`）和这份运行级背景里：前者在文件被审查时判定，后者兜住 `buildSrc`、约定插件等不在 glob 里的写法。判定口径是「取值不得低于基线」，与 diff 是否碰到那一行无关——这是团队统一规则与其余规则唯一的差别。

**禁止反射**同样在第 1 节写明（判定范围是本次改动引入的反射，不是翻旧账），逐文件版在 `**/*.{kt,kts}` 与 `**/*.java`。`android:angle` 必须是 45 的倍数则在第 8 节（`**/res/**/*.xml`，含 `src/main`、`src/debug`、`src/release` 与 flavour 源集）。

**安全基线**（团队统一，同样写在第 1 节与第 3 节红线里）：`allowBackup` 必须 `false`、应用只走 HTTPS、`<application>` 不得声明 `android:requestLegacyExternalStorage="true"`（legacy 存储退出开关，逐文件版见第 7 节）。逐文件版落在 `**/AndroidManifest.xml`、`**/res/**/*.xml`（含 debug/release/flavour 源集）、`**/*.{kt,kts}`、`**/*.java`。口径是「按文件判」：Manifest 与网络配置一出现违规就报（不看 diff），网络配置文件按名字任意、按源集定 severity（debug/test 源集 = `medium`，其它 = `high`），代码/资源里的 `http://` 端点按新增行报——历史 URL 不会因为改了别处就被翻出来。

**R8 优化基线**（团队统一，写在第 1 节与第 3 节红线里）：release 构建类型必须同时开代码压缩与资源压缩、不得用 `proguard-android.txt`、不得关掉 R8 全模式（`android.enableR8.fullMode=false`）、库模块的 `consumer-rules.pro` 里不得出现全局选项。这四项是 Play 后台那三个优化指标（混淆 / 优化 / 裁剪）的直接来源，也是"文件进了审查范围就判"的口径。逐文件版落在 `**/build.gradle*`、`**/gradle.properties`、`**/*.pro`，全部按整份文件判；`.pro` 规则里只有 consumer rules 的全局选项吃整份文件判，其余条目（keep 规则、`-dontwarn` 等）仍按 diff 判。

**权限基线**（团队统一，第 1 节与第 3 节红线各一条）：9 个团队禁止的权限一个都不能声明——`READ_EXTERNAL_STORAGE`、`WRITE_EXTERNAL_STORAGE`、`MANAGE_EXTERNAL_STORAGE`、`READ_MEDIA_IMAGES`（照片）、`READ_MEDIA_VIDEOS`（视频）、`READ_CONTACTS`、`ACCESS_FINE_LOCATION`、`READ_PHONE_NUMBERS`、`QUERY_ALL_PACKAGES`。逐文件版落在 `**/AndroidManifest.xml`（声明）与 `**/*.{kt,kts}`、`**/*.java`（代码里出现权限名或发起申请），口径与安全基线一致：文件进了审查范围就判，不看 diff 是否碰到那一行。这是发版红线，报 `critical` / `security`。

**禁止的敏感 API**（同样在第 1 节与第 3 节红线里）是安全基线里最「不看 diff」的一条：某个 Kotlin/Java 文件因为**任何**改动进入审查范围，文件里既有的 `exec`、`DexClassLoader`、`getExternalStorageDirectory` 都要报。逐文件版落在 `**/*.{kt,kts}` 与 `**/*.java` 两条规则里。这里有个易踩的坑：这两条规则末尾的 Scope 行写的是「不报 diff 没碰到的既有问题」，而条目要求整份文件判——**触发文件级判定的条目必须自己在正文里写清范围**，否则模型会照 Scope 行漏报（实测踩过一次）；Scope 行已改成「除上面这条敏感 API 外，其余只看本次改动」。同一件事也发生在 R8 优化基线上：`**/build.gradle*` 的 Scope 行加了「除版本基线、release 安全网基线与默认 ProGuard 文件基线外」、`**/gradle.properties` 加了「除全模式条目外」、`**/*.pro` 加了「除 consumer rules 的全局选项外」的例外。但还有一个更硬的边界改不动：**整份文件判只决定「模型报不报」，决定不了「OCR 报不报」**——后置过滤按「评论描述的是不是本次 diff 里的代码」裁，违规行落在 hunk 之外时照样被丢掉（实测 `isMinifyEnabled=false` 死在这一步，`fullMode` 因为同 hunk 才留下）。要当硬门禁，得用 `--no-filter` 或让 CI 另跑一条静态检查；细节见 `ADDED-RULES.md` 3.2 节。

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

完整命令见同目录 `README.md` 的「三步采纳」和「验收」。要点：拷 `rule.json` → `<repo>/.opencodereview/rule.json`、`android-conventions.md` → `<repo>/.ocr/`、`scripts/` → `<repo>/scripts/`；填完所有 `<!-- TODO(team) -->`；跑 `collect-lint-report.sh`（自动执行 `./gradlew lint` 并读取各模块报告，传报告路径则跳过 lint）生成全量 lint 报告；上线前务必用 `ocr rules check <file>` 看 Source/Pattern 两行、用 `ocr review --preview --format json` 确认过滤生效。

## 如何保持同步

- 本文档与 `rule.json`、`android-conventions.md` 是同一套规范的三份：**改规范只改 `rule.json` 或 `android-conventions.md`，然后同步更新本文档**，不要让它们各自演化。
- 本次新增的规则另有一份汇总视图 `ADDED-RULES.md`（版本基线 5 条 + 安全基线 5 条 + 代码规则 2 条 + R8 优化基线 3 条，规则与分类都用表格列出，同样跟着改）；该文件第 8 节还有一份 `rule.json` **全部**检查点的索引（10 条文件规则 / 81 条，一行一条，只给标题、判定范围与指向本文档同号小节的指针）——**加规则要跟着补一行**，判定细节仍以 `rule.json` 与本文档为准。
- 改完用 `ocr rules check` 确认命中，跑一次真实 PR 看是否误报。加规则容易，去掉噪声难。
- 规则里**不要写「注意性能」这类写不出判定标准的话**——那会变成模型的自由发挥。
