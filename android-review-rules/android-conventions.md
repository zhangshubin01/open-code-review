# Android 团队审查约定（运行级背景）

> 用法：`ocr review -B .ocr/android-conventions.md`
> 这个文件是**运行级**上下文，会注入到 plan 和主循环的 prompt 里，对本次审查的每个文件都生效。
> 逐文件的判定标准在 `.opencodereview/rule.json` 里，两者分工：这里写"团队是谁、红线是什么"，那里写"看到什么代码报什么问题"。

---

## 1. 技术栈基线

<!-- TODO(team): 按你们项目实际情况改。写清楚"是什么"，模型才能判断"什么算偏离"。 -->

- 语言：Kotlin 优先；Java 仅存在于历史模块，不接受新增 Java 文件（除非改的是已有 Java 文件）。
- UI：Jetpack Compose 优先；新功能不得使用 XML 布局（除 `res/values/` 资源与 `AndroidManifest.xml`）。
- 异步：Kotlin Coroutines + Flow；禁止 `AsyncTask`、禁止 `GlobalScope`。
- 禁止反射：不用 `java.lang.reflect`（`Class.forName`、`getDeclaredMethod`/`getDeclaredField`、`Method.invoke`、`setAccessible(true)`…），也不用 Kotlin 反射（`kotlin.reflect.full.*`、`::class.members`、`KClass.memberProperties`…）。反射把依赖藏在字符串里、让 R8 裁剪失效、只在 release 构建暴露问题，所以团队直接禁止，而不是补 keep 规则。唯一例外是第三方只提供反射入口（SDK 工厂、序列化库自己生成的 adapter、插件公开 API），此时必须在改动里写明理由。
- 禁止运行外部命令与动态加载代码（团队红线，进来就整份文件判）：不 `Runtime.getRuntime().exec(...)`、不 `new ProcessBuilder(...)` 起进程——需要什么就用 SDK（`ConnectivityManager`、`InetAddress.isReachable()`）；不用 `DexClassLoader`、`PathClassLoader`、`InMemoryDexClassLoader`、`ClassLoader.defineClass(...)`、`DexFile.loadDex` 加载 APK 之外的代码（热修复、插件、加固壳都在此列）。共享外部存储同样不用：`Environment.getExternalStorageDirectory()`、`getExternalStoragePublicDirectory(...)`、手写 `/sdcard` 或 `/storage/emulated/0` 路径，都换成 `context.filesDir` / `getExternalFilesDir(null)`。用反射绕到这些 API（`Class.forName("java.lang.Runtime")` 加 `getDeclaredMethod("exec")`）算蓄意规避，按 `critical` 报。Manifest 侧同理：`<application>` 上不得声明 `android:requestLegacyExternalStorage="true"`——应用 target 到 API 30 及以上之后系统就忽略这个 scoped storage 退出开关，团队基线是 `targetSdk ≥ 36`，留着它只是一份死配置加一次 legacy 共享存储的意图声明，`targetSdk` 一旦降回 29 还会立刻生效。**整份文件判**，报 `medium` / `security`。
- 安全基线（团队统一）：`AndroidManifest.xml` 的 `android:allowBackup` 必须显式设为 `false`——平台默认是 `true`，不写就等于开着，`fullBackupContent`/`dataExtractionRules` 不能替代。应用只走 HTTPS：明文 `http://` 网络端点、`usesCleartextTraffic="true"`、允许明文或信任用户安装 CA 的 `networkSecurityConfig` 一律不允许。XML 命名空间 URI（`http://schemas.android.com/...`）不是流量，不在此列。**网络配置要看所有源集**：`android:networkSecurityConfig="@xml/…"` 只是引用一个文件名，要打开那个文件核对——文件名可能是混淆过的（`@xml/hofeuzirufea_vagepawudusi` 这种），根元素是 `<network-security-config>` 就算；同一个名字在不同源集可以是不同内容，`src/debug/res`、`src/release/res`、flavour 的 `res/` 都要看。明文开关只出现在 debug/test 源集报 `medium`（不得带进 release，release 侧必须仍是 `false`），出现在 `src/main/res`、`src/release/res`、flavour 源集报 `high`。
- 禁止的权限（团队统一，进来就整份文件判，发版红线）：`AndroidManifest.xml` 不得声明这 9 个权限——`READ_EXTERNAL_STORAGE`、`WRITE_EXTERNAL_STORAGE`、`MANAGE_EXTERNAL_STORAGE`、`READ_MEDIA_IMAGES`（照片）、`READ_MEDIA_VIDEOS`（视频）、`READ_CONTACTS`、`ACCESS_FINE_LOCATION`、`READ_PHONE_NUMBERS`、`QUERY_ALL_PACKAGES`。这是隐私合规与应用商店的边界，团队不接需要它们的需求：取媒体走系统照片选择器（Photo Picker）或 `MediaStore` 作用域存储，定位用用户自己填写或选择的位置，查已安装应用走 `Intent` 解析或 `<queries>`（`<queries>` 是 `QUERY_ALL_PACKAGES` 的官方替代，不算违规）。声明成什么形式都算违规，用 `tools:node="remove"` 摘掉不算。代码里同样不允许出现：`Manifest.permission.X` 常量、`"android.permission.X"` 字面量、本地别名，或把权限名当字符串传出去（权限映射表、权限数组）；发起申请的 `checkSelfPermission`、`requestPermissions`、`ActivityResultContracts.RequestPermission()`、`requestPermissionLauncher.launch(...)`、`shouldShowRequestPermissionRationale`、`AppOpsManager`、`PackageManager.checkPermission`，以及 `MANAGE_EXTERNAL_STORAGE` 的申请入口 `Environment.isExternalStorageManager()`、`Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION`、`Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` 一并报——只引用不申请也算，注释 / KDoc 里的提及不算。**整份文件判**，按 `critical` / `security` 报。
- 版本基线（团队统一，对所有模块生效）：Gradle（wrapper 分发版本）≥ 9.0.0；Android Gradle Plugin（AGP，`com.android.*`）≥ 9.0.0；Adjust SDK（`com.adjust.sdk:*`）≥ 5.5.0；`minSdk` = 23；`targetSdk` ≥ 36。这几项不是"这次改动才好"的选择题——只要构建脚本、版本目录或 `gradle-wrapper.properties` 在审查范围里，取值低于基线就报，哪怕 diff 没碰那一行。取值低于基线按约定偏离报 `medium`，把原本合规的值降到基线以下按行为变更报 `high`。
- R8 优化基线（团队统一）：release 构建类型必须同时开代码压缩（`isMinifyEnabled = true`）与资源压缩（`isShrinkResources = true`）；不得用 `getDefaultProguardFile("proguard-android.txt")`（它带 `-dontoptimize`，R8 完全不优化、Play 的优化百分比为 0）；不得关掉 R8 全模式（`gradle.properties` 里的 `android.enableR8.fullMode=false`）；库模块的 `consumer-rules.pro` 里不得放全局选项（`-dontoptimize`、`-dontshrink`、`-dontobfuscate`、全量 keep）。这几项就是 Play 后台混淆 / 优化 / 裁剪三个百分比的直接来源，同属"文件进了审查范围就判"，不看 diff 碰没碰到那一行；关闭安全网或从合规值改坏报 `high`，全模式被关报 `medium`。
- DI：<!-- TODO(team): Hilt / Koin / 手写容器 -->
- 网络/序列化：<!-- TODO(team): Retrofit + Moshi / kotlinx.serialization -->
- 架构分层：<!-- TODO(team): 单模块 / :core: :feature: 多模块；UI -> Domain -> Data，跨层调用的约束 -->
- 模块边界：<!-- TODO(team): feature 之间不得直接依赖 -->

