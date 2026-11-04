[CmdletBinding()]
param([string]$RepoPath=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\NightShift.Common.ps1"
$RepoPath=[IO.Path]::GetFullPath($RepoPath)
$stamp=[TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow,[TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')).ToString('yyyyMMdd-HHmmss')
$build=Join-Path $RepoPath "night-shift/logs/preview-$stamp"
[IO.Directory]::CreateDirectory($build) | Out-Null
$source=@(Get-ChildItem $RepoPath -File | Where-Object { $_.Extension -eq '.html' -or $_.Name -in @('CNAME','robots.txt','sitemap.xml') })
if (-not @($source | Where-Object Name -eq 'index.html').Count) { throw 'No index.html; audit cannot build a preview.' }
$hashes=@{}
foreach ($f in $source) { $hashes[$f.Name]=(Get-FileHash $f.FullName -Algorithm SHA256).Hash; Copy-Item $f.FullName (Join-Path $build $f.Name) }
$checks=@(); $findings=@(); $links=@(); $languages=@(); $pages=@()
$probe=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
$probe.Start(); $port=([Net.IPEndPoint]$probe.LocalEndpoint).Port; $probe.Stop()
$ready=Join-Path $build 'ready.txt'
$job=Start-Job -ArgumentList $port,$build,$ready -ScriptBlock {
    param($port,$build,$ready)
    $listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$port)
    try {
        $listener.Start(); [IO.File]::WriteAllText($ready,'ready')
        $client=$listener.AcceptTcpClient()
        try {
            $stream=$client.GetStream()
            $stream.ReadTimeout=10000
            $reader=New-Object IO.StreamReader($stream)
            $line=$reader.ReadLine()
            while ($reader.ReadLine()) { }
            $bytes=[IO.File]::ReadAllBytes((Join-Path $build 'index.html'))
            $header=[Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n")
            $stream.Write($header,0,$header.Length); $stream.Write($bytes,0,$bytes.Length); $stream.Flush()
        } finally { $client.Close() }
    } finally { $listener.Stop() }
}
try {
    $until=[datetime]::UtcNow.AddSeconds(15)
    while (-not (Test-Path $ready) -and [datetime]::UtcNow -lt $until) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path $ready)) { throw 'Local preview listener did not become ready.' }
    $http=Invoke-WebRequest -Uri "http://127.0.0.1:$port/" -UseBasicParsing -TimeoutSec 10
    $checks += [ordered]@{check='static-preview-http';status='PASS';code=[int]$http.StatusCode; bytes=$http.RawContentLength; preview='logs/preview (ignored)'}
} finally { Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue }
foreach ($f in @($source | Where-Object Extension -eq '.html')) {
    $html=[IO.File]::ReadAllText($f.FullName)
    $title=[regex]::Match($html,'(?is)<title[^>]*>(.*?)</title>').Groups[1].Value
    $meta=[regex]::Match($html,'(?is)<meta\b(?=[^>]*\bname\s*=\s*["'']description["''])[^>]*\bcontent\s*=\s*["'']([^"'']*)').Groups[1].Value
    $language=[regex]::Match($html,'(?is)<html[^>]*\blang\s*=\s*["'']([^"'']+)').Groups[1].Value
    $languages+=$language
    $types=@(); $schemaValid=$true
    foreach ($s in [regex]::Matches($html,'(?is)<script\b[^>]*type\s*=\s*["'']application/ld\+json["''][^>]*>(.*?)</script>')) {
        try {
            $obj=$s.Groups[1].Value | ConvertFrom-Json
            $nodes=if ($obj.PSObject.Properties.Name -contains '@graph') { @($obj.'@graph') } else { @($obj) }
            foreach ($n in $nodes) { if ($n.PSObject.Properties.Name -contains '@type') { $types+=@($n.'@type') } }
        } catch { $schemaValid=$false }
    }
    if (-not $title) { $findings+="$($f.Name): missing title" }
    if (-not $meta) { $findings+="$($f.Name): missing description" }
    if (-not $schemaValid) { $findings+="$($f.Name): JSON-LD parse failed" }
    if ('Organization' -notin $types) { $findings+="$($f.Name): Organization schema absent" }
    if (-not @($types | Where-Object { $_ -in @('VideoGame','EducationalApplication','SoftwareApplication') }).Count) { $findings+="$($f.Name): game/application schema absent" }
    foreach ($m in [regex]::Matches($html,'(?is)\b(?:href|src)\s*=\s*["'']([^"'']+)["'']')) {
        $url=[Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
        if ($url -match '^(mailto:|tel:|data:|javascript:)') { continue }
        $status=''; $kind='internal'
        if ($url -match '^https?://') {
            $kind='external'
            try { $rr=Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 15 -MaximumRedirection 5; $status="HTTP $([int]$rr.StatusCode)" }
            catch { $status='UNVERIFIED: external request failed'; $findings+="$($f.Name): external link could not be verified: $url" }
        } elseif ($url.StartsWith('#')) {
            $id=$url.Substring(1)
            $status=if (-not $id -or $html -match ('(?is)\bid\s*=\s*["'']'+[regex]::Escape($id)+'["'']')) {'PASS'} else {'BROKEN'}
        } else {
            $rel=($url -split '[?#]')[0].TrimStart('/')
            if (-not $rel) { $rel='index.html' }
            $target=Join-Path $RepoPath $rel
            $status=if (Test-Path $target) {'PASS'} else {'BROKEN'}
        }
        if ($status -eq 'BROKEN') { $findings+="$($f.Name): broken link: $url" }
        $links += [ordered]@{page=$f.Name;url=$url;kind=$kind;status=$status}
    }
    $pages += [ordered]@{path=$f.Name;language=$language;title=$title;description=$meta;schemaJsonValid=$schemaValid;schemaTypes=$types;canonicalPresent=($html -match '(?is)rel\s*=\s*["'']canonical["'']')}
}
if (-not @($languages | Where-Object { $_ -match '^zh' }).Count) { $findings+='No Chinese HTML page found; bilingual correspondence cannot be verified. Chinese version is absent in this source snapshot.' }
foreach ($f in $source) { if ((Get-FileHash $f.FullName -Algorithm SHA256).Hash -ne $hashes[$f.Name]) { throw "Source mutated during audit: $($f.Name)" } }
$result=[ordered]@{at=[datetime]::UtcNow.ToString('o');audit='GEO-001 static source audit';scope='read-only; source unchanged';build='static file copy; no npm project exists';checks=$checks;pages=$pages;links=$links;findings=$findings;sourceSHA256=$hashes;limitations=@('JSON-LD syntax/type inspection is not external schema.org conformance validation.','Audit checks source and local preview; does not establish search indexing or AI visibility.')}
$rel="night-shift/evidence/$stamp-GEO-001-site-audit.json"
Write-Utf8 (Join-Path $RepoPath $rel) ($result | ConvertTo-Json -Depth 12)
Write-Output "Audit completed; findings=$($findings.Count); evidence=$rel; source unchanged."
