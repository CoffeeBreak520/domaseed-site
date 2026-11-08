$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'NightShift.Common.ps1')
$framework=Split-Path -Parent $PSScriptRoot
$temp=Join-Path ([IO.Path]::GetTempPath()) ('geo-night-tests-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp) | Out-Null
$passed=@()
function Assert([bool]$Condition,[string]$Why) { if (-not $Condition) { throw "FAILED: $Why" }; $script:passed+=$Why }
try {
    foreach ($f in Get-ChildItem $framework -Recurse -Filter '*.ps1') {
        $tokens=$null; $errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors)
        Assert (@($errors).Count -eq 0) ("PowerShell AST: "+$f.Name+': '+(($errors | ForEach-Object Message) -join '; '))
    }
    $queue=Join-Path $temp 'queue.md'
    $content="# Test`n`n## 创始人决定`nTODO in prose is not a task; preserve decision A`n`n## GEO-001`n状态: DONE`n结果: evidence`n`n## GEO-002`n状态: TODO`n结果: pending`n`n## GEO-003`n状态: BLOCKED`n结果: dependency`n"
    Write-Utf8 $queue $content
    $tasks=@(Read-Queue $queue)
    Assert ($tasks.Count -eq 3 -and @($tasks | Where-Object Status -eq TODO)[0].Id -eq 'GEO-002') 'Only first real TODO parsed; prose ignored'
    Set-QueueStatus $queue 'GEO-002' 'NEEDS_FOUNDER' 'Question A/B'
    $updated=[IO.File]::ReadAllText($queue)
    Assert ($updated.Contains('preserve decision A') -and $updated.Contains('状态: DONE') -and $updated.Contains('Question A/B')) 'Status update preserves founder decisions and other tasks'
    Assert (@((Read-Queue $queue) | Where-Object Status -eq TODO).Count -eq 0) 'No TODO means no work'
    $report=Join-Path $temp 'report.md'
    Ensure-Report $report '20261104'
    Add-Report $report '今晚做了什么' 'GEO-001 BLOCKED'
    Ensure-Report $report '20261105'
    Add-Report $report '失败与原因' 'sandbox error'
    $raw=[IO.File]::ReadAllText($report)
    Assert ($raw.Contains('GEO-001 BLOCKED') -and $raw.Contains('sandbox error') -and $raw.Contains('20261104')) 'Resume does not overwrite report or start date'
    $ps=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $r=Invoke-Bounded $ps @('-NoProfile','-Command','[Console]::Out.WriteLine("out"); [Console]::Error.WriteLine("err"); exit 7') $temp 10
    Assert ($r.ExitCode -eq 7 -and $r.Out.Contains('out') -and $r.Err.Contains('err')) 'Native exit code/stdout/stderr preserved without PS stderr exceptions'
    $r=Invoke-Bounded $ps @('-NoProfile','-Command','Start-Sleep -Seconds 30') $temp 1
    Assert ($r.TimedOut -and $r.ExitCode -eq 124) 'Timeout terminates native process'
    $repo=Join-Path $temp 'repo'
    [IO.Directory]::CreateDirectory($repo) | Out-Null
    Invoke-Git $repo @('init','-b','night/geo-20261104') | Out-Null
    Invoke-Git $repo @('config','user.name','NightShift Test') | Out-Null
    Invoke-Git $repo @('config','user.email','test@example.invalid') | Out-Null
    Write-Utf8 (Join-Path $repo 'index.html') 'original'
    Write-Utf8 (Join-Path $repo '.gitignore') '/night-shift/logs/'
    Invoke-Git $repo @('add','.') | Out-Null
    Invoke-Git $repo @('commit','-m','fixture') | Out-Null
    $base=Invoke-Git $repo @('rev-parse','HEAD')
    Write-Utf8 (Join-Path $repo 'index.html') 'changed'
    $denied=$false
    try { Assert-Scope $repo $base 'night/geo-20261104' } catch { $denied=$true }
    Assert $denied 'Forbidden website changes rejected before commit/push'
    # Only disposable fixture file is restored. Production runner never resets changes.
    Invoke-Git $repo @('restore','index.html') | Out-Null
    Write-Utf8 (Join-Path $repo 'night-shift/reports/x.md') 'test'
    Assert-Scope $repo $base 'night/geo-20261104'
    Assert $true 'Report changes allowed on night branch'
    $installer=Join-Path $framework 'install-task.ps1'
    $r=Invoke-Bounded $ps @('-NoProfile','-ExecutionPolicy','Bypass','-File',$installer,'-RepoPath',$repo,'-WhatIf') $temp 15
    Assert ($r.ExitCode -ne 0 -and ($r.Out+$r.Err).Contains('No actual manual-run receipt')) 'Installer rejects missing real trial proof even with WhatIf'
    $lockPath=Join-Path $temp 'exclusive.lock'
    $l=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $denied=$false
    try { $second=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); $second.Dispose() } catch { $denied=$true } finally { $l.Dispose() }
    Assert $denied 'Exclusive lock prevents second instance'
    $again=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); $again.Dispose()
    Assert $true 'Released lock file is reusable after process exit'
    $result=[ordered]@{at=[datetime]::UtcNow.ToString('o');passed=$passed.Count;checks=$passed;limitations=@('Live Codex trial required separately.','Future-day carry-over and reboot/wake not yet end-to-end observed.')}
    $out=Join-Path $framework 'evidence/setup-tests.json'
    Write-Utf8 $out ($result | ConvertTo-Json -Depth 5)
    Write-Output ($result | ConvertTo-Json -Depth 5)
} finally { Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue }
