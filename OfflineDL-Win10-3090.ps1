[CmdletBinding()]
param(
    [ValidateSet("Download", "Check", "Install", "Verify", "RegisterLocalFiles", "Doctor")]
    [string]$Mode,

    [string]$WorkspaceRoot,
    [switch]$Yes,
    [switch]$NonInteractive,
    [switch]$Force,
    [switch]$RecreateVenv,

    [ValidateSet("Minimal", "Research", "Full")]
    [string]$Profile,
    [switch]$ReuseVenv,
    [switch]$IncludeGit,
    [switch]$IncludeCudaToolkit,
    [switch]$IncludeVisualization,
    [switch]$IncludeVSCode
)

$Script:InitialBoundParameters = $PSBoundParameters
Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$Script:ScriptVersion = "0.3.2"
$Script:SchemaVersion = 1
$Script:Phase = 2
$Script:SupportedManifestPhases = @(1, 2)
$Script:Profile = "Research"
$Script:EffectiveProfile = "Research"
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

function Assert-ParameterCombination {
    if ($ReuseVenv -and $RecreateVenv) {
        throw "-ReuseVenv 和 -RecreateVenv 不能同时使用。请选择复用或重建其中一种。"
    }
    $modeForParams = if ([string]::IsNullOrWhiteSpace($Mode)) { "" } else { $Mode }
    foreach ($name in @("ReuseVenv", "RecreateVenv")) {
        if ($Script:InitialBoundParameters.ContainsKey($name) -and $modeForParams -notin @("", "Install")) {
            throw "-$name 只在 Install 模式中使用。"
        }
    }
    foreach ($name in @("IncludeGit", "IncludeCudaToolkit", "IncludeVisualization", "IncludeVSCode")) {
        if ($Script:InitialBoundParameters.ContainsKey($name) -and $modeForParams -notin @("", "Download")) {
            throw "-$name 只在 Download 模式中使用。Install 会严格按照 manifest.json 中记录的内容安装。"
        }
    }
    if ($Script:InitialBoundParameters.ContainsKey("Profile") -and $modeForParams -notin @("", "Download")) {
        throw "-Profile 只在 Download 模式中使用。Install / Check / Verify 会读取 manifest 或 install_state。"
    }
}

function Resolve-EffectiveProfile {
    if ($Script:InitialBoundParameters.ContainsKey("Profile")) {
        $selectedProfile = [string]$Script:InitialBoundParameters["Profile"]
        if (-not [string]::IsNullOrWhiteSpace($selectedProfile)) {
            $Script:EffectiveProfile = $selectedProfile
            $Script:Profile = $selectedProfile
            return $selectedProfile
        }
    }
    if ($Mode -eq "Download" -and -not $NonInteractive -and -not $Yes) {
        Write-Host ""
        Write-Host "请选择离线包档位" -ForegroundColor Green
        Write-Host "[1] Minimal   最小运行环境"
        Write-Host "[2] Research  科研常用环境（推荐）"
        Write-Host "[3] Full      Research + Git/CUDA Toolkit 安装包登记"
        $choice = Read-Host "直接回车默认 Research"
        switch ($choice) {
            "1" { $Script:EffectiveProfile = "Minimal" }
            "3" { $Script:EffectiveProfile = "Full" }
            default { $Script:EffectiveProfile = "Research" }
        }
    }
    else {
        $Script:EffectiveProfile = "Research"
    }
    $Script:Profile = $Script:EffectiveProfile
    return $Script:EffectiveProfile
}

function Get-SelectedOptionalComponents {
    param([Parameter(Mandatory = $true)][string]$ProfileName)
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    if ($ProfileName -eq "Full") {
        $null = $set.Add("Git")
        $null = $set.Add("CudaToolkit")
    }
    if ($IncludeGit) { $null = $set.Add("Git") }
    if ($IncludeCudaToolkit) { $null = $set.Add("CudaToolkit") }
    if ($IncludeVSCode) { $null = $set.Add("VSCode") }
    if ($IncludeVisualization) { $null = $set.Add("Visualization") }
    if ($Mode -eq "Download" -and -not $NonInteractive -and -not $Yes) {
        $visualAnswer = Read-Host "是否加入可视化增强包（seaborn/plotly/ipywidgets/mlflow）？输入 y 加入，直接回车跳过"
        if ($visualAnswer -eq "y") { $null = $set.Add("Visualization") }
        if ($ProfileName -ne "Full") {
            $gitAnswer = Read-Host "是否登记 Git 安装包？把 Git exe 放到 downloads\manual_inbox 即可，脚本会自动整理。输入 y 加入，直接回车跳过"
            if ($gitAnswer -eq "y") { $null = $set.Add("Git") }
            $cudaAnswer = Read-Host "是否登记 CUDA Toolkit 离线安装包？把 local installer 放到 downloads\manual_inbox 即可，脚本会自动整理。输入 y 加入，直接回车跳过"
            if ($cudaAnswer -eq "y") { $null = $set.Add("CudaToolkit") }
        }
        $vscodeAnswer = Read-Host "是否登记 VS Code 安装包？把 VS Code exe 放到 downloads\manual_inbox 即可，脚本会自动整理。输入 y 加入，直接回车跳过"
        if ($vscodeAnswer -eq "y") { $null = $set.Add("VSCode") }
    }
    return @($set | Sort-Object)
}

function Get-ManualDownloadHelpItems {
    param([string[]]$Components)
    $items = New-Object 'System.Collections.Generic.List[object]'
    $wanted = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($component in $Components) {
        if (-not [string]::IsNullOrWhiteSpace($component)) {
            $null = $wanted.Add($component)
        }
    }

    if ($wanted.Contains("Python")) {
        $items.Add([pscustomobject]@{
                Name   = "Python 3.11.9 x64"
                Url    = "https://www.python.org/downloads/release/python-3119/"
                SaveTo = "downloads\manual_inbox（推荐）；脚本会整理到 downloads\python"
                Note   = "脚本通常会自动下载；手动下载时请选择 Windows installer (64-bit)。"
            }) | Out-Null
    }
    if ($wanted.Contains("VcRuntime")) {
        $items.Add([pscustomobject]@{
                Name   = "Microsoft VC++ Runtime x64"
                Url    = "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170"
                SaveTo = "downloads\manual_inbox（推荐）；脚本会整理到 downloads\runtime"
                Note   = "脚本通常会自动下载；手动下载时请选择 X64 版本。"
            }) | Out-Null
    }
    if ($wanted.Contains("NvidiaDriver")) {
        $items.Add([pscustomobject]@{
                Name   = "NVIDIA RTX 3090 Windows 10 x64 驱动"
                Url    = "https://www.nvidia.com/Download/index.aspx"
                SaveTo = "downloads\manual_inbox（推荐）；脚本会整理到 downloads\drivers"
                Note   = "请选择 GeForce RTX 30 Series / GeForce RTX 3090 / Windows 10 64-bit，Studio Driver 或 Game Ready Driver 都可以。"
            }) | Out-Null
    }
    if ($wanted.Contains("Git")) {
        $items.Add([pscustomobject]@{
                Name   = "Git for Windows x64"
                Url    = "https://git-scm.com/install/windows.html"
                SaveTo = "downloads\manual_inbox（推荐）；脚本会整理到 downloads\tools_optional"
                Note   = "下载 x64 Setup 安装包；这里只登记，不会自动安装。"
            }) | Out-Null
    }
    if ($wanted.Contains("CudaToolkit")) {
        $items.Add([pscustomobject]@{
                Name   = "NVIDIA CUDA Toolkit Windows local installer"
                Url    = "https://developer.nvidia.com/cuda-toolkit-archive"
                SaveTo = "downloads\manual_inbox（推荐）；脚本会整理到 downloads\cuda_optional"
                Note   = "请选择 Windows / x86_64 / 10 / exe (local)，不要下载 network installer。"
            }) | Out-Null
    }
    if ($wanted.Contains("VSCode")) {
        $items.Add([pscustomobject]@{
                Name   = "Visual Studio Code Windows"
                Url    = "https://code.visualstudio.com/download"
                SaveTo = "downloads\manual_inbox（推荐）；脚本会整理到 downloads\tools_optional"
                Note   = "下载 Windows x64 User Installer 或 System Installer；这里只登记，不会自动安装。"
            }) | Out-Null
    }
    return $items.ToArray()
}

