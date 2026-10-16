# Android 团队审查规范

一套可直接落地的 OpenCodeReview（`ocr`）规则集。定位是**团队级**：谁改代码都拿到同一套判定标准、同一套严重度词汇，CI 分流才有意义。

## 文件与去处

| 本目录文件 | 放进你的 Android 仓库 | 作用 |
|---|---|---|
| `rule.json` | `<repo>/.opencodereview/rule.json` | 逐文件判定标准（提交进版本库） |
| `android-conventions.md` | `<repo>/.ocr/android-conventions.md` | 运行级团队上下文：技术栈、红线、严重度词表（提交） |
| `deprecated-apis.md` | `<repo>/.ocr/deprecated-apis.md` | 废弃 API 清单，由 lint 报告生成（提交） |
| `scripts/review.sh` | `<repo>/scripts/review.sh` | 包装 `ocr review`，自动注入上面两个背景文件 |
| `scripts/refresh-deprecated-apis.sh` | `<repo>/scripts/refresh-deprecated-apis.sh` | 从 lint 报告刷新废弃 API 清单 |
| `scripts/deprecated-apis.template.md` | `<repo>/scripts/deprecated-apis.template.md` | 废弃清单的文案模板，`refresh-deprecated-apis.sh` 运行时读取 |

`.opencodereview/rule.json` 是官方支持的 per-project 配置，**safe to commit**；`.ocr/` 里是我们自己的约定文档，`rule.json` 已经把 `**/.ocr/**` 排除了，不会自我审查。

## 三步采纳

```bash
# 1. 拷文件
cp android-review-rules/rule.json                     your-android-repo/.opencodereview/rule.json
mkdir -p your-android-repo/.ocr
cp android-review-rules/android-conventions.md        your-android-repo/.ocr/
cp -R android-review-rules/scripts                   your-android-repo/

# 2. 填 android-conventions.md 里所有 <!-- TODO(team) --> 标记（技术栈、分层、模块边界）
#    这一节是整套规范里唯一必须按你们项目改的地方。

# 3. 生成废弃 API 清单
cd your-android-repo && ./gradlew lint
./scripts/refresh-deprecated-apis.sh app/build/reports/lint-results-debug.xml
#    然后手工填清单里的"替代方案"列
```

审查意见的语言单独设：

```bash
ocr config set language 中文
```

## 验收（不花 token）

```bash
# 每个文件类型分别确认命中的规则
for f in app/build.gradle.kts settings.gradle.kts gradle/libs.versions.toml gradle.properties \
         app/AndroidManifest.xml app/src/main/res/layout/home.xml \
         app/src/main/java/com/example/ui/HomeScreen.kt app/src/main/java/com/example/data/Repo.java \
         app/proguard-rules.pro; do
  printf '%-52s' "$f"; ocr rules check "$f" | sed -n '2,3p' | tr '\n' ' '; echo
done

# 确认过滤：生成物/测试/密钥不会被审
ocr review --preview --format json
```

`ocr rules check` 的第二、三行是 `Source`（规则来自哪一层）和 `Pattern`（命中的 glob）。规则文件写错了、顺序不对、glob 不匹配，这里一眼就能看出来——**不要跳过这一步直接跑审查**。

## 日常怎么用

```bash
./scripts/review.sh                                  # 工作区改动
./scripts/review.sh --from main --to HEAD            # 分支区间
./scripts/review.sh -c abc123 --format json -o /tmp/r.json
```

包装脚本固定带上 `--background-file`，所以团队约定不会因为有人忘了加 flag 而失效。

## CI 怎么接

```bash
./scripts/review.sh --from "origin/$BASE" --to "origin/$HEAD" \
  --format json --audience agent -o /tmp/ocr-result.json
```

`--background-file` 一次只接**一个**文件，而我们要注入团队约定 + 废弃清单两份。`scripts/review.sh` 的做法是先 `cat` 成一个合并文件再传（合并结果落在 `.ocr/.review-background.md`，建议加进 `.gitignore`）。CI 里直接调用这个脚本即可，不要手写命令。

GitHub Action 侧，团队规范的价值最终体现在**分流**上：`route_severity_below` 和 `route_categories` 两个 input 直接吃 `rule.json` 让模型输出的那套枚举，所以 `android-conventions.md` 第 2 节必须和技术栈一起定下来，否则分流形同虚设。

## 维护

- **升级 compileSdk / AGP / 依赖后**：重跑 `refresh-deprecated-apis.sh`，清单变化写进 PR 说明。
- **规则演进**：一次只改一条，改完 `ocr rules check` 确认，跑一次真实 PR 看会不会误报。加规则容易，去掉噪声难。
- **规则文件不要写"注意性能"**：写不出来的判定标准就是无效标准，会变成模型的自由发挥。

## 四个 Android 特有的注意点

这些是默认过滤行为，不是本规范的设定，但会直接影响你看到的结果：

1. **`**/build/**` 默认不排除**（只有 `**/.gradle/**` 排除）。所以 `rule.json` 里必须有 `**/build/**`，否则 AGP 生成的 `BuildConfig.java`、`R.java` 会被送审。
2. **`**/src/androidTest/**` 默认不排除**（默认只排 `**/src/test/**`）。本规范选择两个都排除；如果你们想审测试代码，把 `include` 加上：
   ```json
   "include": ["**/*.pro", "**/src/test/**/*.{kt,kts}", "**/src/androidTest/**/*.{kt,kts}"]
   ```
   注意 `include` 会一并绕过扩展名白名单和测试目录排除，所以只加你确实要审的路径。
3. **`build.gradle.kts` 会落到 Kotlin 源码规则上**，因为内置只有 `**/build.gradle` 这一条精确匹配。所以 `rule.json` 里 `**/build.gradle*` 必须排在 `**/*.{kt,kts}` **前面**——顺序错了，Gradle 规则永远不触发。
4. **`.pro` 不在扩展名白名单里**，默认以 `unsupported_ext` 丢弃，规则写了也没用，必须靠 `include` 拉回来。

## 分工：这套规则不做什么

| 检查 | 归谁 |
|---|---|
| 格式、命名、import 顺序 | ktlint |
| 代码异味、复杂度、未使用资源 | detekt / Android Lint |
| API 级别误用、资源/Manifest 结构 | Android Lint |
| 已知 `@Deprecated` 符号 | Android Lint + Kotlin 编译警告 → 喂给本规范的清单 |
| **语义、意图、跨文件影响、架构一致性** | **本规范（OCR）** |

把 lint 能做的事写进 OCR 规则是负收益：花 token、还会和 lint 的结果打架。
