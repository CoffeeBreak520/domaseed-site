# GEO-018 — 发布与回滚操作单（待批准）

日期：2026-11-28  
范围：只读检查站点仓库与 `night-shift/drafts/site-candidate-20261128/`，为候选页面拟定路径、上线核验及恢复步骤。本操作单不是发布批准；候选目录仍不是部署源。

## 当前部署结构与限制

- 当前检出分支为 `night/geo-20261128`，仓库根目录是静态站点文件：`index.html`、`robots.txt`、`sitemap.xml`、`CNAME`；无 `.github/` 工作流、构建配置或仓库内 Pages 配置。Git remote 指向 `https://github.com/CoffeeBreak520/domaseed-site.git`，但本次没有核验托管平台 Pages 设置、生产构建记录或线上行为。因此只能确认源码为根目录静态文件，不能据此断言实际自动部署触发方式、域名绑定或回滚时延。
- 候选 README 明确说候选不能直接作为部署源；须在获得具体批准后另建隔离发布分支。候选 HTML 使用站点绝对路径和内嵌 CSS，无独立媒体文件。
- 建议获批后，将三份 HTML 分别映射到 `index.html`、`development/index.html`、`parents/choosing-adventure-thinking-games/index.html`。后两项为新增路径；首页路径会覆盖当前首页。`sitemap.xml` 需按实际批准页面 URL 更新。保留现有 `CNAME` 与 `robots.txt`；本候选未要求更改域名或爬虫策略，除非发布前发现明确必要变更并另行批准。
- 根候选保留现有创始人故事；三页候选均无表单、外部跟踪脚本或新增媒体。不要用较旧的生产首页覆盖根候选，也不要从其他研究库添加个人资料或未批准媒体。GEO-016 记录的键盘、窄屏及 200% 缩放实测尚未完成；GEO-017 建议修正的 Common Sense Media 链接标签尚未应用。两项应列入候选包审批/验收条件。

## 变更清单（仅在创始人批准具体包后）

| 候选源 | 拟议目标 | 变更 |
|---|---|---|
| `night-shift/drafts/site-candidate-20261128/index.html` | `index.html` | 替换当前首页；须批准保留故事文本及与当前 FAQ/schema 的逐项一致性。 |
| `night-shift/drafts/site-candidate-20261128/development/index.html` | `development/index.html` | 新增开发状态页。 |
| `night-shift/drafts/site-candidate-20261128/parents/choosing-adventure-thinking-games/index.html` | `parents/choosing-adventure-thinking-games/index.html` | 新增家长指南页；先按 GEO-017 编辑审核修正参考链接标签，批准后再纳入。 |
| 候选 `sitemap.xml`（仅批准后逐项比较） | `sitemap.xml` | 只纳入实际获批且可访问的规范 URL；不得提交索引或使用搜索引擎提交工具。 |

除上表路径外不改生产文件；不改 `CNAME`、`robots.txt`、DNS、Pages 设置、脚本或游戏工程。候选包的精确文件哈希/最终版本必须在批准时重新锁定；本次哈希只作本次只读快照，不能替代最终批准包清单。候选 README 提及既有 38 项与渲染记录，但那些不是本次复测结果。

## 批准后执行与验证

1. 创始人书面确认上述候选版本、所有目标路径、首页故事保留、GEO-017 标签修订及待补的 GEO-016 浏览器验收；记录批准日期与候选文件 SHA-256。范围变化时先重新批准。
2. 从本夜班分支创建隔离发布分支（不合并 `main`），仅复制批准表内文件。检查 `git status` 的差异仅限获批路径；运行 `git diff --check`，检查绝对链接、canonical、导航目标、表格与 JSON-LD/可见内容一致性；拒绝未批准个人数据、追踪、表单、媒体及其他生成物。
3. 在本地静态服务器预览根页及两条新路由，记录实际命令、时间、退出码和每条 HTTP 状态；验证 200、标题/规范 URL、导航往返、控制台错误、窄屏/200% 阅读及键盘焦点。浏览器验收未通过或缺证据时停止，不部署。
4. 仅在另行得到明确发布授权且确认托管端部署方式后，由获授权操作者推送隔离发布分支并按托管平台受控流程发布；本操作单本身不授权推送、合并或部署。发布后逐页请求三个规范 URL，确认状态、页面内容/链接、HTTPS 与 sitemap；核验真实部署版本和完成时间。不得主动提交索引。

## 回滚步骤

1. 发现关键页面不可用、错误内容、未批准数据/媒体、导航或 canonical 错误时，停止后续发布动作并记录 URL、时间、状态码与截图/响应证据。
2. 在同一隔离发布分支用一个明确的回滚提交恢复发布前 `index.html`、`robots.txt`、`sitemap.xml`、`CNAME` 的已记录版本，并移除本次新增的 `development/index.html` 与 `parents/choosing-adventure-thinking-games/index.html`（若它们在发布前不存在）。不要使用不受控的硬重置覆盖他人提交。
3. 由发布授权者按已核实的托管流程部署回滚提交；重新请求首页及两条新 URL，确认首页恢复到记录版本、新路径按既定托管行为返回预期状态、sitemap 不再列入撤回页。记录回滚提交、部署标识、命令、时间、退出码和结果。
4. 若 Pages 设置/部署触发方式未核实、回滚失败或恢复依赖改 DNS/仓库设置，暂停并交创始人/托管管理员决定；不得自行改设置。

## 尚待创始人批准的具体候选包

待决定：批准三页候选的确切版本与目标路径，特别是首页替换及故事保留、GEO-017 链接标签修订、GEO-016 实测补齐，以及 sitemap 是否按候选更新。选项：A）批准按本操作单完成编辑和实测后形成发布包，再另行审阅发布；B）暂缓发布，仅保留审核稿；C）修改页面/范围后重新提交审批。本任务未应用任何修订，也未发布。