function Write-ManualDownloadHelp {
    param([string[]]$Components)
    $items = @(Get-ManualDownloadHelpItems -Components $Components)
    if ($items.Count -eq 0) {
        return
    }
    Write-Host ""
    Write-Host "需要手动下载时可参考这些官方页面：" -ForegroundColor Green
    Write-Host "推荐把手动下载的 exe 都先放到 downloads\manual_inbox；脚本会读取并整理到对应目录。"
    Write-Host "如果已经放在 downloads 根目录，脚本也会尝试识别并整理。"
    foreach ($item in $items) {
        Write-Host ("- {0}" -f $item.Name)
        Write-Host ("  官网：{0}" -f $item.Url)
        Write-Host ("  放到：{0}" -f $item.SaveTo)
        Write-Host ("  备注：{0}" -f $item.Note)
    }
    Write-Host ""
}

function Get-ManualInboxPath {
    return (Join-PackagePath @("downloads", "manual_inbox"))
}

function Assert-PathUnderRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root)
    if (-not $fullRoot.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $fullRoot = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    }
    if (-not $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "路径不在允许目录内，已拒绝操作：$fullPath"
    }
}

function Get-ManualInstallerKind {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File)
    if ($File.Extension.ToLowerInvariant() -ne ".exe") {
        return ""
    }
    $name = $File.Name.ToLowerInvariant()
    if ($name -match "vc_redist|vcredist") {
        return "vc-runtime"
    }
    if ($name -match "^python-3\.11.*(amd64|x64).*\.exe$") {
        return "python"
    }
    if ($name -match "cuda|toolkit") {
        return "cuda-toolkit"
    }
    if ($name -match "git") {
        return "git"
    }
    if ($name -match "code|vscode|visualstudiocode") {
        return "vscode"
    }
    if ($name -match "nvidia|geforce|studio|game|desktop-win|dch|whql" -or $File.Length -gt 300MB) {
        return "nvidia-driver"
    }
    return ""
}

function Get-ManualInstallerDestination {
    param([Parameter(Mandatory = $true)][string]$Kind)
    switch ($Kind) {
        "nvidia-driver" { return (Join-PackagePath @("downloads", "drivers")) }
        "cuda-toolkit" { return (Join-PackagePath @("downloads", "cuda_optional")) }
        "git" { return (Join-PackagePath @("downloads", "tools_optional")) }
        "vscode" { return (Join-PackagePath @("downloads", "tools_optional")) }
        "python" { return (Join-PackagePath @("downloads", "python")) }
        "vc-runtime" { return (Join-PackagePath @("downloads", "runtime")) }
        default { throw "未知手动安装包类型：$Kind" }
    }
}

