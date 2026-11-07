Set-StrictMode -Version 2

function Write-Utf8([string]$Path, [string]$Text) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}
function Quote-Native([string]$Value) {
    if ($Value -notmatch '[\s"]' -and $Value.Length) { return $Value }
    return '"' + ([regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
}
function Invoke-Bounded {
    param([string]$Exe, [string[]]$Arguments, [string]$Cwd, [int]$Seconds=120,
          [string]$InputText, [string]$LogPrefix, [datetime]$Deadline=[datetime]::MaxValue)
    $remaining = [Math]::Floor(($Deadline - [datetime]::UtcNow).TotalSeconds)
    $limit = [int][Math]::Min([double]$Seconds, [double]$remaining)
    if ($limit -le 0) { throw 'Night wall-clock deadline reached.' }
    $si = New-Object Diagnostics.ProcessStartInfo
    $si.FileName = $Exe
    $si.Arguments = (($Arguments | ForEach-Object { Quote-Native $_ }) -join ' ')
    $si.WorkingDirectory = $Cwd
    $si.UseShellExecute = $false
    $si.CreateNoWindow = $true
    $si.RedirectStandardOutput = $true
    $si.RedirectStandardError = $true
    $si.RedirectStandardInput = $true
    $si.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $si.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $si.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $si.EnvironmentVariables['GCM_INTERACTIVE'] = 'Never'
    $p = New-Object Diagnostics.Process
    $p.StartInfo = $si
    $timedOut = $false
    try {
        [void]$p.Start()
        $stdout = $p.StandardOutput.ReadToEndAsync()
        $stderr = $p.StandardError.ReadToEndAsync()
        if ($InputText) {
            $bytes = [Text.Encoding]::UTF8.GetBytes($InputText + "`n")
            $p.StandardInput.BaseStream.Write($bytes,0,$bytes.Length)
            $p.StandardInput.BaseStream.Flush()
        }
        $p.StandardInput.Close()
        if (-not $p.WaitForExit($limit * 1000)) {
            $timedOut = $true
            & "$env:SystemRoot\System32\taskkill.exe" /PID $p.Id /T /F 2>&1 | Out-Null
            [void]$p.WaitForExit(5000)
        }
        $out = if ($stdout.Wait(5000)) { $stdout.Result } else { '[stdout drain timed out]' }
        $err = if ($stderr.Wait(5000)) { $stderr.Result } else { '[stderr drain timed out]' }
        $code = if ($timedOut) { 124 } elseif ($p.HasExited) { $p.ExitCode } else { 125 }
        if ($LogPrefix) {
            Write-Utf8 ($LogPrefix + '.stdout.log') $out
            Write-Utf8 ($LogPrefix + '.stderr.log') $err
        }
        return [pscustomobject]@{ExitCode=$code; Out=$out; Err=$err; TimedOut=$timedOut}
    } finally { $p.Dispose() }
}
function Invoke-Git {
    param([string]$Cwd, [string[]]$Arguments, [datetime]$Deadline=[datetime]::MaxValue)
    $r = Invoke-Bounded -Exe (Get-Command git.exe -ErrorAction Stop).Source -Arguments $Arguments -Cwd $Cwd -Seconds 90 -Deadline $Deadline
    if ($r.ExitCode -ne 0) { throw "git $($Arguments -join ' ') failed ($($r.ExitCode)): $($r.Err.Trim()) $($r.Out.Trim())" }
    return $r.Out.Trim()
}
function Read-Queue([string]$Path) {
    $raw = [IO.File]::ReadAllText($Path)
    $items = @()
    foreach ($m in [regex]::Matches($raw, '(?ms)^## (GEO-\d+)\s*\r?\n(.*?)(?=^## |\z)')) {
        $s = [regex]::Match($m.Groups[2].Value, '(?m)^状态: (TODO|DONE|BLOCKED|NEEDS_FOUNDER)\s*$')
        if (-not $s.Success) { throw "Invalid status for $($m.Groups[1].Value)" }
        $items += [pscustomobject]@{Id=$m.Groups[1].Value; Status=$s.Groups[1].Value}
    }
    if (-not $items.Count) { throw 'No parseable queue tasks.' }
    if (@($items.Id | Select-Object -Unique).Count -ne $items.Count) { throw 'Duplicate task IDs.' }
    return $items
}
function Set-QueueStatus([string]$Path,[string]$Id,[string]$Status,[string]$Result) {
    if ($Status -notin @('TODO','DONE','BLOCKED','NEEDS_FOUNDER')) { throw 'Invalid state' }
    $raw = [IO.File]::ReadAllText($Path)
    $pat = '(?ms)^## ' + [regex]::Escape($Id) + '\s*\r?\n.*?(?=^## |\z)'
    $m = [regex]::Match($raw,$pat)
    if (-not $m.Success) { throw "Task missing: $Id" }
    $block = [regex]::Replace($m.Value, '(?m)^状态: .*$', "状态: $Status")
    $block = [regex]::Replace($block, '(?m)^结果: .*$', ('结果: ' + ($Result -replace '[\r\n]+',' ')))
    Write-Utf8 $Path ($raw.Substring(0,$m.Index) + $block + $raw.Substring($m.Index+$m.Length))
}
function Ensure-Report([string]$Path,[string]$Date) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Utf8 $Path "# DOMASEED GEO 晨报 — $Date`n`n## 今晚做了什么`n`n## 改动清单`n`n## 待我决定`n`n## 失败与原因`n"
    }
}
function Add-Report([string]$Path,[string]$Section,[string]$Text) {
    $raw = [IO.File]::ReadAllText($Path)
    $pat = '(?ms)(^## ' + [regex]::Escape($Section) + '\s*\r?\n)(.*?)(?=^## |\z)'
    $m = [regex]::Match($raw,$pat)
    if (-not $m.Success) { throw "Missing report section: $Section" }
    $insert = $m.Value.TrimEnd() + "`n`n" + $Text + "`n`n"
    Write-Utf8 $Path ($raw.Substring(0,$m.Index) + $insert + $raw.Substring($m.Index+$m.Length))
}
function Assert-Scope([string]$Root,[string]$Baseline,[string]$Branch) {
    if ((Invoke-Git $Root @('branch','--show-current')) -ne $Branch) { throw 'Branch changed unexpectedly.' }
    $changed = @((Invoke-Git $Root @('diff','--name-only',$Baseline,'--')) -split '\r?\n')
    $changed += @((Invoke-Git $Root @('ls-files','--others','--exclude-standard')) -split '\r?\n')
    foreach ($f in $changed) {
        if ($f -and $f -ne '.gitignore' -and -not $f.StartsWith('night-shift/')) { throw "Forbidden path change: $f. Preserved for inspection; no commit or push." }
    }
    $trackedLogs = Invoke-Git $Root @('ls-files','night-shift/logs')
    if ($trackedLogs) { throw 'Raw logs must not be tracked.' }
}
function Commit-Night([string]$Root,[string]$Baseline,[string]$Branch,[datetime]$Deadline) {
    Assert-Scope $Root $Baseline $Branch
    Invoke-Git $Root @('add','--','night-shift','.gitignore') $Deadline | Out-Null
    $dirty = Invoke-Git $Root @('diff','--cached','--name-only') $Deadline
    if ($dirty) { Invoke-Git $Root @('commit','-m',"GEO night shift $Branch") $Deadline | Out-Null }
    return Invoke-Git $Root @('rev-parse','HEAD') $Deadline
}
