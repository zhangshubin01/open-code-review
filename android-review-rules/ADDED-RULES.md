# Android 新增审查规则（第一批 11 条 + 第二批 R8 3 条 + 第三批 1 条）

> **给人看的**：这份文件回答一个问题——这段时间给 Android 规范加了哪些规则、加在哪类文件上、怎么判、判多重。
> 判定标准的机器版在 `rule.json`，团队背景版在 `android-conventions.md`，逐条详解在 `CONVENTIONS.md`；本文件是它们的**新增视图**，不定义新规则。改规则时几份一起改。
>
> **怎么读**：1 节一览表（15 条）→ 2 节逐条判定标准 → **3 节判定口径与两个坑（改规则前必读）** → 4 节落在哪些文件 → 5 节验收记录与复现命令 → 6 节待定与已知边界 → 7 节 R8 那批的背景与事实核对 → 8 节 `rule.json` 全量索引（81 条检查点，一行一条）。
>
> 一共 **15 条新规则**，按批与口径分五组：
> **第一批 · 版本基线 5 条**（Gradle wrapper、AGP、Adjust SDK、minSdk、targetSdk）与 **第一批 · 安全基线 4 条**（`allowBackup=false`、只走 HTTPS、禁止的权限 9 项〔声明与代码里都不许出现〕、禁止的敏感 API）——团队统一口径，文件进了审查范围就判，不看 diff 有没有碰那一行；
> **第一批 · 代码规则 2 条**（禁止反射、`android:angle` 必须是 45 的倍数）——按套件默认口径，只判这次改动引入的代码；
> **第二批 · R8 优化基线 3 条**（release 安全网、`proguard-android.txt`、R8 全模式与 consumer rules 全局选项，见 2.3）；
> **第三批 · 安全基线 1 条**（`<application>` 不得声明 `android:requestLegacyExternalStorage="true"`，见 2.2）——团队统一口径，文件进了审查范围就判。

---

## 1. 一览表（15 条）

| # | 批次 | 规则 | 要求 | 判定范围 | 落在哪类文件 | severity | 在 `rule.json` 里的形态 |
|---|---|---|---|---|---|---|---|
| 1 | 第一批 | Gradle wrapper 分发版本 | **≥ 9.0.0** | 整份文件判 | `**/gradle/wrapper/gradle-wrapper.properties` | `medium` / `high` | **新增规则条目**（第 5 条规则） |
| 2 | 第一批 | Android Gradle Plugin（AGP） | **≥ 9.0.0** | 整份文件判 | `**/build.gradle*`、`**/settings.gradle*`、`**/libs.versions.toml` | `medium` / `high` | 在三条既有规则里各加一条 |
| 3 | 第一批 | Adjust SDK | **≥ 5.5.0** | 整份文件判 | `**/build.gradle*`、`**/libs.versions.toml` | `medium` / `high` | 在两条既有规则里各加一条 |
| 4 | 第一批 | `minSdk` | **= 23** | 整份文件判 | `**/build.gradle*`、`**/libs.versions.toml` | `medium` / `high` | 在两条既有规则里各加一条 |
| 5 | 第一批 | `targetSdk` | **≥ 36** | 整份文件判 | `**/build.gradle*`、`**/libs.versions.toml` | `medium` / `high` | 在两条既有规则里各加一条 |
| 6 | 第一批 | `android:allowBackup` | **必须 `false`** | 整份文件判 | `**/AndroidManifest.xml` | `high` / `security` | 在既有 Manifest 规则里加一条 |
| 7 | 第一批 | 只走 HTTPS | **禁止明文 `http://`** | 整份文件判（代码侧的 `http://` 端点按新增行） | `**/AndroidManifest.xml`、`**/res/**/*.xml`（含 `src/main`、`src/debug`、`src/release`、flavour 源集）、`**/*.{kt,kts}`、`**/*.java` | `high` / `security`（debug·test 源集 `medium`） | 在四条既有规则里各加一条；资源规则的 glob 由 `**/src/main/res/**/*.xml` 放宽为 `**/res/**/*.xml` |
| 8 | 第一批 | 禁止反射 | **不允许新增** | 按 diff 判 | `**/*.{kt,kts}`、`**/*.java` | 约定偏离 `medium`；绕过访问限制 / 触达隐藏 API `high` | 在两条既有规则里各加一条 |
| 9 | 第一批 | `android:angle` | **必须是 45 的倍数** | 按 diff 判 | `**/res/**/*.xml` | `medium` / `bug` | 在既有资源规则里加一条 |
| 10 | 第一批 | 禁止的权限（9 项） | **声明与代码里都不许出现** | 整份文件判 | `**/AndroidManifest.xml`、`**/*.{kt,kts}`、`**/*.java` | `critical` / `security` | 在既有 Manifest 规则里加一条 + 在 Kotlin / Java 两条规则里各加一条 |
| 11 | 第一批 | 禁止的敏感 API | **不跑外部命令、不动态加载 APK 之外的代码、不用共享外部存储** | 整份文件判 | `**/*.{kt,kts}`、`**/*.java` | 外部命令与动态加载 `critical`；共享外部存储 `medium`；用反射规避 `critical` | 在两条既有规则里各加一条 |
| 12 | 第二批 | release 安全网 | **release 必须同时开 `isMinifyEnabled` 与 `isShrinkResources`** | 整份文件判 | `**/build.gradle*` | `high` | 在既有规则里加一条（明细见 2.3） |
| 13 | 第二批 | 不得用 `proguard-android.txt` | **改用 `proguard-android-optimize.txt`** | 整份文件判 | `**/build.gradle*` | `high` | 在既有规则里加一条（明细见 2.3） |
| 14 | 第二批 | R8 全模式与 consumer rules | **不得关 `fullMode`；库模块 `consumer-rules.pro` 不得放全局选项** | `gradle.properties` 整份文件判；`.pro` 的 consumer rules 全局选项整份文件判 | `**/gradle.properties`、`**/*.pro` | 全模式 `medium`；consumer rules `high` | 在两条既有规则里各加一条（明细见 2.3） |
| 15 | 第三批 | legacy 存储退出开关 | **`<application>` 不得声明 `android:requestLegacyExternalStorage="true"`** | 整份文件判 | `**/AndroidManifest.xml` | `medium` / `security` | 在既有 Manifest 规则里加一条 |

一句话的关系：**Gradle（构建工具）和 AGP（构建插件）都要 ≥ 9.0.0 且必须配套**；**Adjust SDK ≥ 5.5.0**；`minSdk` 钉死 23、`targetSdk` 不低于 36；**`allowBackup` 必须关掉**；**应用只走 HTTPS**；**团队禁止的 9 个权限一律不得声明**；**`requestLegacyExternalStorage` 不许声明**；**代码里不许新写反射**；**渐变的 `android:angle` 只能是 45 的倍数**；**外部命令、动态加载的代码、共享外部存储一律不许出现**；**release 的安全网不许关、不许用 `proguard-android.txt`、不许关 R8 全模式**。

怎么读「判定范围」这一列：**整份文件判** = 文件进了审查范围就报，不看 diff 碰没碰那一行；**按 diff 判** = 只看本次改动增删改的行。1–5 号的 `medium` / `high` 是「取值本来就低于基线（文件被审时顺带发现）= `medium`；把原本合规的值改到基线以下 = `high`」。

团队统一口径的 **13 条**（版本基线 5 + 安全基线 5 + R8 基线 3）在 `rule.json` 正文里都写明了「整份文件判」。仍按新增行看的只有两处：安全基线里代码侧的 `http://` 端点（第 7 号），以及 `.pro` 规则里 consumer rules 全局选项以外的其余条目（keep 规则、`-dontwarn` 等）。

---

## 2. 判定标准

逐条列出这 15 条的判定标准（这里是中文要点，英文原文即 `rule.json` 的正文，改规则以那边为准），按批分五组。每组附 severity；`category` 没有全部钉死，见第 6 节。

### 2.1 版本基线（5 条，按整份文件判）

