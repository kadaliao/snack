# Snack · 卡片零食

碎片时间刷的 iPhone 闪卡 app。卡片不用自己做：它们从 iCloud 里的一个文件夹流进来，比如 [prompt-en](https://github.com/kadaliao/claude-mods/tree/main/prompt-en) 写 prompt 时收的生词本，或者按格式生成的整套牌组。

现在是 M0：能把 Inbox 里的牌组读进来、合并好、列出来。复习的玩法、连胜和每日目标在 M1。

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
| `SnackKit/` | 不涉及界面的部分：deck/1 的读取、合并成本地内容库。能在 Mac 上直接 `swift test` |
| `Snack/` | iOS app：监视 iCloud 收件箱（`Inbox/`）和界面（`Views/`） |
| `spec/` | 牌组格式 |
| `tools/deck-lint.mjs` | 牌组校验，零依赖 |
| `scripts/device.sh` | 编译、签名，装到连着的 iPhone 上 |

## 开发

```bash
cd SnackKit && swift test        # 逻辑测试
xcodegen generate                 # 改了 project.yml 或增删文件后
scripts/device.sh                 # 装到手机
```

Xcode 工程由 `project.yml` 生成，不进仓库。签名要 Xcode 登录开发者账号（Xcode › Settings › Accounts）：第一次编译会建出 App ID、iCloud 容器 `iCloud.com.kadaliao.snack` 和描述文件。

Bundle ID `com.kadaliao.snack`，iOS 18，Swift 6。

许可证：MIT
