[CmdletBinding(SupportsShouldProcess=$true)]
param([string]$RepoPath='',[switch]$Uninstall)
$ErrorActionPreference='Stop'
if (-not $RepoPath) { $RepoPath = Split-Path -Parent $PSScriptRoot }
. "$PSScriptRoot\NightShift.Common.ps1"
$name='DOMASEED-GEO-NightShift'
if ($Uninstall) {
    if ($PSCmdlet.ShouldProcess($name,'Unregister scheduled task')) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop
    }
    return
}
$RepoPath=[IO.Path]::GetFullPath($RepoPath)
if ((Get-TimeZone).Id -ne 'China Standard Time') { throw '23:30 means Beijing time. Windows timezone must be China Standard Time. No clock settings were changed.' }
$path=Join-Path $RepoPath '.git/night-shift/last-run.json'
if (-not (Test-Path $path)) { throw 'No actual manual-run receipt. Run -OnlyTask GEO-001 first. Nothing installed.' }
$r=[IO.File]::ReadAllText($path) | ConvertFrom-Json
if ($r.onlyTask -ne 'GEO-001' -or -not $r.codexInvoked -or $r.exitCode -ne 0 -or -not $r.remoteVerified -or $r.taskStatus -ne 'DONE') {
    throw 'GEO-001 end-to-end proof has not passed. Nothing installed; inspect last-run.json and morning report.'
}
# Both user-requested real trials must pass before this task may be registered.
$firstPath=Join-Path $RepoPath '.git/night-shift/acceptance-original.json'
if (-not (Test-Path $firstPath)) { throw 'Original manually-closed desktop trial proof missing. Nothing installed.' }
$first=[IO.File]::ReadAllText($firstPath) | ConvertFrom-Json
if ($first.onlyTask -ne 'GEO-001' -or -not $first.codexInvoked -or -not $first.remoteVerified -or $first.exitCode -ne 0 -or $first.taskStatus -ne 'DONE') { throw 'Original-flow trial did not pass.' }
if (-not ($r.PSObject.Properties.Name -contains 'desktopPreflight') -or -not $r.desktopPreflight -or -not $r.desktopPreflight.initiallyRunning -or -not $r.desktopPreflight.closedDesktop -or -not $r.desktopPreflight.released -or $r.desktopPreflight.method -notin @('normal','force')) {
    throw 'Real desktop-open shutdown trial has not passed. Nothing installed.'
}
if ($r.launcherSha256 -ne (Get-FileHash (Join-Path $PSScriptRoot 'run-night-shift.ps1')).Hash -or $r.desktopHelperSha256 -ne (Get-FileHash (Join-Path $PSScriptRoot 'DesktopPreflight.ps1')).Hash) { throw 'Framework changed since desktop-open proof. Rerun validation.' }
Invoke-Git $r.worktree @('merge-base','--is-ancestor',$first.remoteSha,$r.remoteSha) | Out-Null
if (-not (Test-Path $r.reportPath)) { throw 'Verified report no longer exists.' }
$remote=Invoke-Git $RepoPath @('ls-remote','origin',"refs/heads/$($r.branch)")
if (($remote -split '\s+')[0] -ne $r.remoteSha) { throw 'Remote branch changed since proof. Reverify before installation.' }
$head=Invoke-Git $r.worktree @('rev-parse','HEAD')
if ($head -ne $r.remoteSha -or (Invoke-Git $r.worktree @('status','--porcelain'))) { throw 'Manual-run checkout changed after proof.' }
if ((Invoke-Git $RepoPath @('branch','--show-current')) -ne 'setup/night-shift-v1') { throw 'Wrong control branch.' }
if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) { throw 'Task already exists. Inspect it; uninstall explicitly before replacement.' }
$user=[Security.Principal.WindowsIdentity]::GetCurrent().Name
$powershell=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$script=Join-Path $RepoPath 'night-shift/run-night-shift.ps1'
$arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + (Quote-Native $script) + ' -RepoPath ' + (Quote-Native $RepoPath)
$action=New-ScheduledTaskAction -Execute $powershell -Argument $arguments -WorkingDirectory $RepoPath
$trigger=New-ScheduledTaskTrigger -Daily -At '23:30'
$settings=New-ScheduledTaskSettingsSet -WakeToRun -ExecutionTimeLimit (New-TimeSpan -Hours 5) -MultipleInstances IgnoreNew -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal=New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
if ($PSCmdlet.ShouldProcess($name,"Install daily 23:30 Beijing as $user")) {
    Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'DOMASEED GEO: scoped night branch only; no publishing; proof gated.' | Out-Null
    $actual=Get-ScheduledTask -TaskName $name
    if (-not $actual.Settings.WakeToRun -or $actual.Settings.MultipleInstances -ne 'IgnoreNew' -or $actual.Settings.ExecutionTimeLimit -ne 'PT5H') { throw 'Registered task settings did not match requested configuration.' }
    Write-Output "Installed $name. User must remain logged in; machine may sleep, but cannot be powered off."
}