| 规则 | 判定标准（规则原文要点，英文原文见 `rule.json`） | 什么不算违规 |
|---|---|---|
| Gradle wrapper ≥ 9.0.0 | 取 `distributionUrl` 里的 `gradle-x.y.z` 片段（`gradle-9.6.0-bin.zip` 即 9.6.0，写 `9.0` 等同 9.0.0），低于 9.0.0 即报 | `-SNAPSHOT`、`-rc`、`-milestone` 反而算不达标（预发布分发） |
| AGP ≥ 9.0.0 | 本文件声明的每个 `com.android.*` 插件（`application` / `library` / `legacy-kapt`）都适用；`id 'com.android.application' version '9.4.0'`、`classpath 'com.android.tools.build:gradle:9.4.0'`、或经版本目录 alias 解析都算 | 版本从别处（BOM、父插件）声明、本文件看不到数值时不硬判 |
| Adjust SDK ≥ 5.5.0 | 本文件带的每个 `com.adjust.sdk:*` 依赖（`adjust-android` 及配套 artifact），inline 版本或经版本目录 alias 解析都算 | 项目根本没接 Adjust 时不报 |
| `minSdk` = 23 | 精确等于 23：Groovy `minSdkVersion 23` / Kotlin DSL `minSdk = 23` / 版本目录里本文件读到的值 | — |
| `targetSdk` ≥ 36 | 不低于 36，写法同上 | — |

| 情形 | severity | 理由 |
|---|---|---|
| 取值本来就低于基线（文件被审时顺带发现） | `medium` | 约定偏离 |
| 把原本合规的值改到基线以下 | `high` | 契约/行为变更 |

这几条分散落在 4 条 `rule.json` 规则里（`**/build.gradle*`、`**/settings.gradle*`、`**/libs.versions.toml`、`**/gradle/wrapper/gradle-wrapper.properties`）——每条规则里这次各加了哪条、`Scope:` 行怎么配合，见 4.1 与 3.1。

### 2.2 安全基线（5 条，按整份文件判；其中最后一条是第三批新增）

| 规则 | 判定标准（规则原文要点） | severity / category |
|---|---|---|
| **`android:allowBackup` 必须 `false`** | `<application>` 上的 `android:allowBackup` 必须显式设为 `false`。设为 `true`、或**干脆不写**（平台默认就是 `true`），应用的文件、数据库、SharedPreferences 都能被 `adb backup` 拉走；`android:fullBackupContent`/`dataExtractionRules` 不能替代它。**文件进了审查范围就报**，不看 diff 是否碰到那一行。 | `high` / `security` |
| **应用只走 HTTPS** | 不支持明文 HTTP。Manifest 侧：`android:usesCleartextTraffic="true"`、允许明文的 `networkSecurityConfig`（base-config 或任一 `<domain-config>` 的 `cleartextTrafficPermitted="true"`）、信任用户安装的 CA —— 文件进了审查范围就报。代码/资源侧：新增的 `http://` 网络目标（OkHttp/Retrofit `baseUrl`、`URL`/`HttpURLConnection`、`WebView.loadUrl`、硬编码端点、deeplink、`strings.xml` 里的 base URL）按新增行报；显式的明文开关（`ConnectionSpec.CLEARTEXT`、信任一切的 `X509TrustManager`、恒返回 true 的 `HostnameVerifier`）按整份文件报。<br>**不报**：XML 命名空间 / schema URI 里的 `http://`（不是流量）；`localhost`/`127.0.0.1`/`10.0.2.2` 这类本地开发地址，前提是只出现在 debug-only 且改动里写明。<br>**网络配置文件的名字不作数**：`android:networkSecurityConfig="@xml/…"` 只是引用一个文件名，要打开那个文件核对，根元素是 `<network-security-config>` 就算，名字可能是混淆过的（`@xml/hofeuzirufea_vagepawudusi`）——同一个名字在不同源集可以是不同内容。**按源集定 severity**：明文开关只出现在 `src/debug/res`、`src/androidTest/res` 报 `medium`（不得带进 release，release 侧必须仍是 `false`）；出现在 `src/main/res`、`src/release/res`、flavour 的 `res/` 报 `high`。 | `high` / `security`（debug 或 test 源集 `medium` / `security`） |
| **禁止的权限（9 项）** | `AndroidManifest.xml` 不得声明：`READ_EXTERNAL_STORAGE`、`WRITE_EXTERNAL_STORAGE`、`MANAGE_EXTERNAL_STORAGE`、`READ_MEDIA_IMAGES`（照片）、`READ_MEDIA_VIDEOS`（视频）、`READ_CONTACTS`、`ACCESS_FINE_LOCATION`、`READ_PHONE_NUMBERS`、`QUERY_ALL_PACKAGES`。按**权限名**匹配，`android.permission.X` 与 `android:name="android.permission.X"` 是同一种写法；`<uses-permission>` 与 `<uses-permission-sdk-23>` 同样处罚。理由：这是隐私合规与应用商店的发版红线，团队不接需要它们的需求。替代做法——取媒体走系统照片选择器（Photo Picker）或 `MediaStore` 作用域存储；定位用用户自己填写或选择的位置；查已安装应用走 `Intent` 解析或 `<queries>`（`<queries>` 是 `QUERY_ALL_PACKAGES` 的官方替代，**不算违规**）。`tools:node="remove"` 把它摘掉不算违规。**代码里同样不许出现**：`Manifest.permission.X` 常量、`"android.permission.X"` 字面量、本地别名、当字符串传递（权限映射表、权限数组）都算；发起申请的写法（`checkSelfPermission`、`requestPermissions`、`ActivityResultContracts.RequestPermission()`、`requestPermissionLauncher.launch(...)`、`shouldShowRequestPermissionRationale`、`AppOpsManager`、`PackageManager.checkPermission`，以及 `MANAGE_EXTERNAL_STORAGE` 的申请入口 `Environment.isExternalStorageManager()`、`Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION`、`Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`）一并报——注释 / KDoc / javadoc 里的提及不算。只引用不申请也算违规。**文件进了审查范围就报**，不看 diff 是否碰到那一行。 | `critical` / `security` |
| **禁止的敏感 API** | 三组合规红线，**文件进了审查范围就判，不看 diff 是否碰到那一行**：<br>① **跑外部命令** —— `Runtime.getRuntime().exec(...)`、`ProcessBuilder(...).command(...)`/`.start()`。没有任何正当理由，要做的事用 SDK（`ConnectivityManager`、`InetAddress.isReachable()`）。<br>② **动态加载 APK 之外的代码** —— `DexClassLoader`、`PathClassLoader`、`InMemoryDexClassLoader`、`ClassLoader.defineClass(...)`、`DexFile.loadDex`。热修复、插件、加固壳都算隐藏动态代码，应编译进 APK 或独立模块。<br>③ **共享外部存储** —— `Environment.getExternalStorageDirectory()`、`getExternalStoragePublicDirectory(...)`、手写 `/sdcard` 或 `/storage/emulated/0` 路径，改用 `context.filesDir` / `getExternalFilesDir(null)`。<br>用反射绕到这些 API（`Class.forName("java.lang.Runtime")` 加 `getDeclaredMethod("exec")`、按名字取类加载器）算**蓄意规避**，按 `critical` 报，不按普通反射条处理。 | ①② `critical` / `security`；③ `medium` / `security` |
| **不得声明 legacy 存储退出开关** | `<application>` 上不得有 `android:requestLegacyExternalStorage="true"`。官方文档：应用 target 到 Android 11（API 30）及以上后，系统就忽略这个 scoped storage 退出开关；团队基线是 `targetSdk ≥ 36`，所以它只是一份**死配置**——不改运行时行为，却仍在声明「要 legacy 共享外部存储」，`targetSdk` 一旦降回 29 立刻生效。移除即可，没有替代写法，也不需要迁移路径（target ≥ 30 的应用本来就在 scoped storage 下运行，删掉它运行时行为不变）。**文件进了审查范围就报**，不看 diff 是否碰到那一行。 | `medium` / `security` |

### 2.3 R8 优化基线（3 条）

> 触发这三条的背景、Play 的 R8 四项指标里哪些审得了哪些审不了，见第 7 节。

| # | 规则 | 判定标准 | 落在哪类文件 | severity |
|---|---|---|---|---|
| 12 | release 安全网（团队基线） | release 构建类型必须同时写 `isMinifyEnabled = true` 与 `isShrinkResources = true`。关掉压缩会连裁剪、混淆、优化一起没了，`shrinkResources` 没有 minify 也不生效。**整份文件判**，不看 diff 有没有碰那一行。 | `**/build.gradle*` | 关闭或从 `true` 改小 `high` |
| 13 | 不得用 `proguard-android.txt` | 这个默认文件带 `-dontoptimize`（`proguard-android-optimize.txt` 不带），R8 因此完全不优化，Play 的优化百分比就是 0。`postProcessing` 块里把 `isOptimizationsEnabled` / `isObfuscationEnabled` / `isShrinkingEnabled` 设成 `false` 同理。**整份文件判**，不看 diff 有没有碰那一行。 | `**/build.gradle*` | `high` |
| 14 | 不得关 R8 全模式、consumer rules 不得放全局选项 | `android.enableR8.fullMode=false` 关掉类重打包与更强的优化（**整份文件判**）；库模块 `consumer-rules.pro` 里的 `-dontoptimize` / `-dontshrink` / `-dontobfuscate` / 全量 keep 会连带关掉宿主的同一道安全网（**整份文件判**）。 | `**/gradle.properties`、`**/*.pro` | 全模式 `medium`；consumer rules `high` |

