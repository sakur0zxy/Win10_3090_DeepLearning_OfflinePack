# Win10 + RTX 3090 Deep Learning Offline Environment Plan

## 1. Goal

Prepare a reproducible, verifiable, maintainable offline deep learning environment package for an offline Windows 10 x64 + NVIDIA RTX 3090 machine.

Usage model:

```text
Online PC: download the offline package only.
Offline PC: check, install, and verify the environment.
```

Default stack:

- Python 3.11 x64
- PyTorch CUDA 12.8 wheels
- NVIDIA Studio Driver
- Research profile packages

TensorFlow native Windows GPU is not the default path. Normal PyTorch training does not require a separate CUDA Toolkit install.

## 2. Core Principles

- Unified entry, isolated stages.
- Download never installs.
- Python package versions are locked.
- `manifest.json` is the source of truth for package contents.
- Check is read-only.
- Fail fast on missing required files, hash mismatches, profile mismatches, or invalid Python architecture.
- Interactive prompts are Simplified Chinese and beginner-friendly.

## 3. Entry Points

Main script:

```text
OfflineDL-Win10-3090.ps1
```

Beginner-friendly launcher:

```text
OfflineDL-Win10-3090.bat
```

Suggested `.bat`:

```bat
@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0OfflineDL-Win10-3090.ps1" %*
set EXITCODE=%ERRORLEVEL%
if "%1"=="" pause
exit /b %EXITCODE%
```

Phase 1 modes:

```powershell
-Mode Download
-Mode Check
-Mode Install
-Mode Verify
```

`RegisterLocalFiles` and `Doctor` are phase 2 capabilities and are hidden from the phase 1 interactive menu. If these modes are passed on the command line before implementation, the script should print a simple Chinese message:

```text
该功能计划在第二阶段实现，当前版本暂不可用。
```

Menu:

```text
[1] Download  在联网电脑下载离线包
[2] Check     只检查离线包是否完整，不修改文件
[3] Install   在离线电脑安装环境
[4] Verify    验证显卡和 PyTorch 是否可用
[5] Exit      退出
```

## 4. Offline Package Directory

Download always uses `$PSScriptRoot`. It does not ask for a download directory.

Before Download, show a Chinese confirmation prompt:

```text
下载文件会保存到当前脚本所在文件夹：
<脚本所在文件夹>

如果你想把离线包放到移动硬盘或其他位置，请先把整个脚本文件夹移动到目标位置，再运行 Download。
本脚本不会把文件分散下载到其他目录。

确认继续请输入 y：
```

Layout:

```text
Win10_3090_DeepLearning_OfflinePack\
  OfflineDL-Win10-3090.ps1
  OfflineDL-Win10-3090.bat
  config.json
  manifest.json
  PLAN.md
  PLAN.zh-CN.md
  README.md
  downloads\
    drivers\
    python\
    runtime\
    cuda_optional\
    tools_optional\
  wheels\
    pytorch-cu128\
    common\
    optional\
  requirements\
    torch-cu128.lock.txt
    research.lock.txt
  scripts\
  docs\
    troubleshooting.md
    common-errors.md
  logs\
  backups\
```

## 5. AI Workspace

Install asks for one workspace root. Default:

```text
D:\AI
```

Derived layout:

```text
D:\AI\
  envs\dl-py311-cu128\
  datasets\raw\
  datasets\processed\
  datasets\external\
  datasets\cache\
  models\pretrained\
  models\checkpoints\
  models\exported\
  experiments\runs\
  experiments\mlruns\
  experiments\outputs\
  experiments\reports\
  notebooks\
  projects\
  state\
    install_state.json
    resolved-install.lock.txt
  cache\huggingface\
  cache\torch\
  cache\pip\
  activate-dl.ps1
  activate-dl.bat
```

Run naming:

```text
<task>\<model>_<dataset>\<run_id>
```

## 6. Components And Profiles

Phase 1 scope must be as narrow as the menu:

