$ErrorActionPreference='Stop'
$framework=Split-Path -Parent $PSScriptRoot
. "$framework\NightShift.Common.ps1"
. "$framework\DesktopPreflight.ps1"
. "$framework\ValidateWorkerResult.ps1"
$passed=New-Object 'Collections.Generic.List[string]'
function Check([bool]$Ok,[string]$Text) { if (-not $Ok) { throw "FAILED: $Text" }; $passed.Add($Text) }
$package='C:\Program Files\WindowsApps\OpenAI.Codex_Test'
$runtime='C:\Users\Fixture\AppData\Local\OpenAI\Codex\runtimes\cua_node'
Check (Test-DesktopCandidate 'Codex.exe' "$package\app\Codex.exe" @($package) $runtime) 'Actual package root is eligible'
Check (-not (Test-DesktopCandidate 'Codex.exe' ($package+'-other\app\Codex.exe') @($package) $runtime)) 'Package prefix collision is excluded'
Check (-not (Test-DesktopCandidate 'codex.exe' 'C:\Users\Fixture\AppData\Roaming\npm\codex.exe' @($package) $runtime)) 'Local CLI is excluded'
Check (-not (Test-DesktopCandidate 'codex-windows-sandbox-service.exe' "$package\app\codex-windows-sandbox-service.exe" @($package) $runtime)) 'Sandbox service is excluded'
Check (Test-DesktopCandidate 'codex-computer-use-swift.exe' "$runtime\v1\bin\codex-computer-use-swift.exe" @($package) $runtime) 'Verified Swift runtime sidecar is eligible'
Check (-not (Test-DesktopCandidate 'codex-computer-use-swift.exe' 'C:\Unrelated\codex-computer-use-swift.exe' @($package) $runtime)) 'Same-name unrelated process is excluded'
$selfProcess=Get-Process -Id $PID
$selfRow=[pscustomobject]@{pid=$PID;path=$selfProcess.Path;created=$selfProcess.StartTime.ToUniversalTime().ToString('o')}
Check ([bool](Get-VerifiedLiveDesktopProcess $selfRow)) 'PID identity comparison normalizes parsed timestamp to UTC'
$staleRow=[pscustomobject]@{pid=$PID;path=$selfProcess.Path;created=$selfProcess.StartTime.ToUniversalTime().AddMinutes(-1).ToString('o')}
Check (-not (Get-VerifiedLiveDesktopProcess $staleRow)) 'Reused/stale PID identity is rejected'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('geo-desktop-tests-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp) | Out-Null
try {
    $file=Join-Path $temp 'locked.dll'
    Write-Utf8 $file 'not an actual DLL; file-lock probe fixture'
    $hash=(Get-FileHash $file).Hash
    $acl=(Get-Acl $file).Sddl
    Check ([GeoDesktopNative]::Probe($file) -eq 0) 'Unlocked file metadata probe passes'
    $hold=[IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {
        Check ([GeoDesktopNative]::Probe($file) -eq 32) 'Actual exclusive file lock is detected as Windows error 32'
        $observed=@(Test-RuntimeDllRelease @($file))
        Check (-not $observed[0].released) 'Locked file cannot report released'
    } finally { $hold.Dispose() }
    Check ([GeoDesktopNative]::Probe($file) -eq 0) 'Released file probe passes after handle is closed'
    Check ((Get-FileHash $file).Hash -eq $hash -and (Get-Acl $file).Sddl -eq $acl) 'Probe changes neither file bytes nor ACL'
    $root=Join-Path $temp 'repo'
    Write-Utf8 (Join-Path $root 'night-shift/evidence/real.json') '{}'
    Write-Utf8 (Join-Path $root 'night-shift/TASK_QUEUE.md') 'fixture'
    $result=Join-Path $temp 'result.json'
    Write-Utf8 $result (@{task_id='GEO-001';status='DONE';summary='fixture';evidence=@('night-shift/evidence/real.json','night-shift/TASK_QUEUE.md')} | ConvertTo-Json)
    Check ((Read-ValidatedWorkerResult $result $root 'GEO-001' 'DONE').status -eq 'DONE') 'Primary evidence plus supporting document is accepted'
    Write-Utf8 $result (@{task_id='GEO-001';status='DONE';summary='fixture';evidence=@('night-shift/TASK_QUEUE.md')} | ConvertTo-Json)
    $denied=$false
    try { Read-ValidatedWorkerResult $result $root 'GEO-001' 'DONE' | Out-Null } catch { $denied=$true }
    Check $denied 'Supporting document alone cannot establish DONE'
    $record=@{at=[datetime]::UtcNow.ToString('o');passed=$passed.Count;checks=@($passed.ToArray());scope='No real application was terminated by these regression tests. Live desktop trial is separate.'}
    Write-Utf8 "$framework\evidence/desktop-preflight-tests.json" ($record | ConvertTo-Json -Depth 5)
    $record | ConvertTo-Json -Depth 5
} finally { Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue }