---
name: make-deck
description: Make a flashcard deck for Snack (卡片零食), the iPhone flashcard app, and put it in its iCloud Inbox. Use when the user asks to make, generate or add to a deck of cards for Snack, on a topic, from a text or notes, or for a language (做一套卡片、生成牌组、出一套日语/英语卡片、把这篇文章做成卡片、往牌组里加卡).
---

# make-deck

把一个主题、一段材料或一门语言做成 Snack 的牌组（`deck/1` 格式），校验通过后放进 iCloud 收件箱，手机上的卡片零食会自己收到。格式的完整说明在 Snack 仓库的 `spec/deck-format.md`；这里是做一套好牌组要知道的部分。

## 1. 先弄清楚

先看收件箱在不在：`~/Library/Mobile Documents/iCloud~com~kadaliao~snack/Documents` 这个文件夹存在，做好的牌组才放得进去。不存在说明手机上还没装过、打开过卡片零食；告诉用户先装，不要自己建这个文件夹（手动建的不会同步）。

再问清楚（用户已经说了的就别再问）：

- **内容**：主题（"日语旅行常用语"）、材料（一段文章、笔记、一个文件），或者两者都有。
- **语言**：语言牌组要定 `lang.target`（学的语言）和 `lang.native`（母语，通常是 `zh`）。知识类牌组不写 `lang`。
- **多少张**：没说就做 30 张左右。一次不要超过 100 张。
- **新做还是加卡**：往已有的牌组里加，先读出收件箱里那个文件。

## 2. 写卡片

```json
{
  "format": "deck/1",
  "deck": {
    "id": "make-deck.ja-travel",
    "title": "日语 · 旅行",
    "source": "make-deck",
    "lang": { "target": "ja", "native": "zh" },
    "description": "一句话介绍",
    "updatedAt": "2026-11-10T08:00:00.000Z"
  },
  "cards": []
}
```

- `deck.id` 写成 `make-deck.<英文短名>`，以后不要改；`updatedAt` 和每张卡的 `addedAt` 用现在的 ISO 时间。
- 卡片的 `id` 用小写英文短名，从内容来（`on-both-sides`、`nen-no-tame`），牌组里不能重复。**已有的卡 id 一个都不能变**：id 变了，用户在这张卡上的复习进度就丢了。

卡片有四种 `kind`，怎么写才好玩：

| kind | front | back | 要配的字段 |
| --- | --- | --- | --- |
| `phrase` | 母语的说法，短，最好 12 个字以内 | 学的语言：英语这类 1–5 个词、24 个字符以内；日语、中文 12 个字以内 | `example`：一句自然的例句，**原样包含 back**（填一填会把它挖掉） |
| `pattern` | 母语的一整句 | 译文 | `pattern`：可复用的句型，会变的部分写成 `___` |
| `fix` | 常见的错误说法 | 改对的说法，短（日语、中文 12 个字以内，才能让人动手改） | `why`：错在哪，几个词 |
| `qa` | 问题 | 简短的答案，40 个字以内最好 | `distractors`：2–5 个似是而非、长短和形式都像答案的错误选项，3 个最好 |

**语言牌组里，每张卡的 back 和 `distractors` 都用学的语言写。** 听一听会用这门语言的声音把 back 读出来，写成母语就读错了。语言牌组里的 `qa` 卡也一样：问题用母语，答案用学的语言（`吃完离店时说什么？` → `ごちそうさまでした`）。

卡片字段决定能玩什么：front 和 back 都短的卡能配一配；有例句的能填一填；back 短的能默一默、改一改；语言牌组的卡能听一听和拼一拼。

`context` 是 front 的出处，只在从材料做卡时写（材料里出现它的那一句）；按主题做的牌组不写。

日语和中文没有空格：

- `reading`：back 里有汉字时写上，用平假名写整个 back 的读音，片假名照原样留着，不带句号：`生ビールを一つ` → `なまビールをひとつ`。
- `tiles`：`pattern` 卡、`fix` 卡，和超过 6 个字的 `phrase` 写上：2–8 块，一块是一个词连同后面的助词、词尾，**按顺序连起来正好等于 back**：`["テストが", "終わってから", "コミットして", "ください。"]`。不写的话 app 会自己切，但切得没有人工的好。
- 句子的 back 带句号（`。`），短语不带。
- 动词、形容词会变形，例句里要原样包含 back，就让 back 用例句里的那个形式（例句是「別々でお願いします」，back 写 `別々で`，不写 `別々`）。

做得好的卡：

- 一张卡只考一件事。back 有好几种说法时，挑最常用的一种，别写成 "A / B"。
- 例句要像真人会说的话，不要为了塞进 back 硬造。
- 从材料做卡时，只做值得记住的：概念、术语、关键数字、容易混的点，不要把每句话都变成卡。

## 3. 校验

先写到临时文件，用这个 skill 目录下的 `deck-lint.mjs` 校验（它链接到 Snack 仓库的 `tools/deck-lint.mjs`，所以这个 skill 要用链接装，不要把文件夹拷走）：

```bash
node <skill 目录>/deck-lint.mjs "$TMPDIR/make-deck.ja-travel.deck.json"
```

有 error 必须改到没有；warning 也尽量改掉（比如例句里没有 back、pattern 卡没有 `___`）。

## 4. 放进收件箱

收件箱在 Mac 上是 `~/Library/Mobile Documents/iCloud~com~kadaliao~snack/Documents/Inbox/`（第 1 步已经确认它的上一级存在）。

- 文件名和 `deck.id` 一致：`make-deck.ja-travel.deck.json`。
- 先写到临时文件再 `mv` 进去，免得 iCloud 把写了一半的文件传到手机上。
- 往已有牌组里加卡时，整个文件重写一遍：旧卡原样保留（id 不变），新卡加在后面，`updatedAt` 改成现在。要去掉某张卡，不要删它，给它加上 `"deleted": true`。

## 5. 告诉用户

说清楚：牌组叫什么、一共几张、各种 kind 各几张、放在了哪里。手机上打开卡片零食，一两分钟内会出现在「牌组」里；新卡每天按设置的数量混进复习。