```text
Supported: -Mode Download / Check / Install / Verify
Not exposed: -Profile
Internal fixed profile: Research
Fixed: Python 3.11
Fixed: PyTorch CUDA 12.8
Not supported: -IncludeGit
Not supported: -IncludeCudaToolkit
Not supported: -IncludeVisualization
Not supported: -ReuseVenv
Not supported: any -Profile parameter
```

If a phase 2 option is passed, the script must not silently ignore it. It should print:

```text
该选项属于第二阶段能力，当前版本暂不可用。
```

Required:

| Component | Default | Notes |
|---|---|---|
| NVIDIA driver | RTX 3090-compatible Studio Driver | Downloaded, not silently installed |
| Python | Python 3.11.x Windows x64 | Downloaded, validated as 64-bit |
| VC++ Runtime | `VC_redist.x64.exe` | Downloaded, heuristically checked |
| PyTorch | CUDA 12.8 wheels | Required |
| Python wheels | Lock-file driven | Required |

Optional:

These optional components are long-term design items. Phase 1 keeps them in the plan only and does not expose them in the interactive menu.

| Component | Parameter | Notes |
|---|---|---|
| Git | `-IncludeGit` | Local repos/history/sync |
| CUDA Toolkit | `-IncludeCudaToolkit` | Local installer only |
| Visualization | `-IncludeVisualization` | seaborn, plotly, ipywidgets, mlflow |
| VS Code | Future/manual | Not default |

Long-term profile design:

```text
Phase 1 = fixed Research, no public -Profile parameter
Minimal = smallest runtime
Research = default research environment
Full = Research + development/build tools; not Visualization
Visualization = independent optional switch
```

Minimal, Full, and Visualization are phase 2 or long-term design items. In phase 1, passing `-Profile` should return the phase 2/unavailable message.

## 7. Source-Of-Truth Files

```text
config.json                         Desired environment and URLs
requirements\*.lock.txt             Exact Python package versions
manifest.json                       Offline package contents and hashes
<WorkspaceRoot>\state\install_state.json  Installed environment state
```

`install_state.json` lives only in the AI workspace.

## 8. Lock Files

Lock files are pinned and must be included in manifest verification:

```text
requirements\torch-cu128.lock.txt
requirements\research.lock.txt
```

`manifest.json` records each lock file path and SHA256.

Phase 1 reads only `torch-cu128.lock.txt` and `research.lock.txt`. `minimal.lock.txt` and `visualization.lock.txt` are phase 2 placeholders; even if they exist, phase 1 Check / Install must not treat them as required files.

Lock file rules:

- Phase 1 pins top-level package versions first, so the smallest closed loop can be implemented and tested.
- `torch-cu128.lock.txt` declares only `torch`, `torchvision`, and `torchaudio`; `research.lock.txt` must not repeat those PyTorch core packages.
- `manifest.files` records every actually downloaded wheel with size and SHA256, and is the phase 1 final package-completeness source.
- The long-term goal is a complete resolved dependency lock with direct and transitive dependencies pinned.
- Future enhancement: complete dependency-tree lock, hash lock, and `--require-hashes`; not required for the first closed loop.

## 9. Manifest

Suggested top-level fields:

```json
{
  "schemaVersion": 1,
  "phase": 1,
  "packageStatus": "complete",
  "createdAt": "2026-04-29T00:00:00+08:00",
  "createdByScriptVersion": "0.1.0",
  "configHash": "...",
  "profile": "Research",
  "optionalComponents": [],
  "pythonMajorMinor": "3.11",
  "pythonAbi": "cp311",
  "platform": "win_amd64",
  "pythonInstaller": {
    "component": "Python",
    "version": "3.11.x",
    "arch": "x64",
    "installer": "python-3.11.x-amd64.exe"
  },
  "torchCudaTag": "cu128",
  "toolchain": {
    "downloadPython": "3.11.x",
    "pip": "xx.x",
    "setuptools": "xx.x",
    "wheel": "xx.x"
  },
  "downloadCommands": [
    {
      "component": "pytorch",
      "lockFile": "requirements/torch-cu128.lock.txt",
      "targetDir": "wheels/pytorch-cu128",
      "indexUrl": "https://download.pytorch.org/whl/cu128",
      "pythonVersion": "311",
      "abi": "cp311",
      "platform": "win_amd64"
    },
    {
      "component": "research",
      "lockFile": "requirements/research.lock.txt",
      "targetDir": "wheels/common",
      "indexUrl": "https://pypi.org/simple",
      "pythonVersion": "311",
      "abi": "cp311",
      "platform": "win_amd64"
    }
  ],
  "lockFiles": [],
  "files": []
}
```