### 2.4 代码规则（2 条，按 diff 判）

| 规则 | 判定标准（规则原文要点） | severity / category |
|---|---|---|
| **禁止反射** | 新增的 `java.lang.reflect`（`Class.forName`、`getDeclaredMethod`/`getDeclaredField`、`Method.invoke`、`setAccessible(true)`）、Kotlin 反射（`kotlin.reflect.full.*`、`::class.members`、`KClass.memberProperties`、`isAccessible = true`）、只为把反射结果转成类型的强转、或盖在上面的 `@Suppress` 都报。理由：反射把依赖藏在字符串里、让 R8 裁剪失效、只在 release 构建暴露问题，所以团队禁止它，而不是补一条 keep 规则。**例外**：第三方只提供反射入口（SDK 工厂、序列化库自己生成的 adapter、插件公开 API），此时改动必须写明理由；没写理由 = `medium`。用反射**绕过访问限制或触达隐藏的平台 API** = `high`。 | 约定偏离 `medium`；绕过访问限制 / 触达隐藏 API `high`；category 建议 `maintainability` |
| **`android:angle` 必须是 45 的倍数** | `<gradient android:angle="...">`（drawable 的 shape）取值只能是 0/45/90/135/180/225/270/315。线性渐变只画这八个方向，平台会把其它值**静默吸附**到最近的一个，渲染出来的方向与写的值不一致（`android:angle="30"` 实际按 45 渲染），所以报出并给出最近的有效角度。角度超出 0–360 由平台取模，本身不算违规。 | `medium` / `bug`（渲染结果与预期不符） |

判定范围：**只看这次改动引入的代码**，不把文件里既有的反射或历史角度值翻出来——这一点与版本基线、安全基线相反。

---

## 3. 判定口径与两个坑

套件里其余规则都写死了同一句结尾约定：**只看这次改动，不报 diff 没碰到的既有问题**。版本基线、安全基线与 R8 基线是例外（合计 13 条团队统一条目，全部按整份文件判，见第 1 节）：

| | 代码规则与其余规则 | 5 条版本基线 + 5 条安全基线 + 3 条 R8 基线 |
|---|---|---|
| 判定范围 | 只看增删改的行 | 基线条目**按整份文件判**：版本基线按取值；安全基线按 Manifest / 网络配置的配置项、权限声明（权限名在代码里出现也算）与文件里的敏感 API 调用；R8 基线里 release 安全网的压缩开关、`proguard-android.txt` / `postProcessing`、`gradle.properties` 的全模式开关与 `.pro` 的 consumer rules 全局选项也是。<br>明确仍按新增行看的：代码侧的 `http://` 端点、`.pro` 规则里 consumer rules 全局选项以外的其余条目（keep 规则、`-dontwarn` 等） |
| 定位 | 单次改动是否自洽 | **团队统一标准**，等价于一道 CI 门禁 |
| 为什么 | 减少噪声，不翻旧账 | 按 diff 划界会让基线规则几乎从不触发；团队要的是统一标准，不是单次自洽 |

两个兜底：运行级背景 `android-conventions.md` 第 1 节写了同一组内容（覆盖 `buildSrc`、约定插件等不在 glob 里的写法），第 3 节红线里也有 `allowBackup=true`、明文 HTTP、团队禁止的 9 个权限、外部命令与动态加载、legacy 存储退出开关、release 安全网与 R8 优化配置几条；新增模块照抄同一组取值，不要另起一套。

### 3.1 坑一：`Scope:` 行必须替「整份文件判」的条目开口子

`rule.json` 里每条规则末尾都写着一句 `Scope:` 约定，默认是「只看这次改动，不报 diff 没碰到的既有问题」——这与整份文件判的条目直接冲突。**触发文件级判定的条目必须自己在正文里写明范围，`Scope:` 行也要列出例外**，否则模型会照着 `Scope:` 行把既有的 `exec`、`DexClassLoader` 放过去。实测踩过一次：`**/*.{kt,kts}` 与 `**/*.java` 里**同时**装着「禁止的敏感 API」这条按整份文件判的条目，而 `Scope:` 行当时还是默认那句，`Legacy.java` 未改动行上的 `Environment.getExternalStorageDirectory()` 直接漏报（见 5.2 第六轮）；把 `Scope:` 行改成「除上面这条敏感 API 外，其余只看本次改动」后，第七轮复测通过。R8 那批落地时同样处理：`**/build.gradle*` 的例外扩成「除版本基线、release 安全网基线与默认 ProGuard 文件基线外」，`**/gradle.properties` 写成「除全模式条目外」，`**/*.pro` 写成「除 consumer rules 的全局选项外」。

当前各条规则的 `Scope:` 例外，改规则时照着改（全量原文见 `rule.json`）：

| `rule.json` 的 path | `Scope:` 行里的例外 |
|---|---|
| `**/gradle/wrapper/gradle-wrapper.properties` | Gradle 基线条目 |
| `**/settings.gradle*`、`**/libs.versions.toml` | 版本基线条目 |
| `**/build.gradle*` | 版本基线 + release 安全网基线 + 默认 ProGuard 文件基线 |
| `**/gradle.properties` | 全模式条目 |
| `**/AndroidManifest.xml` | HTTPS、`allowBackup`、禁止的权限、legacy 存储退出开关 |
| `**/res/**/*.xml` | 网络配置条目 |
| `**/*.{kt,kts}`、`**/*.java` | 禁止的权限 + 敏感 API |
| `**/*.pro` | consumer rules 的全局选项 |
| 其余规则 | 无（按 diff 判） |

### 3.2 坑二：整份文件判只决定「模型报不报」，决定不了「OCR 报不报」

**一个必须知道的前提**：`Scope` 例外只解决「模型报不报」，不解决「OCR 报不报」。第十二轮实测（见 5.2）：`isMinifyEnabled=false` 那行落在本次 diff 的 hunk **之外**时，审查阶段报出来了，但后置过滤（`review_filter_task`）按「评论描述的是本次 diff 之外的代码」把它丢掉；`fullMode` 那条因为违规行在同一个 hunk 里才活下来。所以整份文件判的条目，命中条件是**违规行落在本次 diff 的 hunk（含上下文行）内**——文件越大、改动越靠近文件头，越容易漏。需要强制执行时用 `--no-filter`（保留全部评论，代价是噪声增多；`scripts/review.sh` 默认不带这个开关）。

---

## 4. 落点

这 15 条不是各占一条 `rule.json` 规则，而是分散加进既有规则；仓库里实际动过的文件见 4.2。

### 4.1 `rule.json`：path → 新增条目

下表左边是 `rule.json` 里的 path，中间是本次新增的条目，右边是该规则此前就有的检查项（未改）：

| `rule.json` 的 path | 新增条目 | 该规则原有的其他内容（未改） |
|---|---|---|
| `**/build.gradle*` | `minSdk` = 23、`targetSdk` ≥ 36、AGP ≥ 9.0.0、Adjust SDK ≥ 5.5.0 | 版本不 pin、`compileSdk` 变更无理由、release 安全网、签名凭据、依赖 scope 漂移、`api()` 滥用、`packagingOptions`、应用身份变更 |
| `**/settings.gradle*` | AGP ≥ 9.0.0（`pluginManagement { plugins { … } }` 里固定版本时） | 新仓库声明、`repositoriesMode` 放宽、`include` 增删 |
| `**/libs.versions.toml` | `minSdk` = 23、`targetSdk` ≥ 36、AGP ≥ 9.0.0（通常叫 `agp`）、Adjust SDK ≥ 5.5.0（通常叫 `adjust`） | 版本被删/降级而仍有引用、alias 无对应版本、同 group 多版本、动态版本 |
| `**/gradle/wrapper/gradle-wrapper.properties` | Gradle 分发版本 ≥ 9.0.0 —— **规则是全新的**，此前这类文件没有任何团队规则 | —（`.properties` 只命中系统层规则，靠 `merge_system_rule` 合并） |

