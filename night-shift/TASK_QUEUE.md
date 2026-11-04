# DOMASEED GEO 任务队列

## 创始人决定

在最新 night/geo-YYYYMMDD 分支编辑本文件，填写任务 ID、问题、决定日期与选择，并把对应任务的“状态”明确改回 TODO。不要在 main 编辑。跨晚自动继承此区及已有结果。没有新决定时保留现状。

| 任务 ID | 日期 | 决定 |
|---|---|---|
| — | — | 待填写 |
| GEO-001 | 2026-11-04 10:45 | 创始人已手动退出桌面应用，授权按原流程重试 GEO-001。 |
| GEO-001 | 2026-11-04 | 创始人明确授权第二次桌面开启验收：仅重放只读 GEO-001，保留第一次成功证据；验收后不再重开桌面应用。 |
| GEO-001 | 2026-11-04 | 按已授权的桌面开启验收修正共享60秒计时后复测：只读GEO-001，保留全部历史证据。 |

## GEO-001
状态: DONE
目标: 站点体检（只读站点，修复建议另存草稿）。
验收标准:
- 为实际静态站点构建本地预览副本，检查 HTTP 返回与内部失效链接，外部链接只读检查并区分网络失败。
- 检查 title、meta description、canonical、Organization 及合适的游戏/教育 schema.org JSON-LD；不强制重复添加不合适的类型。
- 核对中英文页面对应，缺少语言版本如实记录；检查完成不等于全部问题解决。
- 运行 `powershell -NoProfile -File night-shift/audit-site.ps1` 取得证据，核对 findings，必要时仅在 drafts 写建议；报告附实际文件证据。
结果: DONE；2026-11-04 执行 `powershell -NoProfile -File night-shift/audit-site.ps1`，退出码 0；本地静态预览 HTTP 200（8937 bytes），title、description、canonical 存在，JSON-LD 可解析并含 Organization、VideoGame、FAQPage；未发现内部失效链接。外部 canonical 请求失败，记为未验证；源码快照缺少中文页，无法核对语言对应。审计完成不代表问题已解决；证据：night-shift/evidence/20261104-111510-GEO-001-site-audit.json。

## GEO-002
状态: BLOCKED
目标: AI 可见度基线，只记录，不对外发布内容。
验收标准:
- 列出 10 个面向约 10–13 岁孩子家长的问题，保存精确问题、引擎、日期、语言/地区、真实回答/引用和 DOMASEED 是否被提及及如何描述。
- 若无法联网检索或无法取得真实 AI 回答，保留问题清单并标 BLOCKED，明确哪类访问缺失；不得生成模拟基线。
- 禁止把搜索命中等同于 AI 推荐或引用，禁止用旧基线冒充本次测量。
结果: BLOCKED；2026-11-04 仅整理10条英文（美国）及简体中文（中国大陆）精确问题。当前会话没有可调用的真实AI回答通道；可用网页检索不等同于AI回答，因此未执行引擎查询、未生成回答/引用/品牌提及结论。待真实AI访问渠道可用后重新测量。证据：night-shift/evidence/20261104-GEO-002-baseline.json。

## GEO-003
状态: TODO
目标: 根据 GEO-002 实测结果起草 1–2 个 FAQ 或页面。
验收标准:
- 仅当 GEO-002 状态 DONE 才能开始，否则标 BLOCKED 并注明依赖。
- 只写 night-shift/drafts/，说明对应的问题和证据；遵守教育游戏定位，不做学习效果承诺，不写创始人姓名/照片。
- 草稿不进入站点正文、不发布。
结果: 尚未运行。