function Move-ManualInboxFiles {
    $downloadsRoot = Join-PackagePath @("downloads")
    $manualInbox = Get-ManualInboxPath
    Ensure-Directory $manualInbox

    $moved = New-Object 'System.Collections.Generic.List[object]'
    $warnings = New-Object 'System.Collections.Generic.List[string]'
    $candidateFiles = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
    $plannedMoves = New-Object 'System.Collections.Generic.List[object]'

    foreach ($folder in @($manualInbox, $downloadsRoot)) {
        if (Test-Path -LiteralPath $folder) {
            foreach ($file in Get-ChildItem -LiteralPath $folder -File -Filter "*.exe" -ErrorAction SilentlyContinue) {
                $candidateFiles.Add($file) | Out-Null
            }
        }
    }

    foreach ($file in $candidateFiles) {
        $kind = Get-ManualInstallerKind -File $file
        if ([string]::IsNullOrWhiteSpace($kind)) {
            $warnings.Add("未识别手动安装包，已跳过：$($file.FullName)") | Out-Null
            continue
        }

        $check = Test-ManualInstallerFile -File $file -Kind $kind
        foreach ($warning in $check.Warnings) {
            $warnings.Add($warning) | Out-Null
        }
        if (-not $check.Accept) {
            continue
        }

        $destinationDir = Get-ManualInstallerDestination -Kind $kind
        Ensure-Directory $destinationDir
        $targetPath = Join-Path $destinationDir $file.Name
        $sourceFull = [System.IO.Path]::GetFullPath($file.FullName)
        $targetFull = [System.IO.Path]::GetFullPath($targetPath)

        Assert-PathUnderRoot -Path $sourceFull -Root $downloadsRoot
        Assert-PathUnderRoot -Path $targetFull -Root $downloadsRoot

        if ($sourceFull.Equals($targetFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $plannedMoves.Add([pscustomobject]@{
                Kind   = $kind
                Source = $sourceFull
                Target = $targetFull
            }) | Out-Null
    }

    if ($plannedMoves.Count -gt 0) {
        Write-Host ""
        Write-Warn "检测到手动下载的安装包，脚本准备先整理到对应目录："
        foreach ($plan in $plannedMoves) {
            Write-Host ("- {0} -> {1}" -f $plan.Source, $plan.Target)
        }
        Confirm-Continue "确认移动这些安装包吗？" "y" | Out-Null
    }

    foreach ($plan in $plannedMoves) {
        $sourceFull = $plan.Source
        $targetFull = $plan.Target
        if (-not (Test-Path -LiteralPath $sourceFull)) {
            $warnings.Add("计划移动的文件已经不存在，已跳过：$sourceFull") | Out-Null
            continue
        }

        if (Test-Path -LiteralPath $targetFull) {
            $sourceHash = Get-Sha256 $sourceFull
            $targetHash = Get-Sha256 $targetFull
            if ($sourceHash -eq $targetHash) {
                Remove-Item -LiteralPath $sourceFull -Force
                $moved.Add([pscustomobject]@{
                        Kind   = $plan.Kind
                        Source = $sourceFull
                        Target = $targetFull
                        Action = "目标已存在相同文件，已删除收件箱重复文件"
                    }) | Out-Null
                continue
            }
            if (-not $Force) {
                throw "目标目录已有同名但 SHA256 不同的文件：$targetFull。请手动改名/删除，或确认后使用 -Force 覆盖。"
            }
        }

        Move-Item -LiteralPath $sourceFull -Destination $targetFull -Force
        $moved.Add([pscustomobject]@{
                Kind   = $plan.Kind
                Source = $sourceFull
                Target = $targetFull
                Action = "已移动"
            }) | Out-Null
    }

    return [pscustomobject]@{
        Moved    = $moved.ToArray()
        Warnings = $warnings.ToArray()
    }
}

function Get-LockSelection {
    param(
        [Parameter(Mandatory = $true)][string]$ProfileName,
        [string[]]$OptionalComponents = @()
    )
    $locks = New-Object 'System.Collections.Generic.List[object]'
    $locks.Add([pscustomobject]@{
            Name      = "torch-cu128.lock.txt"
            Path      = Join-PackagePath @("requirements", "torch-cu128.lock.txt")
            Component = "torch-lock"
            Profile   = $ProfileName
            Group     = "pytorch"
        }) | Out-Null
    $locks.Add([pscustomobject]@{
            Name      = "minimal.lock.txt"
            Path      = Join-PackagePath @("requirements", "minimal.lock.txt")
            Component = "minimal-lock"
            Profile   = "Minimal"
            Group     = "minimal"
        }) | Out-Null
    if ($ProfileName -in @("Research", "Full")) {
        $locks.Add([pscustomobject]@{
                Name      = "research.lock.txt"
                Path      = Join-PackagePath @("requirements", "research.lock.txt")
                Component = "research-lock"
                Profile   = "Research"
                Group     = "research"
            }) | Out-Null
    }
    if ($OptionalComponents -contains "Visualization") {
        $locks.Add([pscustomobject]@{
                Name      = "visualization.lock.txt"
                Path      = Join-PackagePath @("requirements", "visualization.lock.txt")
                Component = "visualization-lock"
                Profile   = $ProfileName
                Group     = "visualization"
            }) | Out-Null
    }
    return $locks.ToArray()
}

function Show-MainMenu {
    Write-Host ""
    Write-Host "Win10 + RTX 3090 深度学习离线环境工具" -ForegroundColor Green
    Write-Host "支持 Python 3.11 + PyTorch CUDA 12.8，可选择 Minimal / Research / Full"
    Write-Host ""
    Write-Host "[1] Download  在联网电脑下载离线包"
    Write-Host "[2] Check     检查离线包完整性（只读，不修改文件）"
    Write-Host "[3] Register  整理并登记 downloads\manual_inbox 里的手动安装包"
    Write-Host "[4] Install   在离线电脑安装环境"
    Write-Host "[5] Verify    验证 GPU / PyTorch CUDA"
    Write-Host "[6] Doctor    诊断当前状态（只读）"
    Write-Host "[7] Exit      退出"
    Write-Host ""
    $choice = Read-Host "请选择操作"
    switch ($choice) {
        "1" { return "Download" }
        "2" { return "Check" }
        "3" { return "RegisterLocalFiles" }
        "4" { return "Install" }
        "5" { return "Verify" }
        "6" { return "Doctor" }
        "7" { return "" }
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
        [string]$Source = "download",
        [string]$OptionalComponent = "",
        [bool]$UserConfirmed = $false,
        [string]$RegisteredByMode = ""
    )
    $item = Get-Item -LiteralPath $FullPath
    return [ordered]@{
        component        = $Component
        group            = $Group
        kind             = $Kind
        required         = $Required
        profile          = $Profile
        optionalComponent = $OptionalComponent
        path             = Get-RelativePathFromPackage $item.FullName
        fileName         = $item.Name
        size             = [int64]$item.Length
        sha256           = Get-Sha256 $item.FullName
        sourceUrl        = $SourceUrl
        source           = $Source
        downloadedAt     = Get-IsoTimestamp
        registeredAt     = if ($Source -eq "manual") { Get-IsoTimestamp } else { "" }
        registeredByMode = $RegisteredByMode
        userConfirmed    = $UserConfirmed
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
    $manifestPhase = Get-PropertyValue $manifest "phase"
    if ($Script:SupportedManifestPhases -notcontains [int]$manifestPhase) {
        Add-CheckError $result "phase 不匹配，当前脚本只支持 phase = 1 或 phase = 2。"
    }
    $optional = @(Get-PropertyValue $manifest "optionalComponents")
    if ([int]$manifestPhase -eq 1 -and $optional.Count -ne 0) {
        Add-CheckError $result "phase 1 离线包不支持可选组件，manifest.optionalComponents 必须为空数组。"
    }
    $manifestProfile = [string](Get-PropertyValue $manifest "profile")
    if ([string]::IsNullOrWhiteSpace($manifestProfile)) {
        $manifestProfile = "Research"
    }
    if (@("Minimal", "Research", "Full") -notcontains $manifestProfile) {
        Add-CheckError $result "未知 Profile：$manifestProfile"
    }
    $knownOptionalComponents = @("Git", "CudaToolkit", "VSCode", "Visualization")
    foreach ($component in $optional) {
        if ($knownOptionalComponents -notcontains [string]$component) {
            Add-CheckError $result "未知可选组件：$component"
        }
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
        "minimal-lock",
        "verify-script"
    )
    if ($manifestProfile -in @("Research", "Full")) {
        $requiredComponents += "research-lock"
    }
    if ($optional -contains "Visualization") {
        $requiredComponents += "visualization-lock"
    }
    foreach ($component in $requiredComponents) {
        $matches = @($files | Where-Object { $_.component -eq $component -and $_.required -eq $true })
        if ($matches.Count -eq 0) {
            Add-CheckError $result "必需组件没有登记到 manifest.files：$component"
        }
    }
    $commonWheels = @($files | Where-Object { $_.group -eq "research" -and $_.kind -eq "wheel" })
    if ($commonWheels.Count -eq 0) {
        Add-CheckError $result "没有找到通用 Python wheels。"
    }
    if ($optional -contains "Visualization") {
        $visualWheels = @($files | Where-Object { $_.group -eq "visualization" -and $_.kind -eq "wheel" })
        if ($visualWheels.Count -eq 0) {
            Add-CheckError $result "已选择 Visualization，但没有找到 visualization wheels。"
        }
    }
    foreach ($optionalInstaller in @("Git", "CudaToolkit", "VSCode")) {
        if ($optional -contains $optionalInstaller) {
            $matches = @($files | Where-Object { $_.optionalComponent -eq $optionalInstaller -and $_.kind -eq "installer" })
            if ($matches.Count -eq 0) {
                Add-CheckError $result "已选择可选组件 $optionalInstaller，但 manifest.files 中没有对应安装包。"
            }
        }
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
        Write-ManualDownloadHelp -Components @("NvidiaDriver")
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
    $manifest = Read-JsonFile $manifestPath
    $sourceManifestHash = Get-Sha256 $manifestPath
    $resolved = Get-ResolvedLockFile $WorkspaceRoot
    $content = New-Object 'System.Collections.Generic.List[string]'
    $content.Add("# Generated by OfflineDL-Win10-3090.ps1") | Out-Null
    $content.Add("# Source manifest sha256: $sourceManifestHash") | Out-Null
    $content.Add("# Profile: $([string]$manifest.profile)") | Out-Null
    $content.Add("# Optional components: $((@(Get-PropertyValue $manifest 'optionalComponents') | Sort-Object) -join ', ')") | Out-Null
    $content.Add("# Generated at: $(Get-IsoTimestamp)") | Out-Null
    $content.Add("# Do not edit manually.") | Out-Null
    $content.Add("") | Out-Null
    foreach ($manifestLock in @(Get-PropertyValue $manifest "lockFiles")) {
        $lock = Resolve-PackageRelativePath $manifestLock.path
        if (-not (Test-Path -LiteralPath $lock)) {
            throw "manifest 记录的 lock 文件不存在：$($manifestLock.path)"
        }
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

function Assert-ReusableVenv {
    param([Parameter(Mandatory = $true)][string]$VenvPath)
    $venvPython = Get-VenvPythonPath $VenvPath
    $info = Test-PythonCandidate $venvPython
    if ($null -eq $info) {
        throw "无法复用虚拟环境：没有找到可用的 venv Python：$venvPython"
    }
    if ($info.MajorMinor -ne $Script:PythonMajorMinor -or $info.Architecture -ne 64) {
        throw "无法复用虚拟环境：Python 必须是 $Script:PythonMajorMinor x64，当前是 $($info.MajorMinor) / $($info.Architecture)bit。"
    }
    & $venvPython -m pip --version | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "无法复用虚拟环境：venv 内 pip 不可用。"
    }

    $torchProbe = "import importlib.util, sys; spec=importlib.util.find_spec('torch');" +
        "print('missing' if spec is None else 'present');" +
        "sys.exit(0 if spec is None else 0)"
    $torchState = & $venvPython -c $torchProbe 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "无法检查虚拟环境中的 torch 状态。建议使用 -RecreateVenv 重建。"
    }
    if (($torchState | Select-Object -First 1) -eq "present") {
        $cudaProbe = "import torch, sys; cuda=torch.version.cuda; print('None' if cuda is None else cuda); sys.exit(0)"
        $cudaVersion = (& $venvPython -c $cudaProbe 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -ne 0) {
            throw "虚拟环境中已有 torch，但无法导入。建议使用 -RecreateVenv 重建。"
        }
        if ([string]::IsNullOrWhiteSpace($cudaVersion) -or $cudaVersion -eq "None") {
            throw "虚拟环境中已有 CPU 版 PyTorch，不能安全复用。请使用 -RecreateVenv 重建。"
        }
        if ($cudaVersion -ne "12.8") {
            throw "虚拟环境中已有 PyTorch CUDA $cudaVersion，目标是 12.8。请使用 -RecreateVenv 重建。"
        }
    }
    Write-Ok "虚拟环境复用检查通过。"
}

function Invoke-InstallMode {
    $installStep = "start"
    $resolvedWorkspace = $null
    try {
        $installStep = "check-package"
        Invoke-CheckMode
        $manifest = Read-JsonFile (Get-ManifestPath)
        $installProfile = [string]$manifest.profile
        $installOptionalComponents = @(Get-PropertyValue $manifest "optionalComponents")

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
            Write-ManualDownloadHelp -Components @("Python")
            throw "没有检测到可用的 Python 3.11 x64，或 pip/venv 不可用。请手动运行 $pythonDir 中的 Python 安装包，启用 pip 和 venv 后重试。"
        }
        Write-Ok "Python 3.11 x64 可用：$($py.Path)"

        $installStep = "vc-runtime"
        if (-not (Test-VcRuntimeHeuristic)) {
            $runtimeDir = Join-PackagePath @("downloads", "runtime")
            Write-ManualDownloadHelp -Components @("VcRuntime")
            throw "没有检测到完整 VC++ Runtime 相关 DLL。请手动运行 $runtimeDir 中的 VC_redist.x64.exe 后重试。"
        }
        Write-Ok "VC++ Runtime 启发式检查通过。若后续出现 DLL load failed，请重新安装 VC_redist.x64.exe。"

        $installStep = "venv"
        $venvPath = Get-VenvPath $resolvedWorkspace
        $reusingVenv = $false
        if (Test-Path -LiteralPath $venvPath) {
            if ($ReuseVenv) {
                Assert-ReusableVenv -VenvPath $venvPath
                $reusingVenv = $true
            }
            else {
                Assert-VenvDeleteSafe -WorkspaceRoot $resolvedWorkspace -VenvPath $venvPath
                if (-not $RecreateVenv) {
                    if ($NonInteractive) {
                        throw "虚拟环境已存在。若要重建请显式传入 -RecreateVenv；若确认复用请传入 -ReuseVenv。"
                    }
                    Write-Warn "检测到已有虚拟环境。默认不复用，建议删除后重建。"
                    Write-Warn "即将删除：$venvPath"
                    Confirm-Continue "请输入 DELETE 确认删除" "DELETE" | Out-Null
                }
                elseif (-not $NonInteractive -and -not $Yes) {
                    Write-Warn "即将删除：$venvPath"
                    Confirm-Continue "请输入 DELETE 确认删除" "DELETE" | Out-Null
                }
                Remove-Item -LiteralPath $venvPath -Recurse -Force
            }
        }
        if (-not $reusingVenv) {
            Ensure-Directory (Split-Path -Parent $venvPath)
            Invoke-LoggedCommand -FilePath $py.Path -Arguments @("-m", "venv", $venvPath)
        }
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
            profile                 = $installProfile
            optionalComponents      = $installOptionalComponents
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
        throw "没有找到安装状态文件：$statePath。Verify 不会回退系统 Python。"
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

function Write-DoctorLine {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value
    )
    Write-Host ("{0,-22} {1}" -f ($Name + ":"), $Value)
}

function Invoke-DoctorMode {
    Write-Host ""
    Write-Host "诊断摘要（只读）" -ForegroundColor Green
    Write-DoctorLine "脚本版本" $Script:ScriptVersion
    Write-DoctorLine "离线包目录" $Script:PackageRoot
    Write-DoctorLine "PowerShell" $PSVersionTable.PSVersion.ToString()

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        Write-DoctorLine "系统" ("{0} / {1}" -f $os.Caption, $os.OSArchitecture)
    }
    catch {
        Write-DoctorLine "系统" "无法读取"
    }

    try {
        $drive = Get-DriveInfoForPath $Script:PackageRoot
        Write-DoctorLine "离线包磁盘" ("{0}, {1} GB free, {2}" -f $drive.Root, $drive.FreeGB, $drive.FileSystem)
    }
    catch {
        Write-DoctorLine "离线包磁盘" "读取失败：$($_.Exception.Message)"
    }

    $configPath = Get-ConfigPath
    Write-DoctorLine "config.json" $(if (Test-Path -LiteralPath $configPath) { "存在" } else { "缺失" })

    $manifestPath = Get-ManifestPath
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $manifest = Read-JsonFile $manifestPath
            Write-DoctorLine "manifest" ("存在，phase={0}, status={1}" -f (Get-PropertyValue $manifest "phase"), (Get-PropertyValue $manifest "packageStatus"))
            Write-DoctorLine "manifest files" (@(Get-PropertyValue $manifest "files").Count.ToString())
            Write-DoctorLine "optional" ((@(Get-PropertyValue $manifest "optionalComponents") -join ", "))
        }
        catch {
            Write-DoctorLine "manifest" "无法解析：$($_.Exception.Message)"
        }
        $check = Test-OfflinePackage
        Write-DoctorLine "Check 错误数" $check.Errors.Count.ToString()
        Write-DoctorLine "Check 警告数" $check.Warnings.Count.ToString()
        foreach ($errorMessage in $check.Errors | Select-Object -First 5) {
            Write-Fail $errorMessage
        }
    }
    else {
        Write-DoctorLine "manifest" "缺失"
    }

    $pythonCmd = Get-CommandPath "python"
    Write-DoctorLine "python 命令" $(if ($null -eq $pythonCmd) { "未找到" } else { $pythonCmd })
    $pyLauncher = Get-CommandPath "py"
    Write-DoctorLine "py launcher" $(if ($null -eq $pyLauncher) { "未找到" } else { $pyLauncher })
    $py311 = Find-Python311
    if ($null -eq $py311) {
        Write-DoctorLine "Python 3.11 x64" "未找到，或 pip/venv 不可用"
    }
    else {
        Write-DoctorLine "Python 3.11 x64" $py311.Path
    }

    Write-DoctorLine "VC++ Runtime" $(if (Test-VcRuntimeHeuristic) { "可能已安装" } else { "未检测完整，请安装 VC_redist.x64.exe" })

    $nvidiaSmi = Get-NvidiaSmiPath
    if ($null -eq $nvidiaSmi) {
        Write-DoctorLine "nvidia-smi" "未找到"
    }
    else {
        Write-DoctorLine "nvidia-smi" $nvidiaSmi
        $gpuNames = Get-NvidiaGpuNames
        Write-DoctorLine "NVIDIA GPU" $(if ($gpuNames.Count -eq 0) { "未检测到" } else { $gpuNames -join "; " })
    }

    $rootInput = $WorkspaceRoot
    if (-not [string]::IsNullOrWhiteSpace($rootInput)) {
        $resolvedWorkspace = Resolve-WorkspaceRoot $rootInput
        Write-DoctorLine "工作区" $resolvedWorkspace
        $statePath = Get-InstallStatePath $resolvedWorkspace
        if (Test-Path -LiteralPath $statePath) {
            try {
                $state = Read-JsonFile $statePath
                Write-DoctorLine "install_state" ("存在，status={0}" -f (Get-PropertyValue $state "installStatus"))
                Write-DoctorLine "venvPython" ([string](Get-PropertyValue $state "venvPython"))
                $venvPython = [string](Get-PropertyValue $state "venvPython")
                if (-not [string]::IsNullOrWhiteSpace($venvPython)) {
                    $venvRoot = Split-Path -Parent (Split-Path -Parent $venvPython)
                    Write-DoctorLine ".offline_dl_ready" $(if (Test-Path -LiteralPath (Join-Path $venvRoot ".offline_dl_ready")) { "存在" } else { "缺失" })
                }
            }
            catch {
                Write-DoctorLine "install_state" "无法解析：$($_.Exception.Message)"
            }
        }
        else {
            Write-DoctorLine "install_state" "缺失"
        }
    }
    else {
        Write-DoctorLine "工作区" "未指定；如需诊断安装状态，请加 -WorkspaceRoot D:\AI"
    }
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
        throw "没有 NVIDIA 驱动来源。请先从 NVIDIA 官方页面下载 RTX 3090 / Windows 10 x64 驱动 exe 放到 downloads\manual_inbox，或在 config.json 写入 nvidiaDriver.url。"
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

function Get-LockPackageNames {
    param([string[]]$RequirementFiles)
    $names = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($file in $RequirementFiles) {
        if ([string]::IsNullOrWhiteSpace($file) -or -not (Test-Path -LiteralPath $file)) {
            continue
        }
        foreach ($line in (Get-Content -LiteralPath $file -Encoding UTF8)) {
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
                continue
            }
            $pkg = ($trimmed -split "==")[0]
            if (-not [string]::IsNullOrWhiteSpace($pkg)) {
                $null = $names.Add(($pkg -replace "[-_.]+", "-").ToLowerInvariant())
            }
        }
    }
    return $names
}

function Move-ResolvedWheelSet {
    param(
        [Parameter(Mandatory = $true)][string]$Staging,
        [Parameter(Mandatory = $true)][string]$TorchDestination,
        [Parameter(Mandatory = $true)][string]$CommonDestination,
        [Parameter(Mandatory = $true)][string]$OptionalDestination,
        [Parameter(Mandatory = $true)]$OptionalPackageNames
    )
    Ensure-Directory $TorchDestination
    Ensure-Directory $CommonDestination
    Ensure-Directory $OptionalDestination

    foreach ($destination in @($TorchDestination, $CommonDestination, $OptionalDestination)) {
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
        $parsed = Parse-WheelFileName $file.Name
        $isOptional = ($null -ne $parsed -and $OptionalPackageNames.Contains($parsed.Package))
        $destination = if ($isTorchCore) { $TorchDestination } elseif ($isOptional) { $OptionalDestination } else { $CommonDestination }
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
        [Parameter(Mandatory = $true)][string[]]$RequirementFiles,
        [string[]]$OptionalRequirementFiles = @(),
        [Parameter(Mandatory = $true)][string]$TorchDestination,
        [Parameter(Mandatory = $true)][string]$CommonDestination,
        [Parameter(Mandatory = $true)][string]$OptionalDestination
    )
    $staging = Join-PackagePath @("wheels", "_resolved_staging")
    Clear-StagingDirectory $staging
    $args = @(
        "-m", "pip", "download",
        "--dest", $staging,
        "--only-binary=:all:",
        "--platform", $Script:Platform,
        "--implementation", "cp",
        "--python-version", "311",
        "--abi", $Script:PythonAbi,
        "--index-url", "https://download.pytorch.org/whl/cu128",
        "--extra-index-url", "https://pypi.org/simple"
    )
    foreach ($requirement in $RequirementFiles) {
        $args += @("-r", $requirement)
    }
    Invoke-LoggedCommand -FilePath $Python -Arguments $args
    $optionalNames = Get-LockPackageNames $OptionalRequirementFiles
    Move-ResolvedWheelSet -Staging $staging -TorchDestination $TorchDestination -CommonDestination $CommonDestination -OptionalDestination $OptionalDestination -OptionalPackageNames $optionalNames
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
    param(
        $Config,
        [string]$DownloadPython,
        [string]$PipVersion,
        [Parameter(Mandatory = $true)][string]$ProfileName,
        [string[]]$OptionalComponents = @(),
        [Parameter(Mandatory = $true)]$LockSelection
    )
    $files = New-Object 'System.Collections.Generic.List[object]'

    $pythonInstaller = Join-PackagePath @("downloads", "python", $Config.components.python.fileName)
    $files.Add((New-ManifestFileEntry -FullPath $pythonInstaller -Component "python-installer" -Group "python" -Kind "installer" -Profile $ProfileName -SourceUrl $Config.components.python.url)) | Out-Null

    $vcInstaller = Join-PackagePath @("downloads", "runtime", $Config.components.vcRuntime.fileName)
    $files.Add((New-ManifestFileEntry -FullPath $vcInstaller -Component "vc-runtime" -Group "runtime" -Kind "installer" -Profile $ProfileName -SourceUrl $Config.components.vcRuntime.url)) | Out-Null

    $driverDir = Join-PackagePath @("downloads", "drivers")
    $drivers = @(Get-ChildItem -LiteralPath $driverDir -File -Filter "*.exe" -ErrorAction SilentlyContinue)
    if ($drivers.Count -eq 0) {
        throw "缺少 NVIDIA 驱动安装包。请把 RTX 3090 Windows 10 x64 驱动 exe 放到 downloads\drivers，或在 config.json 配置 nvidiaDriver.url。"
    }
    foreach ($driver in $drivers) {
        $files.Add((New-ManifestFileEntry -FullPath $driver.FullName -Component "nvidia-driver" -Group "driver" -Kind "installer" -Profile $ProfileName -SourceUrl $Config.components.nvidiaDriver.url -Source $(if ([string]::IsNullOrWhiteSpace($Config.components.nvidiaDriver.url)) { "manual" } else { "download" }))) | Out-Null
    }

    $lockFiles = New-Object 'System.Collections.Generic.List[object]'
    foreach ($lock in @($LockSelection)) {
        if (-not (Test-Path -LiteralPath $lock.Path)) {
            throw "缺少 lock 文件：$($lock.Path)"
        }
        $files.Add((New-ManifestFileEntry -FullPath $lock.Path -Component $lock.Component -Group "requirements" -Kind "lock" -Profile $lock.Profile -Source "local")) | Out-Null
        $lockFiles.Add([ordered]@{
                name    = $lock.Name
                path    = Get-RelativePathFromPackage $lock.Path
                sha256  = Get-Sha256 $lock.Path
                profile = $lock.Profile
                group   = $lock.Group
            }) | Out-Null
    }

    $verifyScript = Join-PackagePath @("scripts", "verify_torch_cuda.py")
    $files.Add((New-ManifestFileEntry -FullPath $verifyScript -Component "verify-script" -Group "script" -Kind "script" -Profile $ProfileName -Source "local")) | Out-Null

    $torchDir = Join-PackagePath @("wheels", "pytorch-cu128")
    foreach ($wheel in Get-ChildItem -LiteralPath $torchDir -File -Filter "*.whl" -ErrorAction SilentlyContinue) {
        $parsed = Parse-WheelFileName $wheel.Name
        $component = if ($null -ne $parsed) { $parsed.Package } else { "pytorch-wheel" }
        $files.Add((New-ManifestFileEntry -FullPath $wheel.FullName -Component $component -Group "pytorch" -Kind "wheel" -Profile $ProfileName -SourceUrl "https://download.pytorch.org/whl/cu128")) | Out-Null
    }

    $commonDir = Join-PackagePath @("wheels", "common")
    foreach ($wheel in Get-ChildItem -LiteralPath $commonDir -File -Filter "*.whl" -ErrorAction SilentlyContinue) {
        $parsed = Parse-WheelFileName $wheel.Name
        $component = if ($null -ne $parsed) { $parsed.Package } else { "research-wheel" }
        $files.Add((New-ManifestFileEntry -FullPath $wheel.FullName -Component $component -Group "research" -Kind "wheel" -Profile $ProfileName -SourceUrl "https://pypi.org/simple")) | Out-Null
    }

    $optionalDir = Join-PackagePath @("wheels", "optional")
    foreach ($wheel in Get-ChildItem -LiteralPath $optionalDir -File -Filter "*.whl" -ErrorAction SilentlyContinue) {
        $parsed = Parse-WheelFileName $wheel.Name
        $component = if ($null -ne $parsed) { $parsed.Package } else { "optional-wheel" }
        $files.Add((New-ManifestFileEntry -FullPath $wheel.FullName -Component $component -Group "visualization" -Kind "wheel" -Profile $ProfileName -SourceUrl "https://pypi.org/simple" -OptionalComponent "Visualization")) | Out-Null
    }

    $manualScan = Get-RegisterLocalFileEntries
    foreach ($warning in $manualScan.Warnings) {
        Write-Warn $warning
    }
    foreach ($entry in @($manualScan.Entries)) {
        if ((-not $entry.required) -and ($OptionalComponents -contains [string]$entry.optionalComponent)) {
            $files.Add($entry) | Out-Null
        }
    }

    foreach ($optional in $OptionalComponents) {
        if ($optional -in @("Git", "CudaToolkit", "VSCode")) {
            $matches = @($files | Where-Object { $_.optionalComponent -eq $optional })
            if ($matches.Count -eq 0) {
                throw "已选择可选组件 $optional，但没有找到对应安装包。请先把安装包放入 downloads\tools_optional 或 downloads\cuda_optional。"
            }
        }
    }

    return [ordered]@{
        schemaVersion          = $Script:SchemaVersion
        phase                  = $Script:Phase
        packageStatus          = "complete"
        createdAt              = Get-IsoTimestamp
        createdByScriptVersion = $Script:ScriptVersion
        profile                = $ProfileName
        optionalComponents     = @($OptionalComponents | Sort-Object)
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
                lockFiles     = @($LockSelection | ForEach-Object { Get-RelativePathFromPackage $_.Path })
                indexUrl      = "https://download.pytorch.org/whl/cu128"
                extraIndexUrl = "https://pypi.org/simple"
                destination   = "wheels\pytorch-cu128 + wheels\common + wheels\optional"
                platform      = $Script:Platform
                pythonAbi     = $Script:PythonAbi
            }
        )
        lockFiles              = $lockFiles.ToArray()
        files                  = $files.ToArray()
    }
}