> 为什么 Gradle 版本要单独一条：Gradle 的版本号只写在 wrapper 属性文件里，不在构建脚本里，改基线时容易漏掉这一类文件。

### 4.2 仓库里的文件

| 文件 | 作用 | 改动 |
|---|---|---|
| `android-review-rules/rule.json` | 逐文件判定标准（进目标仓库 `.opencodereview/rule.json`） | 新增 1 条规则条目 + 在 7 条既有规则里加条目（文件里共 10 条规则）；禁止权限那批在 `**/AndroidManifest.xml` 里再加一条、并在 `**/*.{kt,kts}` 与 `**/*.java` 里各加一条（代码里出现权限名或发起申请同样报 `critical`）；`**/*.{kt,kts}` 与 `**/*.java` 的 `Scope:` 行改成「除禁止权限与敏感 API 那两条外，只看本次改动」；资源规则 path 由 `**/src/main/res/**/*.xml` 放宽为 `**/res/**/*.xml`（覆盖 debug/release/flavour 源集），正文改成按根元素识别网络配置、按源集定 `medium`/`high`，`Scope:` 行补上「除网络配置那条外」。第二批（R8 优化基线 3 条）再在 `**/build.gradle*`（release 安全网、`postProcessing`、`proguard-android.txt`）、`**/gradle.properties`（`android.enableR8.fullMode=false`，整份文件判）与 `**/*.pro`（consumer rules 的全局选项）里加条目，并把这两条规则的 `Scope:` 例外相应扩写；第三批（legacy 存储退出开关 1 条）再在 `**/AndroidManifest.xml` 里加一条（整份文件判），该规则的 `Scope:` 例外补上 `legacy-storage` |
| `android-review-rules/android-conventions.md` | 运行级团队背景（进 `.ocr/`） | 第 1 节新增「禁止反射」「禁止运行外部命令与动态加载代码」「禁止的敏感 API 与安全基线」三行、「构建基线」扩为「版本基线」、再加「禁止的权限」一行（该行同时覆盖代码侧的常量、字面量与运行时申请）；第 3 节红线加入 `allowBackup=true`、明文 HTTP、禁止的权限；第二批再在第 1 节加「R8 优化基线」一行（release 压缩开关、`proguard-android.txt`、全模式、consumer rules 全局选项），红线第 2 条（关闭安全网）也在那时补齐这几项；第三批再在第 1 节的敏感 API 那一行与第 3 节红线第 7 条各补一句 legacy 存储退出开关（`requestLegacyExternalStorage`） |
| `android-review-rules/CONVENTIONS.md` | 给人看的详细说明 | Gradle wrapper 新章节、章节重排到 10 节；Manifest / 资源 / Kotlin / Java / build.gradle / settings / 版本目录七张表加条目；Manifest 表再加「禁止的权限」行、Kotlin 与 Java 表加「禁止的敏感 API」行，全局红线加第 7、8 条，Kotlin / Java 表再加「禁止的权限（代码侧）」行，运行级一节加「权限基线」段与「敏感 API」段（权限基线段含`**/*.{kt,kts}`、`**/*.java` 落点），分工表补一行；第二批再给 `.pro`（consumer rules 全局选项）、`build.gradle`（release 安全网、`postProcessing`、`proguard-android.txt`）、`gradle.properties`（`android.enableR8.fullMode=false`）三张表加条目；第三批给 Manifest 表加「不得声明 legacy 存储退出开关」一行、红线第 6 条与运行级「安全基线」段各补一句 |
| `android-review-rules/README.md` | 采纳与验收步骤 | 文件表与验收命令列表同步（含 `**/res/**/*.xml` 的调试/主源集两条 `ocr rules check`）；第二批再更新文件表，把 R8 优化基线 3 条与 `R8-OPTIMIZATION-DRAFT.md` 写进去；第三批只改 `ADDED-RULES.md` 那一行的条数（安全基线 5 条 / 81 条检查点） |
| `android-review-rules/ADDED-RULES.md` | 本文件 | 新增 |

---

## 5. 验收记录

14 轮都是真实 `ocr review` 跑的（临时 Android 工程，`deepseek-v4-pro`）。

### 5.1 轮次索引

| 轮次 | 主题 | 文件 | 评论 | 耗时 | tokens | 结论 |
|---|---|---|---|---|---|---|
| 第一轮 | 版本基线 | 4 | 5 | — | — | 5 条全部命中（`high`） |
| 第二轮 | 代码规则 + Adjust 基线 | 5 | 5 | — | — | 全部命中 |
| 第三轮 | 安全基线 | 4 | 4 | — | — | 全部命中；`allowBackup` 那行 diff 根本没碰，照样报出 |
| 第四轮 | 9 条规则一次全踩 | 10 | 20 | 6m34s | 267k | 9 条全命中、零漏报；另有 3 条既有规则的发现与 1 条 `low` 噪声 |
| 第五轮 | 禁止的权限（Manifest 侧） | 1 | 9 | 1m37s | 33k | 8 项权限各自 `critical`，另报 `uses-permission-sdk-23` 的重复声明 |
| 第六轮 | 敏感 API 首测 | 2 | 4 | 4m44s | 102k | **暴露缺陷**：`Scope:` 行与整份文件判冲突，既有的 `getExternalStorageDirectory()` 漏报（见 3.1） |
| 第七轮 | 修复后复测 | 2 | 5 | 4m44s | 102k | 文件级口径成立：未改动行上的违规也报出 |
| 第八轮 | 敏感 API 的其余写法 | 2 | 7 | 3m0s | 63k | `ProcessBuilder`、`PathClassLoader`、手写 `/sdcard` 等变体全部命中；反射规避按 `critical` |
| 第九轮 | 禁止的权限（代码侧） | 2 | 3 | 3m3s | 87k | 常量、字符串字面量、发起申请三类写法都判到 |
| 第十轮 | 明文配置的源集覆盖 | 4 | 4 | 4m56s | 202k | debug 源集 `medium`、flavour 源集 `high`，与规则里的分级一致；`false` 那份不误报 |
| 第十一轮 | R8 三条落地前 | 3 | 3 | 3m13s | 108k | 规则没钉死的条目，模型会自己编依据（`fullMode` 那条理由错） |
| 第十二轮 | R8 落地后（验整份文件判） | — | 默认 1；`--no-filter` 3 | — | — | 命中条件受 diff hunk 限制，见 3.2 |
| 第十三轮 | R8 整份文件判（多 module 复测） | 2 | 3 | 4m13s | 76k | `getDefaultProguardFile`、`postProcessing`、consumer rules 的 `-dontoptimize` 在 diff 未碰对应行的前提下全部报出（`--no-filter`） |
| 第十四轮 | legacy 存储退出开关（第三批） | 1 | 默认 0；`--no-filter` 1 | 默认 2m7s；`--no-filter` 52s | 默认 39k；`--no-filter` 46k | 规则生效：`--no-filter` 下报 `medium`/`security`，理由与规则一致；默认运行被后置过滤丢掉（同 3.2） |

### 5.2 逐轮明细（端到端，`deepseek-v4-pro`）

**第一轮：版本基线**（把 4 个值从合规改到基线以下，审 4 个文件出 5 条评论）——

| # | 位置 | severity/category | 结论 |
|---|---|---|---|
| 1 | `app/build.gradle:4-5` | `high`/`maintainability` | minSdk 23→21、targetSdk 36→34，均低于基线 |
| 2 | `build.gradle:2-3` | `high`/`bug` | AGP 9.4.0→8.7.0，低于 9.0.0 |
| 3 | `gradle/libs.versions.toml:2-4` | `high`/`maintainability` | agp、minSdk、targetSdk 三项都低于基线 |
| 4 | `gradle/wrapper/gradle-wrapper.properties:1-1` | `high`/`bug` | 分发版本 9.6.0→8.7，低于 9.0.0 |
| 5 | `build.gradle:2-2` | `medium`/`bug` | 附带发现：AGP 8.7.0 不支持 `compileSdk 36` |

**第二轮：代码规则与 Adjust 基线**（审 5 个文件出 5 条评论）——