Each `manifest.files` entry should include file type and component metadata:

```json
{
  "component": "torch",
  "group": "pytorch",
  "kind": "wheel",
  "required": true,
  "profile": "Research",
  "path": "wheels/pytorch-cu128/torch-xxx.whl",
  "fileName": "torch-xxx.whl",
  "size": 123456,
  "sha256": "...",
  "sourceUrl": "...",
  "source": "download",
  "downloadedAt": "2026-04-29T00:00:00+08:00"
}
```

Suggested `group` values:

```text
driver
python
runtime
pytorch
research
script
doc
```

`kind` should include at least:

```text
installer
wheel
lock
script
doc
```

`packageStatus` values:

```text
incomplete: download is unfinished or internal validation has not passed
complete: package is complete and installable
failed: Download or RegisterLocalFiles internal validation failed
```

Install requires:

```text
packageStatus == complete
schemaVersion == 1
phase == 1
optionalComponents == []
```

If `phase` is not 1, or `optionalComponents` is not an empty array, phase 1 must stop and report that the manifest may come from a future version or non-phase-1 package.

Status transitions:

```text
Download starts: incomplete
Files downloaded but not checked: incomplete
Download internal validation passes: complete
Download internal validation fails: failed
RegisterLocalFiles internal validation passes: complete
RegisterLocalFiles internal validation fails: failed
```

Regular Check remains read-only and never updates `packageStatus`.

Manifest writes must be atomic:

```text
write manifest.json.tmp
parse tmp to validate JSON
backup old manifest to backups\
replace manifest.json
```

Only Download, RegisterLocalFiles, and successful Force redownloads write manifest. Check, Install, and Verify are read-only with respect to manifest.

## 10. Download Mode

Flow:

```text
Show package-root prompt and require y
Read config
Use fixed Research; reject phase 1-unavailable profiles/options
Print current download Python, pip, and target platform
Check package drive
Scan .part files
Check network/TLS
Download driver, Python, VC++ Runtime, wheels
Verify size/SHA256
Write manifest atomically
Run Check
```

Target wheel platform:

```text
win_amd64 / CPython 3.11 / cp311
```

PyTorch download uses the PyTorch CUDA index:

```powershell
python -m pip download -r .\requirements\torch-cu128.lock.txt `
  --dest .\wheels\pytorch-cu128 `
  --only-binary=:all: `
  --platform win_amd64 `
  --implementation cp `
  --python-version 311 `
  --abi cp311 `
  --index-url https://download.pytorch.org/whl/cu128 `
  --extra-index-url https://pypi.org/simple
