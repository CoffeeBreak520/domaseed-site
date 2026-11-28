# GEO-004 网站修复与核验清单

状态：清单交付完成；修复尚未执行。日期：2026-11-26。仅审核稿，不批准发布。
依据：GEO-001（night-shift/evidence/20261104-111510-GEO-001-site-audit.json）；现有 index.html、robots.txt、sitemap.xml；GEO-006 只读检查。站点代码基线：0e55762555b763ce920c103ec9650a0342c2f31c。

## 按影响排序

| 顺序 | 类型与影响 | 所在页面/文件 | 证据与当前判断 | 难度 | 建议处理与验收 |
|---|---|---|---|---|---|
| P1-01 | 事实复核：网站安全问答用语宽泛 | 首页“Is this site safe for my family?”；index.html 的可见FAQ及FAQPage | 该问答声明不收集儿童信息；仅靠HTML无法验证托管日志、第三方数据流或未来游戏政策。不是已确认违规 | 中 | 分开写当前网站实际行为、未发行游戏的状态和未来待确定政策；独立核验处理行为后再批准。可见问答与JSON-LD一致，不新增无证据的安全保证 |
| P1-02 | 身份语义改进：游戏节点缺稳定标识及网址 | index.html 的 VideoGame | 现有JSON-LD可解析；游戏节点有名称、描述、creator，但缺 @id/url。属于可选改进，不是语法错误 | 低 | 审阅 drafts/schema-graph-candidate-20261126.json 中绝对标识及官网URL；逐项核对creator引用；不伪造sameAs、评分或应用商店信息 |
| P1-03 | 发布前事实一致性 | 首页与所有新草稿 | 现有官网描述未发行、早期设计关注10–13岁、手机优先；没有最终评级或商店支持说明 | 中 | 审核草稿中的功能、设计方向、可用性；每项有证据再上线，发布后再建立新人工测量，避免用旧汇总冒充新基线 |
| P2-01 | 搜索功能预期纠正 | FAQPage 及GEO内部验收 | Google官方更新记录：FAQ富结果自2026-05-07起不再显示；Schema.org仍有FAQPage类型 | 低 | 不以获得FAQ富结果作为验收；保留准确的语义和可见文本对应关系。是否保留标记与是否有搜索特效分开判断 |
| P2-02 | sitemap日期待核对 | sitemap.xml 与 index.html footer | sitemap lastmod为2026-10-22，页面标记更新为2026-11-05。日期不同需要核实，不直接判成故障 | 低 | 依据真实有意义内容变更更新时间，不能为显新而每天改；更新获批后核对部署内容与sitemap，提交收录检查另做 |
| P2-03 | 对外联系入口未见 | 首页footer | 当前footer显示Optiverse；本源码未见独立公开业务联系入口。这是运营与信任改进建议，不作法律结论 | 中 | 只使用确认可公开的项目渠道；本任务不采用私人联系方式，不建表单、不发邮件 |
| P2-04 | 语言覆盖待决定 | 首页 lang=en；无中文公开页 | GEO-001指出无中文页，当前有中文审核草稿；英文市场主目标不自动推出中文上线要求 | 中 | 需要创始人决定是否服务中文家长。未决定前保留草稿，不建 /zh/。若批准再统一URL、可见语言、canonical、hreflang和FAQ对应 |
| P3-01 | 旧外部请求未验证 | 首页canonical → https://domaseed.com/ | GEO-001当次请求失败仅代表当时未验证；不能推断今天域名失效。此次不宣称收录情况 | 低 | 在可用网络单独只读检查HTTP状态、重定向与证书，保存时间证据；索引与AI推荐须另测 |

## 已有检查结果不应重做成“缺失”

GEO-001已检查到title、description、canonical、可解析JSON-LD，以及本地静态预览HTTP 200和内部链接检查。该证据是11月4日的历史检查，不是11月26日线上验收。
当前schema语法/引用/FAQ一致性结果以 GEO-006 的新证据为准。没有“未查到就是失败”的推断。

## 发布次序与边界

先审产品事实与网站数据处理表述，再决定采用哪些FAQ及schema候选。三篇扩展稿适合择要合并进家长FAQ；不建议仅为增加页面数量把相似问答拆成大量薄页面。
清单、草稿和候选JSON均未写入网站正文。没有改DNS、Pages、robots、sitemap，没有付费API或对外发送。

## 官方依据

- https://developers.google.com/search/docs/appearance/structured-data/organization （可选且适用的组织字段）
- https://developers.google.com/search/docs/appearance/structured-data/sd-policies （准确表达可见内容，不保证搜索展示）
- https://developers.google.com/search/updates （FAQ富结果停用记录；2026-11-26核对）