| # | 位置 | severity/category | 结论 |
|---|---|---|---|
| 1 | `app/src/main/res/drawable/bg_gradient.xml:5-5` | `medium`/`bug` | `android:angle="30"` 不是 45 的倍数，被吸附到 45° |
| 2 | `app/build.gradle:10-10` | `high`/`maintainability` | Adjust SDK 5.5.0→5.4.0，低于 5.5.0 |
| 3 | `gradle/libs.versions.toml:2-2` | `high`/`maintainability` | `adjust` 条目 5.5.0→5.4.0 |
| 4 | `app/src/main/java/…/Legacy.java:10-14` | `high`/`bug` | `Class.forName` ＋ `setAccessible(true)`，绕过访问限制 |
| 5 | `app/src/main/java/…/Repo.kt:6-11` | `high`/`bug` | `Class.forName` ＋ `isAccessible = true`，同一条规则 |

**第三轮：安全基线**（审 4 个文件出 4 条评论，全部 `high`/`security`）——

| # | 位置 | 结论 |
|---|---|---|
| 1 | `app/src/main/AndroidManifest.xml:3-3` | `allowBackup="true"` —— **注意这次 diff 只加了 INTERNET 权限，`allowBackup` 那一行根本没被改动**，仍然报出来了，说明「按整份文件判」生效 |
| 2 | `app/src/main/java/…/Api.kt:4-4` | base URL 由 `https://` 改成 `http://` |
| 3 | `app/src/main/res/values/strings.xml:2-2` | `strings.xml` 里的明文 API base URL |
| 4 | `app/src/main/res/xml/network_security_config.xml:3-3` | base-config `cleartextTrafficPermitted="true"` 放行全应用明文 |

**第四轮：全量一轮**（把 9 条规则一次全踩：10 个文件、20 条评论、6 分 34 秒、267k tokens；背景用真实的 `android-conventions.md` 运行级约定）——

| 规则 | 命中的评论 |
|---|---|
| Gradle wrapper ≥ 9.0.0 | `gradle/wrapper/gradle-wrapper.properties:1-1` `high`/`bug`（9.6.0→8.7） |
| AGP ≥ 9.0.0 | `build.gradle:2-3`、`gradle/libs.versions.toml:2-2` |
| Adjust SDK ≥ 5.5.0 | `app/build.gradle:10-10`、`gradle/libs.versions.toml:3-3` |
| `minSdk` = 23 | `app/build.gradle:4-4`、`gradle/libs.versions.toml:4-4` |
| `targetSdk` ≥ 36 | `app/build.gradle:5-5`、`gradle/libs.versions.toml:5-5` |
| `allowBackup` = `false` | `app/src/main/AndroidManifest.xml:6-6` |
| 只走 HTTPS | `AndroidManifest.xml:7-7`（`usesCleartextTraffic`）、`res/xml/network_security_config.xml:3-3`、`res/values/strings.xml:2-2`、`java/…/Api.kt:4-4` |
| 禁止反射 | `java/…/Api.kt:8-11`、`java/…/Legacy.java:11-13` |
| `android:angle` 45 的倍数 | `res/drawable/bg_gradient.xml:3-3` `medium`/`maintainability` |

结论与两处噪声：

- **9 条全部命中，零漏报**；`http://schemas.android.com/apk/res/android` 这类 XML 命名空间 URI 没有被误报，「命名空间不是流量」的例外生效。
- 额外报出 3 条既有规则的问题（Java 新方法缺 `@NonNull`/`@Nullable`、AGP 8.7.0 不支持 `compileSdk 36`、AGP/Gradle 版本互不兼容），属于预期。
- 1 条 `low` 噪声是**测试工程自身的产物**：目录里的 `[versions]` 没有被任何构建脚本引用（演示工程把取值写死在脚本里），模型据此提示"改这里没用"——真实项目走 `libs.versions.*` 引用，不会出现。
- 运行级背景 `android-conventions.md` 有 3588 字符，CLI 提示超过推荐值 2000（仍继续，不影响本次结果）；真实项目的 `review.sh` 还会把 lint 报告合并进来，需注意 8000 字符的硬上限。

**第五轮：禁止的权限**（本轮新增，单文件、1 文件 9 条评论、33k tokens、1 分 37 秒）——

夹具 `app/src/main/AndroidManifest.xml` 里 8 个禁止权限**已经提交在 HEAD 里**，本次 diff 只加了一行无关的 `VIBRATE`。全部报出，且都是 `critical`/`security`，说明整份文件判定的口径生效，且没有把 `INTERNET`、`VIBRATE` 误报：

| # | 位置 | severity/category | 结论 |
|---|---|---|---|
| 1 | `AndroidManifest.xml:4-4` | `critical`/`security` | `READ_EXTERNAL_STORAGE` |
| 2 | `AndroidManifest.xml:5-5` | `critical`/`security` | `WRITE_EXTERNAL_STORAGE`，并指出下方 `uses-permission-sdk-23` 又声明了一次 |
| 3 | `AndroidManifest.xml:6-6` | `critical`/`security` | `READ_MEDIA_IMAGES` |
| 4 | `AndroidManifest.xml:7-7` | `critical`/`security` | `READ_MEDIA_VIDEOS` |
| 5 | `AndroidManifest.xml:8-8` | `critical`/`security` | `READ_CONTACTS` |
| 6 | `AndroidManifest.xml:9-9` | `critical`/`security` | `ACCESS_FINE_LOCATION` |
| 7 | `AndroidManifest.xml:10-10` | `critical`/`security` | `READ_PHONE_NUMBERS` |
| 8 | `AndroidManifest.xml:11-11` | `critical`/`security` | `QUERY_ALL_PACKAGES`，并给出 `<queries>` 的替换写法 |
| 9 | `AndroidManifest.xml:12-12` | `critical`/`security` | `uses-permission-sdk-23` 里重复声明的 `WRITE_EXTERNAL_STORAGE` |

替代做法也被写进了建议里（照片选择器 / `MediaStore` 作用域存储、用户自己填的位置、`<queries>`），符合「报问题必须给出可以照着改的具体建议」。

**第六轮：敏感 API 首测——暴露一处真实缺陷**（2 个文件、4 条评论、4 分 44 秒、102k tokens）——

`Api.kt` 新增的 `exec` 与 `DexClassLoader` 都报了 `critical`/`security`，但 `Legacy.java` 里**位于未被改动行**上的 `Environment.getExternalStorageDirectory()` **没报**。原因是两条 Kotlin/Java 规则末尾的 `Scope:` 行仍写着「不报 diff 没碰到的既有问题」，与条目要求的「整份文件判」直接冲突，模型照 `Scope:` 行执行了。**修法**：`Scope:` 改成「除上面这条敏感 API 外，其余只看本次改动」，条目正文也各自写明范围。

**第七轮：修复后复测**（同一工程、2 个文件、5 条评论、4 分 44 秒、102k tokens）——

| # | 位置 | severity/category | 结论 |
|---|---|---|---|
| 1 | `java/…/Api.kt:10-13` | `critical`/`security` | `Runtime.getRuntime().exec("ping …")` |
| 2 | `java/…/Api.kt:15-18` | `critical`/`security` | `DexClassLoader` + `loadClass` |
| 3 | `java/…/Legacy.java:15-17` | `medium`/`security` | `Environment.getExternalStorageDirectory()` —— **这次 diff 只在该文件加了一个 `label()` 方法，违规那一行根本没被改动**，仍然报出来了，文件级口径成立 |

**第八轮：其余写法的变体**（2 个文件、7 条评论、3 分 0 秒、63k tokens）——

| # | 位置 | severity/category | 结论 |
|---|---|---|---|
| 1 | `java/…/Api.kt:7-7` | `critical`/`security` | `ProcessBuilder(cmd).start()` |
| 2 | `java/…/Api.kt:9-12` | `critical`/`security` | `Class.forName("java.lang.Runtime")` + `getDeclaredMethod("exec")` + `isAccessible`，按**蓄意规避**报 `critical`，没有被当成普通反射条处理 |
| 3 | `java/…/Loader.java:11-11` | `critical`/`security` | `PathClassLoader` 加载 APK 之外的 dex |
| 4 | `java/…/Loader.java:16-16` | `medium`/`security` | 手写 `/sdcard/myapp` 路径 |
| 5 | `java/…/Loader.java:20-20` | `medium`/`security` | `Environment.getExternalStoragePublicDirectory(...)` |

另外两条是既有规则的正常输出，不算这条规则的噪声：新建的 Java 文件违反「Kotlin 优先」（`medium`/`maintainability`，运行级约定生效）、public API 缺 `@NonNull`/`@Nullable`。

