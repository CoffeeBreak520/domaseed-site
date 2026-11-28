# GEO-006 结构化数据检查与建议

状态：检查和候选写法交付；未应用到官网。2026-11-26。
检查对象：当前 index.html，源码基线 0e55762555b763ce920c103ec9650a0342c2f31c。
可重现命令：powershell -NoProfile -File night-shift/inspect-schema.ps1 -Root <nightly-worktree>
机器证据：night-shift/evidence/20261126-GEO-006-schema-audit.json。源码SHA-256与逐项结果以证据为准。

## 实际检查

当前文件含一个JSON-LD块，图中为Organization、VideoGame、FAQPage。针对本文件执行了JSON解析、context检查、节点ID重复检查、游戏creator引用检查，以及可见FAQ与JSON-LD的逐题问答比对。
本检查不是完整JSON-LD扩展、Schema.org全量验证、Google Rich Results Test或收录验证；也没有取得AI回答。

## 已有项、可选缺失与建议

| 对象 | 当前情况 | 建议写法/处理 | 性质 |
|---|---|---|---|
| Organization | name=Optiverse；国家NZ；片段@id=#optiverse | 可统一为https://domaseed.com/#optiverse，保持全部引用对应 | 当前片段ID有效；绝对ID为可选一致性改进 |
| VideoGame | 已有名称、描述、genre、creator | 可增加@id=https://domaseed.com/#domaseed及url=https://domaseed.com/ | 可选身份改进，不是缺必填字段导致语法错误 |
| VideoGame.creator | 引用现有组织节点 | ID改为绝对形式时同步引用 | 引用完整性要求；当前引用是否通过见证据 |
| FAQPage | mainEntity包含现有可见FAQ | 可增加页面@id、url及与html lang一致的inLanguage=en | 可选页面描述；不能先添加未批准的中文路由 |
| Organization.url/sameAs/logo/legalName | 当前未填 | 只有核验存在且适用时再补；本候选不填 | 不创造组织官网、社交帐号、图片地址或法定全称 |
| 发行/商业字段 | 无评分、报价或商店支持信息 | 不增aggregateRating、offers、downloadUrl、gamePlatform或正式评级 | 避免把开发方向误写为发行事实 |
| FAQ语义与Google展示 | FAQPage仍是Schema.org类型 | 以准确描述FAQ为目的；不保证Google显示FAQ富结果 | Google更新记录说明该富结果自2026-05-07不再显示 |

## 候选文件

night-shift/drafts/schema-graph-candidate-20261126.json

该候选由当前图复制生成，仅补充稳定游戏/页面标识与已知页面URL、语言，并同步组织引用；保留现有FAQ原文，不改变站点。
候选保留当前原文并不代表对每个产品或隐私说法重新背书。GEO-004中的安全问答须先完成事实复核。若最终采用新FAQ，须连同可见文本与JSON-LD一起更新并重新检查，不能只部署候选JSON。

## 官方依据（2026-11-26核对）

1. https://schema.org/VideoGame
2. https://schema.org/FAQPage
3. https://developers.google.com/search/docs/appearance/structured-data/organization
4. https://developers.google.com/search/docs/appearance/structured-data/sd-policies
5. https://developers.google.com/search/updates

Google的Organization文档没有通用必填字段要求，建议按适用且可核实的信息填写。完整标记也不保证搜索展示；没有据此推断DOMASEED已收录或被AI采用。
