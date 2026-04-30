[CmdletBinding()]
param(
    [ValidateSet("Download", "Check", "Install", "Verify")]
    [string]$Mode,

    [string]$WorkspaceRoot,
    [switch]$Yes,
    [switch]$NonInteractive,
    [switch]$Force,
    [switch]$RecreateVenv,

    [string]$Profile,
    [switch]$ReuseVenv,
    [switch]$IncludeGit,
    [switch]$IncludeCudaToolkit,
    [switch]$IncludeVisualization
)

$Script:InitialBoundParameters = $PSBoundParameters
Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$Script:ScriptVersion = "0.1.0"
$Script:SchemaVersion = 1
$Script:Phase = 1
$Script:Profile = "Research"
$Script:PythonMajorMinor = "3.11"
$Script:PythonAbi = "cp311"
$Script:Platform = "win_amd64"
$Script:TorchCudaTag = "cu128"
$Script:VenvName = "dl-py311-cu128"
$Script:PackageRoot = $PSScriptRoot
$Script:TranscriptStarted = $false

function Write-Info {
    param([string]$Message)
    Write-Host "[信息] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[警告] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[失败] $Message" -ForegroundColor Red
}

function Join-PackagePath {
    param([Parameter(Mandatory = $true)][string[]]$Parts)
    $path = $Script:PackageRoot
    foreach ($part in $Parts) {
        $path = Join-Path -Path $path -ChildPath $part
    }
    return $path
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-Timestamp {
    return (Get-Date).ToString("yyyyMMdd_HHmmss")
}

function Get-IsoTimestamp {
    return (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
}

function Start-RunLog {
    param([string]$RunMode)
    $logs = Join-PackagePath @("logs")
    Ensure-Directory $logs
    $logPath = Join-Path $logs ("{0}_{1}.log" -f (Get-Timestamp), $RunMode)
    Start-Transcript -Path $logPath -Append | Out-Null
    $Script:TranscriptStarted = $true
    Write-Info "日志文件：$logPath"
}

function Stop-RunLog {
    if ($Script:TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
            # Transcript may already be stopped by the host.
        }
    }
}

function Confirm-Continue {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Expected = "y"
    )
    if ($Yes) {
        return $true
    }
    if ($NonInteractive) {
        throw "非交互模式需要确认：$Message"
    }
    $answer = Read-Host "$Message`n请输入 $Expected 确认"
    if ($answer -ne $Expected) {
        throw "用户未确认，已停止。"
    }
    return $true
}

function Reject-UnsupportedPhase2Options {
    $unsupported = @()
    foreach ($name in @("Profile", "ReuseVenv", "IncludeGit", "IncludeCudaToolkit", "IncludeVisualization")) {
        if ($Script:InitialBoundParameters.ContainsKey($name)) {
            $unsupported += "-$name"
        }
    }
    if ($unsupported.Count -gt 0) {
        throw ("这些选项属于第二阶段，当前第一版暂不可用：{0}" -f ($unsupported -join ", "))
    }
}

function Show-MainMenu {
    Write-Host ""
    Write-Host "Win10 + RTX 3090 深度学习离线环境工具" -ForegroundColor Green
    Write-Host "第一版只支持固定 Research 环境：Python 3.11 + PyTorch CUDA 12.8"
    Write-Host ""
    Write-Host "[1] Download  在联网电脑下载离线包"
    Write-Host "[2] Check     检查离线包完整性（只读，不修改文件）"
    Write-Host "[3] Install   在离线电脑安装环境"
    Write-Host "[4] Verify    验证 GPU / PyTorch CUDA"
    Write-Host "[5] Exit      退出"
    Write-Host ""
    $choice = Read-Host "请选择操作"
    switch ($choice) {
        "1" { return "Download" }
        "2" { return "Check" }
        "3" { return "Install" }
        "4" { return "Verify" }
        "5" { return "" }
        default { throw "无效选择：$choice" }
    }
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "文件不存在：$Path"
    }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $dir = Split-Path -Parent $Path
    Ensure-Directory $dir
    $tmp = "$Path.tmp"
    $json = $Object | ConvertTo-Json -Depth 30
    Set-Content -LiteralPath $tmp -Value $json -Encoding UTF8
    $null = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8 | ConvertFrom-Json

    if (Test-Path -LiteralPath $Path) {
        $backupDir = Join-PackagePath @("backups", ("{0}-manifest" -f (Get-Timestamp)))
        Ensure-Directory $backupDir
        Copy-Item -LiteralPath $Path -Destination (Join-Path $backupDir (Split-Path -Leaf $Path)) -Force
    }

    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-RelativePathFromPackage {
    param([Parameter(Mandatory = $true)][string]$FullPath)
    $root = [System.IO.Path]::GetFullPath($Script:PackageRoot).TrimEnd("\") + "\"
    $full = [System.IO.Path]::GetFullPath($FullPath)
    $rootUri = New-Object System.Uri($root)
    $fileUri = New-Object System.Uri($full)
    return ([System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($fileUri).ToString())).Replace("/", "\")
}

function Resolve-PackageRelativePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $normalized = $RelativePath.Replace("/", "\")
    return Join-Path $Script:PackageRoot $normalized
}

function Get-ManifestPath {
    return (Join-PackagePath @("manifest.json"))
}

function Get-ConfigPath {
    return (Join-PackagePath @("config.json"))
}

function Get-InstallStatePath {
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Join-Path (Join-Path $Root "state") "install_state.json")
}

function Get-FailedInstallStatePath {
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Join-Path (Join-Path $Root "state") "install_state.failed.json")
}

function Get-VenvPath {
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Join-Path (Join-Path $Root "envs") $Script:VenvName)
}

function Get-VenvPythonPath {
    param([Parameter(Mandatory = $true)][string]$VenvPath)
    return (Join-Path (Join-Path $VenvPath "Scripts") "python.exe")
}

function Get-DriveInfoForPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($full)
    $driveName = $root.TrimEnd("\").TrimEnd(":")
    $psDrive = Get-PSDrive -Name $driveName -ErrorAction Stop
    $fileSystem = ""
    try {
        $fileSystem = (Get-Volume -DriveLetter $driveName -ErrorAction Stop).FileSystem
    }
    catch {
        $fileSystem = "Unknown"
    }
    return [pscustomobject]@{
        Root       = $root
        DriveName  = $driveName
        FreeGB     = [math]::Round($psDrive.Free / 1GB, 2)
        FileSystem = $fileSystem
    }
}

function Test-PathWritable {
    param([Parameter(Mandatory = $true)][string]$Path)
    Ensure-Directory $Path
    $testFile = Join-Path $Path (".write-test-{0}.tmp" -f ([guid]::NewGuid().ToString("N")))
    try {
        Set-Content -LiteralPath $testFile -Value "ok" -Encoding ASCII
        Remove-Item -LiteralPath $testFile -Force
        return $true
    }
    catch {
        return $false
    }
}

