# 牌组格式 deck/1

Snack 从 iCloud 文件夹里读牌组。任何程序都能往里放：prompt-en、AI 生成的整套卡片，或者你手写的 JSON。这份文档说明文件该怎么写。

## 放在哪里

```
iCloud Drive / Snack / Inbox / *.deck.json
```

在 Mac 上是 `~/Library/Mobile Documents/iCloud~com~kadaliao~snack/Documents/Inbox/`。这个文件夹要等 iPhone 上装好 Snack、第一次打开以后才会出现；**不要在 Mac 上手动建它**，手动建出来的文件夹不会同步。

- 文件名以 `.deck.json` 结尾，其他文件一概不读。
- 一个文件是一个牌组的完整快照。生产者每次都可以把整个文件重写一遍。
- 同一个牌组可以分成几个文件写，比如两台 Mac 各写一份。文件里的 `deck.id` 相同，Snack 就把它们合并成一个牌组。
- Snack 只读这些文件，从不改写它们。
- 写文件时先写到别处，再移进来，免得手机读到写了一半的文件。

## 文件结构

```json
{
  "format": "deck/1",
  "deck": {
    "id": "prompt-en.en",
    "title": "prompt-en · 英语",
    "source": "prompt-en",
    "lang": { "target": "en", "native": "zh" },
    "description": "写 prompt 时学到的英语",
    "updatedAt": "2026-11-10T08:00:00Z"
  },
  "cards": [
    { "id": "1dwgyhsq", "kind": "phrase", "front": "顺便", "back": "while you're at it" }
  ]
}
```

### `deck`

| 字段 | 必填 | 说明 |
|---|---|---|
| `id` | 是 | 牌组的标识，生产者自己定，以后不要改。建议写成 `来源.名字`，如 `prompt-en.en` |
| `title` | 是 | 显示的名字 |
| `source` | 否 | 生产者的名字，如 `prompt-en`、`make-deck` |
| `lang` | 否 | 语言牌组才写：`target` 是要学的语言，`native` 是母语，都用 BCP 47 代码（`en`、`ja`、`zh`）。写了 `target`，Snack 才会出朗读和拼句这类语言玩法 |
| `description` | 否 | 一句话介绍 |
| `updatedAt` | 否 | 这份快照的时间，ISO 8601。同一张卡出现在几个文件里时，以 `updatedAt` 最新的那份为准 |

### `cards[]`

| 字段 | 必填 | 说明 |
|---|---|---|
| `id` | 是 | 卡片在牌组里的标识，以后不要改。同一个 `id` 再出现，算同一张卡的新版本，复习进度不变 |
| `kind` | 是 | `phrase`、`pattern`、`fix`、`qa`，见下文 |
| `front` | 是 | 先看到的一面 |
| `back` | 是 | 要想起来的一面 |
| `reading` | 否 | 读音，比如日语的平假名：`念のため` → `ねんのため` |
| `context` | 否 | 正面出自的原句，比如你写的那句 prompt |
| `example` | 否 | 含有背面原文的例句，填空玩法要用它挖空 |
| `why` | 否 | `fix` 卡：错在哪、为什么，几个词 |
| `pattern` | 否 | `pattern` 卡：可复用的句型，会变的部分写成 `___` |
| `distractors` | 否 | 选择题用的错误选项，2–5 个；不写时从同一牌组里挑 |
| `tiles` | 否 | 拼句用的词块，按顺序连起来要正好等于 `back`。日语没有空格，最好写上 |
| `tags` | 否 | 标签 |
| `seen` | 否 | 生产者遇到这张卡的次数。`fix` 卡的 `seen` 变大，说明又犯了同样的错，Snack 会把它当作一次遗忘 |
| `addedAt` | 否 | 收进来的时间，ISO 8601 |
| `deleted` | 否 | 写 `true` 就把这张卡藏起来。只是从文件里去掉的卡不会被删，Snack 会保留它 |

### `kind`

- `phrase`：一个表达。`front` 是母语，`back` 是要学的语言。`顺便` → `while you're at it`
- `pattern`：一整句，外加一个能套用的句型。`front` 是母语的句子，`back` 是译文，`pattern` 是句型。`先别急着提交，等测试跑完再说` → `Hold off on committing until the tests finish.` · `Hold off on ___ until ___`
- `fix`：你写过的错误说法和改正后的说法。`front` 是你写的，`back` 是改正的。`add timeout` → `add a timeout`
- `qa`：通用的知识卡，问题和答案。`What does CAP stand for?` → `Consistency, Availability, Partition tolerance`

## 校验

```bash
node tools/deck-lint.mjs Inbox/*.deck.json
```

有错误时退出码是 1，并列出每处错误的位置。AI 生成的牌组写进 Inbox 之前必须先通过校验。机器可读的定义在 [`deck.schema.json`](deck.schema.json)。

## 版本

`format` 写 `deck/1`。以后只会加可选字段；要改已有字段的含义时，会换成 `deck/2`。Snack 不认识的字段会被忽略。
