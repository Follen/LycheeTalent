# 平台介绍与发布素材

这里维护平台介绍与素材，先讲玩家的使用场景，再介绍具体操作。当前仓库版本、安装包路径和各平台最后一次记录见 [metadata.json](metadata.json)，历史执行参数与回执保存在 `publish/`。

仓库版本：1.1.0，已推送 GitHub tag。新手盒子插件 ID **27799** 的 1.1.0 已审核通过并公开，文件 ID 为 **654467**；网易 DD 分享码 **766554** 的 1.1.0 已上传，作者列表、详情与版本历史均已确认新版本，接口未返回明确的审核结论。本次保留了平台现有介绍与素材；仓库中尚未同步的资料变更没有随版本上传。完整回读与会话清理结果见本次 `publish/20261015-231918-*-plugin-update/` 记录。

## 可直接使用的内容

| 文件 | 用途 |
| --- | --- |
| [中文介绍](description.zh-CN.md) | 新蜂、DD、黑盒、ModUs 的中文详情文案 |
| [中文 HTML](description.zh-CN.html) | 支持富文本／HTML 的详情字段 |
| [English](description.en.md) / [HTML](description.en.html) | CurseForge 等英文详情 |
| [metadata.json](metadata.json) | 名称、摘要、版本、协议与本地素材路径；不是可执行上传参数 |
| [更新记录](../../Changelog.md) | 各版本更新内容 |
| [封面](../media/release-cover.png) | 参照荔枝黑红风格的宣传封面 |
| [实机图库](../media/README.md) | 独立游戏截图与说明 |
| [Logo](../media/talent-logo.png) | 平台项目标识 |

安装包由 `tools/package.ps1` 生成于 `dist/LycheeTalent-<主包 TOC 版本>.zip`，附 SHA256 文件。14 个文件夹须完整保留；附带许可证与第三方声明。平台适配图片时保留原始实机截图，不用生成式图片替换真实 UI 证据。

## Fupload 平台说明

| 平台 | 素材选择 | 实际发布时的入口 |
| --- | --- | --- |
| 新蜂 NewBeeBox | 中文介绍、封面、截图、ZIP | 默认优先官方 ncc；先核对已安装 CLI 的 docs 和具体命令帮助 |
| 网易 DD | 中文摘要及 HTML、封面、截图、ZIP | Fupload 的 DD 工作流；复用官方客户端会话，完成后清理 |
| CurseForge | 英文介绍、更新记录、ZIP | 先在 Authors 网站创建项目；Fupload 上传到已有项目 |
| 黑盒工坊 | 中文介绍、封面、截图、ZIP | Fupload 的 blackbox 工作流，按目标项目能力更新 |
| ModUs / 大脚 | 中文介绍、Logo、截图、协议、ZIP | Fupload 的 modus 工作流，复用 ModUs.Creator 登录 |

这些是平台入口说明；实际提交前以已安装 Fupload 技能、命令帮助和平台读回为准。游戏版本、分类、平台项目 ID、可见性、审核意图和商业字段都必须由目标平台查询与作者选择确定，资料中没有虚构这些字段。

实际执行需先读取目标项目，再把完整计划保存在 `publish/<时间>-<平台>-plugin-<动作>/`，遵循 [协作与发布规则](../../AGENTS.md) 及 Fupload 流程提交并回读。此文档不包含可直接执行的创建或上传请求。

## 授权说明

使用 Lychee 非商业署名许可证 1.0；名称和来源适配本项目。平台若要求授权全文，使用根目录 LICENSE。游戏画面、图标及 WCL 来源的权利说明见 THIRD_PARTY_NOTICES.md。
