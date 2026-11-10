# Snack · 卡片零食

碎片时间刷的 iPhone 闪卡 app。卡片不用自己做：它们从 iCloud 里的一个文件夹流进来，比如 [prompt-en](https://github.com/kadaliao/claude-mods/tree/main/prompt-en) 写 prompt 时收的生词本，或者按格式生成的整套牌组。

现在是 M1：能刷了。FSRS-6 排期，四种玩法自动评级，连胜、每日目标和每日提醒。更多玩法、XP 和小组件在 M2。

## 怎么刷

一节 10 题左右，两分钟。到期的卡先来，最可能忘的最先；每天再混几张新卡（默认 10 张）。答错的卡在这一节末尾再出一次。

每张卡按熟悉程度换玩法，越熟越难：

| 玩法 | 怎么玩 | 什么时候出 | 最高评级 |
| --- | --- | --- | --- |
| 选一选 | 四个答案选一个 | 新卡 | Hard（蒙对的概率有 1/4） |
| 拼一拼 | 用词块拼出答案，混着几块不相干的 | 在学的卡；长句 | Good |
| 默一默 | 打出答案，单词里的小拼写错误不算错 | 熟悉的短答案 | Easy |
| 翻一翻 | 想一想，翻过来，自己说记没记住 | 别的玩法都出不了时 | Good |

不用自己打分：答错或点了「不会」记 Again；对了但用了提示或花了太久记 Hard；对了记 Good；默一默又快又准记 Easy。每张卡每节只有第一次作答进排期，末尾重来的那次只算练习。少一个词就是错，"add timeout" 不是 "add a timeout"。

一天刷完一节就算打卡，连胜按天数算。每天的提醒在「设置」里调。

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
| `Snack/` | iOS app：iCloud 收件箱（`Inbox/`）、复习记录（`Store/`，SwiftData 里只追加的日志）、提醒（`Notify/`）、朗读（`Speech/`）和界面（`Views/`） |
| `SnackUITests/` | 把一节课从头刷到尾，四种玩法各走一遍 |
| `spec/` | 牌组格式 |
| `tools/deck-lint.mjs` | 牌组校验，零依赖 |
| `scripts/device.sh` | 编译、签名，装到连着的 iPhone 上 |

## 开发

```bash
cd SnackKit && swift test        # 逻辑测试
xcodegen generate                 # 改了 project.yml 或增删文件后
scripts/device.sh                 # 装到手机

# 界面测试：在模拟器上刷一节，每种玩法截一张图放进 /tmp/shots
TEST_RUNNER_SNACK_SHOTS=/tmp/shots xcodebuild test -project Snack.xcodeproj -scheme Snack \
  -destination 'platform=iOS Simulator,name=iPhone Air'
```

界面测试用的是模拟器里已有的牌组，复习记录只放在内存里，不碰真实进度。

Xcode 工程由 `project.yml` 生成，不进仓库。签名要 Xcode 登录开发者账号（Xcode › Settings › Accounts）：第一次编译会建出 App ID、iCloud 容器 `iCloud.com.kadaliao.snack` 和描述文件。

Bundle ID `com.kadaliao.snack`，iOS 18，Swift 6。

许可证：MIT