敏感 API 的复现要点：把 `exec` 或 `DexClassLoader` 写在**工作区新增行**上，把 `getExternalStorageDirectory()` **提交在 HEAD 基线里**，再随便改该文件一行别的方法——三条都要报出。

**第九轮：禁止权限的代码侧**（2 个文件、3 条评论、3 分 3 秒、87k tokens）——

`Perms.kt` 与 `LegacyPerms.java` 里的权限引用**全部提交在 HEAD 基线里**，本次 diff 只各加了一个无关的辅助方法（`tag()` / `label()`）。两个文件都报出 `critical`/`security`，并把引用逐条点名：

| # | 位置 | severity/category | 结论 |
|---|---|---|---|
| 1 | `java/…/LegacyPerms.java:20-22` | `critical`/`security` | 一次点出三处：`Manifest.permission.ACCESS_FINE_LOCATION`（第 8 行的常量）、`checkSelfPermission("android.permission.READ_PHONE_NUMBERS")`（第 11 行的字面量）、`PackageManager.checkPermission("android.permission.QUERY_ALL_PACKAGES", pkg)`（第 16 行） |
| 2 | `java/…/Perms.kt:25-25` | `critical`/`security` | `ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS)`（第 11 行）、`requestPermissions(arrayOf("android.permission.READ_MEDIA_IMAGES"), …)`（第 15 行） |

第 3 条 `medium`/`maintainability` 是既有 Java 规则的正常输出（新增 public 方法缺 `@NonNull`），不算这条规则的噪声。三种写法都判到了：常量引用、字符串字面量、发起申请的调用（`checkSelfPermission` / `requestPermissions` / `checkPermission`）。两条规则末尾的 `Scope:` 行这次一并改对，没有重演敏感 API 那轮「照 `Scope:` 行漏报」的问题。

**第十轮：明文配置的源集覆盖（本轮新增）**（3 个源集各一份网络配置 + Manifest 引用，4 个文件、4 条评论、4 分 56 秒、202k tokens）——

改之前先确认过缺口：`ocr rules check app/src/debug/res/xml/<配置>.xml`（`--rule` 指到本仓库的 `rule.json`）返回 `Source: System built-in` / `Pattern: default`，即团队规则完全没命中；把 glob 放宽为 `**/res/**/*.xml` 后同一个文件命中 `Pattern: **/res/**/*.xml`。

夹具：`app/src/main/AndroidManifest.xml` 里 `android:networkSecurityConfig="@xml/hofeuzirufea_vagepawudusi"`（**混淆过的名字**，故意不用 `network_security_config.xml`）+ 同名文件三份——`src/main/res`（`false`）、`src/debug/res`（`true`）、`src/capGoogle/res`（另一个文件名的 flavour 配置，`true`）。

| # | 位置 | severity/category | 结论 |
|---|---|---|---|
| 1 | `app/src/capGoogle/res/xml/flavour_network_config.xml:4-5` | `high`/`security` | flavour 源集放行明文 = `high`（不得进 release）——**这个文件在放宽 glob 之前根本不会被审** |
| 2 | `app/src/debug/res/xml/hofeuzirufea_vagepawudusi.xml:4-5` | `medium`/`security` | debug 源集放行明文 = `medium`，评论里写明「可以只当调试开关，但绝不能进 release，`src/main` 那份要保持 `false`」 |
| 3 | `app/src/main/res/xml/hofeuzirufea_vagepawudusi.xml`（`false`） | 未报 | 合规配置不误报 |

- **B 口径生效**：同一处写法（`cleartextTrafficPermitted="true"`）在 debug 源集报 `medium`、flavour 源集报 `high`，与规则里写的完全一致。
- **按引用核对生效**：Manifest 只写了 `@xml/hofeuzirufea_vagepawudusi`，模型自己找到了三份同名文件并说明了「debug 构建解析到 `true`、release 解析到 `false`」——文件名混淆不影响判定。
- `http://schemas.android.com/apk/res/android` 这类命名空间 URI 没有被误报。
- 另外两条是与本次改动无关的正常发现：flavour 配置没被任何 manifest 引用（资源名不匹配，等于死文件）、Manifest 里的 `package=` 在 AGP ≥ 8 已不支持（夹具写法，真实项目走 `namespace`）。

**第十一、十二轮：R8 优化基线**——临时工程（AGP 9.4.0 的 `app/build.gradle.kts`、`gradle.properties`、`app/proguard-rules.pro`）造两轮退步，用本目录 `rule.json` + `android-conventions.md` 跑真实 `ocr review`（`deepseek-v4-pro`）：

| 轮次 | 改动 | 结果 |
|---|---|---|
| 第十一轮（三条规则落地前，背景 = `android-conventions.md`） | `isMinifyEnabled = true → false`；`proguard-android-optimize.txt → proguard-android.txt`；`gradle.properties` 加 `android.enableR8.fullMode=false`；`.pro` 加 `-dontoptimize` | 3 文件 3m13s / 108k tokens：minify 与 `-dontoptimize` 各报 `security`/`high`（正确，还点出 `proguard-android.txt` 会一并丢掉默认优化规则）；`fullMode=false` 报了行但理由是错的（称「AGP 7.0 起该开关被忽略」，而 9.4 仍在读它）——规则没钉死的条目，模型会自己编依据 |
| 第十二轮（落地后，验「整份文件判」） | 把违规提交进 HEAD，只改无关行（`versionName`、加 `org.gradle.configuration-cache=true`），再跑 | 默认（带后置过滤）：只报出 `fullMode` 一条——它的违规行恰好落在同一个 hunk 的上下文里；`isMinifyEnabled=false` **审查阶段确实报了，被后置过滤丢掉**。同一份改动加 `--no-filter` 后三条全部命中：`isMinifyEnabled`/`high`（并把 `proguard-android.txt` 并进同一条）、`fullMode`/`medium`，理由与规则原文一致 |

**第十三轮：R8 整份文件判（多 module 复测）**——把上一轮批注的判定范围改动落地后（`getDefaultProguardFile`、`postProcessing`、consumer rules 全局选项三条改成整份文件判），用多 module 夹具复测：`app`（application）+ `lib`、`feature/login`（两个 library，各带 `consumer-rules.pro`）。违规提交进 HEAD，本次 diff 只改了两处无关行——`app/build.gradle.kts` 的 `versionName` 1.0→1.1、`lib/consumer-rules.pro` 加一条注释。`--no-filter` 跑真实 `ocr review`（`deepseek-v4-pro`，2 文件 4m13s / 76k tokens）：

| # | 位置 | severity/category | 结论 |
|---|---|---|---|
| 1 | `app/build.gradle.kts:23` | `high`/`maintainability` | `getDefaultProguardFile("proguard-android.txt")`——违规行在 release 块里，diff 只碰了 `versionName`，照样报出 |
| 2 | `app/build.gradle.kts:26-28` | `high`/`maintainability` | `postProcessing { isOptimizationsEnabled = false }` 同一条评论并出 |
| 3 | `lib/consumer-rules.pro:3` | `high`/`maintainability` | `-dontoptimize` 全局选项——diff 只加了一条注释、未碰该行，照样报出 |

三条整份文件判的新口径全部成立；另有一条与规则改动无关的正常发现（`versionName` 升了但 `versionCode` 没跟，`high`/`bug`，落在真正的改动行上）。`feature/login/consumer-rules.pro` 里的 `-dontshrink` 未报出——它不在本次 diff 里，OCR 是 diff 驱动的，只审进入审查范围的文件（见 3.2 的边界）。

**第十四轮：legacy 存储退出开关**（第三批唯一一条，验的是新条目本身）——夹具照 `m12_20241216` 的 `app/src/main/AndroidManifest.xml` 复刻：`<application>` 上带 `android:requestLegacyExternalStorage="true"` 与 `tools:targetApi="24"`，`app/build.gradle` 里 `minSdkVersion 23` / `targetSdkVersion 36`。违规行**提交进 HEAD**，本次 diff 只在 Manifest 里加了一行无关的 `INTERNET` 权限（把文件拉进审查范围）。`ocr review -B .ocr/android-conventions.md`（`deepseek-v4-pro`，1 文件）：

