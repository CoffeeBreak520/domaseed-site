$ErrorActionPreference='Stop'
$framework=Split-Path -Parent $PSScriptRoot
. (Join-Path $framework 'NightShift.Common.ps1')
. (Join-Path $framework 'TaskReporting.ps1')
. (Join-Path $framework 'ValidateWorkerResult.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('geo-report-tests-'+[guid]::NewGuid().ToString('N'))
$passed=@()
function Assert([bool]$Condition,[string]$Why){if(-not $Condition){throw "FAILED: $Why"};$script:passed+=$Why}
try {
    $queue=Join-Path $temp 'night-shift/TASK_QUEUE.md'
    Write-Utf8 $queue "## GEO-001`n状态: DONE`n结果: audit`n## GEO-002`n状态: BLOCKED`n阻塞原因: no real answer channel`n已尝试: search is not an AI answer`n所需决定: preserve manual path; no API spending`n结果: no raw capture`n## GEO-003`n状态: DONE`n结果: draft awaiting measurement`n"
    $report=Join-Path $temp 'night-shift/reports/morning-20261126.md'
    Ensure-Report $report '20261126'
    Add-Report $report '今晚做了什么' '- original run: no output'
    $prior=Join-Path $temp 'night-shift/reports/morning-20261125.md'
    Ensure-Report $prior '20261125'
    Add-Report $prior '今晚做了什么' '| GEO-002 | BLOCKED |'
    $ev=Update-TaskReport $temp $report '20261126'
    $state=[IO.File]::ReadAllText((Join-Path $temp $ev)) | ConvertFrom-Json
    $item=@($state.tasks | Where-Object task -eq 'GEO-002')[0]
    Assert ($item.escalated -and $item.blockedNights -eq 2) 'Two recorded blocked nights escalate automatically'
    $raw=[IO.File]::ReadAllText($report)
    Assert ($raw.Contains('no real answer channel') -and $raw.Contains('search is not an AI answer') -and $raw.Contains('preserve manual path')) 'Report includes actual reason, attempt and required action'
    Update-TaskReport $temp $report '20261126' | Out-Null
    $state=[IO.File]::ReadAllText((Join-Path $temp $ev)) | ConvertFrom-Json
    Assert (@($state.tasks | Where-Object task -eq 'GEO-002')[0].blockedNights -eq 2) 'Same-night rerun does not increase blocked count'
    $raw=[IO.File]::ReadAllText($report)
    Assert ([regex]::Matches($raw,'<!-- geo-auto:blockers -->').Count -eq 1 -and $raw.Contains('original run: no output')) 'Reporting is idempotent and preserves earlier observations'
    Write-Utf8 $prior "## 今晚做了什么`nStartup only; state unknown`n"
    Update-TaskReport $temp $report '20261126' | Out-Null
    $state=[IO.File]::ReadAllText((Join-Path $temp $ev)) | ConvertFrom-Json
    Assert (-not @($state.tasks | Where-Object task -eq 'GEO-002')[0].escalated) 'Missing prior status never fabricates a blocked night'
    Set-QueueStatus $queue 'GEO-002' 'PARTIAL-MANUAL' 'Historical summary only; raw answer null'
    $tasks=@(Read-Queue $queue)
    Assert (@($tasks | Where-Object Status -eq 'PARTIAL-MANUAL').Count -eq 1 -and @($tasks | Where-Object Status -eq 'TODO').Count -eq 0) 'Manual partial is parseable and not automatically dispatched'
    Update-TaskReport $temp $report '20261126' | Out-Null
    $raw=[IO.File]::ReadAllText($report)
    Assert ($raw.Contains('PARTIAL-MANUAL') -and -not $raw.Contains('已升级：连续 2')) 'Manual status clears obsolete escalation but retains missing evidence notice'
    $result=Join-Path $temp 'result.json'
    Write-Utf8 $result '{"task_id":"GEO-002","status":"PARTIAL-MANUAL","summary":"raw missing","evidence":[]}'
    $denied=$false
    try{Read-ValidatedWorkerResult $result $temp 'GEO-002' 'PARTIAL-MANUAL' | Out-Null}catch{$denied=$true}
    Assert $denied 'Manual partial requires a real primary evidence file'
    Write-Utf8 $result ('{"task_id":"GEO-002","status":"PARTIAL-MANUAL","summary":"raw missing","evidence":["'+$ev+'"]}')
    Read-ValidatedWorkerResult $result $temp 'GEO-002' 'PARTIAL-MANUAL' | Out-Null
    Assert $true 'Manual evidence validates without promoting status to DONE'
    $launcher=[IO.File]::ReadAllText((Join-Path $framework 'run-night-shift.ps1'))
    Assert ($launcher.IndexOf('if (-not $first.Count)') -lt $launcher.IndexOf('$desktop = Close-CodexDesktop')) 'Empty queue is handled before desktop or model execution'
    $result=[ordered]@{at=[datetime]::UtcNow.ToString('o');passed=$passed.Count;checks=$passed}
    Write-Utf8 (Join-Path $framework 'evidence/task-reporting-tests-20261126.json') ($result | ConvertTo-Json -Depth 5)
    $result | ConvertTo-Json -Depth 5
} finally {Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue}
