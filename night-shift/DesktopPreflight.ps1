# Host-side preflight only. It does not modify Codex permissions, ACLs, or sandbox configuration.
if (-not ('GeoDesktopNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class GeoDesktopNative {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    public static int Probe(string path) {
        // Detect mapped-image sharing locks as well as ACL handle restrictions.
        // Requesting read/write/WRITE_DAC access changes neither bytes nor ACLs.
        using (var h=CreateFile(path,0xC0040000,0,IntPtr.Zero,3,0x80,IntPtr.Zero)) {
            return h.IsInvalid ? Marshal.GetLastWin32Error() : 0;
        }
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct UniqueProcess { public uint pid; public System.Runtime.InteropServices.ComTypes.FILETIME start; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct ProcessInfo {
        public UniqueProcess process;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=256)] public string appName;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=64)] public string service;
        public uint appType; public uint appStatus; public uint session;
        [MarshalAs(UnmanagedType.Bool)] public bool restartable;
    }
    [DllImport("rstrtmgr.dll",CharSet=CharSet.Unicode)] static extern int RmStartSession(out uint session,int flags,string key);
    [DllImport("rstrtmgr.dll",CharSet=CharSet.Unicode)] static extern int RmRegisterResources(uint session,uint count,string[] paths,uint apps,IntPtr appList,uint services,string[] serviceNames);
    [DllImport("rstrtmgr.dll")] static extern int RmGetList(uint session,out uint needed,ref uint count,[In,Out] ProcessInfo[] info,ref uint reasons);
    [DllImport("rstrtmgr.dll")] static extern int RmEndSession(uint session);
    public static uint[] Owners(string[] paths) {
        if(paths.Length==0) return new uint[0];
        uint session;
        int e=RmStartSession(out session,0,Guid.NewGuid().ToString("N"));
        if(e!=0) throw new System.ComponentModel.Win32Exception(e);
        try {
            e=RmRegisterResources(session,(uint)paths.Length,paths,0,IntPtr.Zero,0,null);
            if(e!=0) throw new System.ComponentModel.Win32Exception(e);
            uint needed=0,count=0,reasons=0;
            e=RmGetList(session,out needed,ref count,null,ref reasons);
            if(e==0) return new uint[0];
            if(e!=234) throw new System.ComponentModel.Win32Exception(e);
            for(int retry=0;retry<3;retry++) {
                count=needed;
                var info=new ProcessInfo[count];
                e=RmGetList(session,out needed,ref count,info,ref reasons);
                if(e==234) continue;
                if(e!=0) throw new System.ComponentModel.Win32Exception(e);
                var result=new uint[count];
                for(int i=0;i<count;i++) result[i]=info[i].process.pid;
                return result;
            }
            throw new Exception("Owner list kept changing.");
        } finally { RmEndSession(session); }
    }
}
'@ | Out-Null
}