| 运行方式 | 命令 | 结果 |
|---|---|---|
| 默认（带后置过滤） | `ocr review --audience agent -B .ocr/android-conventions.md` | **0 条评论**，2m7s / 39k tokens——违规行不在本次 diff 的 hunk 里，后置过滤丢掉（同 3.2） |
| `--no-filter` | 同上再加 `--no-filter` | 1 条：`AndroidManifest.xml:9-10`，`medium` / `security`，正文与规则一致——「`<application>` 不得带 `android:requestLegacyExternalStorage="true"`；平台在 target API 30+ 之后忽略这个 scoped storage opt-out（团队基线 `targetSdk ≥ 36`），所以它今天是死配置，但 `targetSdk` 一旦降回 29 会静默恢复 legacy 共享外部存储，移除即可」 |

结论：规则本身生效（severity、category、理由都对），但它受 3.2 那条边界约束——**要当硬门禁就用 `--no-filter`，或在 CI 里跑 grep**（见 6 节）。这一轮同时复核了确定性工具侧的空白：`m12_20241216` 的全量 lint 报告（21 error / 647 warning / 214 文件）里没有 `requestLegacyExternalStorage` 的任何命中，`UnusedAttribute` 也一声没响——该元素上的 `tools:targetApi="24"` 把 API 级别检查一并抑制了（同一元素上的 `android:networkSecurityConfig` / `android:resizeableActivity` 都是 API 24 属性、minSdk 23，本该同样触发，这个 `tools:targetApi` 正是为它们加的）。

### 5.3 规则是否命中（不花 token）

`ocr rules check`，全部落在 `Source: Project (.opencodereview/rule.json)`：

| 文件 | 命中的 Pattern |
|---|---|
| `build.gradle`、`app/build.gradle` | `**/build.gradle*`（没被 Kotlin 规则抢走，顺序正确） |
| `settings.gradle` | `**/settings.gradle*` |
| `gradle/libs.versions.toml` | `**/libs.versions.toml` |
| `gradle/wrapper/gradle-wrapper.properties` | `**/gradle/wrapper/gradle-wrapper.properties`（新规则生效） |
| `app/src/main/AndroidManifest.xml` | `**/AndroidManifest.xml`（禁止权限也走这条） |
| `app/src/main/res/**/*.xml`、`app/src/debug/res/**/*.xml`、`app/src/capGoogle/res/**/*.xml`（`strings.xml`、网络配置 XML） | `**/res/**/*.xml`（放宽后 debug / release / flavour 源集一并命中） |
| `app/src/main/java/…/Repo.kt`、`Api.kt` | `**/*.{kt,kts}` |
| `app/src/main/java/…/Legacy.java` | `**/*.java` |

### 5.4 复现命令

```bash
# 1) 规则命中（不花 token）
ocr rules check gradle/wrapper/gradle-wrapper.properties
ocr rules check app/build.gradle
ocr rules check app/src/main/AndroidManifest.xml
ocr rules check app/src/main/res/xml/network_security_config.xml

# 2) 真跑一次
./scripts/review.sh                     # 工作区改动，自动带团队背景
ocr review --preview --format json      # 先确认过滤，再决定要不要跑
```

禁止权限这条的最小复现：把 9 个权限写在 `AndroidManifest.xml` 里**提交**，再随便改一行无关的，然后 `./scripts/review.sh` —— 9 项应当各自报出 `critical`/`security`。代码侧同理：把 `Manifest.permission.READ_CONTACTS` 或 `"android.permission.READ_PHONE_NUMBERS"` 这类引用提交进 HEAD，再随便改同一个文件一行别的方法，Kotlin 与 Java 两个文件都应当报出 `critical`/`security`，并逐条点出权限名。

第二批（R8）三条：

```bash
# 1) 规则命中（不花 token）
ocr rules check app/build.gradle.kts     # 期望 Pattern: **/build.gradle*
ocr rules check gradle.properties        # 期望 Pattern: **/gradle.properties
ocr rules check app/proguard-rules.pro   # 期望 Pattern: **/*.pro

# 2) 整份文件判是否生效：把违规提交进 HEAD，再改同一文件一行无关的
git commit -am "baseline with isMinifyEnabled = false"
# 然后改一条无关行（例如 versionName），再跑：
ocr review --audience agent --no-filter -B .ocr/android-conventions.md
# 期望：minify / fullMode 仍然报出，说明 Scope 例外生效（为什么要 `--no-filter` 见 3.2）
```

第三批（legacy 存储退出开关）一条：

```bash
# 1) 规则命中（不花 token）
ocr rules check app/src/main/AndroidManifest.xml   # 期望 Pattern: **/AndroidManifest.xml

# 2) 整份文件判是否生效：把 android:requestLegacyExternalStorage="true" 提交进 HEAD，
#    再在同一个 Manifest 里加一行无关的 <uses-permission>，然后跑：
ocr review --audience agent --no-filter -B .ocr/android-conventions.md
# 期望：Manifest 报出一条 medium/security，指向 <application>（为什么要 `--no-filter` 见 3.2）
```

---

## 6. 待定与已知边界

- **资源规则的 glob 放宽后，既有检查项也会跑到其它源集**：`**/res/**/*.xml` 现在包含 `src/debug/res`、`src/release/res`、flavour 的 `res/`，所以硬编码文案、RTL、`android:angle`、`translatable` 这些原有检查同样会对这些源集报。这是有意的（按源集覆盖才不会有漏网），但如果你们只在 `src/main/res` 上做资源规范，会多出一点噪声——需要的话可以在 `exclude` 里把非 main 源集排除，只保留网络配置那条。
- **整份文件判的条目受 diff hunk 限制**：违规行落在本次 diff 的 hunk（含上下文行）之外时，审查阶段报出来、后置过滤会丢掉——机制与实测见 3.2。规则文本改不动这一点——要当硬门禁就得配 `--no-filter`，或在 CI 侧另跑一条静态检查（例如 grep `isMinifyEnabled = false` / `android.enableR8.fullMode=false` 的脚本，零成本零漏报）。
- **legacy 存储退出开关这条同样是符号级可判的**：`grep -rn 'requestLegacyExternalStorage' --include=AndroidManifest.xml` 在 CI 里零成本零漏报，比 OCR 稳，也不受 diff hunk 限制（第十四轮实测里默认运行就被后置过滤丢掉了，见 5.2）。Android Lint 在这条上给不出信号：`m12_20241216` 的全量报告（21 error / 647 warning / 214 文件）里一次没有报出，`UnusedAttribute` 也一声没响——`<application>` 上的 `tools:targetApi="24"` 把该元素的 API 级别检查一并抑制了（同一元素上的 `android:networkSecurityConfig` / `android:resizeableActivity` 同属 API 24 属性、minSdk 23，本该同样触发）。OCR 这条的价值只在「文件被审到时顺带发现」。
- 这批规则的 `category` 没有全部钉死，实测分类不稳定（版本基线判出过 `bug` 和 `maintainability` 两种）。CI 若用 `route_categories` 分流，需要统一（版本基线建议 `maintainability`，安全基线已经是 `security`）——在相应规则里各补一句 `Category: …` 即可。
- 目标仓库（如 `m12_20241216`）里装的仍是旧 `rule.json`，要吃到这批规则需按 README「三步采纳」重新拷贝。
- 「禁止的敏感 API」只能审**本仓库源码**：第三方 `.aar`/`.jar` 里的 `exec`、`DexClassLoader` 不在 OCR 的输入里，那部分得靠依赖成分分析（SCA）或反编译扫描，别指望这条规则。
- 这条规则本质是「符号清单」，静态可判。符号级零漏报靠自定义 Android Lint 规则或 Semgrep 全仓扫更划算，OCR 补的是语义与变相绕过（反射、字符串拼接、封装多层）；两边都开才完整（分工见 `CONVENTIONS.md` 开头那张表）。

---

## 7. 附：R8 那批的立项背景与事实核对

> 触发这份清单的是 Play 后台的 R8 三项指标（Optimisation / Obfuscation / Shrinking percentage）与 R8 configuration 四项。**三个百分比本身不在这套规范的能力范围内**——它们是 AAB 构建产物里的数字（`BUNDLE-METADATA/com.android.tools/r8.json`），不在 diff 里；能审的是**导致它们的构建配置**，也就是 2.3 节那 3 条。

**已核对的事实**（读 AGP 9.4.0 插件字节码与源码 jar，不是为了写规则凭记忆）：

