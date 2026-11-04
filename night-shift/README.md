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

若出现 `setup refresh had errors`，CLI 认证和沙盒初始化是两件事。先在当前用户的管理员 PowerShell 中启动：

```powershell
Set-Location D:\AI-Mission-World\domaseed-site-night-shift
codex --disable plugins --disable apps --disable hooks -c 'windows.sandbox="elevated"' -s workspace-write
```

在交互式 Codex 中完成提示的 Windows 沙盒初始化和系统确认，退出。这里不能保证系统提示一定出现；若仍报相同错误，保留错误并检查 Codex 沙盒诊断，不要改成完全访问模式。不要尝试未经当前 `--help` 验证的 `sandbox setup` 命令。

已 BLOCKED 的 GEO-001 不会自动重试。修复环境后在最新 night 分支的 TASK_QUEUE.md 把 GEO-001 改为 TODO 并提交（可以在 GitHub 编辑），再试跑上面的 `-OnlyTask GEO-001`。保留旧失败证据。若远端队列和本地干净，启动器会 fast-forward；发生并发修改则停止，不强制覆盖。

## 每晚与早上

- 每天北京时间 23:30，最多 5 次独立 Codex 调用，单次 45 分钟，整晚 4 小时（预留最后 3 分钟报告推送）。调度器另设 5 小时硬停止、唤醒和禁止并发。
- 电脑必须保持登录；可锁屏、可睡眠，但不能关机。唤醒还受 Windows 电源策略影响，Git/Codex 需要网络。不会修改其他计划任务。
- 默认 `gpt-6-luna`，不自动升级模型或改用付费 API。若不可用则报告失败。全局关闭插件/apps/hooks/multi_agent，保持 workspace-write、never approvals。
- 新晚站点代码取最新 main，但队列、创始人决定、报告、证据和草稿从最新前一晚远端 night 分支继承。框架代码取 setup 分支。已有当晚分支只续跑，绝不 reset。
- 报告：GitHub 切换到 `night/geo-YYYYMMDD` → `night-shift/reports/morning-YYYYMMDD.md`。日期为本轮开始的北京时间，即 23:30 所属日期；跨午夜不改日期。
- 本地报告路径见 `.git/night-shift/last-run.json` 的 reportPath。原始 logs 在 nightly worktree 的 `night-shift/logs/`，不提交。预检在 night 分支就绪前失败时，报告只能落到控制目录 logs，回执会说明远端未验证。
- 只保留一份当晚报告，多次启动追加至同一份。完成队列后停止调用模型。没有队列维护就不会凭空生成新任务。
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

自动检查是技术验证，不代表 GEO 增长成果。未实际取得 AI 回答的 GEO-002 必须 BLOCKED，GEO-003 不得越过其依赖。站点源文件只读，改进只可起草在 drafts。