function Test-DesktopCandidate {
    param([string]$Name,[string]$Path,[string[]]$PackageRoots,[string]$RuntimeRoot)
    if (-not $Path) { return $false }
    # Never terminate the CLI, sandbox helpers, or a merely similarly named application.
    if ($Name -match '^codex-(windows-sandbox|command-runner)') { return $false }
    foreach ($r in $PackageRoots) {
        if ($Path.StartsWith($r.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return ($Name -ieq 'codex-computer-use-swift.exe' -and $Path.StartsWith($RuntimeRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase))
}
function Get-DesktopCandidates {
    param([string[]]$PackageRoots,[string]$RuntimeRoot)
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $session=(Get-Process -Id $PID).SessionId
    foreach ($p in @(Get-CimInstance Win32_Process)) {
        if ($p.ProcessId -eq $PID -or $p.SessionId -ne $session) { continue }
        if (-not (Test-DesktopCandidate $p.Name $p.ExecutablePath $PackageRoots $RuntimeRoot)) { continue }
        $owner=Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid -ErrorAction SilentlyContinue
        if (-not $owner -or $owner.ReturnValue -ne 0 -or $owner.Sid -ne $sid) { continue }
        [pscustomobject]@{pid=[int]$p.ProcessId;name=$p.Name;path=$p.ExecutablePath;created=$p.CreationDate.ToUniversalTime().ToString('o')}
    }
}
function Get-RuntimeDlls([string]$RuntimeRoot) {
    foreach ($v in @(Get-ChildItem -LiteralPath $RuntimeRoot -Directory -ErrorAction SilentlyContinue)) {
        $dll=Join-Path $v.FullName 'bin/node_modules/@oai/sky/bin/windows/swift/x64/VCRUNTIME140_1.dll'
        if (Test-Path -LiteralPath $dll -PathType Leaf) { $dll }
    }
}
function Test-RuntimeDllRelease([string[]]$Paths) {
    foreach ($p in $Paths) {
        $errorCode=[GeoDesktopNative]::Probe($p)
        [pscustomobject]@{path=$p;released=($errorCode -eq 0);win32Error=$errorCode;message=if($errorCode){(New-Object ComponentModel.Win32Exception($errorCode)).Message}else{'Exclusive read/write-capable metadata handle opened; no bytes or ACLs changed.'}}
    }
}
function Get-VerifiedLiveDesktopProcess($Row) {
    try {
        $live=Get-Process -Id $Row.pid -ErrorAction Stop
        $sameStart=[Math]::Abs(($live.StartTime.ToUniversalTime()-[datetime]$Row.created).TotalMilliseconds) -lt 1
        if ($sameStart -and $live.Path -ieq $Row.path) { return $live }
    } catch { }
    return $null
}
function Get-KnownLiveDesktop($Rows) {
    foreach ($row in $Rows) { if (Get-VerifiedLiveDesktopProcess $row) { $row } }
}
function Close-CodexDesktop {
    param([ValidateRange(0,60)][int]$GraceSeconds=60,[datetime]$Deadline=[datetime]::MaxValue)
    $start=[datetime]::UtcNow
    $runtime=Join-Path $env:LOCALAPPDATA 'OpenAI/Codex/runtimes/cua_node'
    $packages=@(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction Stop | ForEach-Object InstallLocation)
    $initial=@(Get-DesktopCandidates $packages $runtime | Sort-Object created)
    $initialDllChecks=@(Test-RuntimeDllRelease @(Get-RuntimeDlls $runtime))
    $actions=New-Object 'Collections.Generic.List[object]'
    $graceStarted=[datetime]::UtcNow
    $graceEnd=$graceStarted.AddSeconds($GraceSeconds)
    if ($Deadline -lt $graceEnd) { $graceEnd=$Deadline }
    foreach ($p in $initial) {
        if ([datetime]::UtcNow -ge $graceEnd) { break }
        $requested=$false; $message='No main window; waits for application shutdown.'
        try {
            $live=Get-VerifiedLiveDesktopProcess $p
            if ($live) { $requested=$live.CloseMainWindow() }
            if ($requested) { $message='WM_CLOSE requested for main window.' }
        } catch { $message=$_.Exception.Message }
        $actions.Add([pscustomobject]@{pid=$p.pid;name=$p.name;method='normal-request';windowCloseRequested=$requested;at=[datetime]::UtcNow.ToString('o');detail=$message})
    }
    $remaining=@(Get-KnownLiveDesktop $initial)
    while ($remaining.Count -and [datetime]::UtcNow -lt $graceEnd) {
        $ms=[int][Math]::Min(500.0,[Math]::Max(1.0,($graceEnd-[datetime]::UtcNow).TotalMilliseconds))
        Start-Sleep -Milliseconds $ms
        $remaining=@(Get-KnownLiveDesktop $initial)
    }
    $graceFinished=[datetime]::UtcNow
    $remaining=@(Get-DesktopCandidates $packages $runtime)
    $forced=$false
    # Revalidate current identity immediately before each stop; never kill a whole unrelated process tree.
    for ($round=0;$round -lt 3 -and $remaining.Count -and [datetime]::UtcNow -lt $Deadline;$round++) {
        foreach ($p in $remaining) {
            try {
                $same=Get-VerifiedLiveDesktopProcess $p
                if ($same) {
                    Stop-Process -Id $p.pid -Force -ErrorAction Stop
                    $forced=$true
                    $actions.Add([pscustomobject]@{pid=$p.pid;name=$p.name;method='force';at=[datetime]::UtcNow.ToString('o');detail='Still running after shared graceful timeout.'})
                }
            } catch {
                $actions.Add([pscustomobject]@{pid=$p.pid;name=$p.name;method='force-failed';at=[datetime]::UtcNow.ToString('o');detail=$_.Exception.Message})
            }
        }
        Start-Sleep -Milliseconds 500
        $remaining=@(Get-DesktopCandidates $packages $runtime)
    }
    $remaining=@(Get-DesktopCandidates $packages $runtime)
    $dlls=@(Get-RuntimeDlls $runtime)
    $checks=@(Test-RuntimeDllRelease $dlls)
    $released=($dlls.Count -gt 0 -and @($checks | Where-Object { -not $_.released }).Count -eq 0 -and $remaining.Count -eq 0)
    $owners=@();$ownerError=$null
    if (-not $released -and $dlls.Count) {
        try {
            foreach ($ownerId in @([GeoDesktopNative]::Owners([string[]]$dlls))) {
                $p=Get-CimInstance Win32_Process -Filter "ProcessId=$ownerId" -ErrorAction SilentlyContinue
                if ($p) { $owners+=[pscustomobject]@{pid=[int]$p.ProcessId;name=$p.Name;path=$p.ExecutablePath;session=$p.SessionId} }
            }
        } catch { $ownerError=$_.Exception.Message }
    }
    $method=if($forced){'force'}elseif($initial.Count){'normal'}else{'none'}
    return [pscustomobject]@{
        started=$start.ToString('o');finished=[datetime]::UtcNow.ToString('o');graceSeconds=$GraceSeconds;graceStarted=$graceStarted.ToString('o');graceFinished=$graceFinished.ToString('o');graceElapsedSeconds=($graceFinished-$graceStarted).TotalSeconds
        initiallyRunning=($initial.Count -gt 0);initialProcesses=$initial;closedDesktop=($initial.Count -gt 0 -and $remaining.Count -eq 0)
        initialDllChecks=$initialDllChecks;method=$method;actions=@($actions.ToArray());remainingProcesses=$remaining;dllChecks=$checks;released=$released
        lockOwners=$owners;ownerQueryError=$ownerError;missingDll=($dlls.Count -eq 0)
        scope='Only current-user/current-session OpenAI.Codex package processes and validated Codex Swift sidecar. CLI and sandbox service excluded.'
    }
}