## 2. 严重度与分类（必须统一，否则 CI 分流失效）

OCR 的评论带 `severity` 和 `category` 两个字段，取值是**固定枚举**，团队的 CI 分流（GitHub Action 的 `route_severity_below` / `route_categories`）和事后过滤（`ocr session comments --severity critical,high --category bug,security`）都建立在这套词表上。所以规则里必须让模型用同一套词。

**severity**（枚举：`critical` / `high` / `medium` / `low`），团队的判定标准：

| 值 | 什么时候用 |
|---|---|
| `critical` | 会导致发版崩溃、数据丢失、凭据泄露、越权访问 |
| `high` | 功能性缺陷、生命周期/线程错误、契约或行为变更、Manifest 安全边界被放宽 |
| `medium` | 可维护性问题、资源/内存浪费、可访问性与国际化缺失、约定偏离 |
| `low` | 风格、命名、文案、可读性 |

**category**（枚举：`bug` / `security` / `performance` / `maintainability` / `test` / `style` / `documentation` / `other`），团队的归属约定：

- 只要涉及可被外部触达的边界（Manifest、Intent、Provider、网络、存储权限）→ `security`，即使同时是 bug。
- 崩溃、空指针、并发/生命周期错误 → `bug`。
- 主线程阻塞、内存泄漏、重组开销 → `performance`。
- 分层破坏、依赖方向错误、重复实现 → `maintainability`。
- 一个改动同时属于多类时，取**最严重的那个**，不要报两条。

