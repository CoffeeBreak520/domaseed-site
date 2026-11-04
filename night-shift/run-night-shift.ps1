[CmdletBinding()]
param(
    [string]$RepoPath = '',
    [ValidatePattern('^GEO-\d+$')][string]$OnlyTask,
    [ValidateRange(1,5)][int]$MaxIterations=5,
    [ValidateRange(1,2700)][int]$TaskTimeoutSeconds=2700,
    [ValidateRange(60,14400)][int]$NightTimeoutSeconds=14400,
    [string]$Model='gpt-6-luna'
)
$ErrorActionPreference='Stop'
if (-not $RepoPath) { $RepoPath = Split-Path -Parent $PSScriptRoot }
. "$PSScriptRoot\NightShift.Common.ps1"
. "$PSScriptRoot\ValidateWorkerResult.ps1"
. "$PSScriptRoot\DesktopPreflight.ps1"
$started = [datetime]::UtcNow
$deadline = $started.AddSeconds($NightTimeoutSeconds)
$day = [TimeZoneInfo]::ConvertTimeFromUtc($started,[TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')).ToString('yyyyMMdd')
$branch = "night/geo-$day"
$reportRel = "night-shift/reports/morning-$day.md"
$control = [IO.Path]::GetFullPath($RepoPath)
$root = $null; $baseline = $null; $lock = $null; $report = $null; $taskId=$null; $queue=$null
$invoked = $false; $allValid = $true; $remoteVerified = $false; $exitCode=1; $selectedStatus=$null; $unsafe=$false; $desktop=$null; $skipForDll=$false
$receipt = [ordered]@{ date=$day; started=$started.ToString('o'); onlyTask=$OnlyTask; branch=$branch; codexInvoked=$false; remoteVerified=$false; exitCode=1; taskStatus=$null }
$stateDir = Join-Path $control '.git/night-shift'
$fallback = Join-Path $control "night-shift/logs/$day"
[IO.Directory]::CreateDirectory($fallback) | Out-Null
try {
    if (-not (Test-Path (Join-Path $control '.git') -PathType Container)) { throw 'RepoPath must be the dedicated control clone, not a worktree.' }
    [IO.Directory]::CreateDirectory($stateDir) | Out-Null
    $lock = [IO.File]::Open((Join-Path $stateDir 'run.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    if ((Invoke-Git $control @('remote','get-url','origin') $deadline) -notmatch '^https://github\.com/CoffeeBreak520/domaseed-site(?:\.git)?$') { throw 'Unexpected repository origin.' }
    if ((Invoke-Git $control @('branch','--show-current') $deadline) -ne 'setup/night-shift-v1') { throw 'Control clone must remain on setup/night-shift-v1.' }
    if (Invoke-Git $control @('status','--porcelain') $deadline) { throw 'Control clone has uncommitted changes; preserved.' }
    Invoke-Git $control @('fetch','origin','--prune') $deadline | Out-Null
    Invoke-Git $control @('merge','--ff-only','origin/setup/night-shift-v1') $deadline | Out-Null
    # Night worktrees are siblings. The control clone is never switched to main/night.
    $root = Join-Path (Split-Path -Parent $control) "domaseed-geo-night-$day"
    $localRefs = Invoke-Git $control @('for-each-ref','--format=%(refname:short)','refs/heads/night/geo-*') $deadline
    $remoteRefs = Invoke-Git $control @('for-each-ref','--format=%(refname:short)','refs/remotes/origin/night/geo-*') $deadline
    $isLocal = @($localRefs -split '\r?\n') -contains $branch
    $isRemote = @($remoteRefs -split '\r?\n') -contains "origin/$branch"
    $newNight = -not ($isLocal -or $isRemote)
    if (-not (Test-Path $root)) {
        if ($isLocal) { Invoke-Git $control @('worktree','add',$root,$branch) $deadline | Out-Null }
        elseif ($isRemote) { Invoke-Git $control @('worktree','add','-b',$branch,$root,"origin/$branch") $deadline | Out-Null }
        else { Invoke-Git $control @('worktree','add','-b',$branch,$root,'origin/main') $deadline | Out-Null }
    } elseif ($newNight) { throw 'Night directory already exists without matching branch; not overwriting.' }
    if ((Invoke-Git $root @('branch','--show-current') $deadline) -ne $branch) { throw 'Existing directory belongs to another branch.' }
    if (-not $newNight) {
        if (Invoke-Git $root @('status','--porcelain') $deadline) { throw 'Night worktree has uncommitted changes; manual recovery needed, no reset/stash.' }
        if ($isRemote) { Invoke-Git $root @('merge','--ff-only',"origin/$branch") $deadline | Out-Null }
    }
    # Compare all site paths against this immutable baseline, including committed worker changes.
    $baseline = if ($newNight) { Invoke-Git $root @('rev-parse','origin/main') $deadline } else {
        Invoke-Git $root @('merge-base','HEAD','origin/main') $deadline
    }
    if ($newNight) {
        # Framework from reviewed setup branch. Copy tracked files only, never local logs.
        $files = (Invoke-Git $control @('ls-files','night-shift') $deadline) -split '\r?\n'
        foreach ($f in $files) {
            if (-not $f) { continue }
            $dest = Join-Path $root $f
            [IO.Directory]::CreateDirectory((Split-Path -Parent $dest)) | Out-Null
            [IO.File]::Copy((Join-Path $control $f),$dest,$false)
        }
        # Carry only durable state, not old website source or unreviewed controller scripts.
        $previous = @($remoteRefs -split '\r?\n' | Where-Object { $_ -match '^origin/night/geo-\d{8}$' -and $_ -lt "origin/$branch" } | Sort-Object -Descending | Select-Object -First 1)
        if ($previous.Count) {
            foreach ($p in @('night-shift/TASK_QUEUE.md','night-shift/reports','night-shift/evidence','night-shift/drafts')) {
                if (Invoke-Git $control @('ls-tree','--name-only',$previous[0],'--',$p) $deadline) {
                    Invoke-Git $root @('restore',"--source=$($previous[0])",'--staged','--worktree','--',$p) $deadline | Out-Null
                }
            }
        }
        $ignore = Join-Path $root '.gitignore'
        $oldIgnore = if (Test-Path $ignore) { [IO.File]::ReadAllText($ignore) } else { '' }
        if ($oldIgnore -notmatch '(?m)^/night-shift/logs/\s*$') { Write-Utf8 $ignore ($oldIgnore.TrimEnd() + "`n/night-shift/logs/`n") }
    }
    $report = Join-Path $root $reportRel
    Ensure-Report $report $day
    $logDir = Join-Path $root "night-shift/logs/$day/$($started.ToString('HHmmss'))"
    [IO.Directory]::CreateDirectory($logDir) | Out-Null
    Add-Report $report '今晚做了什么' "- 启动：$($started.ToString('o'))；分支 $branch；站点只读；当日基线 $baseline。"
    # Host preflight occurs before task claim and before any codex exec. Failure preserves TODO.
    $desktop = Close-CodexDesktop -GraceSeconds 60 -Deadline $deadline.AddSeconds(-180)
    foreach ($collection in @('initialProcesses','remainingProcesses','lockOwners','dllChecks','initialDllChecks')) {
        foreach ($entry in @($desktop.$collection)) {
            if ($entry.PSObject.Properties.Name -contains 'path' -and $entry.path) {
                $entry.path=$entry.path.Replace($env:USERPROFILE,'%USERPROFILE%')
            }
        }
    }
    $desktopRel="night-shift/evidence/$day-$($started.ToString('HHmmss'))-desktop-preflight.json"
    Write-Utf8 (Join-Path $root $desktopRel) ($desktop | ConvertTo-Json -Depth 10)
    $modeText=if($desktop.method -eq 'force'){'强制'}elseif($desktop.method -eq 'normal'){'正常'}else{'未发现桌面进程'}
    Add-Report $report '今晚做了什么' "- 桌面预检：起始 $($desktop.started)，结束 $($desktop.finished)；发现应用=$($desktop.initiallyRunning)，已关闭=$($desktop.closedDesktop)，方式=$modeText；DLL释放验证=$($desktop.released)。证据：$desktopRel。"
    if (-not $desktop.released) {
        $skipForDll=$true
        $ownerText=(@($desktop.lockOwners | ForEach-Object { "$($_.name)(PID=$($_.pid))" }) -join ', ')
        if (-not $ownerText) { $ownerText='未能定位占用进程；探测错误码见证据' }
        $reason=if($desktop.missingDll){'未找到预期运行时 DLL，无法确认释放状态，未执行任务'}else{'DLL 仍被占用，未执行任务'}
        Add-Report $report '失败与原因' "- $reason；占用信息：$ownerText；证据：$desktopRel。任务状态保留，未调用 Codex。"
        throw $reason
    }
    $queue = Join-Path $root 'night-shift/TASK_QUEUE.md'
    $initialTasks = @(Read-Queue $queue)
    $first = @($initialTasks | Where-Object Status -eq 'TODO' | Select-Object -First 1)
    if ($OnlyTask -and (-not $first.Count -or $first[0].Id -ne $OnlyTask)) { throw "OnlyTask must equal first TODO; no task dispatched. Requested $OnlyTask" }
    $taskId = if ($first.Count) { $first[0].Id } else { $null }
    # Protect executable/rule files against model edits; drafts/queue/reports/evidence are writable.
    $protected = @{}
    foreach ($f in @(Get-ChildItem (Join-Path $root 'night-shift') -File)) {
        if ($f.Name -ne 'TASK_QUEUE.md') { $protected[$f.FullName] = (Get-FileHash $f.FullName -Algorithm SHA256).Hash }
    }
    $protected[(Join-Path $root '.gitignore')] = (Get-FileHash (Join-Path $root '.gitignore') -Algorithm SHA256).Hash
    $codexShim = Get-Command codex -ErrorAction Stop
    $npmRoot = Split-Path -Parent $codexShim.Source
    $codex = Join-Path $npmRoot 'node_modules/@openai/codex/node_modules/@openai/codex-win32-x64/vendor/x86_64-pc-windows-msvc/bin/codex.exe'
    if (-not (Test-Path $codex)) {
        $native = Get-Command codex.exe -ErrorAction SilentlyContinue
        if (-not $native) { throw 'Native codex.exe unavailable; refusing to Start-Process a .ps1 shim.' }
        $codex = $native.Source
    }
    $execHelp = Invoke-Bounded $codex @('exec','--help') $root 30 -Deadline $deadline
    $globalHelp = Invoke-Bounded $codex @('--help') $root 30 -Deadline $deadline
    if ($execHelp.ExitCode -ne 0 -or $globalHelp.ExitCode -ne 0) { throw 'codex help preflight failed.' }
    foreach ($flag in @('--sandbox','workspace-write','--cd','--json','--output-last-message','--ignore-user-config','--output-schema')) {
        if (-not $execHelp.Out.Contains($flag)) { throw "Unsupported Codex exec capability: $flag" }
    }
    foreach ($flag in @('--ask-for-approval','never','--no-daemon','--disable')) {
        if (-not $globalHelp.Out.Contains($flag)) { throw "Unsupported Codex global capability: $flag" }
    }
    Write-Utf8 (Join-Path $logDir 'exec-help.txt') $execHelp.Out
    Write-Utf8 (Join-Path $logDir 'global-help.txt') $globalHelp.Out
    for ($i=1; $i -le $MaxIterations; $i++) {
        if ([datetime]::UtcNow -ge $deadline.AddSeconds(-180)) { throw 'Night budget exhausted; 180 seconds reserved for final report and push.' }
        $tasks = @(Read-Queue $queue)
        $todo = @($tasks | Where-Object Status -eq 'TODO' | Select-Object -First 1)
        if (-not $todo.Count) { break }
        $taskId = $todo[0].Id
        if ($OnlyTask -and $taskId -ne $OnlyTask) { break }
        # Fetch before claim; never overwrite local report/queue edits with remote changes.
        if ($isRemote) {
            Invoke-Git $root @('fetch','origin',$branch) $deadline | Out-Null
            $remoteNow = Invoke-Git $root @('rev-parse','FETCH_HEAD') $deadline
            $localNow = Invoke-Git $root @('rev-parse','HEAD') $deadline
            if ($remoteNow -ne $localNow) { throw 'Concurrent remote changes detected. Preserve local state; reconcile before retry.' }
        }
        $last = Join-Path $logDir "$i-$taskId-result.json"
        $prompt = "读 night-shift/NIGHT_SHIFT.md 和 night-shift/TASK_QUEUE.md，执行下一个 TODO 任务，按规则结束。`n本次只能领 $taskId，分支 $branch，报告 $reportRel。站点只读，只可写 night-shift 的队列、报告、证据、草稿；不得改系统脚本。不能用自生成回答冒充AI搜索实测。保持沙盒、不请求审批。结束输出规则指定JSON。"
        Write-Utf8 (Join-Path $logDir "$i-prompt.txt") $prompt
        $argsList = @('--no-daemon','--disable','plugins','--disable','apps','--disable','hooks','--disable','multi_agent','-a','never')
        if ($taskId -eq 'GEO-002') {
            if (-not $globalHelp.Out.Contains('--search')) { throw 'Live search flag unavailable.' }
            $argsList += '--search'
        }
        $argsList += @('exec','--ignore-user-config','-c','windows.sandbox="elevated"','-s','workspace-write','-m',$Model,'-C',$root,'--json','--output-schema',(Join-Path $root 'night-shift/result.schema.json'),'-o',$last,'-')
        $invoked = $true
        $r = Invoke-Bounded -Exe $codex -Arguments $argsList -Cwd $root -Seconds $TaskTimeoutSeconds -Deadline $deadline.AddSeconds(-150) -InputText $prompt -LogPrefix (Join-Path $logDir "$i-$taskId")
        foreach ($p in $protected.Keys) {
            if (-not (Test-Path $p) -or (Get-FileHash $p -Algorithm SHA256).Hash -ne $protected[$p]) { $unsafe=$true; throw 'Protected framework file changed; refusing commit/push.' }
        }
        Assert-Scope $root $baseline $branch
        $afterTasks = @(Read-Queue $queue)
        $after = @($afterTasks | Where-Object Id -eq $taskId)[0]
        foreach ($t in $tasks) {
            $other = @($afterTasks | Where-Object Id -eq $t.Id)
            if ($t.Id -ne $taskId -and ($other.Count -ne 1 -or $other[0].Status -ne $t.Status)) { $unsafe=$true; throw 'Worker changed another task status; refusing to persist.' }
        }
        $valid=$true; $issue=''
        try {
            if ($r.ExitCode -ne 0) { throw "Codex process exit $($r.ExitCode); timeout=$($r.TimedOut)." }
            $answer = Read-ValidatedWorkerResult -ResultPath $last -Root $root -TaskId $taskId -QueueStatus $after.Status
        } catch { $valid=$false; $issue=$_.Exception.Message }
        if (-not $valid) {
            $allValid=$false
            if ($r.Err -match 'setup refresh had errors') { $issue='Windows sandbox failed before command startup: setup refresh had errors.' }
            elseif ($r.Err -match 'read-only filesystem|only filesystem reads') { $issue='Codex effective environment is read-only; workspace-write execution unavailable.' }
            $evRel="night-shift/evidence/$day-$($started.ToString('HHmmss'))-$taskId-launcher-$i.json"
            Write-Utf8 (Join-Path $root $evRel) (([ordered]@{task=$taskId;at=[datetime]::UtcNow.ToString('o');status='BLOCKED';processExit=$r.ExitCode;timeout=$r.TimedOut;reason=$issue;rawLogs='night-shift/logs (local, ignored)'; verifiedCompletion=$false} | ConvertTo-Json))
            Set-QueueStatus $queue $taskId 'BLOCKED' "$issue Evidence: $evRel"
            Add-Report $report '失败与原因' "- $taskId：$issue；证据：$evRel。没有把本次任务报为完成。"
            if ($issue -match 'sandbox|read-only') {
                Add-Report $report '待我决定' '- P1：本地 Codex 工作区沙盒不可用。A（推荐）：当前用户在管理员 PowerShell 中完成 Codex Windows 沙盒初始化后重试；B：保持夜班未安装。不要关闭沙盒或使用完全访问模式。'
            }
        }
        $selectedStatus = @((Read-Queue $queue) | Where-Object Id -eq $taskId)[0].Status
        Add-Report $report '今晚做了什么' "- $taskId：$selectedStatus；Codex 进程退出码 $($r.ExitCode)；结构化结果验证 $valid。具体结论与证据见 TASK_QUEUE.md 该项及 evidence。"
        $changedPaths = @((Invoke-Git $root @('diff','--name-only',$baseline) $deadline) -split '\r?\n') + @((Invoke-Git $root @('ls-files','--others','--exclude-standard') $deadline) -split '\r?\n')
        Add-Report $report '改动清单' "- 第 $i 次会话：$(($changedPaths | Where-Object { $_ } | Sort-Object -Unique) -join ', ')。"
        $sha = Commit-Night $root $baseline $branch $deadline
        Invoke-Git $root @('push','origin',"HEAD:refs/heads/$branch") $deadline | Out-Null
        $isRemote=$true
        if ($OnlyTask) { break }
    }
    $exitCode = if ($allValid) { 0 } else { 2 }
} catch {
    $exitCode=1
    $failure=$_.Exception.Message
    Write-Utf8 (Join-Path $fallback 'failure.txt') $failure
    if (-not $skipForDll -and -not $unsafe -and $taskId -and $queue -and (Test-Path $queue)) {
        try {
            $current=@((Read-Queue $queue) | Where-Object Id -eq $taskId)[0]
            if ($current.Status -eq 'TODO') {
                $startupEvidence="night-shift/evidence/$day-$taskId-preflight.json"
                Write-Utf8 (Join-Path $root $startupEvidence) ((@{task=$taskId;status='BLOCKED';reason='Launcher/preflight failed; see local ignored logs for diagnostics.';at=[datetime]::UtcNow.ToString('o')} | ConvertTo-Json))
                Set-QueueStatus $queue $taskId 'BLOCKED' "Launcher/preflight failed. Evidence: $startupEvidence"
                $selectedStatus='BLOCKED'
            }
        } catch { }
    }
    if ($report -and (Test-Path $report)) { Add-Report $report '失败与原因' ("- 启动器失败：" + $failure) }
    else {
        $report=Join-Path $fallback "morning-$day.md"
        Ensure-Report $report $day
        Add-Report $report '失败与原因' ("- 预检失败：" + $failure + '。尚未获得可安全写入的 night 分支；此报告只保存在本地 logs。')
    }
} finally {
    if ($lock) {
        try {
            if (-not $unsafe -and $root -and $baseline -and $report -and $report.StartsWith($root) -and [datetime]::UtcNow -lt $deadline.AddSeconds(-20)) {
                $snapshot = "| 任务 | 当前状态 |`n|---|---|`n" + (((Read-Queue (Join-Path $root 'night-shift/TASK_QUEUE.md')) | ForEach-Object { "| $($_.Id) | $($_.Status) |" }) -join "`n")
                Add-Report $report '今晚做了什么' $snapshot
                $sha = Commit-Night $root $baseline $branch $deadline
                Invoke-Git $root @('push','origin',"HEAD:refs/heads/$branch") $deadline | Out-Null
                $remoteLine = Invoke-Git $root @('ls-remote','origin',"refs/heads/$branch") $deadline
                if (($remoteLine -split '\s+')[0] -ne $sha) { throw 'Remote SHA verification failed.' }
                if (Invoke-Git $root @('status','--porcelain') $deadline) { throw 'Night worktree not clean after final push.' }
                $remoteVerified=$true
                $receipt['remoteSha']=$sha
            }
        } catch {
            $exitCode=3
            $pushFailure=$_.Exception.Message
            Write-Utf8 (Join-Path $fallback 'push-failure.txt') $pushFailure
            if ($report -and (Test-Path $report)) {
                Add-Report $report '失败与原因' "- 最终提交/推送验证失败：$pushFailure。需要检查本地报告；未声称远端已收到。"
                try { if ([datetime]::UtcNow -lt $deadline.AddSeconds(-5)) { Commit-Night $root $baseline $branch $deadline | Out-Null } } catch { }
            }
        }
        if (-not $remoteVerified -and $exitCode -eq 0) { $exitCode=3 }
        $receipt['desktopPreflight']=$desktop
        $receipt['launcherSha256']=(Get-FileHash (Join-Path $control 'night-shift/run-night-shift.ps1') -Algorithm SHA256).Hash
        $receipt['desktopHelperSha256']=(Get-FileHash (Join-Path $control 'night-shift/DesktopPreflight.ps1') -Algorithm SHA256).Hash
        $receipt['codexInvoked']=$invoked
        $receipt['remoteVerified']=$remoteVerified
        $receipt['exitCode']=$exitCode
        $receipt['taskStatus']=$selectedStatus
        $receipt['reportPath']=$report
        $receipt['worktree']=$root
        $receipt['finished']=[datetime]::UtcNow.ToString('o')
        Write-Utf8 (Join-Path $stateDir 'last-run.json') ($receipt | ConvertTo-Json -Depth 12)
        $lock.Dispose()
    }
}
Write-Output ($receipt | ConvertTo-Json -Depth 12)
exit $exitCode