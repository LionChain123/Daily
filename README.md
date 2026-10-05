# 拾日 · 个人成长日志

SwiftUI 原生 iPhone / iPad App，最低 iOS 17，无第三方依赖。延续训练 App 的工作流：本地记录 → 历史查看 → 导出备份 → Mac / GitHub Actions 构建 unsigned IPA → 在自己的设备上签名安装。

## 与训练 App 实现的对应

参考已有训练 App 的 SwiftUI 原生实现，保持一致的界面、存储保护和构建方式。

- `App.swift`：沿用 `@StateObject` 与 `environmentObject`，并使用相同的 `Palette` 深色背景、卡片和荧光绿配色。
- `Views.swift`：沿用原生 TabView / NavigationStack、大号圆体标题与 24 点圆角卡片；从后台回到前台刷新今日日期。
- `MotivationLibrary.swift` / `MotivationStore.swift`：借鉴数据层与界面状态分离、原子写入、写入失败不改变可见数据、损坏文件暂停编辑的方式。日志数据使用独立文件，不迁移训练记录。
- `verify-on-mac.sh`、`scripts/build-iphone.sh` 与 GitHub workflow：沿用模拟器验证、Mac 数据测试、unsigned arm64 IPA 打包和日志附件流程。
- `work/verify_extracted.py`：借鉴现有 tree-sitter Swift 语法解析与 OpenStep 工程结构验证；本次已实际执行通过。语法解析不等于 Swift 类型检查。

工程与数据均独立于训练 App，可与训练 App 并存。

## 使用

- **今日**：早上确定一件重要的事；白天记学习、工作和支出；晚上写收获、改进与明日行动。感想和状态选填。
- **日志**：全文搜索、选择日期补记、编辑历史。删除文字日志不影响当天支出。
- **时间**：给具体事项分类，支持自定义分类、手动补记日期和时长，以及单事项计时、暂停、继续、结束保存。按天查看总时长、分类占比、事项累计，按周查看每日趋势与事项总时长。
- **回顾**：按周一至周日统计记录天数、学习分钟、人民币支出、类别分布；写每周成果、教训和下周行动。
- **我的**：准备 JSON 备份后用原生分享面板存到“文件”；导入前检查并确认，同日期日志、同 ID 支出和同周复盘以备份为准，其他记录保留。

记录在编辑页面点“保存”后写入。取消未保存的修改会确认，禁止直接下滑关闭编辑页。金额按整数分保存，避免浮点累计误差。数据采用 Codable JSON 原子文件写入，保存失败保留编辑内容并提示错误。初始为空，不预填虚假的个人记录。

## v1.1 时间记录

每条时间记录包含日期、分类、具体事项、时长和可选备注。比如“学习 / 英语听力 / 30 分钟”和“工作 / 写方案 / 1 小时”。金额与时间分开保存和统计，时间按整数秒存储，手动补记最多 24 小时，同日明细合计不能超过当天长度。

计时器一次跟踪一件事。开始、暂停和继续都会保存状态，后台或重新启动后根据保存的起始时间计算。暂停间隔不计入。结束后跨午夜的时段会拆到对应日期；未结束的计时不加入已保存统计。后台不持续执行秒表任务，不发通知；这些数值来自时间戳差。修改设备时间或跨时区会影响计时和日期归属，建议结束当前计时后再调整。

当天有时间明细时，所有时间统计以明细为准，日志旧学习分钟不再相加；当天完全没有明细时，旧学习分钟作为“日志学习时间”参与统计。开始使用明细后，请分别记录学习和其他事项。类别“阅读”和“学习”为不同类别，可自行统一分类。

计时忘记结束超过 31 天时会提示放弃并补记。编辑或导入产生同日总时长超过一天时会拒绝写入；正在运行的计时器保留，可修正重复明细后再结束。App 无法自动判断手动记录是否重叠，请避免重复记录同一段时间。

数据格式升级为 version 2，自动兼容旧版本地记录和 version 1 备份。重复导入按记录 ID 去重。备份导入保留本机正在进行的计时器，不从备份恢复计时状态。Bundle ID 与数据路径保持原样；覆盖更新前先导出备份，不要先卸载旧 App。旧版 App 不支持新版备份，避免降级使用。