function Assert-StorageReady {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$MinFreeGB
    )
    Ensure-Directory $Path
    if (-not (Test-PathWritable $Path)) {
        throw "目录不可写：$Path"
    }
    $drive = Get-DriveInfoForPath $Path
    Write-Info ("目标磁盘：{0} 文件系统：{1} 可用空间：{2} GB" -f $drive.Root, $drive.FileSystem, $drive.FreeGB)
    if ($drive.FileSystem -eq "FAT32") {
        throw "当前磁盘是 FAT32，不适合离线深度学习包。Windows 间使用建议 NTFS；需要跨平台再考虑 exFAT。"
    }
    if ($drive.FreeGB -lt $MinFreeGB) {
        throw "空间不足：至少需要 $MinFreeGB GB，当前只有 $($drive.FreeGB) GB。"
    }
}

function New-CheckResult {
    return [pscustomobject]@{
        Errors   = New-Object 'System.Collections.Generic.List[string]'
        Warnings = New-Object 'System.Collections.Generic.List[string]'
        Infos    = New-Object 'System.Collections.Generic.List[string]'
    }
}

function Add-CheckError {
    param($Result, [string]$Message)
    $Result.Errors.Add($Message) | Out-Null
}

function Add-CheckWarning {
    param($Result, [string]$Message)
    $Result.Warnings.Add($Message) | Out-Null
}

function Add-CheckInfo {
    param($Result, [string]$Message)
    $Result.Infos.Add($Message) | Out-Null
}

function Get-PropertyValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) {
        return $null
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        return $null
    }
    return $prop.Value
}

function Parse-WheelFileName {
    param([Parameter(Mandatory = $true)][string]$FileName)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    if ($base -match "^(?<name>.+?)-(?<version>\d[^-]*)-") {
        $name = ($matches["name"] -replace "[-_.]+", "-").ToLowerInvariant()
        return [pscustomobject]@{
            Package = $name
            Version = $matches["version"]
        }
    }
    return $null
}

function New-ManifestFileEntry {
    param(
        [Parameter(Mandatory = $true)][string]$FullPath,
        [Parameter(Mandatory = $true)][string]$Component,
        [Parameter(Mandatory = $true)][string]$Group,
        [Parameter(Mandatory = $true)][string]$Kind,
        [bool]$Required = $true,
        [string]$Profile = "Research",
        [string]$SourceUrl = "",
        [string]$Source = "download"
    )
    $item = Get-Item -LiteralPath $FullPath
    return [ordered]@{
        component    = $Component
        group        = $Group
        kind         = $Kind
        required     = $Required
        profile      = $Profile
        path         = Get-RelativePathFromPackage $item.FullName
        fileName     = $item.Name
        size         = [int64]$item.Length
        sha256       = Get-Sha256 $item.FullName
        sourceUrl    = $SourceUrl
        source       = $Source
        downloadedAt = Get-IsoTimestamp
    }
}

function Test-OfflinePackage {
    param([switch]$AllowIncomplete)
    $result = New-CheckResult
    $manifestPath = Get-ManifestPath
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Add-CheckError $result "manifest.json 不存在。请先在联网电脑运行 Download。"
        return $result
    }

    try {
        $manifest = Read-JsonFile $manifestPath
    }
    catch {
        Add-CheckError $result "manifest.json 无法解析：$($_.Exception.Message)"
        return $result
    }

    if ((Get-PropertyValue $manifest "schemaVersion") -ne $Script:SchemaVersion) {
        Add-CheckError $result "schemaVersion 不匹配，当前脚本只支持 schemaVersion = 1。"
    }
    if ((Get-PropertyValue $manifest "phase") -ne $Script:Phase) {
        Add-CheckError $result "phase 不匹配，当前第一版脚本只支持 phase = 1。"
    }
    $optional = @(Get-PropertyValue $manifest "optionalComponents")
    if ($optional.Count -ne 0) {
        Add-CheckError $result "第一阶段不支持可选组件，manifest.optionalComponents 必须为空数组。"
    }
    if (-not $AllowIncomplete) {
        if ((Get-PropertyValue $manifest "packageStatus") -ne "complete") {
            Add-CheckError $result "离线包状态不是 complete，当前状态：$(Get-PropertyValue $manifest 'packageStatus')。Install 只接受完整离线包。"
        }
    }

    $lockFiles = @(Get-PropertyValue $manifest "lockFiles")
    foreach ($lock in $lockFiles) {
        $lockPath = Resolve-PackageRelativePath $lock.path
        if (-not (Test-Path -LiteralPath $lockPath)) {
            Add-CheckError $result "缺少 lock 文件：$($lock.path)"
            continue
        }
        $actual = Get-Sha256 $lockPath
        if ($actual -ne $lock.sha256) {
            Add-CheckError $result "lock 文件 SHA256 不一致：$($lock.path)"
        }
    }

    $files = @(Get-PropertyValue $manifest "files")
    if ($files.Count -eq 0) {
        Add-CheckError $result "manifest.files 为空。"
    }

    $requiredComponents = @(
        "python-installer",
        "vc-runtime",
        "nvidia-driver",
        "torch",
        "torchvision",
        "torchaudio",
        "torch-lock",
        "research-lock",
        "verify-script"
    )
    foreach ($component in $requiredComponents) {
        $matches = @($files | Where-Object { $_.component -eq $component -and $_.required -eq $true })
        if ($matches.Count -eq 0) {
            Add-CheckError $result "必需组件没有登记到 manifest.files：$component"
        }
    }
    $researchWheels = @($files | Where-Object { $_.group -eq "research" -and $_.kind -eq "wheel" })
    if ($researchWheels.Count -eq 0) {
        Add-CheckError $result "没有找到 Research wheels。"
    }

    foreach ($entry in $files) {
        $relative = [string]$entry.path
        if ([string]::IsNullOrWhiteSpace($relative)) {
            Add-CheckError $result "manifest.files 中存在空 path。"
            continue
        }
        $full = Resolve-PackageRelativePath $relative
        if ($relative.ToLowerInvariant().EndsWith(".tar.gz") -or $relative.ToLowerInvariant().EndsWith(".zip")) {
            Add-CheckError $result "第一阶段不接受源码包或 zip 包：$relative"
        }
        if (-not (Test-Path -LiteralPath $full)) {
            Add-CheckError $result "文件不存在：$relative"
            continue
        }
        $item = Get-Item -LiteralPath $full
        if ([int64]$item.Length -ne [int64]$entry.size) {
            Add-CheckError $result "文件大小不一致：$relative"
            continue
        }
        $actualHash = Get-Sha256 $full
        if ($actualHash -ne $entry.sha256) {
            Add-CheckError $result "SHA256 不一致：$relative"
        }
    }

    $wheelFiles = Get-ChildItem -LiteralPath (Join-PackagePath @("wheels")) -Recurse -File -Filter "*.whl" -ErrorAction SilentlyContinue
    $fileHashes = @{}
    $packageVersions = @{}
    $packageVersionFiles = @{}
    foreach ($wheel in $wheelFiles) {
        $hash = Get-Sha256 $wheel.FullName
        if ($fileHashes.ContainsKey($wheel.Name) -and $fileHashes[$wheel.Name] -ne $hash) {
            Add-CheckError $result "发现同名但 SHA256 不同的 wheel：$($wheel.Name)"
        }
        else {
            $fileHashes[$wheel.Name] = $hash
        }

        $parsed = Parse-WheelFileName $wheel.Name
        if ($null -ne $parsed) {
            if (-not $packageVersions.ContainsKey($parsed.Package)) {
                $packageVersions[$parsed.Package] = New-Object 'System.Collections.Generic.HashSet[string]'
            }
            $null = $packageVersions[$parsed.Package].Add($parsed.Version)
            $pvKey = "$($parsed.Package)==$($parsed.Version)"
            if (-not $packageVersionFiles.ContainsKey($pvKey)) {
                $packageVersionFiles[$pvKey] = New-Object 'System.Collections.Generic.HashSet[string]'
            }
            $null = $packageVersionFiles[$pvKey].Add($wheel.Name)
        }
    }
    foreach ($pkg in $packageVersions.Keys) {
        if ($packageVersions[$pkg].Count -gt 1) {
            Add-CheckError $result ("同一个包出现多个版本：{0} -> {1}" -f $pkg, (($packageVersions[$pkg] | Sort-Object) -join ", "))
        }
    }
    foreach ($pv in $packageVersionFiles.Keys) {
        if ($packageVersionFiles[$pv].Count -gt 1) {
            Add-CheckWarning $result ("同包同版本出现多个 wheel 文件：{0} -> {1}" -f $pv, (($packageVersionFiles[$pv] | Sort-Object) -join ", "))
        }
    }

    if ($result.Errors.Count -eq 0) {
        Add-CheckInfo $result "离线包校验通过。"
    }
    return $result
}