function Set-JsonProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][AllowNull()]$Value
    )
    if ($null -eq $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
    else {
        $Object.$Name = $Value
    }
}

function New-BaseManifest {
    $verifyScript = Join-PackagePath @("scripts", "verify_torch_cuda.py")

    $lockFiles = New-Object 'System.Collections.Generic.List[object]'
    $files = New-Object 'System.Collections.Generic.List[object]'
    $defaultLocks = Get-LockSelection -ProfileName "Research" -OptionalComponents @()
    foreach ($lock in @($defaultLocks)) {
        if (-not (Test-Path -LiteralPath $lock.Path)) {
            continue
        }
        $lockFiles.Add([ordered]@{
                name    = $lock.Name
                path    = Get-RelativePathFromPackage $lock.Path
                sha256  = Get-Sha256 $lock.Path
                profile = $lock.Profile
                group   = $lock.Group
            }) | Out-Null
        $files.Add((New-ManifestFileEntry -FullPath $lock.Path -Component $lock.Component -Group "requirements" -Kind "lock" -Profile $lock.Profile -Source "local")) | Out-Null
    }
    if (Test-Path -LiteralPath $verifyScript) {
        $files.Add((New-ManifestFileEntry -FullPath $verifyScript -Component "verify-script" -Group "script" -Kind "script" -Source "local")) | Out-Null
    }

    return [pscustomobject][ordered]@{
        schemaVersion          = $Script:SchemaVersion
        phase                  = $Script:Phase
        packageStatus          = "incomplete"
        createdAt              = Get-IsoTimestamp
        createdByScriptVersion = $Script:ScriptVersion
        profile                = $Script:Profile
        optionalComponents     = @()
        pythonMajorMinor       = $Script:PythonMajorMinor
        pythonAbi              = $Script:PythonAbi
        platform               = $Script:Platform
        torchCudaTag           = $Script:TorchCudaTag
        toolchain              = [ordered]@{
            downloadPython = ""
            pip            = ""
            setuptools     = ""
            wheel          = ""
        }
        downloadCommands       = @()
        lockFiles              = $lockFiles.ToArray()
        files                  = $files.ToArray()
    }
}

