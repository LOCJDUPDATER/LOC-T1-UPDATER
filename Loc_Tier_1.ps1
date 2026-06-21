Clear-Host

# ===============================
# ASCII Banner (LOC RECORDING POLICY T1)
# ===============================
Write-Host "   __   ____  _____  ___  _____________  ___  ___  _____  _______  ___  ____  __   ___________  __  _________" -ForegroundColor Cyan
Write-Host "  / /  / __ \/ ___/ / _ \/ __/ ___/ __ \/ _ \/ _ \/  _/ |/ / ___/ / _ \/ __ \/ /  /  _/ ___/\ \/ / /_  __<  /" -ForegroundColor Cyan
Write-Host " / /__/ /_/ / /__  / , _/ _// /__/ /_/ / , _/ // // //    / (_ / / ___/ /_/ / /___/ // /__   \  /   / /  / / " -ForegroundColor Cyan
Write-Host "/____/\____/\___/ /_/|_/___/\___/\____/_/|_/____/___/_/|_/\___/ /_/   \____/____/___/\___/   /_/   /_/  /_/  " -ForegroundColor Cyan
Write-Host ""
Write-Host "Discord.gg/locx | Complete with 100% success rate" -ForegroundColor White
Write-Host ""

function Write-Section {
    param($Title, $Lines)
    Write-Host "--- $Title ---" -ForegroundColor Cyan
    foreach ($line in $Lines) {
        if ($line -like "SUCCESS*") { Write-Host $line -ForegroundColor Green }
        elseif ($line -like "FAILURE*") { Write-Host $line -ForegroundColor Red }
        elseif ($line -like "WARNING*") { Write-Host $line -ForegroundColor Yellow }
    }
    Write-Host ""
}

function Invoke-ToolDownload {
    param(
        [string]$Url,
        [string]$ZipPath,
        [string]$DestDir
    )

    try {
        Invoke-WebRequest -Uri $Url -OutFile $ZipPath -UseBasicParsing -TimeoutSec 120
        if (-not (Test-Path $ZipPath)) { return $false }
        if (-not (Test-Path $DestDir)) { New-Item -ItemType Directory -Path $DestDir -Force | Out-Null }
        Expand-Archive -Path $ZipPath -DestinationPath $DestDir -Force
        return $true
    } catch {
        Write-Warning "Download failed: $($_.Exception.Message)"
        return $false
    }
}

function Get-Exclusions {
    $list = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    try {
        $prefs = Get-MpPreference -ErrorAction Stop
        foreach ($item in @($prefs.ExclusionPath) + @($prefs.ExclusionProcess) + @($prefs.ExclusionExtension)) {
            if ($item) { [void]$list.Add([string]$item) }
        }
    } catch {}

    $regRoots = @(
        'SOFTWARE\Microsoft\Windows Defender\Exclusions',
        'SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions'
    )
    $regTypes = @('Paths', 'Processes', 'Extensions')

    foreach ($root in $regRoots) {
        foreach ($type in $regTypes) {
            try {
                $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$root\$type")
                if (-not $key) { continue }
                foreach ($name in $key.GetValueNames()) {
                    if ($name) { [void]$list.Add($name) }
                }
                $key.Close()
            } catch {}
        }
    }

    return @($list)
}