## 3. 全局红线（任何文件里出现都要报）

1. 硬编码的密钥、token、签名密码、私钥。
2. 关闭安全网：`minifyEnabled=false`、`isShrinkResources=false`、`getDefaultProguardFile("proguard-android.txt")`、`android.enableR8.fullMode=false`、库模块 `consumer-rules.pro` 里的全局选项、`android:debuggable=true`、`android:allowBackup=true`、移除 keep 规则。
3. 让组件可被任意应用触达：导出且无权限守卫的 Activity/Service/Receiver/Provider。
4. 在应用里引入全新技术栈（新框架、新网络库、新 DI）而没有在改动里说明理由。
5. 静默失败：吞掉异常、忽略错误返回值、`catch` 后不处理也不上报。
6. 明文 HTTP：新增 `http://` 网络端点，或打开明文流量（`usesCleartextTraffic="true"`、`cleartextTrafficPermitted="true"`、信任用户安装的 CA）。XML 命名空间 URI 不算。
7. 运行外部命令或加载 APK 之外的代码：`Runtime.exec`、`ProcessBuilder`、`DexClassLoader`/`PathClassLoader`/`InMemoryDexClassLoader`/`ClassLoader.defineClass`/`DexFile.loadDex`；共享外部存储（`getExternalStorageDirectory`、手写 `/sdcard` 路径）；`AndroidManifest.xml` 里声明 `android:requestLegacyExternalStorage="true"`（legacy 存储退出开关，同属这条）。反射绕进来按同一红线报。
8. 声明团队禁止的权限：`READ_EXTERNAL_STORAGE`、`WRITE_EXTERNAL_STORAGE`、`MANAGE_EXTERNAL_STORAGE`、`READ_MEDIA_IMAGES`（照片）、`READ_MEDIA_VIDEOS`（视频）、`READ_CONTACTS`、`ACCESS_FINE_LOCATION`、`READ_PHONE_NUMBERS`、`QUERY_ALL_PACKAGES`——隐私合规与应用商店的发版红线，写成什么形式、加不加理由都不放行。代码里引用这些权限名（常量、字面量、别名、当字符串传递）或发起申请，同样按这条报。

## 4. lint 全量扫描与 OCR 的分工（别在这里重复劳动）

每次审查前，`scripts/review.sh` 会跑一次全量 `./gradlew lint`，把结果整理成 `.ocr/lint-report.md` 作为背景注入。OCR 对照这份报告审查，**不重复报** lint 已经发现的问题，只做工具做不到的事。

以下检查交给工具链，OCR 规则里**不要**写，模型也不该重复报：

- 代码格式、缩进、import 顺序、命名规范 → ktlint
- 可静态判定的代码异味、复杂度、未使用资源 → detekt / Android Lint
- API 级别误用（`NewApi`）、资源引用错误、Manifest 结构错误 → Android Lint
- 已知的 `@Deprecated` 符号 → Android Lint + Kotlin 编译警告（见 `.ocr/lint-report.md`）
- 固定符号的静态匹配（`Runtime.exec`、`ProcessBuilder`、`DexClassLoader`、`getExternalStorageDirectory`、`/sdcard` 字面量）→ 自定义 Android Lint 规则 / Semgrep 兜底

OCR 只做这些工具做不到的事：**语义、意图、跨文件影响、约定与架构的一致性**——在敏感 API 上就是那些列表匹配抓不到的写法：反射与字符串拼出来的调用、import 别名、封装多层的工具类、看起来无害实则起进程的第三方接口。两边同时报同一处是允许的，但 OCR 不要只复述一遍 grep 的结论。

## 5. 交付质量的最低要求

- 新增或修改的公开行为要有对应测试；测试缺失时按 `medium` 报一条，不要每个文件都报。
- 同一个问题在一个文件里只报一次，不要对同一处重复刷屏。
- 报问题必须给出**可以照着改的具体建议**；拿不准就写"需要确认"并说明你的依据，不要编造替代 API 或不存在的 API。