function Read-OrCreateManifest {
    $manifestPath = Get-ManifestPath
    if (Test-Path -LiteralPath $manifestPath) {
        return Read-JsonFile $manifestPath
    }
    return New-BaseManifest
}

function Add-ManifestFileEntries {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)]$Entries
    )
    $existing = New-Object 'System.Collections.Generic.List[object]'
    foreach ($entry in @(Get-PropertyValue $Manifest "files")) {
        $existing.Add($entry) | Out-Null
    }

    foreach ($newEntry in @($Entries)) {
        $kept = New-Object 'System.Collections.Generic.List[object]'
        foreach ($oldEntry in $existing) {
            if ([string]$oldEntry.path -ne [string]$newEntry.path) {
                $kept.Add($oldEntry) | Out-Null
            }
        }
        $kept.Add($newEntry) | Out-Null
        $existing = $kept
    }
    Set-JsonProperty -Object $Manifest -Name "files" -Value ($existing.ToArray())
}

function Add-ManifestOptionalComponents {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [string[]]$Components
    )
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($component in @(Get-PropertyValue $Manifest "optionalComponents")) {
        if (-not [string]::IsNullOrWhiteSpace($component)) {
            $null = $set.Add([string]$component)
        }
    }
    foreach ($component in $Components) {
        if (-not [string]::IsNullOrWhiteSpace($component)) {
            $null = $set.Add($component)
        }
    }
    Set-JsonProperty -Object $Manifest -Name "optionalComponents" -Value (@($set | Sort-Object))
}

