# DOMASEED GEO 夜班 v1

控制目录：`D:\AI-Mission-World\domaseed-site-night-shift`，保持在 `setup/night-shift-v1`。独立 nightly worktree：`D:\AI-Mission-World\domaseed-geo-night-YYYYMMDD`。不影响现有项目执行器。

## 首次安装（管理员 PowerShell，当前已登录用户）

已由本次搭建建立目录时不再 clone。新电脑依次运行：

```powershell
git clone --branch setup/night-shift-v1 https://github.com/CoffeeBreak520/domaseed-site.git D:\AI-Mission-World\domaseed-site-night-shift
Set-Location D:\AI-Mission-World\domaseed-site-night-shift
codex exec --help
codex --help
codex login status
powershell -NoProfile -ExecutionPolicy Bypass -File .\night-shift\run-night-shift.ps1 -OnlyTask GEO-001
Get-Content .\.git\night-shift\last-run.json
powershell -NoProfile -ExecutionPolicy Bypass -File .\night-shift\install-task.ps1
Get-ScheduledTask -TaskName DOMASEED-GEO-NightShift
```

安装器要求 GEO-001 实际 Codex 调用、任务 DONE、进程/结构化验证通过、报告提交推送、远端 SHA 一致。任何一项未通过都拒绝安装，不要绕过门槛。

## Codex Windows 沙盒不可用时

2026-11-04 实测：`setup refresh had errors` 的具体原因是 `codex-computer-use-swift` 占用 `VCRUNTIME140_1.dll`，导致沙盒 ACL 更新失败（Windows 错误 32）。这不是登录失效。保存其他工作后完整退出使用此运行时的 Codex 桌面应用，或重启 Windows 释放占用；不要自动结束其他项目进程。之后可在当前用户的管理员 PowerShell 中检查：

```powershell
Set-Location D:\AI-Mission-World\domaseed-site-night-shift
codex --disable plugins --disable apps --disable hooks -c 'windows.sandbox="elevated"' -s workspace-write
```

在交互式 Codex 中完成提示的 Windows 沙盒初始化和系统确认，退出。这里不能保证系统提示一定出现；若仍报相同错误，保留错误并检查 Codex 沙盒诊断，不要改成完全访问模式。不要尝试未经当前 `--help` 验证的 `sandbox setup` 命令。

已 BLOCKED 的 GEO-001 不会自动重试。修复环境后运行以下命令，显式记录创始人决定并重排该任务，再试跑。也可在 GitHub 最新 night 分支编辑队列；保留旧失败证据。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\night-shift\retry-blocked-task.ps1 -TaskId GEO-001 -Decision '已释放 DLL 占用，批准重新试跑 GEO-001。'
powershell -NoProfile -ExecutionPolicy Bypass -File .\night-shift\run-night-shift.ps1 -OnlyTask GEO-001
```若远端队列和本地干净，启动器会 fast-forward；发生并发修改则停止，不强制覆盖。

## 每晚与早上

- 每天北京时间 23:30，最多 5 次独立 Codex 调用，单次 45 分钟，整晚 4 小时（预留最后 3 分钟报告推送）。调度器另设 5 小时硬停止、唤醒和禁止并发。
- 电脑必须保持登录；可锁屏、可睡眠，但不能关机。唤醒还受 Windows 电源策略影响，Git/Codex 需要网络。不会修改其他计划任务。
- 默认 `gpt-6-luna`，不自动升级模型或改用付费 API。若不可用则报告失败。全局关闭插件/apps/hooks/multi_agent，保持 workspace-write、never approvals。
- 新晚站点代码取最新 main，但队列、创始人决定、报告、证据和草稿从最新前一晚远端 night 分支继承。框架代码取 setup 分支。已有当晚分支只续跑，绝不 reset。
- 报告：GitHub 切换到 `night/geo-YYYYMMDD` → `night-shift/reports/morning-YYYYMMDD.md`。日期为本轮开始的北京时间，即 23:30 所属日期；跨午夜不改日期。
- 本地报告路径见 `.git/night-shift/last-run.json` 的 reportPath。原始 logs 在 nightly worktree 的 `night-shift/logs/`，不提交。预检在 night 分支就绪前失败时，报告只能落到控制目录 logs，回执会说明远端未验证。
- 只保留一份当晚报告，多次启动追加至同一份。完成队列后停止调用模型。没有队列维护就不会凭空生成新任务。连续两次有记录夜班 BLOCKED 自动写入失败原因与所需决定；同晚重跑不累计。无 TODO 时只生成确定性报告，不关闭桌面或调用模型。
- 本仓库公开，Git 分支上的报告、证据和草稿也公开可读；不含个人信息/秘密。Git 推送不是上线网站；不改任何 Pages 设置。

## 卸载

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\night-shift\install-task.ps1 -Uninstall
# 等价命令：
Unregister-ScheduledTask -TaskName DOMASEED-GEO-NightShift -Confirm:$false
```

## 验证与限制

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\night-shift\tests\run-tests.ps1
```

自动检查是技术验证，不代表 GEO 增长成果。GEO-002 可标 PARTIAL-MANUAL，明确人工汇总与原始证据缺口；无真实渠道不重复尝试。GEO-003 仅依赖 GEO-001 DONE，可先起草并标注待 GEO-002 数据复核。站点源文件只读，改进只可起草在 drafts。
## 自动关闭桌面应用（新增）

每次夜班在领取任务及启动 codex exec 前，检测当前用户/会话的已核实 Codex 桌面程序和 Swift sidecar。正常退出最多等待60秒，仍存活再强制结束；CLI、沙盒服务及其他同名程序均排除。随后对已知版本的 VCRUNTIME140_1.dll 进行独占读/权限元数据句柄检查；该检查不写文件、不改 ACL。若无法确认释放，写晨报和占用信息、提交推送、跳过本晚，任务状态不变。结束后不重新打开应用。

新增回归测试：`powershell -NoProfile -File .\night-shift\tests\desktop-preflight-tests.ps1`。安装器另要求保留原流程成功回执，并验证真实应用开启→自动关闭→DLL释放→GEO-001完成→远端提交一致，且当前脚本哈希与该次证明一致。示例进程或模拟运行不能替代实际验收。

修正回归检查：`powershell -NoProfile -File night-shift/tests/task-reporting-tests.ps1`。当晚已存在的工作树会从已提交的 setup 分支刷新框架，不覆盖队列、证据或草稿。

2026-11-26追加：GEO-004–006为已授权的新交付；每日报告新增【本周需人工补测】，按北京时间周一开始的一周去重，记录在evidence/manual-reminder-week-YYYYMMDD.json。不新建重复提醒任务，不使用付费API。提醒仅写入报告，无外发通知。