- AGP 8.13 源码里 `proguard-android.txt` 对应 `DONT_OPTIMIZE`，正文追加 `-dontoptimize`；`proguard-android-optimize.txt` 对应 `OPTIMIZE`，只多 `proguard-optimizations.txt`（`-allowaccessmodification`）。
- AGP 9.4 的 `BaseExtension.getDefaultProguardFile` 已读 `android.r8.proguardAndroidTxt.disallowed`（默认 true，AGP 10.0 强制）并对 `proguard-android.txt` 直接 `reportError`——9.4 上这是构建错误，更早的 AGP 不报，所以规则要留这条。
- `android.enableR8.fullMode` 仍被 `BaseR8Task` 读进 `R8ToolParameters.fullMode`（选项 `FULL_R8`，默认 true），**不是废弃开关**；`android.r8.optimizedResourceShrinking` 默认 true、`android.r8.optimizedShrinking` 默认 false。
- 真实 AAB 抽样：`app-google-release.aab` 的 `app-metadata.properties` 写着 `androidGradlePluginVersion=8.4.0`，`jar tf` 里确实没有 `r8.json`，只有 `com.android.tools.build.obfuscation/proguard.map`——文档「AGP 8.10 起才写」成立，而团队 AGP ≥ 9.0.0 的基线已经覆盖它。

立项背景、逐项「谁能发现」的对照与边界说明另有一份 `R8-OPTIMIZATION-DRAFT.md`（同目录），本文件这里只留结论与事实核对。

---

## 8. 附：`rule.json` 全量索引（10 条文件规则 / 81 条检查点）

> 1–4 节讲的是**这批新加的 15 条**；这一节把 `rule.json` 里现有的**全部**检查点按文件规则排成一行一条，用来回答「`rule.json` 现在到底有哪些检查点」。
>
> 这里只有标题与判定范围，**判定标准以 `rule.json` 正文为唯一准据**，逐条详解见 `CONVENTIONS.md` 的同号小节（那里的 §1–§10 与这里的 8.1–8.10 一一对应）。
>
> 行尾标 **▲** 的是本批新增或改过口径的条目（新增 25 条 + 只改口径 2 条 = 27 条），详细判定见第 2 节；其余 53 条是既有检查点。
>
> 全局默认口径仍是**只看这次改动**，不报 diff 没碰到的既有问题；每个小节里的「例外」列的就是该规则中不受这条默认口径约束的条目（两个坑见第 3 节）。
>
> 维护：`rule.json` 加了检查点就在这里加一行、删了就删行，标题照 `CONVENTIONS.md` 的措辞写。这里是索引——判定细节只留在 `rule.json` 与 `CONVENTIONS.md`，在这里再写一遍就多一处要同步的地方。

### 8.1 `**/*.pro` — 5 条（`CONVENTIONS.md` §1）

范围：按 diff 判。**例外**：库模块 `consumer-rules.pro` 里的全局选项按整份文件判。

- keep 规则被删除或收窄
- `-dontshrink` / `-dontobfuscate` / `-dontoptimize`
- 全量 keep（`-keep class **`）
- 新增 `-dontwarn <package>`
- consumer rules 里的全局选项 ▲

### 8.2 `**/build.gradle*` — 15 条（`CONVENTIONS.md` §2）

范围：按 diff 判。**例外**：版本基线（`minSdk` / `targetSdk`、AGP、Adjust SDK）、release 安全网基线、默认 ProGuard 文件基线（`proguard-android.txt`）按整份文件判。

- 依赖版本未 pin
- 团队版本基线：`minSdk` = 23、`targetSdk` ≥ 36 ▲
- 团队版本基线：AGP ≥ 9.0.0 ▲
- 团队版本基线：Adjust SDK ≥ 5.5.0 ▲
- `compileSdk` 变更
- 团队 release 安全网基线（`isMinifyEnabled` + `isShrinkResources`）▲
- 用了 `proguard-android.txt` ▲
- release 的 `postProcessing` ▲
- 签名凭据硬编码
- 依赖 scope 漂移
- `api()` 用在 `implementation()` 就够的地方
- 加依赖没写版本
- 仓库声明散落在构建脚本里
- 打包选项（`packagingOptions` / `packaging` 静默丢 `.so` 或资源）
- 应用身份变更（`applicationId` / `versionCode` / `versionName`）

### 8.3 `**/settings.gradle*` — 5 条（`CONVENTIONS.md` §3）

范围：按 diff 判。**例外**：版本基线（AGP ≥ 9.0.0）按整份文件判。

- 新增非允许清单仓库
- 仓库模式放宽（`repositoriesMode`）
- 模块从 `include` 移除
- 模块加入 `include` 但没有对应目录
- 团队版本基线：AGP ≥ 9.0.0 ▲

### 8.4 `**/libs.versions.toml` — 6 条（`CONVENTIONS.md` §4）

范围：按 diff 判。**例外**：版本基线按整份文件判。

- `[versions]` 条目被删除或降级，但 `[libraries]` / `[plugins]` 仍引用它
- alias 没有对应的版本条目
- 同 group 多版本
- 版本未 pin
- 改名未同步消费者
- 团队版本基线（`minSdk` / `targetSdk` / AGP / Adjust SDK）▲

### 8.5 `**/gradle/wrapper/gradle-wrapper.properties` — 1 条（`CONVENTIONS.md` §5）

范围：整份文件判——本规则只有版本基线这一条。

- 团队版本基线：Gradle ≥ 9.0.0 ▲

### 8.6 `**/gradle.properties` — 6 条（`CONVENTIONS.md` §6）

范围：按 diff 判。**例外**：R8 全模式那一条按整份文件判。

- `android.enableJetifier=true`
- AndroidX 开关被关（`android.useAndroidX` / `android.nonTransitiveRClass`）
- R8 全模式被关（`android.enableR8.fullMode=false`）▲
- 构建缓存开关被关
- JVM 参数
- 凭据

### 8.7 `**/AndroidManifest.xml` — 11 条（`CONVENTIONS.md` §7）

范围：按 diff 判。**例外**：只走 HTTPS、`allowBackup` 必须 `false`、禁止的权限（9 项）、不得声明 legacy 存储退出开关四条按整份文件判。

- 组件导出
- 新增权限
- 团队权限基线：禁止的权限（发版红线）▲
- 团队安全基线：只走 HTTPS ▲
- 团队安全基线：`allowBackup` 必须 `false` ▲
- 团队安全基线：不得声明 legacy 存储退出开关（`android:requestLegacyExternalStorage="true"`）▲
- 调试/备份开关（`android:debuggable` / `android:fullBackupContent`）
- Provider 授权
- deep-link 扩宽
- 入口 Activity
- 应用身份变更

### 8.8 `**/res/**/*.xml` — 9 条（`CONVENTIONS.md` §8，glob 含 `src/main`、`src/debug`、`src/release` 与 flavour 源集）

范围：按 diff 判。**例外**：网络安全配置文件按整份文件判（值里的明文 `http://` 端点仍按 diff）。

- 用户可见文案硬编码
- 硬编码颜色/尺寸
- 无障碍缺失
- RTL 敌意属性
- 字号单位
- 翻译标注
- `android:angle` 不是 45 的倍数 ▲
- 只走 HTTPS：值里的明文 `http://` 端点 ▲
- 只走 HTTPS：网络安全配置文件（根元素 `<network-security-config>`，按源集定 severity）▲

### 8.9 `**/*.{kt,kts}` — 13 条（`CONVENTIONS.md` §9）

范围：按 diff 判。**例外**：禁止的权限、禁止的敏感 API（含用反射绕到这些 API）按整份文件判。

- 主线程阻塞
- 对象泄漏
- 协程作用域
- Flow 收集
- Compose
- 平台类型强转
- 吞掉失败
- 废弃 API
- 禁止反射 ▲
- 只走 HTTPS ▲
- 禁止的权限（9 项，代码侧，整份文件判）▲
- 禁止的敏感 API（整份文件判）▲
- 用反射绕到上述 API（蓄意规避，按 `critical`）▲

### 8.10 `**/*.java` — 10 条（`CONVENTIONS.md` §10）

范围：按 diff 判。**例外**：禁止的权限、禁止的敏感 API（含用反射绕到这些 API）按整份文件判。

- 可空性标注
- 裸线程（`AsyncTask` / 裸 `Thread`）
- 静态引用泄漏
- 监听器反注册
- 废弃 API
- 禁止反射 ▲
- 只走 HTTPS ▲
- 禁止的权限（9 项，代码侧，整份文件判）▲
- 禁止的敏感 API（整份文件判）▲
- 用反射绕到上述 API（蓄意规避，按 `critical`）▲
