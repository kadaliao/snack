# 发版到 TestFlight

发版要在维护者的 Mac 上做：Xcode 登录着开发者账号（签名用），加上 App Store Connect API 密钥（上传和管测试组用）。

## 第一次之前

这些都已经做过了（2026-11-10），App 记录叫「卡片零食」，App ID `6832964830`。要重做时照下面来。

1. **App 记录**：只能在网页上建（API 做不到）。[App Store Connect](https://appstoreconnect.apple.com/apps) › 我的 App › ＋ › 新建 App：

   | 字段 | 填写 |
   | --- | --- |
   | 平台 | iOS |
   | 名称 | 卡片零食（全局唯一；被占用了就换一个，比如「卡片零食 Snack」，主屏幕上显示的名字不受影响） |
   | 主要语言 | 简体中文 |
   | 套装 ID | com.kadaliao.snack |
   | SKU | snack-ios |

   建好以后脚本按套装 ID 找它，不用记 App ID。

2. **测试信息**：给外部测试员的构建要先过 TestFlight 审核，审核要这些信息：Beta 版描述、反馈邮箱、审核联系人（姓名、电话、邮箱）。不用演示账号。可以在 App Store Connect › TestFlight › 测试信息 里填，也可以用 API 写 `betaAppLocalizations` 和 `betaAppReviewDetails`（第一次是从开心果的设置复制的）。

   内部测试组「内部测试」（能看到所有构建，不用审核）也已经建好，维护者在里面。

3. **CloudKit 的正式环境**：开发版（`scripts/device.sh` 装的）用 CloudKit 的开发环境，TestFlight 和 App Store 版用正式环境。正式环境的结构要从开发环境部署过去，不然 TestFlight 版的复习记录同步不了：

   1. 让开发环境里有 `CD_ReviewRecord` 和 `CD_LessonRecord` 两种记录：用 `scripts/device.sh` 装到手机上，再带参数打开一次，它会把记录类型推上去（输出 `CloudKit schema: initialized`）：

      ```sh
      xcrun devicectl device process launch --console --device <udid> com.kadaliao.snack -- -SnackInitCloudKitSchema YES
      ```

   2. [CloudKit Console](https://icloud.developer.apple.com/dashboard) › iCloud.com.kadaliao.snack › Deploy Schema Changes。

   以后 `ReviewRecord`、`LessonRecord` 加了字段，都要再部署一次。正式环境的字段只能加、不能删，所以改模型时只加带默认值的字段。

4. **外部测试组**「朋友」：`scripts/beta-review.sh` 第一次运行时会建出来，开着公开链接，谁拿到链接都能装。

## 每次发版

1. `project.yml` 里升 `MARKETING_VERSION`（版本号）和 `CURRENT_PROJECT_VERSION`（构建号，每次上传都要比上次大）。
2. `CHANGELOG.md` 里写这个版本的条目，它会变成 TestFlight 里的「测试内容」。
3. 上传并提交审核：

   ```sh
   ASC_KEY_ID=<密钥 ID> ASC_ISSUER_ID=<Issuer ID> scripts/testflight.sh
   ```

   归档、导出、上传，然后等 App Store Connect 处理完（5–15 分钟），把构建加进「朋友」并提交 TestFlight 审核。审核一般一天内通过，之后公开链接就能装。

## 邀请别人测试

把公开链接发给对方就行。也可以按邮箱邀请，TestFlight 会发邮件：

```sh
ASC_KEY_ID=… ASC_ISSUER_ID=… scripts/invite.sh friend@example.com
```

## 说明

- **调 API**：`scripts/asc.sh <方法> <路径> [JSON]`，例如 `scripts/asc.sh GET "/v1/apps?filter[bundleId]=com.kadaliao.snack"`。
- **国区 iCloud**：国区 Apple ID 的 iCloud 由云上贵州运营。复习记录同步用的是 CloudKit，第一次给国区账号的朋友测试时，看看「设置」里的「iCloud 同步」是不是显示「已同步」。
- **上传报 TLS 错误**：开着代理或 VPN 时 `altool` 可能报 `-9816`，常常重试后仍会成功。重传之前先到 App Store Connect 看构建是不是已经在了。