function Write-CheckReport {
    param($Result)
    Write-Host ""
    Write-Host "检查结果" -ForegroundColor Green
    foreach ($info in $Result.Infos) {
        Write-Ok $info
    }
    foreach ($warning in $Result.Warnings) {
        Write-Warn $warning
    }
    foreach ($errorMessage in $Result.Errors) {
        Write-Fail $errorMessage
    }
    if ($Result.Errors.Count -gt 0) {
        throw "Check 未通过，共 $($Result.Errors.Count) 个错误。"
    }
}

function Invoke-CheckMode {
    Write-Info "开始只读检查离线包。Check 不会修改 manifest，也不会登记或修复文件。"
    $result = Test-OfflinePackage
    Write-CheckReport $result
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )
    Write-Info ("执行命令：{0} {1}" -f $FilePath, ($Arguments -join " "))
    & $FilePath @Arguments 2>&1 | ForEach-Object { Write-Host $_ }
    $exitCode = $LASTEXITCODE
    Write-Info "命令退出码：$exitCode"
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "外部命令执行失败：$FilePath，退出码：$exitCode"
    }
    return $exitCode
}

function Get-CommandPath {
    param([Parameter(Mandatory = $true)][string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        return $null
    }
    return $cmd.Source
}

function Test-PythonCandidate {
    param([Parameter(Mandatory = $true)][string]$PythonPath)
    if (-not (Test-Path -LiteralPath $PythonPath)) {
        return $null
    }
    try {
        $code = "import sys, struct; print(f'{sys.version_info.major}.{sys.version_info.minor}|{struct.calcsize('P')*8}|{sys.executable}')"
        $output = & $PythonPath -c $code 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($output)) {
            return $null
        }
        $parts = ($output | Select-Object -First 1).Split("|")
        return [pscustomobject]@{
            Path         = $parts[2]
            MajorMinor   = $parts[0]
            Architecture = [int]$parts[1]
        }
    }
    catch {
        return $null
    }
}

function Find-Python311 {
    $candidates = New-Object 'System.Collections.Generic.List[string]'

    $py = Get-CommandPath "py"
    if ($null -ne $py) {
        try {
            $path = & $py -3.11 -c "import sys; print(sys.executable)" 2>$null
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($path)) {
                $candidates.Add(($path | Select-Object -First 1)) | Out-Null
            }
        }
        catch {
        }
    }

    $python = Get-CommandPath "python"
    if ($null -ne $python) {
        $candidates.Add($python) | Out-Null
    }

    foreach ($reg in @(
            "HKLM:\SOFTWARE\Python\PythonCore\3.11\InstallPath",
            "HKCU:\SOFTWARE\Python\PythonCore\3.11\InstallPath",
            "HKLM:\SOFTWARE\WOW6432Node\Python\PythonCore\3.11\InstallPath",
            "HKCU:\SOFTWARE\WOW6432Node\Python\PythonCore\3.11\InstallPath"
        )) {
        try {
            $key = Get-Item -LiteralPath $reg -ErrorAction Stop
            $installPath = $key.GetValue("")
            if (-not [string]::IsNullOrWhiteSpace($installPath)) {
                $candidates.Add((Join-Path $installPath "python.exe")) | Out-Null
            }
        }
        catch {
        }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        $info = Test-PythonCandidate $candidate
        if ($null -ne $info -and $info.MajorMinor -eq "3.11" -and $info.Architecture -eq 64) {
            try {
                & $info.Path -m pip --version | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    continue
                }
                & $info.Path -m venv --help | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    continue
                }
                return $info
            }
            catch {
            }
        }
    }
    return $null
}

