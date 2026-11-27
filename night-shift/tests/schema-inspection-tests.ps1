$ErrorActionPreference='Stop'
$framework=Split-Path -Parent $PSScriptRoot
. (Join-Path $framework 'NightShift.Common.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('geo-schema-tests-'+[guid]::NewGuid().ToString('N'))
$ps=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$script=Join-Path $framework 'inspect-schema.ps1'
$passed=@()
function Assert([bool]$Condition,[string]$Why){if(-not $Condition){throw "FAILED: $Why"};$script:passed+=$Why}
try{
    $source=[IO.File]::ReadAllText((Join-Path (Split-Path -Parent $framework) 'index.html'))
    Write-Utf8 (Join-Path $temp 'index.html') $source
    $r=Invoke-Bounded $ps @('-NoProfile','-ExecutionPolicy','Bypass','-File',$script,'-Root',$temp) $temp 20
    Assert ($r.ExitCode -eq 0) ('Valid site snapshot checks pass: '+$r.Err)
    $evidence=Join-Path $temp 'night-shift/evidence/20261126-GEO-006-schema-audit.json'
    $data=[IO.File]::ReadAllText($evidence) | ConvertFrom-Json
    Assert ($data.jsonldBlocks -ge 1 -and @($data.checks | Where-Object status -eq FAIL).Count -eq 0) 'Syntax, references and visible FAQ checks recorded'
    $candidate=[IO.File]::ReadAllText((Join-Path $temp $data.candidatePath)) | ConvertFrom-Json
    $games=@($candidate.'@graph' | Where-Object {$_.'@type' -eq 'VideoGame'})
    Assert ($games.Count -eq 1 -and $games[0].creator.'@id' -eq 'https://domaseed.com/#optiverse') 'Candidate graph keeps exactly one game with a resolvable creator identity'
    $changed=$source.Replace('<h3>What is DOMASEED?</h3>','<h3>Changed visible question</h3>')
    Assert ($changed -ne $source) 'Mismatch fixture changes only the visible question'
    Write-Utf8 (Join-Path $temp 'index.html') $changed
    $before=(Get-FileHash (Join-Path $temp 'index.html') -Algorithm SHA256).Hash
    $r=Invoke-Bounded $ps @('-NoProfile','-ExecutionPolicy','Bypass','-File',$script,'-Root',$temp) $temp 20
    $data=[IO.File]::ReadAllText($evidence) | ConvertFrom-Json
    Assert ($r.ExitCode -ne 0 -and @($data.checks | Where-Object {$_.check -eq 'faq-visible-jsonld-correspondence' -and $_.status -eq 'FAIL'}).Count -eq 1) 'Visible/schema mismatch cannot pass'
    Assert ((Get-FileHash (Join-Path $temp 'index.html') -Algorithm SHA256).Hash -eq $before) 'Inspection never modifies source even on failure'
    Write-Utf8 (Join-Path $temp 'index.html') '<script type="application/ld+json">{"broken":</script>'
    $r=Invoke-Bounded $ps @('-NoProfile','-ExecutionPolicy','Bypass','-File',$script,'-Root',$temp) $temp 20
    $data=[IO.File]::ReadAllText($evidence) | ConvertFrom-Json
    Assert ($r.ExitCode -ne 0 -and @($data.checks | Where-Object {$_.check -eq 'json-parse' -and $_.status -eq 'FAIL'}).Count -eq 1) 'Malformed JSON is recorded as a failing check'
    $result=[ordered]@{at=[datetime]::UtcNow.ToString('o');passed=$passed.Count;checks=$passed}
    Write-Utf8 (Join-Path $framework 'evidence/schema-inspection-tests-20261126.json') ($result | ConvertTo-Json -Depth 5)
    $result | ConvertTo-Json -Depth 5
}finally{Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue}
