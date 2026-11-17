[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidatePattern('^GEO-\d+$')][string]$TaskId,
      [Parameter(Mandatory=$true)][string]$Decision,[string]$RepoPath='')
$ErrorActionPreference='Stop'
if (-not $RepoPath) { $RepoPath=Split-Path -Parent $PSScriptRoot }
. "$PSScriptRoot\NightShift.Common.ps1"
$r=[IO.File]::ReadAllText((Join-Path $RepoPath '.git/night-shift/last-run.json')) | ConvertFrom-Json
$root=$r.worktree; $branch=$r.branch
if ($branch -notmatch '^night/geo-\d{8}$' -or -not (Test-Path $root)) { throw 'Night worktree missing.' }
if ((Invoke-Git $root @('branch','--show-current')) -ne $branch) { throw 'Unexpected branch.' }
if (Invoke-Git $root @('status','--porcelain')) { throw 'Uncommitted changes preserved. Reconcile before recording decision.' }
Invoke-Git $root @('fetch','origin',$branch) | Out-Null
Invoke-Git $root @('merge','--ff-only','FETCH_HEAD') | Out-Null
$base=Invoke-Git $root @('rev-parse','HEAD')
$q=Join-Path $root 'night-shift/TASK_QUEUE.md'
$t=@((Read-Queue $q) | Where-Object Id -eq $TaskId)
if ($t.Count -ne 1 -or $t[0].Status -notin @('BLOCKED','NEEDS_FOUNDER')) { throw 'Only BLOCKED/NEEDS_FOUNDER may be explicitly requeued.' }
$raw=[IO.File]::ReadAllText($q)
$head=[regex]::Match($raw,'(?ms)^## 创始人决定\s*\r?\n.*?(?=^## |\z)')
if (-not $head.Success) { throw 'Founder decision section missing.' }
$decisionDate=[TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow,[TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')).ToString('yyyy-MM-dd HH:mm')
$clean=$Decision -replace '[\r\n|]',' '
$insert=$head.Value.TrimEnd()+"`n| $TaskId | $decisionDate | $clean |`n`n"
Write-Utf8 $q ($raw.Substring(0,$head.Index)+$insert+$raw.Substring($head.Index+$head.Length))
Set-QueueStatus $q $TaskId 'TODO' ('Founder explicitly authorized retry: '+$clean+'; earlier evidence retained.')
$sha=Commit-Night $root $base $branch ([datetime]::UtcNow.AddMinutes(3))
Invoke-Git $root @('push','origin',"HEAD:refs/heads/$branch") | Out-Null
$remote=Invoke-Git $root @('ls-remote','origin',"refs/heads/$branch")
if (($remote -split '\s+')[0] -ne $sha) { throw 'Decision push could not be verified.' }
Write-Output "Recorded decision; $TaskId is TODO on $branch. Run launcher separately."