function Test-ManualInstallerFile {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][string]$Kind
    )
    $name = $File.Name.ToLowerInvariant()
    $sizeMB = [math]::Round($File.Length / 1MB, 1)
    $warnings = New-Object 'System.Collections.Generic.List[string]'

    if ($File.Extension.ToLowerInvariant() -ne ".exe") {
        return [pscustomobject]@{ Accept = $false; Warnings = @("不是 exe 安装包：$($File.Name)") }
    }

    switch ($Kind) {
        "nvidia-driver" {
            if ($name -notmatch "nvidia|geforce|studio|game|desktop-win|dch|whql") {
                $warnings.Add("驱动文件名没有明显 NVIDIA / GeForce / Studio / DCH / WHQL 关键词：$($File.Name)") | Out-Null
            }
            if ($File.Length -lt 100MB) {
                $warnings.Add("NVIDIA 驱动文件体积偏小（$sizeMB MB），请确认不是网页下载器。") | Out-Null
            }
        }
        "cuda-toolkit" {
            if ($File.Length -lt 500MB) {
                return [pscustomobject]@{ Accept = $false; Warnings = @("CUDA Toolkit 文件体积偏小（$sizeMB MB），很可能是 network installer，离线包拒绝登记：$($File.Name)") }
            }
            if ($name -notmatch "cuda|toolkit") {
                $warnings.Add("CUDA Toolkit 文件名没有明显 cuda/toolkit 关键词：$($File.Name)") | Out-Null
            }
        }
        "git" {
            if ($name -notmatch "git") {
                return [pscustomobject]@{ Accept = $false; Warnings = @("Git 安装包文件名应包含 Git：$($File.Name)") }
            }
            if ($name -notmatch "64|x64") {
                $warnings.Add("Git 安装包文件名没有明显 64/x64 标记，请确认是 64 位版本。") | Out-Null
            }
        }
        "vscode" {
            if ($name -notmatch "code|vscode|visualstudiocode") {
                return [pscustomobject]@{ Accept = $false; Warnings = @("VS Code 安装包文件名不明确：$($File.Name)") }
            }
        }
        "python" {
            if ($name -notmatch "^python-3\.11.*(amd64|x64).*\.exe$") {
                return [pscustomobject]@{ Accept = $false; Warnings = @("Python 安装包必须是 Python 3.11 x64 / amd64 版本：$($File.Name)") }
            }
            if ($name -match "win32|x86|arm64|embed") {
                return [pscustomobject]@{ Accept = $false; Warnings = @("Python 安装包架构不适合 Win10 x64 + RTX 3090 离线包：$($File.Name)") }
            }
        }
        "vc-runtime" {
            if ($name -notmatch "vc_redist|vcredist") {
                return [pscustomobject]@{ Accept = $false; Warnings = @("VC++ Runtime 安装包文件名不明确：$($File.Name)") }
            }
            if ($name -notmatch "x64") {
                $warnings.Add("VC++ Runtime 文件名没有明显 x64 标记，请确认是 64 位版本。") | Out-Null
            }
        }
    }
    return [pscustomobject]@{ Accept = $true; Warnings = $warnings.ToArray() }
}