数据全部在 App 私有目录，没有账号或跨设备同步。卸载会删除本地数据，请定期导出并保存到其他位置。导入前原始文件副本保留在 App 私有目录；如需自行恢复它，可通过 Mac Xcode 的设备容器下载功能取得，日常恢复建议先手动导出备份。读取到损坏文件时暂停写入，允许导出原始文件及导入有效备份。没有提供“清空全部”按钮。

## 记录方法与来源

这是针对日常使用的轻量改编，不是完整方法课程。

1. [Bullet Journal Daily Log](https://bulletjournal.com/blogs/faq/how-to-write-a-daily-log)：日期下快速记录任务、事件与笔记，晚间回看。用在晨间重点与每日短句记录。
2. [康奈尔大学 Cornell Notes](https://lsc.cornell.edu/how-to-study/taking-notes/cornell-note-taking-system/)：学习模板采用问题 / 线索、笔记和总结三个区域；可用自己的话复述，再回看补充。
3. [CFPB Your Money, Your Goals / Spending Tracker](https://www.consumerfinance.gov/consumer-tools/educator-tools/your-money-your-goals/toolkit/)：按类别记录支出，定期汇总。App 默认币种人民币，不做理财建议。
4. 工作“事项—结果—下一步”和成长“收获—改进—行动”为本 App 的简化复盘模板。无需每天填满全部栏目。

## Mac 上运行

打开 `DailyGrowth.xcodeproj`，选择 `DailyGrowth` scheme 和 iPhone 模拟器，运行。

真机需要在 Signing & Capabilities 中选择自己的开发团队并设置唯一 Bundle ID。当前标识 `com.lionchain.DailyGrowth` 与训练 App 不同，可并存。

```bash
bash scripts/build-iphone.sh
```

脚本先执行纯 Foundation 数据测试，再构建 arm64 iPhone Release App，最后生成 `artifacts/DailyGrowth-unsigned.ipa`。IPA 尚未签名，不能直接安装。

## 沿用 GitHub Actions 构建流程

本工程仓库为 [LionChain123/Daily](https://github.com/LionChain123/Daily)。仓库根目录包含 `DailyGrowth.xcodeproj`、`DailyGrowth/`、`.github/`、`scripts/`、`tests/`。

GitHub → Actions → **Build DailyGrowth iPhone IPA** → Run workflow。通过后下载 **DailyGrowth-iPhone-IPA** 附件并解压。用之前使用的 iLoader / Sideloadly 流程在本机签名安装；Apple 账号和签名证书不提交 GitHub。unsigned IPA 不表示已具备安装资格。

后续覆盖更新要保持实际安装 Bundle ID 和签名身份相同，避免卸载后重新安装而丢失数据。

## 验证范围

2026-10-05，GitHub Actions 使用 Xcode 26.6 完成模型测试和 iPhone Release 构建，生成未签名 IPA。日志显示数据测试 PASS 和 BUILD SUCCEEDED。

[首次成功构建](https://github.com/LionChain123/Daily/actions/runs/37299881082) · [下载 IPA 附件](https://github.com/LionChain123/Daily/actions/runs/37299881082/artifacts/11341250855)

附件解压后是 `DailyGrowth-unsigned.ipa`，需要在本机签名后安装。构建附件保留 7 天，过期可重新运行 workflow。未执行 iOS 模拟器视觉检查和真机交互验收。

Windows 本机已完成 Swift 语法解析、OpenStep 工程语法和源文件/资源阶段检查，以及方案引用、工作流结构和资源完整性检查。语法检查不等于类型检查；实际 iOS 编译由上述 Mac 云端构建验证。

在 Mac 上运行 `bash verify-on-mac.sh` 可先执行模型测试并构建模拟器目标；运行 `bash scripts/build-iphone.sh` 生成未签名真机 IPA。验证脚本位于当前工作区的 `verify_project.py`，重跑需要参考目录内的现有 tree-sitter 依赖。

真机验收：新增日志与支出后重启；跨日与跨周查看；搜索、补记、改价和删除；导出再导入两次（不重复支出）；取消导入不修改数据；取消编辑有放弃提示；长文本、大字号和 iPad 横屏；备份损坏时原记录保留。周回顾统计真实记录，没有预设目标或虚构完成率。
