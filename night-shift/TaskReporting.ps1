function Set-ReportEntry {
    param([string]$Path,[string]$Section,[string]$Key,[string]$Text)
    $raw=[IO.File]::ReadAllText($Path)
    $begin='<!-- geo-auto:'+ $Key +' -->'
    $end='<!-- /geo-auto:'+ $Key +' -->'
    $block=$begin+"`n"+$Text+"`n"+$end
    $pattern='(?s)'+[regex]::Escape($begin)+'.*?'+[regex]::Escape($end)
    if ([regex]::IsMatch($raw,$pattern)) {
        $raw=[regex]::Replace($raw,$pattern,[System.Text.RegularExpressions.MatchEvaluator]{param($m) $block})
        Write-Utf8 $Path $raw
    } else { Add-Report $Path $Section $block }
}

function Update-TaskReport {
    param([string]$Root,[string]$Report,[string]$Day)
    $tasks=@(Read-Queue (Join-Path $Root 'night-shift/TASK_QUEUE.md'))
    $table="| 任务 | 当前状态 |`n|---|---|`n"+(($tasks | ForEach-Object {"| $($_.Id) | $($_.Status) |"}) -join "`n")
    Set-ReportEntry $Report '今晚做了什么' 'task-status' $table
    $reports=@(Get-ChildItem (Join-Path $Root 'night-shift/reports') -Filter 'morning-*.md' -File | Where-Object {$_.Name -match '^morning-\d{8}\.md$' -and $_.Name -le "morning-$Day.md"} | Sort-Object Name)
    $entries=@(); $failures=@(); $decisions=@()
    foreach ($task in $tasks) {
        $samples=@()
        foreach ($file in $reports) {
            $raw=[IO.File]::ReadAllText($file.FullName)
            $pattern='(?m)^\|\s*'+[regex]::Escape($task.Id)+'\s*\|\s*(TODO|DONE|BLOCKED|NEEDS_FOUNDER|PARTIAL-MANUAL)\s*\|\s*$'
            $found=[regex]::Matches($raw,$pattern)
            $status=if($found.Count){$found[$found.Count-1].Groups[1].Value}else{'UNKNOWN'}
            $samples+=@{day=$file.BaseName.Substring(8);status=$status}
        }
        $streak=0
        for($i=$samples.Count-1;$i -ge 0;$i--) {if($samples[$i].status -ne 'BLOCKED'){break};$streak++}
        $escalated=$task.Status -eq 'BLOCKED' -and $streak -ge 2
        $entries+=@{task=$task.Id;status=$task.Status;blockedNights=$streak;escalated=$escalated;history=$samples}
        if($task.Status -in @('BLOCKED','NEEDS_FOUNDER','PARTIAL-MANUAL')) {
            $reason=if($task.Reason){$task.Reason}elseif($task.Result){$task.Result}else{'任务未提供详细原因；执行端需补充诊断，不能据此声称完成。'}
            $tried=if($task.Tried){$task.Tried}else{'既有证据见该任务结果；没有记录的新尝试不作推断。'}
            $decision=if($task.Decision){$task.Decision}else{'无需重复批准既有范围；执行端继续排查，只有明确缺少登录、资料或新增预算时才提出具体请求。'}
            $label=if($escalated){"已升级：连续 $streak 个有记录的夜班 BLOCKED"}elseif($task.Status -eq 'PARTIAL-MANUAL'){'人工汇总已录入；原始证据及完整测量待补'}else{$task.Status}
            $failures+="- $($task.Id)（$label）：$reason 已尝试：$tried"
            $decisions+="- $($task.Id)：$decision"
        }
    }
    if(-not $failures.Count){$failures=@('- 当前队列无 BLOCKED、NEEDS_FOUNDER 或待补证据的人工记录；启动器错误另列。')}
    if(-not $decisions.Count){$decisions=@('- 当前无需创始人决定；已授权任务由执行端继续。')}
    Set-ReportEntry $Report '失败与原因' 'blockers' ($failures -join "`n")
    Set-ReportEntry $Report '待我决定' 'decisions' ($decisions -join "`n")
    $relative="night-shift/evidence/$Day-task-escalation.json"
    Write-Utf8 (Join-Path $Root $relative) (([ordered]@{at=[datetime]::UtcNow.ToString('o');day=$Day;counting='one observation per dated report; missing status breaks streak; same-night reruns do not increment';tasks=$entries}) | ConvertTo-Json -Depth 9)
    return $relative
}