function Get-RegisterLocalFileEntries {
    $entries = New-Object 'System.Collections.Generic.List[object]'
    $optionalComponents = New-Object 'System.Collections.Generic.List[string]'
    $warnings = New-Object 'System.Collections.Generic.List[string]'

    $driverDir = Join-PackagePath @("downloads", "drivers")
    foreach ($file in Get-ChildItem -LiteralPath $driverDir -File -Filter "*.exe" -ErrorAction SilentlyContinue) {
        $check = Test-ManualInstallerFile -File $file -Kind "nvidia-driver"
        foreach ($warning in $check.Warnings) { $warnings.Add($warning) | Out-Null }
        if ($check.Accept) {
            $entries.Add((New-ManifestFileEntry -FullPath $file.FullName -Component "nvidia-driver" -Group "driver" -Kind "installer" -Required $true -Source "manual" -UserConfirmed $true -RegisteredByMode "RegisterLocalFiles")) | Out-Null
        }
    }

    $cudaDir = Join-PackagePath @("downloads", "cuda_optional")
    foreach ($file in Get-ChildItem -LiteralPath $cudaDir -File -Filter "*.exe" -ErrorAction SilentlyContinue) {
        $check = Test-ManualInstallerFile -File $file -Kind "cuda-toolkit"
        foreach ($warning in $check.Warnings) { $warnings.Add($warning) | Out-Null }
        if ($check.Accept) {
            $entries.Add((New-ManifestFileEntry -FullPath $file.FullName -Component "cuda-toolkit" -Group "cuda_optional" -Kind "installer" -Required $false -Source "manual" -OptionalComponent "CudaToolkit" -UserConfirmed $true -RegisteredByMode "RegisterLocalFiles")) | Out-Null
            $optionalComponents.Add("CudaToolkit") | Out-Null
        }
    }

    $toolsDir = Join-PackagePath @("downloads", "tools_optional")
    foreach ($file in Get-ChildItem -LiteralPath $toolsDir -File -Filter "*.exe" -ErrorAction SilentlyContinue) {
        $name = $file.Name.ToLowerInvariant()
        if ($name -match "git") {
            $check = Test-ManualInstallerFile -File $file -Kind "git"
            foreach ($warning in $check.Warnings) { $warnings.Add($warning) | Out-Null }
            if ($check.Accept) {
                $entries.Add((New-ManifestFileEntry -FullPath $file.FullName -Component "git" -Group "tools_optional" -Kind "installer" -Required $false -Source "manual" -OptionalComponent "Git" -UserConfirmed $true -RegisteredByMode "RegisterLocalFiles")) | Out-Null
                $optionalComponents.Add("Git") | Out-Null
            }
        }
        elseif ($name -match "code|vscode|visualstudiocode") {
            $check = Test-ManualInstallerFile -File $file -Kind "vscode"
            foreach ($warning in $check.Warnings) { $warnings.Add($warning) | Out-Null }
            if ($check.Accept) {
                $entries.Add((New-ManifestFileEntry -FullPath $file.FullName -Component "vscode" -Group "tools_optional" -Kind "installer" -Required $false -Source "manual" -OptionalComponent "VSCode" -UserConfirmed $true -RegisteredByMode "RegisterLocalFiles")) | Out-Null
                $optionalComponents.Add("VSCode") | Out-Null
            }
        }
        else {
            $warnings.Add("tools_optional 中存在未识别 exe，已跳过：$($file.Name)") | Out-Null
        }
    }

    return [pscustomobject]@{
        Entries            = $entries.ToArray()
        OptionalComponents = $optionalComponents.ToArray()
        Warnings           = $warnings.ToArray()
    }
}

