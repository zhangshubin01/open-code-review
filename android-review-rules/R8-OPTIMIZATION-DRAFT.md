# R8 优化指标：哪些能审、哪些审不了

> **状态**：已落地（2026-10-16）。三条规则进了 `android-review-rules/rule.json`，同步改了 `CONVENTIONS.md`、`android-conventions.md`、`ADDED-RULES.md`、`README.md`；本文件保留的是**立项背景、AGP 事实核对与边界说明**，规则原文以 `rule.json` 为准，不要在这里另写一份。
> **来源问题**：Lark 文档《R8 / Play 优化指标》——"这个能检测、审查吗"。
> **结论一句话**：Play 那三个百分比是**构建产物里的数字**，静态审查看不见；**导致它们的构建配置**能审，现有规范原本已覆盖三条，这次补了三条，全部按整份文件判（release 安全网、`proguard-android.txt`、`fullMode` + consumer rules 全局选项）。

---

## 1. 文档逐项 → 谁能发现

| 文档里的东西 | 静态审查能发现吗 | 归谁 | 现状 |
|---|---|---|---|
| Optimisation / Obfuscation / Shrinking 三个百分比 | ❌ | AAB 里的 `BUNDLE-METADATA/com.android.tools/r8.json`，构建后取数 | CI 门禁脚本（见第 4 节） |
| Play 的 25% 底线（2027-02 起，DEX > 10 MB） | ❌ 不是代码问题 | 团队策略 | 已写进 `android-conventions.md` 第 1 节 |
| `r8.json` 到底有没有写进包里（AGP ≥ 8.10） | ✅ 间接 | AGP 版本基线 | 已覆盖：团队基线 AGP ≥ 9.0.0 |
| `isMinifyEnabled` / `isShrinkResources` | ✅ | `**/build.gradle*` 规则 | **本次落地**：整份文件判 |
| `getDefaultProguardFile("proguard-android.txt")` | ✅ | `**/build.gradle*` 规则 | **本次落地**：整份文件判 |
| `android.enableR8.fullMode=false` | ✅ | `**/gradle.properties` 规则 | **本次落地**：整份文件判 |
| consumer rules 里的全局选项 | ✅ | `**/*.pro` 规则 | **本次落地**：整份文件判 |
| Resource shrinking optimised / Repackage classes | ✅ 间接 | AGP 9 默认开 | 版本基线已覆盖 |
| `-dontoptimize` / `-dontshrink` / `-dontobfuscate`、大 blanket keep | ✅ | `**/*.pro` 规则 | 原本已覆盖 |
| Configuration Analyzer / keep-radius 报告 | ❌ 报告不是代码 | 构建期工具 | 静态侧只兜底"大 keep" |

## 2. 核对到的 AGP 事实（本地读 AGP 9.4.0 插件字节码 + 8.13 源码 jar）

| 事实 | 证据 |
|---|---|
| `proguard-android.txt` 含 `-dontoptimize`，`proguard-android-optimize.txt` 不含（只多 `-allowaccessmodification`） | AGP 8.13 源码 `ProguardFiles.createProguardFile` 的 `DONT_OPTIMIZE` / `OPTIMIZE` 分支 |
| **AGP 9.4 起 `getDefaultProguardFile("proguard-android.txt")` 直接报 error**，提示改用 `proguard-android-optimize.txt` | `BaseExtension.getDefaultProguardFile` 读 `BooleanOption.R8_PROGUARD_ANDROID_TXT_DISALLOWED`（`android.r8.proguardAndroidTxt.disallowed`，默认 true，AGP 10.0 强制）后 `IssueReporter.reportError` |
| `android.enableR8.fullMode` **仍然生效**（默认 true），不是"被忽略" | `BaseR8Task$CreationAction` 把它读进 `R8ToolParameters.fullMode`；选项 `FULL_R8`，默认 `true`，AGP 10.0 前为 SoftlyEnforced |
| `android.r8.optimizedResourceShrinking` 默认 **true**、`android.r8.optimizedShrinking` 默认 **false**、`android.r8.integratedResourceShrinking` 恒为 true | `BooleanOption` 静态初始化里的默认值 |
| AAB 元数据目录就是 `BUNDLE-METADATA/com.android.tools/r8.json` | `PackageBundleTask$BundleToolWorkAction` 里的 `com.android.tools` + `r8.json` 常量 |
| 一份真实 AAB 实测：**AGP 8.4.0，包里没有 r8.json**，只有 `com.android.tools.build.obfuscation/proguard.map` | `app-google-release.aab` 的 `app-metadata.properties`：`androidGradlePluginVersion=8.4.0`，`jar tf` 无 `r8.json` 条目 |

结论：`r8.json` 的写入门槛不用写成审查规则（版本基线已保证）；`proguard-android.txt` 在 9.4 上虽然被构建期挡掉，但团队基线写的是 AGP ≥ 9.0.0，9.0–9.3 上它仍是静默关优化，所以规则里保留了这一条。

## 3. 实测：规则落地前后的真实表现

最小工程（AGP 9.4.0 的 `app/build.gradle.kts`、`gradle.properties`、`app/proguard-rules.pro`），`deepseek-v4-pro`：

| 轮次 | 改动 | 结果 |
|---|---|---|
| 落地前 | `isMinifyEnabled = true → false`；`proguard-android-optimize.txt → proguard-android.txt`；加 `fullMode=false`；`.pro` 加 `-dontoptimize` | 3 文件 3m13s / 108k tokens：minify 与 `-dontoptimize` 各报 `high`；`fullMode=false` 报了行但**理由是错的**（称"AGP 7.0 起该开关被忽略"，而 9.4 仍在读它）——规则没钉死的条目，模型会自己编依据 |
| 落地后（改动仍留在 diff 里） | 同上 | 三条规则判定与理由均与规则原文一致 |
| 落地后（违规提交进 HEAD，只改无关行） | 改 `versionName`、加 `org.gradle.configuration-cache=true` | 默认：只报出 `fullMode`（违规行恰在同一 hunk 的上下文里）；`isMinifyEnabled=false` 审查阶段报了、被后置过滤丢掉。加 `--no-filter` 后全部命中 |

**边界（重要）**：整份文件判只决定"模型报不报"。后置过滤按"评论描述的是不是本次 diff 里的代码"裁剪，**违规行落在 diff hunk 之外时仍会被丢**。要当硬门禁就用 `--no-filter`，或在 CI 侧另跑一条静态检查。细节见 `ADDED-RULES.md` 3.2 节。

## 4. 没做、需要你定的

1. **CI 取数脚本**：AAB → `jar xf … BUNDLE-METADATA/com.android.tools/r8.json` → 读 `options` / `stats` → 与 25% 比。字段名要用一份**真的 AGP ≥ 8.10 打出来的 r8.json** 落地，手上这份 AAB 是 AGP 8.4.0、没有该文件，所以脚本暂不写。
2. **`android.r8.optimizedShrinking=true`**：默认 false，打开会让 R8 用更激进的精简（能抬 shrinking 百分比），属于"怎么提高"那一节，不进规则。
3. 零成本的兜底门禁：CI 里直接 grep `isMinifyEnabled = false` / `android.enableR8.fullMode=false` / `proguard-android.txt`，比 OCR 更可靠（不受 hunk 限制）。