function Resolve-WorkspaceRoot {
    param([string]$InputRoot, [switch]$Create)
    $root = $InputRoot
    if ([string]::IsNullOrWhiteSpace($root)) {
        if ($NonInteractive -or $Yes) {
            $root = "D:\AI"
        }
        else {
            $answer = Read-Host "请输入 AI 工作区地址，直接回车默认 D:\AI"
            if ([string]::IsNullOrWhiteSpace($answer)) {
                $root = "D:\AI"
            }
            else {
                $root = $answer
            }
        }
    }
    $root = [System.IO.Path]::GetFullPath($root)
    if ($root.IndexOfAny([System.IO.Path]::GetInvalidPathChars()) -ge 0) {
        throw "工作区路径不合法：$root"
    }
    if ($root.Contains(" ")) {
        Write-Warn "工作区路径包含空格。Windows 下建议使用 D:\AI 或 E:\AI 这类简单路径。"
    }
    if ($Create) {
        Ensure-Directory $root
    }
    return $root.TrimEnd("\")
}

function Test-VcRuntimeHeuristic {
    $dlls = @(
        "$env:SystemRoot\System32\vcruntime140.dll",
        "$env:SystemRoot\System32\vcruntime140_1.dll",
        "$env:SystemRoot\System32\msvcp140.dll"
    )
    foreach ($dll in $dlls) {
        if (-not (Test-Path -LiteralPath $dll)) {
            return $false
        }
    }
    return $true
}

function Get-NvidiaSmiPath {
    return (Get-CommandPath "nvidia-smi")
}

function Get-NvidiaGpuNames {
    $nvidiaSmi = Get-NvidiaSmiPath
    if ($null -eq $nvidiaSmi) {
        return @()
    }
    $names = & $nvidiaSmi --query-gpu=name --format=csv,noheader 2>$null
    if ($LASTEXITCODE -ne 0) {
        return @()
    }
    return @($names)
}

function Assert-TargetGpu {
    $nvidiaSmi = Get-NvidiaSmiPath
    if ($null -eq $nvidiaSmi) {
        $driverDir = Join-PackagePath @("downloads", "drivers")
        throw "没有检测到 nvidia-smi。请先手动安装 $driverDir 中的 NVIDIA 驱动并重启。"
    }
    $names = Get-NvidiaGpuNames
    if ($names.Count -eq 0) {
        throw "nvidia-smi 存在，但没有检测到 NVIDIA GPU。"
    }
    Write-Info ("当前检测到 GPU：{0}" -f ($names -join "; "))
    $is3090 = $false
    foreach ($name in $names) {
        if ($name -match "3090") {
            $is3090 = $true
        }
    }
    if (-not $is3090) {
        if ($NonInteractive) {
            throw "当前 GPU 不是 RTX 3090，非交互模式下停止安装。"
        }
        Write-Warn "当前 GPU 不是 RTX 3090。本脚本仍可能可用，但这不是原始目标机器。"
        Confirm-Continue "确认继续安装吗？" "y" | Out-Null
    }
}

function Assert-VenvDeleteSafe {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$VenvPath
    )
    $expected = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $WorkspaceRoot "envs") $Script:VenvName)).TrimEnd("\")
    $actual = [System.IO.Path]::GetFullPath($VenvPath).TrimEnd("\")
    if ($expected -ne $actual) {
        throw "拒绝删除虚拟环境：路径不在预期位置。预期 $expected，实际 $actual"
    }
    $leaf = Split-Path -Leaf $actual
    $hasMarker = (Test-Path -LiteralPath (Join-Path $actual ".offline_dl_installing")) -or (Test-Path -LiteralPath (Join-Path $actual ".offline_dl_ready"))
    if ($leaf -ne $Script:VenvName -and -not $hasMarker) {
        throw "该目录不像本脚本创建的虚拟环境，为防止误删，拒绝自动删除：$actual"
    }
}

function New-ActivationScripts {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$VenvPath
    )
    $cacheRoot = Join-Path $WorkspaceRoot "cache"
    $hf = Join-Path $cacheRoot "huggingface"
    $torch = Join-Path $cacheRoot "torch"
    $pip = Join-Path $cacheRoot "pip"
    foreach ($dir in @($hf, $torch, $pip)) {
        Ensure-Directory $dir
    }

    $ps1 = Join-Path $WorkspaceRoot "activate-dl.ps1"
    $bat = Join-Path $WorkspaceRoot "activate-dl.bat"
    $activatePs = Join-Path (Join-Path $VenvPath "Scripts") "Activate.ps1"
    $activateBat = Join-Path (Join-Path $VenvPath "Scripts") "activate.bat"

    $psContent = @"
`$env:HF_HOME = "$hf"
`$env:TORCH_HOME = "$torch"
`$env:PIP_CACHE_DIR = "$pip"
& "$activatePs"
"@
    Set-Content -LiteralPath $ps1 -Value $psContent -Encoding UTF8

    $batContent = @"
@echo off
set HF_HOME=$hf
set TORCH_HOME=$torch
set PIP_CACHE_DIR=$pip
call "$activateBat"
cmd /k
"@
    Set-Content -LiteralPath $bat -Value $batContent -Encoding ASCII
}

function Get-ResolvedLockFile {
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)
    $stateDir = Join-Path $WorkspaceRoot "state"
    Ensure-Directory $stateDir
    return (Join-Path $stateDir "resolved-install.lock.txt")
}

function New-ResolvedInstallLock {
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)
    $manifestPath = Get-ManifestPath
    $sourceManifestHash = Get-Sha256 $manifestPath
    $resolved = Get-ResolvedLockFile $WorkspaceRoot
    $torchLock = Join-PackagePath @("requirements", "torch-cu128.lock.txt")
    $researchLock = Join-PackagePath @("requirements", "research.lock.txt")
    $content = New-Object 'System.Collections.Generic.List[string]'
    $content.Add("# Generated by OfflineDL-Win10-3090.ps1") | Out-Null
    $content.Add("# Source manifest sha256: $sourceManifestHash") | Out-Null
    $content.Add("# Profile: Research") | Out-Null
    $content.Add("# Optional components: none") | Out-Null
    $content.Add("# Generated at: $(Get-IsoTimestamp)") | Out-Null
    $content.Add("# Do not edit manually.") | Out-Null
    $content.Add("") | Out-Null
    foreach ($lock in @($torchLock, $researchLock)) {
        $content.Add("# From $(Get-RelativePathFromPackage $lock)") | Out-Null
        foreach ($line in (Get-Content -LiteralPath $lock -Encoding UTF8)) {
            if (-not [string]::IsNullOrWhiteSpace($line) -and -not $line.TrimStart().StartsWith("#")) {
                $content.Add($line) | Out-Null
            }
        }
        $content.Add("") | Out-Null
    }
    Set-Content -LiteralPath $resolved -Value $content -Encoding UTF8
    return $resolved
}

function Write-FailedInstallState {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$Step,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $stateDir = Join-Path $WorkspaceRoot "state"
    Ensure-Directory $stateDir
    $failed = [ordered]@{
        schemaVersion = $Script:SchemaVersion
        installStatus = "failed"
        failedAtStep  = $Step
        message       = $Message
        failedAt      = Get-IsoTimestamp
        scriptVersion = $Script:ScriptVersion
    }
    Write-JsonAtomic $failed (Get-FailedInstallStatePath $WorkspaceRoot)
}

function Invoke-InstallMode {
    $installStep = "start"
    $resolvedWorkspace = $null
    try {
        $installStep = "check-package"
        Invoke-CheckMode

        $installStep = "workspace"
        $resolvedWorkspace = Resolve-WorkspaceRoot $WorkspaceRoot -Create
        Write-Info "工作区：$resolvedWorkspace"
        Assert-StorageReady -Path $resolvedWorkspace -MinFreeGB 50

        $installStep = "nvidia"
        Assert-TargetGpu

        $installStep = "python"
        $py = Find-Python311
        if ($null -eq $py) {
            $pythonDir = Join-PackagePath @("downloads", "python")
            throw "没有检测到可用的 Python 3.11 x64，或 pip/venv 不可用。请手动运行 $pythonDir 中的 Python 安装包，启用 pip 和 venv 后重试。"
        }
        Write-Ok "Python 3.11 x64 可用：$($py.Path)"

        $installStep = "vc-runtime"
        if (-not (Test-VcRuntimeHeuristic)) {
            $runtimeDir = Join-PackagePath @("downloads", "runtime")
            throw "没有检测到完整 VC++ Runtime 相关 DLL。请手动运行 $runtimeDir 中的 VC_redist.x64.exe 后重试。"
        }
        Write-Ok "VC++ Runtime 启发式检查通过。若后续出现 DLL load failed，请重新安装 VC_redist.x64.exe。"

        $installStep = "venv"
        $venvPath = Get-VenvPath $resolvedWorkspace
        if (Test-Path -LiteralPath $venvPath) {
            Assert-VenvDeleteSafe -WorkspaceRoot $resolvedWorkspace -VenvPath $venvPath
            if (-not $RecreateVenv) {
                if ($NonInteractive) {
                    throw "虚拟环境已存在。第一阶段不支持复用，请显式传入 -RecreateVenv 后重建。"
                }
                Write-Warn "检测到已有虚拟环境，第一阶段不支持复用，必须删除后重建。"
                Write-Warn "即将删除：$venvPath"
                Confirm-Continue "请输入 DELETE 确认删除" "DELETE" | Out-Null
            }
            elseif (-not $NonInteractive -and -not $Yes) {
                Write-Warn "即将删除：$venvPath"
                Confirm-Continue "请输入 DELETE 确认删除" "DELETE" | Out-Null
            }
            Remove-Item -LiteralPath $venvPath -Recurse -Force
        }
        Ensure-Directory (Split-Path -Parent $venvPath)
        Invoke-LoggedCommand -FilePath $py.Path -Arguments @("-m", "venv", $venvPath)
        $installingMarker = Join-Path $venvPath ".offline_dl_installing"
        Set-Content -LiteralPath $installingMarker -Value (Get-IsoTimestamp) -Encoding ASCII

        $installStep = "pip-install"
        $venvPython = Get-VenvPythonPath $venvPath
        $resolvedLock = New-ResolvedInstallLock $resolvedWorkspace
        $findLinks = @(
            "--find-links", (Join-PackagePath @("wheels", "pytorch-cu128")),
            "--find-links", (Join-PackagePath @("wheels", "common")),
            "--find-links", (Join-PackagePath @("wheels", "optional"))
        )
        $installArgs = @("-m", "pip", "install", "--no-index") + $findLinks + @("-r", $resolvedLock)
        Invoke-LoggedCommand -FilePath $venvPython -Arguments $installArgs

        $installStep = "pip-check"
        Invoke-LoggedCommand -FilePath $venvPython -Arguments @("-m", "pip", "check")

        $installStep = "basic-cuda"
        $basicCode = "import sys, torch; print(torch.__version__); sys.exit(0 if torch.cuda.is_available() else 1)"
        Invoke-LoggedCommand -FilePath $venvPython -Arguments @("-c", $basicCode)

        $readyMarker = Join-Path $venvPath ".offline_dl_ready"
        if (Test-Path -LiteralPath $installingMarker) {
            Remove-Item -LiteralPath $installingMarker -Force
        }
        Set-Content -LiteralPath $readyMarker -Value (Get-IsoTimestamp) -Encoding ASCII

        $installStep = "activation"
        New-ActivationScripts -WorkspaceRoot $resolvedWorkspace -VenvPath $venvPath

        $installStep = "install-state"
        $state = [ordered]@{
            schemaVersion           = $Script:SchemaVersion
            installStatus           = "success"
            workspaceRoot           = $resolvedWorkspace
            venvPython              = $venvPython
            profile                 = $Script:Profile
            optionalComponents      = @()
            pythonMajorMinor        = $Script:PythonMajorMinor
            pythonArch              = "64bit"
            torchCudaTag            = $Script:TorchCudaTag
            installedAt             = Get-IsoTimestamp
            installedByScriptVersion = $Script:ScriptVersion
            sourceManifestHash      = Get-Sha256 (Get-ManifestPath)
            resolvedLockSha256      = Get-Sha256 $resolvedLock
        }
        Write-JsonAtomic $state (Get-InstallStatePath $resolvedWorkspace)

        $installStep = "verify"
        Invoke-VerifyMode -WorkspaceRootOverride $resolvedWorkspace
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace($resolvedWorkspace)) {
            Write-FailedInstallState -WorkspaceRoot $resolvedWorkspace -Step $installStep -Message $_.Exception.Message
        }
        throw
    }
}

function Invoke-VerifyMode {
    param([string]$WorkspaceRootOverride)
    $rootInput = $WorkspaceRootOverride
    if ([string]::IsNullOrWhiteSpace($rootInput)) {
        $rootInput = $WorkspaceRoot
    }
    $resolvedWorkspace = Resolve-WorkspaceRoot $rootInput
    $statePath = Get-InstallStatePath $resolvedWorkspace
    if (-not (Test-Path -LiteralPath $statePath)) {
        throw "没有找到安装状态文件：$statePath。Verify 第一版不会回退系统 Python。"
    }
    $state = Read-JsonFile $statePath
    $venvPython = [string]$state.venvPython
    if (-not (Test-Path -LiteralPath $venvPython)) {
        throw "install_state.json 中记录的 venvPython 不存在：$venvPython"
    }
    $venvRoot = Split-Path -Parent (Split-Path -Parent $venvPython)
    $readyMarker = Join-Path $venvRoot ".offline_dl_ready"
    if (-not (Test-Path -LiteralPath $readyMarker)) {
        Write-Warn "未发现 .offline_dl_ready，环境可能不是由本脚本完整安装。继续验证当前环境可用性。"
    }

    $manifestPath = Get-ManifestPath
    if (Test-Path -LiteralPath $manifestPath) {
        $currentHash = Get-Sha256 $manifestPath
        if ((Get-PropertyValue $state "sourceManifestHash") -and $state.sourceManifestHash -ne $currentHash) {
            Write-Warn "当前离线包 manifest 与安装时来源不一致。Verify 只验证当前环境可用性。"
        }
    }
    else {
        Write-Warn "当前目录没有 manifest.json，无法确认安装来源。"
    }

    Invoke-LoggedCommand -FilePath $venvPython -Arguments @("-m", "pip", "check")
    $verifyScript = Join-PackagePath @("scripts", "verify_torch_cuda.py")
    Invoke-LoggedCommand -FilePath $venvPython -Arguments @($verifyScript)
}

function Enable-Tls12 {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
    catch {
        Write-Warn "无法显式设置 TLS 1.2：$($_.Exception.Message)"
    }
}

function Test-InternetEndpoint {
    param([Parameter(Mandatory = $true)][string]$Url)
    try {
        Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 20 | Out-Null
        Write-Ok "网络可访问：$Url"
        return
    }
    catch {
        try {
            Invoke-WebRequest -Uri $Url -Method Get -UseBasicParsing -TimeoutSec 20 | Out-Null
            Write-Ok "网络可访问：$Url"
            return
        }
        catch {
            throw "网络不可访问：$Url。错误：$($_.Exception.Message)"
        }
    }
}

function Get-DownloadPython {
    $python = Get-CommandPath "python"
    if ($null -eq $python) {
        throw "联网电脑没有找到 python 命令。请先安装任意可用 Python，并确保 pip 可用。"
    }
    & $python -m pip --version | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "当前 python 没有可用 pip：$python"
    }
    return $python
}

function Test-ExistingFileTrusted {
    param([Parameter(Mandatory = $true)][string]$FullPath)
    $manifestPath = Get-ManifestPath
    if (-not (Test-Path -LiteralPath $FullPath) -or -not (Test-Path -LiteralPath $manifestPath)) {
        return $false
    }
    try {
        $manifest = Read-JsonFile $manifestPath
        $rel = Get-RelativePathFromPackage $FullPath
        $entry = @($manifest.files | Where-Object { $_.path -eq $rel }) | Select-Object -First 1
        if ($null -eq $entry) {
            return $false
        }
        $item = Get-Item -LiteralPath $FullPath
        if ([int64]$item.Length -ne [int64]$entry.size) {
            return $false
        }
        return ((Get-Sha256 $FullPath) -eq $entry.sha256)
    }
    catch {
        return $false
    }
}

function Download-FileWithPart {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    Ensure-Directory (Split-Path -Parent $Destination)
    if ((Test-Path -LiteralPath $Destination) -and -not $Force) {
        if (Test-ExistingFileTrusted $Destination) {
            Write-Ok "文件已存在且与 manifest 匹配，跳过：$Destination"
            return
        }
        if ($NonInteractive) {
            throw "文件已存在但不能确认完整性，非交互模式停止。请使用 -Force 重新下载：$Destination"
        }
        Write-Warn "文件已存在但无法确认完整性：$Destination"
        Confirm-Continue "是否删除并重新下载？" "y" | Out-Null
        Remove-Item -LiteralPath $Destination -Force
    }
    elseif ((Test-Path -LiteralPath $Destination) -and $Force) {
        Remove-Item -LiteralPath $Destination -Force
    }

    $part = "$Destination.part"
    if (Test-Path -LiteralPath $part) {
        if ($Force -or $Yes) {
            Remove-Item -LiteralPath $part -Force
        }
        else {
            Confirm-Continue "检测到未完成下载文件 $part，是否删除并重下？" "y" | Out-Null
            Remove-Item -LiteralPath $part -Force
        }
    }
    Write-Info "下载：$Url"
    Invoke-WebRequest -Uri $Url -OutFile $part -UseBasicParsing
    if ((Get-Item -LiteralPath $part).Length -le 0) {
        throw "下载结果为空：$Url"
    }
    Move-Item -LiteralPath $part -Destination $Destination -Force
}

function Assert-NvidiaDriverSourceAvailable {
    param($Config)
    if (-not [string]::IsNullOrWhiteSpace($Config.components.nvidiaDriver.url)) {
        return
    }
    $driverDir = Join-PackagePath @("downloads", "drivers")
    $drivers = @(Get-ChildItem -LiteralPath $driverDir -File -Filter "*.exe" -ErrorAction SilentlyContinue)
    if ($drivers.Count -eq 0) {
        throw "没有 NVIDIA 驱动来源。请先从 NVIDIA 官方页面下载 RTX 3090 / Windows 10 x64 驱动 exe 放到 downloads\drivers，或在 config.json 写入 nvidiaDriver.url。"
    }
}

function Confirm-WheelDirectoryCanBeReplaced {
    param([Parameter(Mandatory = $true)][string]$Path)
    Ensure-Directory $Path
    $wheels = @(Get-ChildItem -LiteralPath $Path -File -Filter "*.whl" -ErrorAction SilentlyContinue)
    if ($wheels.Count -eq 0) {
        return
    }
    if ($Force -or $Yes) {
        return
    }
    if ($NonInteractive) {
        throw "wheels 目录已有旧 wheel，非交互模式下请使用 -Force 清理后重新下载：$Path"
    }
    Write-Warn "检测到已有 wheel：$Path"
    Confirm-Continue "为避免旧包混入新离线包，下载成功后是否替换这些 wheel？" "y" | Out-Null
}

function Clear-StagingDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetFullPath($Script:PackageRoot)
    if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "拒绝清理非离线包目录内的 staging：$full"
    }
    if (Test-Path -LiteralPath $full) {
        Remove-Item -LiteralPath $full -Recurse -Force
    }
    Ensure-Directory $full
}

function Move-StagedFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Staging,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    Ensure-Directory $Destination
    foreach ($file in Get-ChildItem -LiteralPath $Staging -File) {
        $target = Join-Path $Destination $file.Name
        if ((Test-Path -LiteralPath $target) -and -not $Force) {
            $oldHash = Get-Sha256 $target
            $newHash = Get-Sha256 $file.FullName
            if ($oldHash -eq $newHash) {
                Remove-Item -LiteralPath $file.FullName -Force
                continue
            }
            throw "目标 wheel 已存在但 SHA256 不同：$target"
        }
        Move-Item -LiteralPath $file.FullName -Destination $target -Force
    }
}

function Move-ResolvedWheelSet {
    param(
        [Parameter(Mandatory = $true)][string]$Staging,
        [Parameter(Mandatory = $true)][string]$TorchDestination,
        [Parameter(Mandatory = $true)][string]$CommonDestination
    )
    Ensure-Directory $TorchDestination
    Ensure-Directory $CommonDestination

    foreach ($destination in @($TorchDestination, $CommonDestination)) {
        foreach ($oldWheel in Get-ChildItem -LiteralPath $destination -File -Filter "*.whl" -ErrorAction SilentlyContinue) {
            Remove-Item -LiteralPath $oldWheel.FullName -Force
        }
    }

    foreach ($file in Get-ChildItem -LiteralPath $Staging -File -Filter "*.whl") {
        $lowerName = $file.Name.ToLowerInvariant()
        $isTorchCore = (
            $lowerName.StartsWith("torch-") -or
            $lowerName.StartsWith("torchvision-") -or
            $lowerName.StartsWith("torchaudio-")
        )
        $destination = if ($isTorchCore) { $TorchDestination } else { $CommonDestination }
        $target = Join-Path $destination $file.Name
        Move-Item -LiteralPath $file.FullName -Destination $target -Force
    }
}

function Download-WheelsToFolder {
    param(
        [Parameter(Mandatory = $true)][string]$Python,
        [Parameter(Mandatory = $true)][string]$RequirementFile,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string[]]$ExtraPipArgs = @()
    )
    $staging = Join-Path $Destination "_staging"
    Clear-StagingDirectory $staging
    $args = @(
        "-m", "pip", "download",
        "-r", $RequirementFile,
        "--dest", $staging,
        "--only-binary=:all:",
        "--platform", $Script:Platform,
        "--implementation", "cp",
        "--python-version", "311",
        "--abi", $Script:PythonAbi
    ) + $ExtraPipArgs
    Invoke-LoggedCommand -FilePath $Python -Arguments $args
    Move-StagedFiles -Staging $staging -Destination $Destination
    Remove-Item -LiteralPath $staging -Recurse -Force
}

function Download-ResolvedWheels {
    param(
        [Parameter(Mandatory = $true)][string]$Python,
        [Parameter(Mandatory = $true)][string]$TorchRequirementFile,
        [Parameter(Mandatory = $true)][string]$ResearchRequirementFile,
        [Parameter(Mandatory = $true)][string]$TorchDestination,
        [Parameter(Mandatory = $true)][string]$CommonDestination
    )
    $staging = Join-PackagePath @("wheels", "_resolved_staging")
    Clear-StagingDirectory $staging
    $args = @(
        "-m", "pip", "download",
        "-r", $TorchRequirementFile,
        "-r", $ResearchRequirementFile,
        "--dest", $staging,
        "--only-binary=:all:",
        "--platform", $Script:Platform,
        "--implementation", "cp",
        "--python-version", "311",
        "--abi", $Script:PythonAbi,
        "--index-url", "https://download.pytorch.org/whl/cu128",
        "--extra-index-url", "https://pypi.org/simple"
    )
    Invoke-LoggedCommand -FilePath $Python -Arguments $args
    Move-ResolvedWheelSet -Staging $staging -TorchDestination $TorchDestination -CommonDestination $CommonDestination
    Remove-Item -LiteralPath $staging -Recurse -Force
}

function Assert-PytorchCu128Wheels {
    $torchDir = Join-PackagePath @("wheels", "pytorch-cu128")
    foreach ($name in @("torch", "torchvision", "torchaudio")) {
        $matches = @(Get-ChildItem -LiteralPath $torchDir -File -Filter "$name-*.whl" -ErrorAction SilentlyContinue)
        if ($matches.Count -eq 0) {
            throw "没有找到 PyTorch 核心 wheel：$name"
        }
        $ok = $false
        foreach ($file in $matches) {
            if ($file.Name.ToLowerInvariant().Contains("cu128")) {
                $ok = $true
            }
        }
        if (-not $ok) {
            throw "$name wheel 文件名不包含 cu128，可能下载成 CPU 版或错误 CUDA 版本。"
        }
    }
}

function Build-ManifestFromFiles {
    param($Config, [string]$DownloadPython, [string]$PipVersion)
    $files = New-Object 'System.Collections.Generic.List[object]'

    $pythonInstaller = Join-PackagePath @("downloads", "python", $Config.components.python.fileName)
    $files.Add((New-ManifestFileEntry -FullPath $pythonInstaller -Component "python-installer" -Group "python" -Kind "installer" -SourceUrl $Config.components.python.url)) | Out-Null

    $vcInstaller = Join-PackagePath @("downloads", "runtime", $Config.components.vcRuntime.fileName)
    $files.Add((New-ManifestFileEntry -FullPath $vcInstaller -Component "vc-runtime" -Group "runtime" -Kind "installer" -SourceUrl $Config.components.vcRuntime.url)) | Out-Null

    $driverDir = Join-PackagePath @("downloads", "drivers")
    $drivers = @(Get-ChildItem -LiteralPath $driverDir -File -Filter "*.exe" -ErrorAction SilentlyContinue)
    if ($drivers.Count -eq 0) {
        throw "缺少 NVIDIA 驱动安装包。请把 RTX 3090 Windows 10 x64 驱动 exe 放到 downloads\drivers，或在 config.json 配置 nvidiaDriver.url。"
    }
    foreach ($driver in $drivers) {
        $files.Add((New-ManifestFileEntry -FullPath $driver.FullName -Component "nvidia-driver" -Group "driver" -Kind "installer" -SourceUrl $Config.components.nvidiaDriver.url -Source $(if ([string]::IsNullOrWhiteSpace($Config.components.nvidiaDriver.url)) { "manual" } else { "download" }))) | Out-Null
    }

    $torchLock = Join-PackagePath @("requirements", "torch-cu128.lock.txt")
    $researchLock = Join-PackagePath @("requirements", "research.lock.txt")
    $verifyScript = Join-PackagePath @("scripts", "verify_torch_cuda.py")
    $files.Add((New-ManifestFileEntry -FullPath $torchLock -Component "torch-lock" -Group "requirements" -Kind "lock" -Source "local")) | Out-Null
    $files.Add((New-ManifestFileEntry -FullPath $researchLock -Component "research-lock" -Group "requirements" -Kind "lock" -Source "local")) | Out-Null
    $files.Add((New-ManifestFileEntry -FullPath $verifyScript -Component "verify-script" -Group "script" -Kind "script" -Source "local")) | Out-Null

    $torchDir = Join-PackagePath @("wheels", "pytorch-cu128")
    foreach ($wheel in Get-ChildItem -LiteralPath $torchDir -File -Filter "*.whl" -ErrorAction SilentlyContinue) {
        $parsed = Parse-WheelFileName $wheel.Name
        $component = if ($null -ne $parsed) { $parsed.Package } else { "pytorch-wheel" }
        $files.Add((New-ManifestFileEntry -FullPath $wheel.FullName -Component $component -Group "pytorch" -Kind "wheel" -SourceUrl "https://download.pytorch.org/whl/cu128")) | Out-Null
    }

    $commonDir = Join-PackagePath @("wheels", "common")
    foreach ($wheel in Get-ChildItem -LiteralPath $commonDir -File -Filter "*.whl" -ErrorAction SilentlyContinue) {
        $parsed = Parse-WheelFileName $wheel.Name
        $component = if ($null -ne $parsed) { $parsed.Package } else { "research-wheel" }
        $files.Add((New-ManifestFileEntry -FullPath $wheel.FullName -Component $component -Group "research" -Kind "wheel" -SourceUrl "https://pypi.org/simple")) | Out-Null
    }

    $lockFiles = @(
        [ordered]@{
            name    = "torch-cu128.lock.txt"
            path    = "requirements\torch-cu128.lock.txt"
            sha256  = Get-Sha256 $torchLock
            profile = "Research"
        },
        [ordered]@{
            name    = "research.lock.txt"
            path    = "requirements\research.lock.txt"
            sha256  = Get-Sha256 $researchLock
            profile = "Research"
        }
    )

    return [ordered]@{
        schemaVersion          = $Script:SchemaVersion
        phase                  = $Script:Phase
        packageStatus          = "complete"
        createdAt              = Get-IsoTimestamp
        createdByScriptVersion = $Script:ScriptVersion
        profile                = $Script:Profile
        optionalComponents     = @()
        pythonMajorMinor       = $Script:PythonMajorMinor
        pythonAbi              = $Script:PythonAbi
        platform               = $Script:Platform
        torchCudaTag           = $Script:TorchCudaTag
        toolchain              = [ordered]@{
            downloadPython = $DownloadPython
            pip            = $PipVersion
            setuptools     = ""
            wheel          = ""
        }
        downloadCommands       = @(
            [ordered]@{
                component     = "resolved-wheel-set"
                lockFile      = "requirements\torch-cu128.lock.txt"
                extraLockFile = "requirements\research.lock.txt"
                indexUrl      = "https://download.pytorch.org/whl/cu128"
                extraIndexUrl = "https://pypi.org/simple"
                destination   = "wheels\pytorch-cu128 + wheels\common"
                platform      = $Script:Platform
                pythonAbi     = $Script:PythonAbi
            }
        )
        lockFiles              = $lockFiles
        files                  = $files.ToArray()
    }
}

function Invoke-DownloadMode {
    Write-Host ""
    Write-Warn "下载内容会保存到当前脚本所在文件夹：$Script:PackageRoot"
    Write-Warn "下载完成后，请拷贝整个文件夹到离线电脑，不要只拷贝 wheels 或 downloads。"
    Confirm-Continue "确认在此文件夹下载离线包吗？" "y" | Out-Null

    Enable-Tls12
    Assert-StorageReady -Path $Script:PackageRoot -MinFreeGB 50

    $config = Read-JsonFile (Get-ConfigPath)
    $downloadPython = Get-DownloadPython
    $pyVersion = & $downloadPython -c "import sys; print(sys.version.replace(chr(10),' '))"
    $pipVersion = & $downloadPython -m pip --version
    Write-Info "当前下载用 Python：$downloadPython"
    Write-Info "Python 版本：$pyVersion"
    Write-Info "pip：$pipVersion"
    Write-Info "目标下载平台：$Script:Platform / $Script:PythonAbi"

    Test-InternetEndpoint "https://pypi.org/simple"
    Test-InternetEndpoint "https://download.pytorch.org/whl/cu128"
    Assert-NvidiaDriverSourceAvailable $config

    $pythonInstaller = Join-PackagePath @("downloads", "python", $config.components.python.fileName)
    Download-FileWithPart -Url $config.components.python.url -Destination $pythonInstaller

    $vcInstaller = Join-PackagePath @("downloads", "runtime", $config.components.vcRuntime.fileName)
    Download-FileWithPart -Url $config.components.vcRuntime.url -Destination $vcInstaller

    if (-not [string]::IsNullOrWhiteSpace($config.components.nvidiaDriver.url)) {
        $driverName = $config.components.nvidiaDriver.fileName
        if ([string]::IsNullOrWhiteSpace($driverName)) {
            $driverName = "NVIDIA-RTX3090-driver.exe"
        }
        $driverTarget = Join-PackagePath @("downloads", "drivers", $driverName)
        Download-FileWithPart -Url $config.components.nvidiaDriver.url -Destination $driverTarget
    }
    else {
        $driverDir = Join-PackagePath @("downloads", "drivers")
        $drivers = @(Get-ChildItem -LiteralPath $driverDir -File -Filter "*.exe" -ErrorAction SilentlyContinue)
        if ($drivers.Count -eq 0) {
            throw "config.json 没有配置 NVIDIA 驱动直链，downloads\drivers 里也没有驱动 exe。请先从 NVIDIA 官方页面下载 RTX 3090 Windows 10 x64 驱动放入该目录，再重新运行 Download。"
        }
        Write-Warn "NVIDIA 驱动使用本地已存在文件登记：$($drivers[0].FullName)"
    }

    $torchReq = Join-PackagePath @("requirements", "torch-cu128.lock.txt")
    $researchReq = Join-PackagePath @("requirements", "research.lock.txt")
    $torchDest = Join-PackagePath @("wheels", "pytorch-cu128")
    $commonDest = Join-PackagePath @("wheels", "common")
    Confirm-WheelDirectoryCanBeReplaced $torchDest
    Confirm-WheelDirectoryCanBeReplaced $commonDest

    Download-ResolvedWheels -Python $downloadPython -TorchRequirementFile $torchReq -ResearchRequirementFile $researchReq -TorchDestination $torchDest -CommonDestination $commonDest
    Assert-PytorchCu128Wheels

    $manifest = Build-ManifestFromFiles -Config $config -DownloadPython $downloadPython -PipVersion ($pipVersion -join " ")
    $manifestPath = Get-ManifestPath
    Write-JsonAtomic $manifest $manifestPath

    $check = Test-OfflinePackage
    if ($check.Errors.Count -gt 0) {
        $manifest.packageStatus = "failed"
        Write-JsonAtomic $manifest $manifestPath
        Write-CheckReport $check
        throw "Download 已完成部分文件，但内部校验失败，manifest 状态已写为 failed。"
    }
    Write-CheckReport $check
    Write-Ok "Download 完成。离线包已经可拷贝到 Win10 + RTX 3090 电脑。"
}

function Invoke-Main {
    Reject-UnsupportedPhase2Options
    if ([string]::IsNullOrWhiteSpace($Mode)) {
        $selected = Show-MainMenu
        if ([string]::IsNullOrWhiteSpace($selected)) {
            Write-Info "已退出。"
            return 0
        }
        $script:Mode = $selected
    }

    Start-RunLog $Mode
    switch ($Mode) {
        "Download" { Invoke-DownloadMode }
        "Check" { Invoke-CheckMode }
        "Install" { Invoke-InstallMode }
        "Verify" { Invoke-VerifyMode }
        default { throw "未知模式：$Mode" }
    }
    return 0
}

$exitCode = 0
try {
    $exitCode = Invoke-Main
}
catch {
    Write-Fail $_.Exception.Message
    $exitCode = 1
}
finally {
    Stop-RunLog
}
exit $exitCode