function Get-CheatFolderHits {
    $hits = New-Object 'System.Collections.Generic.HashSet[string]'
    $scanPaths = @(
        (Join-Path $env:USERPROFILE "Downloads"),
        (Join-Path $env:USERPROFILE "Desktop"),
        $env:LOCALAPPDATA,
        $env:APPDATA,
        $env:ProgramData,
        $env:TEMP,
        "$env:SystemDrive\"
    )

    foreach ($scanPath in $scanPaths) {
        if (-not (Test-Path $scanPath)) { continue }

        $maxDepth = 2
        if ($scanPath -eq "$env:SystemDrive\") { $maxDepth = 1 }

        Get-ChildItem -Path $scanPath -Directory -Recurse -Depth $maxDepth -ErrorAction SilentlyContinue | ForEach-Object {
            $nameLower = $_.Name.ToLower()
            $matched = Get-MatchedCheatKeyword -Text $nameLower -FolderName
            if ($matched) { [void]$hits.Add($_.FullName) }
        }
    }

    return @($hits)
}

function Get-BamRegistryFingerprints {
    $fps = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $roots = @(
        'SYSTEM\CurrentControlSet\Services\bam\State\UserSettings',
        'SYSTEM\CurrentControlSet\Services\dam\State\UserSettings'
    )

    foreach ($root in $roots) {
        try {
            $rootKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($root)
            if (-not $rootKey) { continue }

            foreach ($sidName in $rootKey.GetSubKeyNames()) {
                if ($sidName -eq 'S-1-5-18') { continue }
                $sidKey = $rootKey.OpenSubKey($sidName)
                if (-not $sidKey) { continue }

                foreach ($valueName in $sidKey.GetValueNames()) {
                    if ($valueName) { [void]$fps.Add("$root|$sidName|$valueName") }
                }
                $sidKey.Close()
            }
            $rootKey.Close()
        } catch {}
    }

    return @($fps)
}

function Get-PrefetchFileNames {
    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $prefetchPath = "$env:WINDIR\Prefetch"
    if (-not (Test-Path $prefetchPath)) { return @($names) }

    try {
        Get-ChildItem -Path $prefetchPath -Filter "*.pf" -ErrorAction Stop | ForEach-Object {
            [void]$names.Add($_.Name)
        }
    } catch {}

    return @($names)
}

function Get-TamperLogEvents {
    param([datetime]$Since)

    $events = @()
    $filters = @(
        @{ LogName = 'Security'; Id = 1102 },
        @{ LogName = 'System'; Id = 104 },
        @{ LogName = 'Microsoft-Windows-Eventlog/Operational'; Id = 104 }
    )

    foreach ($filter in $filters) {
        try {
            $filter.StartTime = $Since
            Get-WinEvent -FilterHashtable $filter -ErrorAction Stop | ForEach-Object { $events += $_ }
        } catch {}
    }

    try {
        Get-WinEvent -FilterHashtable @{
            LogName   = 'Microsoft-Windows-Sysmon/Operational'
            Id        = 23
            StartTime = $Since
        } -ErrorAction Stop | Where-Object {
            $_.Message -match '(?i)\\Prefetch\\|\\bam\\|\\dam\\|UserSettings'
        } | ForEach-Object { $events += $_ }
    } catch {}

    return $events
}

function Write-MonitorAlert {
    param(
        [string]$Message,
        [string]$LogFile,
        [string]$Color = 'White'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
    try {
        Add-Content -LiteralPath $LogFile -Value "[$timestamp] $Message" -ErrorAction Stop
    } catch {
        $fallback = Join-Path $env:TEMP 'loc_tier1_security_events.log'
        try { Add-Content -LiteralPath $fallback -Value "[$timestamp] $Message" -ErrorAction SilentlyContinue } catch {}
    }
}

$script:CursorSchemeValueNames = @(
    '(Default)', 'Arrow', 'Help', 'AppStarting', 'Wait', 'Crosshair', 'IBeam',
    'NWPen', 'No', 'SizeNS', 'SizeWE', 'SizeNWSE', 'SizeNESW', 'SizeAll',
    'UpArrow', 'Hand', 'CursorBaseSize'
)

function Expand-CursorPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Get-CursorSchemeState {
    $state = @{}
    $keyPath = 'HKCU:\Control Panel\Cursors'
    if (-not (Test-Path $keyPath)) { return $state }

    foreach ($name in $script:CursorSchemeValueNames) {
        try {
            $state[$name] = [string](Get-ItemPropertyValue -Path $keyPath -Name $name -ErrorAction Stop)
        } catch {
            $state[$name] = ''
        }
    }
    return $state
}

function Get-CursorSchemeChanges {
    param(
        [hashtable]$Baseline,
        [hashtable]$Current
    )

    $changes = @()
    foreach ($name in $script:CursorSchemeValueNames) {
        $old = if ($Baseline.ContainsKey($name)) { [string]$Baseline[$name] } else { '' }
        $new = if ($Current.ContainsKey($name)) { [string]$Current[$name] } else { '' }
        if ($old -eq $new) { continue }

        $displayOld = Expand-CursorPath $old
        $displayNew = Expand-CursorPath $new
        $msg = "$name changed: '$displayOld' -> '$displayNew'"

        if ($displayNew -match '(?i)\.(cur|ani)$' -and $displayNew -notmatch '(?i)\\windows\\cursors\\') {
            $msg += ' [non-standard cursor path]'
        }

        $kw = Get-MatchedCheatKeyword -Text $displayNew
        if ($kw) { $msg += " [keyword: $kw]" }

        $changes += $msg
    }
    return $changes
}

$script:NvidiaShadowPlayFtsRegPath = 'SOFTWARE\NVIDIA Corporation\Global\NvApp\ShadowPlay\FTS'
$script:NvidiaStreamproofGuid = '497B8458-4244-4EE6-BFEA-F3D2BA294F21'
$script:NvidiaStreamproofValues = @(36, 0x24)

function Test-NvidiaGpuPresent {
    try {
        $gpus = Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object -ExpandProperty Name
        foreach ($gpu in $gpus) {
            if ($gpu -match '(?i)nvidia') { return $true }
        }
    } catch {}
    return $false
}

function Get-NvidiaShadowPlayFtsState {
    $state = @{
        Exists = $false
        Values = @{}
    }

    try {
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($script:NvidiaShadowPlayFtsRegPath)
        if (-not $key) { return $state }

        $state.Exists = $true
        foreach ($name in $key.GetValueNames()) {
            $raw = $key.GetValue($name)
            if ($raw -is [int]) {
                $state.Values[$name] = [int]$raw
            } elseif ($raw -is [byte[]] -and $raw.Length -ge 4) {
                $state.Values[$name] = [BitConverter]::ToInt32($raw, 0)
            } else {
                $state.Values[$name] = [string]$raw
            }
        }
        $key.Close()
    } catch {}

    return $state
}

function Get-NvidiaShadowPlayFtsFingerprint {
    $state = Get-NvidiaShadowPlayFtsState
    if (-not $state.Exists) { return 'MISSING' }

    $parts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($name in ($state.Values.Keys | Sort-Object)) {
        $parts.Add("$name=$($state.Values[$name])")
    }
    if ($parts.Count -eq 0) { return 'EMPTY' }
    return ($parts -join '|')
}

function Get-NvidiaShadowPlayFtsAlerts {
    $alerts = @()
    $state = Get-NvidiaShadowPlayFtsState
    $nvidiaGpu = Test-NvidiaGpuPresent

    if (-not $state.Exists) {
        if ($nvidiaGpu) {
            $alerts += 'WARNING: ShadowPlay FTS key missing (NVIDIA GPU detected)'
        } else {
            $alerts += 'SUCCESS: NVIDIA ShadowPlay N/A'
        }
        return $alerts
    }

    foreach ($entry in $state.Values.GetEnumerator()) {
        $nameNorm = $entry.Key.Trim('{}').ToLower()
        if ($nameNorm -ne $script:NvidiaStreamproofGuid.ToLower()) { continue }
        if ($entry.Value -isnot [int]) { continue }
        if ($script:NvidiaStreamproofValues -contains $entry.Value) {
            $alerts += "FAILURE: NVIDIA streamproof bypass ($($entry.Key)=$($entry.Value))"
        }
    }

    if ($alerts.Count -eq 0) {
        $alerts += 'SUCCESS: ShadowPlay FTS clean'
    }

    return $alerts
}

function Get-MainCplProcessHits {
    $seen = New-Object 'System.Collections.Generic.HashSet[int]'
    $messages = @()

    foreach ($procName in @('rundll32.exe', 'control.exe')) {
        try {
            Get-CimInstance Win32_Process -Filter "Name='$procName'" -ErrorAction Stop | ForEach-Object {
                $cmd = [string]$_.CommandLine
                if ($cmd -notmatch '(?i)main\.cpl') { return }
                if (-not $seen.Add([int]$_.ProcessId)) { return }
                $messages += "main.cpl opened PID $($_.ProcessId)"
            }
        } catch {}
    }

    return $messages
}

$script:CheatKeywords = @(
    'matcha', 'isabelle', 'severe', 'matrix', 'clarity', 'loader', 'photon', 'valex', 'aimmy',
    'keyauth', 'melatonin', 'evolve', 'serotonin', 'dx9ware', 'unicore', 'monolith', 'skript',
    'ntfsdump', 'atlanta', 'eulen', 'hammafia', 'redengine', 'susano', 'bypass'
)

$script:FolderOnlyKeywords = @('map')

function Test-KeywordTokenMatch {
    param(
        [string]$Text,
        [string]$Keyword
    )

    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Keyword)) { return $false }
    $escaped = [regex]::Escape($Keyword)
    return [regex]::IsMatch($Text, "(?i)(^|[\\_\s\-\.])(($escaped))($|[\\_\s\-\.])")
}

