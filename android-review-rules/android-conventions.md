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
2. 关闭安全网：`minifyEnabled=false`、`usesCleartextTraffic=true`、`android:debuggable=true`、移除 keep 规则。
3. 让组件可被任意应用触达：导出且无权限守卫的 Activity/Service/Receiver/Provider。
4. 在应用里引入全新技术栈（新框架、新网络库、新 DI）而没有在改动里说明理由。
5. 静默失败：吞掉异常、忽略错误返回值、`catch` 后不处理也不上报。

## 4. lint 全量扫描与 OCR 的分工（别在这里重复劳动）

每次审查前，`scripts/review.sh` 会跑一次全量 `./gradlew lint`，把结果整理成 `.ocr/lint-report.md` 作为背景注入。OCR 对照这份报告审查，**不重复报** lint 已经发现的问题，只做工具做不到的事。

以下检查交给工具链，OCR 规则里**不要**写，模型也不该重复报：

- 代码格式、缩进、import 顺序、命名规范 → ktlint
- 可静态判定的代码异味、复杂度、未使用资源 → detekt / Android Lint
- API 级别误用（`NewApi`）、资源引用错误、Manifest 结构错误 → Android Lint
- 已知的 `@Deprecated` 符号 → Android Lint + Kotlin 编译警告（见 `.ocr/lint-report.md`）

OCR 只做这些工具做不到的事：**语义、意图、跨文件影响、约定与架构的一致性**。

## 5. 交付质量的最低要求

- 新增或修改的公开行为要有对应测试；测试缺失时按 `medium` 报一条，不要每个文件都报。
- 同一个问题在一个文件里只报一次，不要对同一处重复刷屏。
- 报问题必须给出**可以照着改的具体建议**；拿不准就写"需要确认"并说明你的依据，不要编造替代 API 或不存在的 API。
