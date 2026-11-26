[CmdletBinding()]
param([string]$Root=(Split-Path -Parent $PSScriptRoot),[string]$Output='night-shift/evidence/20261126-GEO-006-schema-audit.json')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NightShift.Common.ps1')
$path=Join-Path $Root 'index.html'
$before=(Get-FileHash $path -Algorithm SHA256).Hash
$html=[IO.File]::ReadAllText($path)
function Normalize-Text([string]$s){return ([regex]::Replace([Net.WebUtility]::HtmlDecode(([regex]::Replace($s,'<[^>]+>',' '))),'\s+',' ')).Trim()}
$blocks=@([regex]::Matches($html,'(?is)<script\b[^>]*type\s*=\s*["'']application/ld\+json["''][^>]*>(.*?)</script>'))
$nodes=@();$checks=@();$findings=@()
foreach($b in $blocks){
    try{
        $data=$b.Groups[1].Value | ConvertFrom-Json
        $nodes+=@(if($data.PSObject.Properties.Name -contains '@graph'){$data.'@graph'}else{$data})
        $checks+=@{check='json-parse';status='PASS'}
        $context=if($data.PSObject.Properties.Name -contains '@context'){$data.'@context'}else{$null}
        $checks+=@{check='schema-context';status=if($context -in @('https://schema.org','http://schema.org')){'PASS'}else{'REVIEW'}}
    }catch{$checks+=@{check='json-parse';status='FAIL';reason=$_.Exception.Message}}
}
if(-not $blocks.Count){$findings+=@{priority='P1';kind='MISSING';message='No JSON-LD found; evaluate whether it applies, not a claim of required markup.'}}
$org=@($nodes | Where-Object {$_.'@type' -contains 'Organization'})
$games=@($nodes | Where-Object {$_.'@type' -contains 'VideoGame'})
$faqs=@($nodes | Where-Object {$_.'@type' -contains 'FAQPage'})
$ids=@($nodes | Where-Object {$_.PSObject.Properties.Name -contains '@id'} | ForEach-Object {$_.'@id'})
$checks+=@{check='duplicate-node-ids';status=if(@($ids | Group-Object | Where-Object Count -gt 1).Count){'FAIL'}else{'PASS'}}
foreach($game in $games){
    if($game.PSObject.Properties.Name -contains 'creator'){
        $ref=$game.creator.'@id'
        $checks+=@{check='game-creator-reference';reference=$ref;status=if($ref -in $ids){'PASS'}else{'FAIL'}}
    }
    foreach($field in @('@id','url')){
        if($game.PSObject.Properties.Name -notcontains $field){$findings+=@{priority='P1';kind='OPTIONAL_IMPROVEMENT';node='VideoGame';field=$field;message='Add a stable game identity/canonical URL if approved; not a JSON syntax error or guaranteed ranking improvement.'}}
    }
}
foreach($o in $org){
    foreach($field in @('url','sameAs','logo','legalName')){
        if($o.PSObject.Properties.Name -notcontains $field){$findings+=@{priority='P2';kind='VERIFY_BEFORE_ADDING';node='Organization';field=$field;message='Optional; add only when verified and appropriate. Do not invent profiles, image URLs, legal identity or claim this is required.'}}
    }
}
$visible=@([regex]::Matches($html,'(?is)<article\b[^>]*class\s*=\s*["'']faq-item["''][^>]*>\s*<h3[^>]*>(.*?)</h3>\s*<p[^>]*>(.*?)</p>\s*</article>'))
$pairs=@()
foreach($faq in $faqs){
    foreach($q in @($faq.mainEntity)){
        $question=Normalize-Text $q.name
        $answer=Normalize-Text $q.acceptedAnswer.text
        $matches=@($visible | Where-Object {(Normalize-Text $_.Groups[1].Value) -eq $question -and (Normalize-Text $_.Groups[2].Value) -eq $answer})
        $pairs+=@{question=$question;visibleMatch=$matches.Count -eq 1}
    }
}
$checks+=@{check='faq-visible-jsonld-correspondence';status=if($pairs.Count -eq $visible.Count -and -not @($pairs | Where-Object {-not $_.visibleMatch}).Count){'PASS'}else{'FAIL'};schemaQuestions=$pairs.Count;visibleQuestions=$visible.Count}
$findings+=@{priority='P1';kind='SEARCH_FEATURE_LIMITATION';node='FAQPage';message='Google documentation records FAQ rich results no longer appearing from 2026-05-07. Schema.org FAQPage still exists; retain only for accurate semantic description, not rich-result promises.';source='https://developers.google.com/search/updates'}
$findings+=@{priority='P2';kind='OPTIONAL_IMPROVEMENT';node='FAQPage';field='@id/url/inLanguage';message='Stable page identity and language can be added after page/route approval. No Chinese route has been approved.'}
$candidate=@()
foreach($sourceNode in $nodes) {
    $node=($sourceNode | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
    if($node.'@type' -contains 'Organization') {$node | Add-Member NoteProperty '@id' 'https://domaseed.com/#optiverse' -Force}
    if($node.'@type' -contains 'VideoGame') {
        $node | Add-Member NoteProperty '@id' 'https://domaseed.com/#domaseed' -Force
        $node | Add-Member NoteProperty 'url' 'https://domaseed.com/' -Force
        $node.creator.'@id'='https://domaseed.com/#optiverse'
    }
    if($node.'@type' -contains 'FAQPage') {
        $node | Add-Member NoteProperty '@id' 'https://domaseed.com/#webpage' -Force
        $node | Add-Member NoteProperty 'url' 'https://domaseed.com/' -Force
        $node | Add-Member NoteProperty 'inLanguage' 'en' -Force
    }
    $candidate+=,$node
}
$candidatePath='night-shift/drafts/schema-graph-candidate-20261126.json'
if(-not @($checks | Where-Object status -eq 'FAIL').Count) {
    $candidateJson=(@{'@context'='https://schema.org';'@graph'=$candidate}) | ConvertTo-Json -Depth 30
    $roundTrip=$candidateJson | ConvertFrom-Json
    if($roundTrip.'@graph'.Count -ne $nodes.Count){throw 'Candidate graph shape changed'}
    foreach($candidateNode in $roundTrip.'@graph'){if($candidateNode.PSObject.Properties.Name -notcontains '@type'){throw 'Candidate node lost its type'}}
    Write-Utf8 (Join-Path $Root $candidatePath) $candidateJson
}
$result=[ordered]@{task='GEO-006';at=[datetime]::UtcNow.ToString('o');scope='local index.html only; read-only';sourceSHA256=$before;candidatePath=$candidatePath;currentGraph=$nodes;jsonldBlocks=$blocks.Count;nodeTypes=@($nodes | ForEach-Object {$_.'@type'});checks=$checks;faqPairs=$pairs;findings=$findings;limitations=@('Targeted syntax, references and current FAQ-text checks, not a complete JSON-LD expansion or Schema.org conformance validation.','No Rich Results Test, Search Console indexing inspection or AI-answer measurement was performed.','Optional properties are not universal required fields.','No changes to index.html, DNS, sitemap or publication.');sources=@('https://schema.org/VideoGame','https://schema.org/FAQPage','https://developers.google.com/search/docs/appearance/structured-data/organization','https://developers.google.com/search/docs/appearance/structured-data/sd-policies','https://developers.google.com/search/updates')}
if((Get-FileHash $path -Algorithm SHA256).Hash -ne $before){throw 'Source changed during inspection'}
Write-Utf8 (Join-Path $Root $Output) ($result | ConvertTo-Json -Depth 10)
if(@($checks | Where-Object status -eq 'FAIL').Count){throw 'Schema inspection found failures; review recorded evidence'}
[pscustomobject]$result | Select-Object task,sourceSHA256,jsonldBlocks,nodeTypes,checks | ConvertTo-Json -Depth 7