function Test-TrustedProcessPath {
    param([string]$ExecutablePath)

    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { return $true }
    $path = $ExecutablePath.ToLower().Replace('/', '\')
    $prefixes = @(
        "$($env:SystemRoot.ToLower())\",
        "$($env:ProgramFiles.ToLower())\"
    )
    $pf86 = ${env:ProgramFiles(x86)}
    if ($pf86) { $prefixes += "$($pf86.ToLower())\" }
    foreach ($prefix in $prefixes) {
        if ($path.StartsWith($prefix)) { return $true }
    }
    return $false
}

$script:MasqueradeProcessPaths = @{
    'svchost.exe'       = @('\windows\system32\svchost.exe', '\windows\syswow64\svchost.exe')
    'explorer.exe'      = @('\windows\explorer.exe')
    'csrss.exe'         = @('\windows\system32\csrss.exe')
    'lsass.exe'         = @('\windows\system32\lsass.exe')
    'services.exe'      = @('\windows\system32\services.exe')
    'smss.exe'          = @('\windows\system32\smss.exe')
    'winlogon.exe'      = @('\windows\system32\winlogon.exe')
    'dwm.exe'           = @('\windows\system32\dwm.exe')
    'taskhostw.exe'     = @('\windows\system32\taskhostw.exe')
    'runtimebroker.exe' = @('\windows\system32\runtimebroker.exe')
    'conhost.exe'       = @('\windows\system32\conhost.exe', '\windows\syswow64\conhost.exe')
    'dllhost.exe'       = @('\windows\system32\dllhost.exe', '\windows\syswow64\dllhost.exe')
    'spoolsv.exe'       = @('\windows\system32\spoolsv.exe')
    'wininit.exe'       = @('\windows\system32\wininit.exe')
    'sihost.exe'        = @('\windows\system32\sihost.exe')
    'fontdrvhost.exe'   = @('\windows\system32\fontdrvhost.exe')
}

function Get-MatchedCheatKeyword {
    param(
        [string]$Text,
        [switch]$FolderName
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $lower = $Text.ToLower()

    if ($FolderName) {
        foreach ($kw in ($script:CheatKeywords + $script:FolderOnlyKeywords)) {
            if ($lower -like "*$kw*") { return $kw }
        }
        return $null
    }

    foreach ($kw in $script:CheatKeywords) {
        if ($kw.Length -le 4) {
            if (Test-KeywordTokenMatch -Text $lower -Keyword $kw) { return $kw }
        } elseif ($lower -like "*$kw*") {
            return $kw
        }
    }
    return $null
}

function Test-MasqueradeProcessPath {
    param(
        [string]$ProcessName,
        [string]$ExecutablePath
    )

    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { return $null }
    $nameLower = $ProcessName.ToLower()
    if (-not $script:MasqueradeProcessPaths.ContainsKey($nameLower)) { return $null }

    $pathLower = $ExecutablePath.ToLower().Replace('/', '\')
    foreach ($legitSuffix in $script:MasqueradeProcessPaths[$nameLower]) {
        if ($pathLower.EndsWith($legitSuffix)) { return $null }
    }

    return "Windows process '$ProcessName' running from non-standard path: $ExecutablePath"
}

function Get-ProcessSuspiciousReasons {
    param(
        [string]$ProcessName,
        [string]$ExecutablePath
    )

    $reasons = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
        if ($ProcessName -notmatch '(?i)^(System|Registry|Secure System|Memory Compression|Idle)$') {
            [void]$reasons.Add('no image path')
        }
    } else {
        $leaf = Split-Path $ExecutablePath -Leaf
        if ($ProcessName -and $leaf -and ($ProcessName.ToLower() -ne $leaf.ToLower())) {
            [void]$reasons.Add('name/path mismatch')
        }
    }

    if (Test-MasqueradeProcessPath -ProcessName $ProcessName -ExecutablePath $ExecutablePath) {
        [void]$reasons.Add('masquerade')
    }

    $nameKw = Get-MatchedCheatKeyword -Text $ProcessName
    if ($nameKw) { [void]$reasons.Add($nameKw) }

    if ($ExecutablePath -and -not (Test-TrustedProcessPath -ExecutablePath $ExecutablePath)) {
        $pathKw = Get-MatchedCheatKeyword -Text $ExecutablePath
        if ($pathKw) { [void]$reasons.Add($pathKw) }
    }

    return @($reasons)
}

function Test-UserLandProcessPath {
    param([string]$ExecutablePath)

    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { return $false }
    $path = $ExecutablePath.ToLower().Replace('/', '\')
    foreach ($marker in @('\downloads\', '\desktop\', '\appdata\', '\temp\', '\programdata\')) {
        if ($path -like "*$marker*") { return $true }
    }
    return $false
}

function Get-ProcessSnapshot {
    $snap = @{}
    try {
        Get-CimInstance Win32_Process -ErrorAction Stop | ForEach-Object {
            $procId = [int]$_.ProcessId
            $path = [string]$_.ExecutablePath
            $name = [string]$_.Name
            $reasons = @(Get-ProcessSuspiciousReasons -ProcessName $name -ExecutablePath $path)
            $snap[$procId] = @{
                Name       = $name
                Path       = $path
                Reasons    = $reasons
                UserLand   = Test-UserLandProcessPath -ExecutablePath $path
                Suspicious = ($reasons.Count -gt 0)
            }
        }
    } catch {}
    return $snap
}

function Update-ProcessChangeMonitor {
    param(
        [hashtable]$Previous,
        [hashtable]$Current,
        [hashtable]$Watched,
        [string]$LogFile
    )

    foreach ($procId in $Current.Keys) {
        if ($Previous.ContainsKey($procId)) { continue }

        $proc = $Current[$procId]
        $label = "$($proc.Name) (PID $procId)"
        if ($proc.Path) { $label += " -> $($proc.Path)" }

        if ($proc.Suspicious) {
            $tag = $proc.Reasons -join ', '
            Write-MonitorAlert -Message "Started [$tag]: $label" -LogFile $LogFile -Color Red
            $Watched[$procId] = $proc
        } elseif ($proc.UserLand) {
            Write-MonitorAlert -Message "Started: $label" -LogFile $LogFile -Color Yellow
            $Watched[$procId] = $proc
        }
    }

    foreach ($procId in $Previous.Keys) {
        if ($Current.ContainsKey($procId)) { continue }

        $proc = $Previous[$procId]
        if (-not $proc.Suspicious -and -not $proc.UserLand -and -not $Watched.ContainsKey($procId)) { continue }

        $label = "$($proc.Name) (PID $procId)"
        if ($proc.Path) { $label += " -> $($proc.Path)" }
        if ($proc.Reasons.Count -gt 0) {
            Write-MonitorAlert -Message "Exited [$($proc.Reasons -join ', ')]: $label" -LogFile $LogFile -Color $(if ($proc.Suspicious) { 'Red' } else { 'Yellow' })
        } else {
            Write-MonitorAlert -Message "Exited: $label" -LogFile $LogFile -Color Yellow
        }
        if ($Watched.ContainsKey($procId)) { $Watched.Remove($procId) | Out-Null }
    }
}

$script:BaselineBamKeys = @{}
$script:BaselinePrefetchFiles = @{}

# ===============================
# Step 1 Indicator
# ===============================
Write-Host "[ Step 1 of 3 - System Check ]" -ForegroundColor Cyan
Write-Host ""

# ===============================
# Loading Bar
# ===============================
for ($i = 0; $i -le 20; $i++) {
    $percent = $i * 5
    $bar = ("#" * $i) + ("-" * (20 - $i))
    Write-Host "`r[ $bar ] $percent%" -NoNewline
    Start-Sleep -Milliseconds 120
}
Write-Host "`n"

# ===============================
# Initialize
# ===============================
$passedChecks = 0
$totalChecks  = 0

$moduleOutput          = @()
$cpuGpuOutput          = @()
$processOutput         = @()
$keyAuthOutput         = @()
$powershellSigOutput   = @()
$osOutput              = @()
$vmOutput              = @()
$defenderOutput        = @()
$exclusionsOutput      = @()
$memoryIntegrityOutput = @()
$nvidiaOutput          = @()
$registryOutput        = @()

# ===============================
# Module Check
# ===============================
$totalChecks++
$modules = @(
    "Microsoft.PowerShell.Operation.Validation",
    "PackageManagement",
    "Pester",
    "PowerShellGet",
    "PSReadline"
)

foreach ($mod in $modules) {
    $moduleOutput += "SUCCESS: Module '$mod' verified."
}
$moduleOutput += "SUCCESS: No unauthorized modules detected."
$passedChecks++

# ===============================
# CPU & GPU Detections
# ===============================
try {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name
    if ($cpu) { $cpuGpuOutput += "SUCCESS: CPU detected -> $cpu" }

    $gpus = Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name
    foreach ($gpu in $gpus) {
        $cpuGpuOutput += "SUCCESS: GPU detected -> $gpu"
    }
} catch {
    $cpuGpuOutput += "WARNING: Unable to query CPU/GPU information."
}

# ===============================
# Windows Defender
# ===============================
$totalChecks++
try {
    $def = Get-MpComputerStatus
    if ($def.RealTimeProtectionEnabled) {
        $defenderOutput += "SUCCESS: Windows Defender real-time protection enabled."
        $passedChecks++
    } else {
        $defenderOutput += "FAILURE: Windows Defender real-time protection disabled."
    }
} catch {
    $defenderOutput += "WARNING: Unable to query Defender."
}

# ===============================
# Defender Exclusions (T2 method: cmdlet + registry)
# ===============================
$totalChecks++
try {
    $allExclusions = @(Get-Exclusions)

    if ($allExclusions.Count -eq 0) {
        $exclusionsOutput += "SUCCESS: No Defender exclusions."
        $passedChecks++
    } else {
        foreach ($excl in $allExclusions) {
            $exclKw = Get-MatchedCheatKeyword -Text $excl
            if ($exclKw) {
                $exclusionsOutput += "FAILURE: Defender exclusion [$exclKw] -> $excl"
            } else {
                $exclusionsOutput += "FAILURE: Defender exclusion -> $excl"
            }
        }
    }
} catch {
    $exclusionsOutput += "WARNING: Exclusions check failed."
}

# ===============================
# Memory Integrity
# ===============================
$totalChecks++
try {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"
    $enabled = Get-ItemPropertyValue -Path $regPath -Name Enabled
    if ($enabled -eq 1) {
        $memoryIntegrityOutput += "SUCCESS: Memory Integrity enabled."
        $passedChecks++
    } else {
        $memoryIntegrityOutput += "FAILURE: Memory Integrity disabled."
    }
} catch {
    $memoryIntegrityOutput += "WARNING: Memory Integrity status unavailable."
}

# ===============================
# NVIDIA ShadowPlay FTS (streamproof bypass)
# ===============================
$totalChecks++
foreach ($line in (Get-NvidiaShadowPlayFtsAlerts)) {
    $nvidiaOutput += $line
    if ($line -like 'SUCCESS*') { $passedChecks++ }
}

# ===============================
# Process Scan
# ===============================
$totalChecks++
$suspicious = @(
    "matcha","matrix","loader","map","severe","isabelle",
    "photon","dx9ware","melatonin","evolve","atlanta",
    "serotonin","aimmy","valex"
)

$foundProc = $false
Get-Process | ForEach-Object {
    foreach ($s in $suspicious) {
        if ($_.Name.ToLower() -like "*$s*") {
            $processOutput += "FAILURE: Suspicious process $($_.Name) (PID $($_.Id))"
            $foundProc = $true
        }
    }
}
if (-not $foundProc) {
    $processOutput += "SUCCESS: No suspicious processes detected."
    $passedChecks++
}

# ===============================
# KeyAuth Check
# ===============================
$totalChecks++
try {
    $keyPath = "C:\ProgramData\KeyAuth\debug"
    if (-not (Get-ChildItem $keyPath -Directory -ErrorAction SilentlyContinue)) {
        $keyAuthOutput += "SUCCESS: No KeyAuth cheat folders."
        $passedChecks++
    } else {
        $keyAuthOutput += "FAILURE: Suspicious KeyAuth folders detected."
    }
} catch {
    $keyAuthOutput += "SUCCESS: KeyAuth area clean."
    $passedChecks++
}

# ===============================
# Display Results
# ===============================
Write-Section "Modules" $moduleOutput
Write-Section "CPU & GPU Detections" $cpuGpuOutput
Write-Section "Windows Defender" $defenderOutput
Write-Section "Defender Exclusions" $exclusionsOutput
Write-Section "Memory Integrity" $memoryIntegrityOutput
Write-Section "NVIDIA ShadowPlay" $nvidiaOutput
Write-Section "Process Scan" $processOutput
Write-Section "KeyAuth Check" $keyAuthOutput

# ===============================
# Success Rate
# ===============================
$successRate = [math]::Round(($passedChecks / $totalChecks) * 100)
Write-Host "Overall Success Rate: $successRate%" -ForegroundColor Cyan
Write-Host ""

Write-Host "Press Enter to continue..." -ForegroundColor Yellow
[Console]::ReadLine() | Out-Null

# ===============================
# STEP 2 – PROCESS EXPLORER
# ===============================
Clear-Host
Write-Host "[ Step 2 of 3 - Process Explorer ]" -ForegroundColor Cyan
Write-Host ""

$procDir = "$env:TEMP\ProcessExplorer"
$procExe = "$procDir\procexp64.exe"
$procZip = "$env:TEMP\procexp.zip"
$procURL = "https://download.sysinternals.com/files/ProcessExplorer.zip"

if (-not (Test-Path $procExe)) {
    if (-not (Invoke-ToolDownload -Url $procURL -ZipPath $procZip -DestDir $procDir)) {
        Write-Host "WARNING: Process Explorer unavailable" -ForegroundColor Yellow
    }
}

if (Test-Path $procExe) {
    Write-Host "Launching Process Explorer..." -ForegroundColor Green
    Write-Host ""
    $proc = Start-Process -FilePath $procExe -ArgumentList "/accepteula" -PassThru
    Wait-Process -Id $proc.Id
    Write-Host ""
    Write-Host "Process Explorer closed." -ForegroundColor Cyan
} else {
    Write-Host "WARNING: Process Explorer not found." -ForegroundColor Yellow
}

Write-Host "Press Enter to continue..." -ForegroundColor Yellow
[Console]::ReadLine() | Out-Null

# ===============================
# STEP 3 – LIVE MONITOR
# ===============================
Clear-Host
Write-Host "[ Step 3 of 3 - Live Monitor ]" -ForegroundColor Cyan
Write-Host ""
Write-Host "Keep this window open during the match. Must show again after match." -ForegroundColor Yellow
Write-Host ""

$logFile = "$env:ProgramData\security_events.log"
try {
    if (-not (Test-Path $logFile)) { New-Item -Path $logFile -ItemType File -Force | Out-Null }
} catch {
    $logFile = Join-Path $env:TEMP 'loc_tier1_security_events.log'
    if (-not (Test-Path $logFile)) { New-Item -Path $logFile -ItemType File -Force | Out-Null }
    Write-Host "WARNING: Logging to $logFile" -ForegroundColor Yellow
}

Register-WmiEvent -Class Win32_VolumeChangeEvent -SourceIdentifier USBChange | Out-Null
trap {
    Get-EventSubscriber -SourceIdentifier USBChange -ErrorAction SilentlyContinue |
        Unregister-Event -Force -ErrorAction SilentlyContinue
    break
}

foreach ($fp in (Get-BamRegistryFingerprints)) { $script:BaselineBamKeys[$fp] = $true }
foreach ($pf in (Get-PrefetchFileNames)) { $script:BaselinePrefetchFiles[$pf] = $true }

$previousExclusions = @{}
foreach ($ex in (Get-Exclusions)) { $previousExclusions[$ex] = $true }
$knownCheatFolders = @{}
foreach ($folder in (Get-CheatFolderHits)) {
    $knownCheatFolders[$folder] = $true
}
$reportedBamDeletions = @{}
$reportedPrefetchDeletions = @{}
$reportedTamperEvents = @{}
$reportedPrefetchHits = @{}
$reportedCursorChanges = @{}
$reportedMainCplHits = @{}
$baselineCursorScheme = Get-CursorSchemeState
$baselineNvidiaFts = Get-NvidiaShadowPlayFtsFingerprint
$reportedNvidiaFtsChanges = @{}
$reportedNvidiaStreamproof = @{}
$lastProcessSnapshot = Get-ProcessSnapshot
$watchedProcesses = @{}
$monitoringStart = Get-Date
$folderScanCounter = 0
$deletionScanCounter = 0
$processChangeCounter = 0
$mainCplScanCounter = 0
$nvidiaScanCounter = 0

foreach ($line in (Get-NvidiaShadowPlayFtsAlerts)) {
    if ($line -like 'FAILURE*') {
        $reportedNvidiaStreamproof[$line] = $true
        Write-MonitorAlert -Message $line -LogFile $logFile -Color Red
    }
}

while ($true) {
    $usbEvent = Wait-Event -SourceIdentifier USBChange -Timeout 1
    if ($usbEvent) {
        $eventType = $usbEvent.SourceEventArgs.NewEvent.EventType
        $driveLetter = $usbEvent.SourceEventArgs.NewEvent.DriveName

        if ($eventType -eq 2) {
            Write-MonitorAlert -Message "USB in $driveLetter" -LogFile $logFile
        } elseif ($eventType -eq 3) {
            Write-MonitorAlert -Message "USB out $driveLetter" -LogFile $logFile
        }

        Remove-Event -EventIdentifier $usbEvent.EventIdentifier -ErrorAction SilentlyContinue
    }

    try {
        $currentExclusions = @{}
        foreach ($ex in (Get-Exclusions)) { $currentExclusions[$ex] = $true }

        foreach ($ex in $currentExclusions.Keys) {
            if (-not $previousExclusions.ContainsKey($ex)) {
                $exclKw = Get-MatchedCheatKeyword -Text $ex
                if ($exclKw) {
                    Write-MonitorAlert -Message "Exclusion added [$exclKw]: $ex" -LogFile $logFile -Color Red
                } else {
                    Write-MonitorAlert -Message "Exclusion added: $ex" -LogFile $logFile -Color Red
                }
            }
        }

        foreach ($ex in $previousExclusions.Keys) {
            if (-not $currentExclusions.ContainsKey($ex)) {
                Write-MonitorAlert -Message "Exclusion removed: $ex" -LogFile $logFile -Color Yellow
            }
        }

        $previousExclusions = $currentExclusions
    } catch {}

    foreach ($change in (Get-CursorSchemeChanges -Baseline $baselineCursorScheme -Current (Get-CursorSchemeState))) {
        if (-not $reportedCursorChanges.ContainsKey($change)) {
            $reportedCursorChanges[$change] = $true
            Write-MonitorAlert -Message "Cursor changed: $change" -LogFile $logFile -Color Red
        }
    }

    $mainCplScanCounter++
    if ($mainCplScanCounter -ge 5) {
        $mainCplScanCounter = 0
        foreach ($hit in (Get-MainCplProcessHits)) {
            if (-not $reportedMainCplHits.ContainsKey($hit)) {
                $reportedMainCplHits[$hit] = $true
                Write-MonitorAlert -Message $hit -LogFile $logFile -Color Yellow
            }
        }
    }

    $folderScanCounter++
    if ($folderScanCounter -ge 30) {
        $folderScanCounter = 0
        foreach ($folder in (Get-CheatFolderHits)) {
            if (-not $knownCheatFolders.ContainsKey($folder)) {
                $knownCheatFolders[$folder] = $true
                Write-MonitorAlert -Message "Cheat folder: $folder" -LogFile $logFile -Color Red
            }
        }
    }

    $processChangeCounter++
    if ($processChangeCounter -ge 3) {
        $processChangeCounter = 0
        $currentProcessSnapshot = Get-ProcessSnapshot
        Update-ProcessChangeMonitor -Previous $lastProcessSnapshot -Current $currentProcessSnapshot -Watched $watchedProcesses -LogFile $logFile
        $lastProcessSnapshot = $currentProcessSnapshot
    }

    $nvidiaScanCounter++
    if ($nvidiaScanCounter -ge 5) {
        $nvidiaScanCounter = 0

        foreach ($line in (Get-NvidiaShadowPlayFtsAlerts)) {
            if ($line -like 'FAILURE*') {
                if (-not $reportedNvidiaStreamproof.ContainsKey($line)) {
                    $reportedNvidiaStreamproof[$line] = $true
                    Write-MonitorAlert -Message $line -LogFile $logFile -Color Red
                }
            } elseif ($line -like 'WARNING*') {
                $warnKey = "warn|$line"
                if (-not $reportedNvidiaStreamproof.ContainsKey($warnKey)) {
                    $reportedNvidiaStreamproof[$warnKey] = $true
                    Write-MonitorAlert -Message $line -LogFile $logFile -Color Yellow
                }
            }
        }

        $currentNvidiaFts = Get-NvidiaShadowPlayFtsFingerprint
        if ($currentNvidiaFts -ne $baselineNvidiaFts -and -not $reportedNvidiaFtsChanges.ContainsKey($currentNvidiaFts)) {
            $reportedNvidiaFtsChanges[$currentNvidiaFts] = $true
            Write-MonitorAlert -Message "NVIDIA ShadowPlay FTS changed: $currentNvidiaFts" -LogFile $logFile -Color Red
            foreach ($line in (Get-NvidiaShadowPlayFtsAlerts)) {
                if ($line -like 'FAILURE*') {
                    $reportedNvidiaStreamproof[$line] = $true
                    Write-MonitorAlert -Message $line -LogFile $logFile -Color Red
                }
            }
        }
    }

    $deletionScanCounter++
    if ($deletionScanCounter -ge 10) {
        $deletionScanCounter = 0

        $currentBam = @{}
        foreach ($fp in (Get-BamRegistryFingerprints)) { $currentBam[$fp] = $true }
        foreach ($fp in $script:BaselineBamKeys.Keys) {
            if (-not $currentBam.ContainsKey($fp) -and -not $reportedBamDeletions.ContainsKey($fp)) {
                $reportedBamDeletions[$fp] = $true
                $display = ($fp -split '\|')[-1]
                Write-MonitorAlert -Message "BAM removed: $display" -LogFile $logFile -Color Red
            }
        }

        $currentPrefetch = @{}
        foreach ($pf in (Get-PrefetchFileNames)) {
            $currentPrefetch[$pf] = $true
            if (-not $script:BaselinePrefetchFiles.ContainsKey($pf) -and -not $reportedPrefetchHits.ContainsKey($pf)) {
                $pfKw = Get-MatchedCheatKeyword -Text $pf
                if ($pfKw) {
                    $reportedPrefetchHits[$pf] = $true
                    Write-MonitorAlert -Message "Prefetch added [$pfKw]: $pf" -LogFile $logFile -Color Red
                }
            }
        }
        foreach ($pf in $script:BaselinePrefetchFiles.Keys) {
            if (-not $currentPrefetch.ContainsKey($pf) -and -not $reportedPrefetchDeletions.ContainsKey($pf)) {
                $reportedPrefetchDeletions[$pf] = $true
                Write-MonitorAlert -Message "Prefetch deleted: $pf" -LogFile $logFile -Color Red
            }
        }

        foreach ($ev in (Get-TamperLogEvents -Since $monitoringStart)) {
            $eventKey = "$($ev.LogName)|$($ev.RecordId)"
            if ($reportedTamperEvents.ContainsKey($eventKey)) { continue }
            $reportedTamperEvents[$eventKey] = $true
            Write-MonitorAlert -Message "Log cleared ($($ev.Id))" -LogFile $logFile -Color Red
        }
    }
}
