# Snack · 卡片零食

碎片时间刷的 iPhone 闪卡 app。卡片不用自己做：它们从 iCloud 里的一个文件夹流进来，比如 [prompt-en](https://github.com/kadaliao/claude-mods/tree/main/prompt-en) 写 prompt 时收的生词本，或者按格式生成的整套牌组。

现在是 M2：八种玩法，越熟越难；XP、连对加成和冻结卡；音效；桌面和锁屏小组件。更多来源（AI 出整套牌组、分享导入）和 iPad 同步在 M3。

## 怎么刷

一节 10 题左右，两分钟。到期的卡先来，最可能忘的最先；每天再混几张新卡（默认 10 张）。答错的卡在这一节末尾再出一次。

每张卡按熟悉程度换玩法，越熟越难，卡片有哪些字段就能玩哪些：

| 玩法 | 怎么玩 | 什么时候出 | 最高评级 |
| --- | --- | --- | --- |
| 选一选 | 四个答案选一个 | 新卡 | Hard（蒙对的概率有 1/4） |
| 配一配 | 五对卡片连线 | 一节里有五张短的新卡或在学的卡时 | Hard |
| 拼一拼 | 用词块拼出答案，混着几块不相干的；日语、中文按词切 | 在学的卡；长句 | Good |
| 听一听 | 听答案，拼出来；太短拼不了就选意思 | 在学、熟悉的卡（语言牌组） | Good（选意思是 Hard） |
| 填一填 | 例句挖掉答案，填回去 | 有例句的卡 | Good |
| 默一默 | 打出答案，单词里的小拼写错误不算错 | 熟悉的短答案 | Easy |
| 改一改 | 把你写过的错句改对 | 纠错卡 | Good |
| 翻一翻 | 想一想，翻过来，自己说记没记住 | 别的玩法都出不了时 | Good |

不用自己打分：答错或点了「不会」记 Again；对了但用了提示或花了太久记 Hard；对了记 Good；默一默又快又准记 Easy。每张卡每节只有第一次作答进排期，末尾重来的那次只算练习。少一个词就是错，"add timeout" 不是 "add a timeout"。听一听可以点「现在不方便听」，之后 15 分钟改成看着拼。

**XP**：答对一题 10，配对一张 5，末尾重来答对 5；连对 5 题起每题再加 5；刷完一节加 10，全对再加 20。一节大约 100 XP。每天的目标按 XP 算，默认 300。

**连胜和冻结卡**：一天刷完一节就算打卡。每刷 10 节送一张冻结卡，最多存 2 张；哪天一节都没刷，自动用掉一张，连胜不断（那天不加天数）。

**小组件**：桌面上显示连胜、今天的 XP 和待复习的卡，锁屏上显示连胜；点一下直接开始一节。卡片到期和过零点时会自己更新。

## 放卡片进来

任何程序都能往这个文件夹放 `*.deck.json`：

```
iCloud 云盘 / Snack / Inbox
~/Library/Mobile Documents/iCloud~com~kadaliao~snack/Documents/Inbox   （Mac 上）
```

这个文件夹要等 iPhone 上装好卡片零食、第一次打开以后才会出现，不要在 Mac 上手动建。

- 格式：[spec/deck-format.md](spec/deck-format.md)，以及 [`deck.schema.json`](spec/deck.schema.json)、[示例](spec/examples/)。
- 校验：`node tools/deck-lint.mjs <文件>...`。
- prompt-en 0.5.0 起会自动导出生词本；也可以在会话里用 `/vocab export` 手动导出。

文件归写它们的程序所有，卡片零食只读不改。生产者每次都可以把整个牌组重写一遍：同一个 `id` 的卡片算同一张；从文件里消失的卡片照样保留；只有写了 `"deleted": true` 的才会隐藏。

## 目录

| | |
| --- | --- |
| `SnackKit/` | 不涉及界面的部分：deck/1 的读取和合并、FSRS 排期（`SnackFSRS/` 包着 [swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs)）、复习记录回放、组一节课、判分评级、连胜。能在 Mac 上直接 `swift test` |
| `Snack/` | iOS app：iCloud 收件箱（`Inbox/`）、复习记录（`Store/`，SwiftData 里只追加的日志）、提醒（`Notify/`）、朗读和音效（`Speech/`、`Sounds/`）和界面（`Views/`） |
| `SnackWidget/`、`Shared/` | 小组件。app 把当天的摘要写进 App Group `group.com.kadaliao.snack`，小组件从摘要推算之后的样子 |
| `SnackUITests/` | 把一节课从头刷到尾，各种玩法走一遍；小组件的链接和样子 |
| `spec/` | 牌组格式 |
| `tools/deck-lint.mjs` | 牌组校验，零依赖 |
| `scripts/device.sh` | 编译、签名，装到连着的 iPhone 上 |
| `scripts/make-sounds.py` | 用正弦波合成音效，改了声音就重跑一遍 |

## 开发

```bash
cd SnackKit && swift test        # 逻辑测试
xcodegen generate                 # 改了 project.yml 或增删文件后
scripts/device.sh                 # 装到手机

# 界面测试：在模拟器上刷一节，每种玩法和小组件各截一张图放进 /tmp/shots
TEST_RUNNER_SNACK_SHOTS=/tmp/shots xcodebuild test -project Snack.xcodeproj -scheme Snack \
  -destination 'platform=iOS Simulator,name=iPhone Air'
```

界面测试用的是模拟器里已有的牌组，复习记录只放在内存里，不碰真实进度。

Xcode 工程由 `project.yml` 生成，不进仓库。签名要 Xcode 登录开发者账号（Xcode › Settings › Accounts）：第一次编译会建出 App ID、iCloud 容器 `iCloud.com.kadaliao.snack` 和描述文件。

Bundle ID `com.kadaliao.snack`，iOS 18，Swift 6。

许可证：MIT