function Invoke-RegisterLocalFilesMode {
    Write-Info "开始登记本地手动放入的安装包。此模式会原子更新 manifest；普通 Check 仍然只读。"
    Write-ManualDownloadHelp -Components @("NvidiaDriver", "Git", "CudaToolkit", "VSCode")
    $organize = Move-ManualInboxFiles
    foreach ($warning in $organize.Warnings) {
        Write-Warn $warning
    }
    foreach ($item in $organize.Moved) {
        Write-Ok ("已整理手动安装包：{0} -> {1}" -f $item.Source, $item.Target)
    }
    $scan = Get-RegisterLocalFileEntries
    foreach ($warning in $scan.Warnings) {
        Write-Warn $warning
    }
    if (@($scan.Entries).Count -eq 0) {
        throw "没有发现可登记的本地文件。请把 NVIDIA 驱动、CUDA/Git/VS Code 安装包放入 downloads\manual_inbox 后重试。"
    }

    Write-Host ""
    Write-Host "将登记以下文件：" -ForegroundColor Green
    foreach ($entry in @($scan.Entries)) {
        Write-Host ("- {0} ({1}, {2})" -f $entry.path, $entry.component, $(if ($entry.required) { "必需" } else { "可选" }))
    }
    Confirm-Continue "确认登记这些文件吗？" "y" | Out-Null

    $manifest = Read-OrCreateManifest
    Set-JsonProperty -Object $manifest -Name "schemaVersion" -Value $Script:SchemaVersion
    Set-JsonProperty -Object $manifest -Name "phase" -Value $Script:Phase
    Set-JsonProperty -Object $manifest -Name "createdByScriptVersion" -Value $Script:ScriptVersion
    Add-ManifestFileEntries -Manifest $manifest -Entries $scan.Entries
    Add-ManifestOptionalComponents -Manifest $manifest -Components $scan.OptionalComponents
    Set-JsonProperty -Object $manifest -Name "packageStatus" -Value "incomplete"

    $manifestPath = Get-ManifestPath
    Write-JsonAtomic $manifest $manifestPath

    $strictCheck = Test-OfflinePackage
    if ($strictCheck.Errors.Count -eq 0) {
        Set-JsonProperty -Object $manifest -Name "packageStatus" -Value "complete"
        Write-JsonAtomic $manifest $manifestPath
        Write-Ok "登记完成，离线包当前已完整。"
    }
    else {
        Set-JsonProperty -Object $manifest -Name "packageStatus" -Value "incomplete"
        Write-JsonAtomic $manifest $manifestPath
        Write-Warn "登记完成，但离线包还不完整。后续请继续运行 Download 或补齐缺失文件，再运行 Check。"
        foreach ($errorMessage in $strictCheck.Errors) {
            Write-Warn $errorMessage
        }
    }
}

function Invoke-DownloadMode {
    $profileName = Resolve-EffectiveProfile
    $optionalComponents = @(Get-SelectedOptionalComponents -ProfileName $profileName)
    $lockSelection = @(Get-LockSelection -ProfileName $profileName -OptionalComponents $optionalComponents)

    Write-Host ""
    Write-Warn "下载内容会保存到当前脚本所在文件夹：$Script:PackageRoot"
    Write-Warn "下载完成后，请拷贝整个文件夹到离线电脑，不要只拷贝 wheels 或 downloads。"
    Write-Info "本次离线包档位：$profileName"
    if (@($optionalComponents).Count -gt 0) {
        Write-Info "本次可选组件：$($optionalComponents -join ', ')"
    }
    else {
        Write-Info "本次不包含可选组件。"
    }
    $downloadHelpComponents = New-Object 'System.Collections.Generic.List[string]'
    foreach ($component in @("Python", "VcRuntime", "NvidiaDriver")) {
        $downloadHelpComponents.Add($component) | Out-Null
    }
    foreach ($component in @($optionalComponents)) {
        if ($component -in @("Git", "CudaToolkit", "VSCode")) {
            $downloadHelpComponents.Add([string]$component) | Out-Null
        }
    }
    Write-ManualDownloadHelp -Components ($downloadHelpComponents.ToArray())
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
    $organize = Move-ManualInboxFiles
    foreach ($warning in $organize.Warnings) {
        Write-Warn $warning
    }
    foreach ($item in $organize.Moved) {
        Write-Ok ("已整理手动安装包：{0} -> {1}" -f $item.Source, $item.Target)
    }
    Assert-NvidiaDriverSourceAvailable $config
    $preScan = Get-RegisterLocalFileEntries
    foreach ($warning in $preScan.Warnings) {
        Write-Warn $warning
    }
    foreach ($optionalInstaller in @("Git", "CudaToolkit", "VSCode")) {
        if ($optionalComponents -contains $optionalInstaller -and @($preScan.OptionalComponents) -notcontains $optionalInstaller) {
            throw "已选择 $optionalInstaller，但没有发现可登记的本地安装包。请先把对应 exe 放入 downloads\tools_optional 或 downloads\cuda_optional。"
        }
    }

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

    $torchDest = Join-PackagePath @("wheels", "pytorch-cu128")
    $commonDest = Join-PackagePath @("wheels", "common")
    $optionalDest = Join-PackagePath @("wheels", "optional")
    Confirm-WheelDirectoryCanBeReplaced $torchDest
    Confirm-WheelDirectoryCanBeReplaced $commonDest
    Confirm-WheelDirectoryCanBeReplaced $optionalDest

    $allRequirementFiles = @($lockSelection | ForEach-Object { $_.Path })
    $optionalRequirementFiles = @($lockSelection | Where-Object { $_.Component -eq "visualization-lock" } | ForEach-Object { $_.Path })
    Download-ResolvedWheels -Python $downloadPython -RequirementFiles $allRequirementFiles -OptionalRequirementFiles $optionalRequirementFiles -TorchDestination $torchDest -CommonDestination $commonDest -OptionalDestination $optionalDest
    Assert-PytorchCu128Wheels

    $manifest = Build-ManifestFromFiles -Config $config -DownloadPython $downloadPython -PipVersion ($pipVersion -join " ") -ProfileName $profileName -OptionalComponents $optionalComponents -LockSelection $lockSelection
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
    Assert-ParameterCombination
    if ([string]::IsNullOrWhiteSpace($Mode)) {
        $selected = Show-MainMenu
        if ([string]::IsNullOrWhiteSpace($selected)) {
            Write-Info "已退出。"
            return 0
        }
        $script:Mode = $selected
        Assert-ParameterCombination
    }

    Start-RunLog $Mode
    switch ($Mode) {
        "Download" { Invoke-DownloadMode }
        "Check" { Invoke-CheckMode }
        "RegisterLocalFiles" { Invoke-RegisterLocalFilesMode }
        "Install" { Invoke-InstallMode }
        "Verify" { Invoke-VerifyMode }
        "Doctor" { Invoke-DoctorMode }
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
