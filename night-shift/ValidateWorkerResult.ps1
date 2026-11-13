function Read-ValidatedWorkerResult {
    param([string]$ResultPath,[string]$Root,[string]$TaskId,[string]$QueueStatus)
    if (-not (Test-Path -LiteralPath $ResultPath -PathType Leaf)) { throw 'Structured final result missing.' }
    $answer=[IO.File]::ReadAllText($ResultPath) | ConvertFrom-Json
    if ($answer.task_id -ne $TaskId -or $answer.status -ne $QueueStatus -or $answer.status -notin @('DONE','BLOCKED','NEEDS_FOUNDER')) { throw 'Structured result disagrees with claimed task/queue.' }
    if ($answer.status -eq 'DONE') {
        $primary=0
        $rootPrefix=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
        $evidencePrefix=[IO.Path]::GetFullPath((Join-Path $Root 'night-shift/evidence')).TrimEnd('\')+'\'
        foreach ($e in @($answer.evidence)) {
            if (-not ($e -is [string]) -or [IO.Path]::IsPathRooted($e)) { throw 'Evidence reference must be a repository-relative path.' }
            $path=[IO.Path]::GetFullPath((Join-Path $Root $e))
            if (-not $path.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Referenced output missing/outside workspace.' }
            if ($path.StartsWith($evidencePrefix,[StringComparison]::OrdinalIgnoreCase)) { $primary++ }
            elseif ($e.Replace('\','/') -notmatch '^night-shift/(TASK_QUEUE\.md|reports/[^/]+\.md|drafts/.+)$') { throw 'Unsupported evidence attachment (logs/code cannot qualify).' }
        }
        if ($primary -eq 0) { throw 'DONE requires an existing primary file under night-shift/evidence/.' }
    }
    return $answer
}