```

Download starts by printing and logging:

```text
当前下载用 Python：<path/version>
当前 pip：<version>
目标下载平台：win_amd64 / cp311
```

The exact `torch-cu128.lock.txt` version syntax must be validated on the online PC with a real successful `pip download`. Do not guess between `torch==x.x.x` and `torch==x.x.x+cu128`; derive the first version from a known-good download so the script does not accidentally fetch CPU wheels or fail to find CUDA wheels.

After PyTorch download, hard-check wheel filenames:

```text
torch wheel lowercase filename must contain cu128
torchvision wheel lowercase filename must contain cu128
torchaudio wheel lowercase filename must contain cu128
```

Use a lowercase contains check such as `$fileName.ToLower().Contains("cu128")`. If any PyTorch core wheel lacks `cu128`, fail immediately to avoid accidentally using CPU wheels.

Download rules:

- Skip only when manifest, size, and SHA256 match.
- Download to `<target>.part`, then rename after verification.
- On startup, `.part` files are deleted and redownloaded only after confirmation, or automatically with `-Force`.
- Network checks use HTTPS HEAD/GET, not only ping.
- Enable TLS 1.2 for PowerShell 5.1 before HTTPS requests.

`-Force` limits:

- May overwrite Download-managed target files only.
- Does not delete venvs.
- Does not touch user projects, datasets, or model directories.
- Does not skip SHA256 verification.
- Does not allow Check to write manifest.

## 11. RegisterLocalFiles Mode (Phase 2)

Registers manually placed installers into manifest.

Phase 1 does not implement this mode and does not show it in the menu. If passed from the command line, return the Chinese “phase 2/currently unavailable” message.

When registering a Python installer, accept only normal `x64/amd64` installers for the target machine. Reject `win32`, `x86`, `arm64`, and `embed` packages.

Flow:

```text
Scan downloads\drivers, downloads\cuda_optional, downloads\tools_optional
Show detected files
Explain the component in Chinese
Ask for confirmation
Calculate size/SHA256
Write manifest atomically
```

Register NVIDIA drivers as `source: manual`. CUDA Toolkit must be a local installer, not a network installer.

Safety checks:

- NVIDIA driver: `.exe`, filename should suggest NVIDIA/Studio/Game Ready/GeForce, warn if too small.
- CUDA Toolkit: local installer only; reject small network installers.
- Git: filename should indicate Git / 64-bit installer.
- Manual entries record `source`, `registeredAt`, `registeredByMode`, and `userConfirmed`.

## 12. Check Mode

Check is always read-only.

Implementation must separate the internal validation function from Check mode:

```text
Test-OfflinePackage: check only, return a result object, write no files
Invoke-CheckMode: call Test-OfflinePackage and print results, write no manifest
Write-ManifestAtomic: called only by writable flows such as Download / RegisterLocalFiles
```

Download may call `Test-OfflinePackage`, but Download itself decides whether to atomically write `packageStatus`. Check mode must never write manifest.

It verifies:

```text
manifest parse
schemaVersion == 1
phase == 1
optionalComponents == []
packageStatus
lock file hashes
required files
size/SHA256
manifest.files wheel existence, size, and SHA256
fixed Research required components are present in manifest.files
```

It never modifies manifest, registers local files, or repairs files.

Phase 1 required components include at least:

```text
NVIDIA Driver installer
Python 3.11 x64 installer
VC++ Runtime installer
torch wheel
torchvision wheel
torchaudio wheel
Research wheels
requirements lock files
verify_torch_cuda.py
```

Phase 1 Check is based on `manifest.files` and does not implement a complex wheel tag parser:

```text
reject .tar.gz / .zip source archives
confirm every manifest wheel exists
confirm size and SHA256 match
warn or fail on obvious cp312/linux/win32 incompatibilities
```

Phase 1 also scans duplicate wheels and version conflicts:

```text
scan wheels\pytorch-cu128, wheels\common, wheels\optional
same filename + same SHA256: allow
same filename + different SHA256: fail
same package/version with different filenames: warn
same package with different versions: fail
```

Phase 2 can add stricter wheel coverage for each locked package:

```text
package name matches
version matches
Python tag / ABI / platform are compatible with cp311 / win_amd64
a wheel exists
source archives only are not accepted
```

## 13. Install Mode

Flow:

```text
Read manifest
Require packageStatus == complete
Run Check
Resolve WorkspaceRoot
Check workspace drive
Check OS, nvidia-smi, VC++ Runtime, Python 3.11 x64, pip, venv
Create workspace
Handle existing venv: phase 1 supports clean installs only
Generate resolved-install.lock.txt from manifest-selected lock files
Install offline
Run pip check
Generate activate scripts
Run basic Verify: torch import and CUDA available
Write install_state.json only after all success checks pass
Run Verify for the full report
```

Install treats manifest as the source of truth:

```text
lock files generate resolved-install.lock.txt
manifest.files confirms which files the package actually has
obvious lock / manifest.files mismatches fail immediately
```

Phase 1 does not require `pip install --dry-run`, because old pip versions may not support it reliably. It can be an optional diagnostic enhancement. A real `pip install` failure must stop, preserve pip logs, and never write success state.

If `nvidia-smi` is missing, show a clear Chinese prompt:

```text
Install 要求 NVIDIA 驱动已安装并且 nvidia-smi 可用。
如果你还没有安装驱动，请先手动安装 downloads\drivers 中的驱动并重启。
```

Install also checks GPU name:

```text
no NVIDIA GPU detected: fail
RTX 3090 detected: continue
NVIDIA GPU detected but not RTX 3090: interactive warning and ask whether to continue
NonInteractive + GPU mismatch: fail
```

Prompt example:

```text
当前检测到 GPU：NVIDIA GeForce RTX 3090
目标 GPU：NVIDIA RTX 3090
```

Python validation must include:

```text
python --version == 3.11.x
Python is 64-bit
python -m pip --version works
python -m venv --help works
```

If Python exists but pip/venv is unavailable, show:

```text
检测到 Python 3.11，但 pip/venv 不可用。
请重新运行 Python 安装包，选择 Modify，并启用 pip 和 venv。
```

Existing venv handling in phase 1:

```text
[1] Delete and recreate environment
[2] Exit
```

Deletion requires typing `DELETE`. `-Yes` does not delete. `-RecreateVenv` explicitly permits recreation in command-line mode.

Phase 1 does not support `ReuseVenv`. In command-line mode, if venv already exists and `-RecreateVenv` was not passed, fail and ask for explicit recreation.

Clean venv rules:

```text
if venv does not exist: create it
if venv exists without .offline_dl_ready: require delete and recreate
if venv exists with .offline_dl_ready: still require DELETE and recreate
```

Before deleting a venv, perform deletion-safety checks:

```text
VenvPath must equal <WorkspaceRoot>\envs\dl-py311-cu128
directory name must be dl-py311-cu128, or the directory must contain .offline_dl_installing / .offline_dl_ready
```

If the path is outside WorkspaceRoot, is not the expected venv path, or neither the directory name nor marker files match, refuse automatic deletion and report that the directory does not look like a venv created by this script.

`ReuseVenv` is a phase 2 capability. Before reusing a venv in the future:

```text
venvPython exists
venv Python version matches manifest.pythonMajorMinor
venv Python is 64-bit
if torch is already installed, torch.version.cuda matches the target CUDA runtime
```

Future `ReuseVenv` only fills missing dependencies. If core package conflicts, CPU-only torch, or CUDA mismatches are found, fail and recommend `RecreateVenv`.

`installStatus = success` is written only after all of these pass:

```text
venv create or reuse check
pip install
pip check
torch import
torch.cuda.is_available() == True
```

On failure, do not write a success-looking `install_state.json`. The rule is:

```text
Install success: write install_state.json
Install failure: write install_state.failed.json
```

A failed attempt must not overwrite an existing successful `install_state.json`.

Phase 1 uses venv marker files to avoid reusing half-installed environments:

```text
install starts: write <venv>\.offline_dl_installing
install succeeds: delete .offline_dl_installing and write <venv>\.offline_dl_ready
```

If the next Install finds `.offline_dl_installing` without `.offline_dl_ready`, warn that the previous install may have been interrupted and the venv is not trustworthy; recommend delete and recreate.

Lock composition:

```text
Always: torch-cu128.lock.txt
Phase 1 fixed Research: research.lock.txt
Visualization: phase 2 adds visualization.lock.txt
```

Install once from:

```text
<WorkspaceRoot>\state\resolved-install.lock.txt
```

The resolved lock file should include a header:

```text
# Generated by OfflineDL-Win10-3090.ps1
# Source manifest sha256: ...
# Profile: Research
# Optional components: none
# Generated at: ...
# Do not edit manually.
```

Using all wheel directories:

```text
wheels\pytorch-cu128
wheels\common
wheels\optional
```

All pip operations must use:

```powershell
& $VenvPython -m pip ...
```

Never call bare `pip` or rely on PATH pip.

VC++ Runtime detection is heuristic: missing DLLs stop Install; existing DLLs are treated as "maybe installed".

Install generates:

```text
<WorkspaceRoot>\activate-dl.ps1
<WorkspaceRoot>\activate-dl.bat
```

Suggested `install_state.json` includes `schemaVersion`, `installStatus`, `venvPython`, `sourceManifestHash`, `resolvedLockSha256`, and script version.

## 14. Verify Mode

Verify uses `install_state.json` and must not silently fall back to system Python.

Verify checks that `.offline_dl_ready` exists in the venv directory.

If the current offline package directory contains `manifest.json`, Verify calculates the current manifest hash and compares it with `install_state.sourceManifestHash`.

It reports:

```text
NVIDIA Driver Version
nvidia-smi CUDA Version
torch.__version__
torch.version.cuda
GPU name
CUDA matmul result
```

The default CUDA matmul test uses a small 1024 x 1024 matrix. It only proves CUDA can run; it is not a stress test. A future `-Stress` option can add larger matrix and VRAM tests.

Important user note:

```text
nvidia-smi 显示的 CUDA Version 代表驱动支持能力，不代表已安装 CUDA Toolkit。
普通 PyTorch 训练通常不需要单独安装 CUDA Toolkit。
```

Compatibility rule:

```text
Driver CUDA Version >= PyTorch CUDA Runtime: OK
Driver CUDA Version < PyTorch CUDA Runtime: fail, driver too old
Driver CUDA Version > PyTorch CUDA Runtime: OK, no warning
```

Compare CUDA versions numerically by major/minor, not as strings. `12.10` is greater than `12.8`.

If `torch.version.cuda == None`, fail with a clear message that CPU-only PyTorch was likely installed and cu128 wheels are required.

`sourceManifestHash` rules:

```text
current manifest matches install_state.sourceManifestHash: OK
current manifest differs: warn, do not fail
current manifest not found: continue Verify, but warn that source cannot be confirmed
```

Warning message:

```text
当前离线包 manifest 与安装时来源不一致，Verify 只验证当前环境可用性，不代表此环境由当前离线包安装。
```

If `.offline_dl_ready` is missing, Verify should warn but continue:

```text
未发现 .offline_dl_ready，环境可能不是由本脚本完整安装。将继续验证，但来源完整性无法确认。
```

## 15. Disk And Filesystem

Download checks the package drive. Install checks the workspace drive.

Filesystem guidance:

```text
Windows-only: prefer NTFS
Cross-platform removable drive: exFAT is acceptable
FAT32: block
```

Package free-space minimum:

```text
Minimal: 20 GB
Research: 30 GB
Research + Visualization: 50 GB
Full + CUDA Toolkit: 80 GB
```

Workspace free-space guidance:

```text
Minimum: 50 GB
Recommended: 100 GB+
Image/SAR/large model/checkpoint-heavy work: 200 GB+
```

## 16. Logs, Exit Codes, Diagnostics

Each run writes a timestamped log under `logs`.

Exit codes:

```text
0 success
1 general failure
2 manifest validation failed
3 required component missing
4 Python version/architecture mismatch
5 CUDA/GPU verification failed
6 disk/filesystem failed
7 user cancelled
```

Failures include a doctor-style summary:

```text
OS, PowerShell, Python, NVIDIA, nvidia-smi, VC++ Runtime, Manifest, Wheels, Venv
```

Logs must include external commands, exit codes, stdout/stderr summaries, and the last 50 output lines on failure. Key commands: `pip download`, `pip install`, `pip check`, `nvidia-smi`.

Phase 1 does not automatically clean logs. README should say:

```text
logs 目录可定期手动清理，不影响离线包安装。
manifest、requirements、wheels、downloads 不要手动删除。
```

Doctor mode:

- Read-only.
- Reports OS, PowerShell, Python, NVIDIA/nvidia-smi, VC++ Runtime, manifest, wheels, workspace status.
- Planned for phase 2; failure summaries are part of phase 1.

## 17. Automation And Safety Parameters

```text
-Yes
-NonInteractive
-Force
-RecreateVenv
-PersistEnvVars
```

`-Yes` accepts safe defaults only. Destructive operations still require explicit parameters or `DELETE`.

Phase 1 does not support `-ReuseVenv`. If passed, return the phase 2/unavailable message.

## 18. Implementation Rules

- Use `Join-Path`.
- Prefer `-LiteralPath`.
- Use `&` for external commands.
- Do not use `Invoke-Expression` for built command strings.
- README must document PowerShell execution-policy bypass.
- README must include a beginner-friendly recommended flow for online and offline PCs.
- README must say the script does not automatically install NVIDIA Driver, Python, or VC++ Runtime; users must manually run the installers from `downloads` when prompted and reboot when needed.
- README must remind users to copy the whole `Win10_3090_DeepLearning_OfflinePack` folder to the offline PC, not only `wheels` or `downloads`.
- README should recommend workspace paths without spaces or special characters, such as `D:\AI` or `E:\AI`; avoid paths like `E:\AI Workspace`.
- Add `docs\troubleshooting.md` and `docs\common-errors.md` for common failures.

## 19. Git Decision

Git is optional and unsupported in phase 1. Download it in phase 2 only when local history, local bare repos, or Git-based removable-drive/LAN sync is needed.

## 20. Next Steps

First implement the smallest stable loop:

```text
Online Download -> Check -> copy -> offline Check -> Install -> Verify
```

Phase 1:

```text
Download / Check / Install / Verify
fixed Research
clean venv install
PyTorch CUDA 12.8
Python 3.11 x64
manifest.files / top-level lock / SHA256 validation
hide unimplemented menu items
```

Phase 2:

```text
RegisterLocalFiles
Visualization
Doctor
CUDA Toolkit local installer checks
VS Code
Minimal / Full / -Profile
ReuseVenv
complete dependency-tree locks
hashlock / --require-hashes
```

Concrete next steps:

1. Create `config.json`.
2. Create phase 1 top-level pinned lock files and record actual downloaded wheels in `manifest.files`.
3. Create `OfflineDL-Win10-3090.ps1` and `.bat`.
4. Create verification scripts.
5. Create README and troubleshooting docs.
6. Test the phase 1 closed loop.

Recommended implementation order:

```text
1. Base paths, parameters, and logging
2. Manifest read/write, SHA256, atomic writes
3. Check
4. Verify
5. Install
6. Download
```

Recommended test order:

```text
Prepare a tiny wheel test package and manifest by hand, then make Check pass.
Test Install against an existing Python environment.
Test Verify on the RTX 3090 machine.
Implement real Download last.
```

## 21. Phase 1 P0 Implementation Checklist

Download:

```text
confirm target directory
reject FAT32
check free space
check TLS / network
print current Python / pip / target platform
pip download fixed to win_amd64 / cp311
PyTorch wheel lowercase filename contains cu128
generate manifest.files
verify SHA256
write manifest atomically
```

Check:

```text
Check is read-only
manifest parses
schemaVersion == 1
phase == 1
optionalComponents == []
packageStatus == complete
lock SHA256 matches
required components are present in manifest.files
manifest.files existence / size / SHA256 match
reject source archives
scan duplicate wheels / multiple wheel versions
```

Install:

```text
packageStatus == complete
run Check first
nvidia-smi exists
GPU is RTX 3090 or interactively confirmed
Python 3.11 x64 / pip / venv work
existing venv must be deleted and recreated
DELETE required before deletion
VenvPath must equal <WorkspaceRoot>\envs\dl-py311-cu128
delete target must be dl-py311-cu128 or contain this script's marker files
write .offline_dl_installing
pip install succeeds
pip check succeeds
torch import + CUDA available
write .offline_dl_ready
write install_state.json
```

Verify:

```text
read install_state.json
use venvPython
check .offline_dl_ready
pip check
torch.version.cuda is not None
compare driver CUDA and torch CUDA numerically
1024 x 1024 CUDA matmul
```
