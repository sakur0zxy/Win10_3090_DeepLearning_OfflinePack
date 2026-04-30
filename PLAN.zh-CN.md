# Win10 + RTX 3090 深度学习离线环境计划

## 1. 目标和定位

为一台离线 Windows 10 x64 + NVIDIA RTX 3090 电脑准备可复现、可校验、可长期维护的深度学习离线环境包。

使用方式：

```text
联网电脑：下载离线包，不安装。
离线电脑：检查离线包，安装环境，验证 GPU/PyTorch。
```

默认技术栈：

- Python 3.11 x64
- PyTorch CUDA 12.8 wheels
- NVIDIA Studio Driver
- Research 档位科研常用依赖

TensorFlow 原生 Windows GPU 支持已过时，不作为默认路线。普通 PyTorch 训练不需要单独安装 CUDA Toolkit。

## 2. 核心原则

- 统一入口，阶段隔离：一个主脚本，多种模式。
- 下载不安装：避免把 Win10 + 3090 的目标环境误装到联网 AMD 电脑。
- 版本锁定：Python 包使用 lock 文件，不依赖 latest。
- manifest 绑定：Check 和 Install 以 `manifest.json` 为事实来源。
- Check 只读：检查不修改状态，不登记文件，不修复文件。
- 失败即停：必需组件缺失、哈希不一致、Profile 不匹配、Python 位数不对时直接停止。
- 中文优先：交互提示使用简体中文，尽量让小白也能看懂。

## 3. 操作入口

主逻辑：

```text
OfflineDL-Win10-3090.ps1
```

小白双击入口：

```text
OfflineDL-Win10-3090.bat
```

`.bat` 只负责进入脚本目录并调用 PowerShell，不写复杂逻辑：

```bat
@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0OfflineDL-Win10-3090.ps1" %*
set EXITCODE=%ERRORLEVEL%
if "%1"=="" pause
exit /b %EXITCODE%
```

第一阶段主模式：

```powershell
-Mode Download
-Mode Check
-Mode Install
-Mode Verify
```

`RegisterLocalFiles` 和 `Doctor` 属于第二阶段能力，第一阶段不出现在交互菜单里。若命令行传入未实现模式，应直接用中文提示：

```text
该功能计划在第二阶段实现，当前版本暂不可用。
```

无 `-Mode` 时显示中文菜单：

```text
Win10 + RTX 3090 深度学习离线环境工具

[1] Download  在联网电脑下载离线包
[2] Check     只检查离线包是否完整，不修改文件
[3] Install   在离线电脑安装环境
[4] Verify    验证显卡和 PyTorch 是否可用
[5] Exit      退出
```

## 4. 离线包目录

Download 模式固定使用脚本所在目录 `$PSScriptRoot`，不询问下载目录。

Download 开始前必须提示并要求用户输入 `y` 确认：

```text
下载文件会保存到当前脚本所在文件夹：
<脚本所在文件夹>

如果你想把离线包放到移动硬盘或其他位置，请先把整个脚本文件夹移动到目标位置，再运行 Download。
本脚本不会把文件分散下载到其他目录。

确认继续请输入 y：
```

目录结构：

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
    verify_torch_cuda.py
    test_one_batch.py

  docs\
    troubleshooting.md
    common-errors.md

  logs\
  backups\
```

## 5. AI 工作区目录

Install 模式只询问一个 AI 工作区根目录，默认建议：

```text
D:\AI
```

派生目录：

```text
D:\AI\
  envs\
    dl-py311-cu128\

  datasets\
    raw\
    processed\
    external\
    cache\

  models\
    pretrained\
    checkpoints\
    exported\

  experiments\
    runs\
    mlruns\
    outputs\
    reports\

  notebooks\
    classification\
    segmentation\

  projects\

  state\
    install_state.json
    resolved-install.lock.txt

  cache\
    huggingface\
    torch\
    pip\

  activate-dl.ps1
  activate-dl.bat
```

多任务命名规则：

```text
<任务>\<模型>_<数据集>\<run_id>
```

示例：

```text
D:\AI\experiments\runs\classification\resnet50_cats_vs_dogs\2026-04-29_001
D:\AI\models\checkpoints\segmentation\unet_cityscapes\2026-04-29_001
```

## 6. 组件和档位

第一阶段范围必须和菜单一样收敛：

```text
只支持：-Mode Download / Check / Install / Verify
不暴露：-Profile
内部固定：Research
固定：Python 3.11
固定：PyTorch CUDA 12.8
不支持：-IncludeGit
不支持：-IncludeCudaToolkit
不支持：-IncludeVisualization
不支持：-ReuseVenv
不支持：任何 -Profile 参数
```

如果用户传入第二阶段参数，不能静默忽略，必须明确提示：

```text
该选项属于第二阶段能力，当前版本暂不可用。
```

必需组件：

| 组件 | 默认选择 | 说明 |
|---|---|---|
| NVIDIA 驱动 | RTX 3090 兼容 Studio Driver | 必需下载，不静默安装 |
| Python | Python 3.11.x Windows x64 | 必需下载，安装时验证 64 位 |
| VC++ Runtime | `VC_redist.x64.exe` | 必需下载，安装时启发式检测 |
| PyTorch | `torch/torchvision/torchaudio` CUDA 12.8 wheels | 必需 |
| Python wheels | 由 lock 文件决定 | 必需 |

可选组件：

下面的可选组件是长期设计，第一阶段只保留为规划，不暴露在交互菜单中。

| 组件 | 参数 | 说明 |
|---|---|---|
| Git | `-IncludeGit` | 本地仓库、代码历史、移动盘同步需要时下载 |
| CUDA Toolkit | `-IncludeCudaToolkit` | 只接受 local installer，不下载 network installer |
| 可视化增强 | `-IncludeVisualization` | `seaborn/plotly/ipywidgets/mlflow` |
| VS Code | 未来可选或手动 | 当前不默认下载 |

长期 Profile 设计：

```text
第一阶段：固定 Research，不暴露 -Profile 参数。
Minimal：最小运行环境。
Research：默认科研环境。
Full：Research + 开发/编译工具，例如 Git、CUDA Toolkit。
Visualization：独立可选项，不属于 Full。
```

注意：Minimal / Full / Visualization 都属于第二阶段或长期设计。第一阶段如果用户传入 `-Profile`，应提示该参数属于第二阶段能力。

## 7. 状态文件职责

```text
config.json                    目标环境和下载配置
requirements\*.lock.txt        精确 Python 包和版本
manifest.json                  离线包内容、哈希、Profile、可选组件
<WorkspaceRoot>\state\install_state.json  某台电脑上的安装结果
```

`install_state.json` 只属于 AI 工作区，不放在离线包目录中。

## 8. lock 文件

lock 文件必须固定版本，并纳入 manifest 校验。

```text
requirements\
  torch-cu128.lock.txt          PyTorch CUDA 栈
  research.lock.txt             Research 普通包
```

第一阶段只读取 `torch-cu128.lock.txt` 和 `research.lock.txt`。`minimal.lock.txt`、`visualization.lock.txt` 属于第二阶段预留；即使目录中存在，第一阶段 Check / Install 也不能把它们当成必需文件。

`manifest.json` 必须记录 lock 文件 SHA256：

```json
{
  "lockFiles": [
    {
      "path": "requirements/torch-cu128.lock.txt",
      "sha256": "...",
      "profile": "Base"
    },
    {
      "path": "requirements/research.lock.txt",
      "sha256": "...",
      "profile": "Research"
    }
  ]
}
```

Check 和 Install 都必须确认 lock 文件未被修改。

lock 文件规则：

- 第一阶段 lock 文件固定顶层包版本，先保证最小闭环可落地。
- `torch-cu128.lock.txt` 只声明 `torch`、`torchvision`、`torchaudio`，`research.lock.txt` 不重复声明这些 PyTorch 核心包。
- `manifest.files` 记录实际下载到的全部 wheel 文件、大小和 SHA256，作为第一阶段离线包完整性的最终依据。
- 长期目标是完整依赖锁：包含直接依赖和间接依赖，且所有包都固定版本。
- 复杂的完整依赖树 lock、`--require-hashes` / hashlock 暂列未来增强，不进入第一版闭环实现。

## 9. manifest 设计

`manifest.json` 是离线包事实来源。

建议顶层字段：

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

`manifest.files` 条目建议包含文件类型和组件信息，方便 Check 输出清晰错误：

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

`group` 建议使用：

```text
driver
python
runtime
pytorch
research
script
doc
```

`kind` 至少包括：

```text
installer
wheel
lock
script
doc
```

`packageStatus`：

```text
incomplete：下载未完成或未通过内部校验。
complete：离线包完整，可安装。
failed：Download 或 RegisterLocalFiles 流程中的内部校验失败。
```

Install 前必须要求：

```text
packageStatus == complete
schemaVersion == 1
phase == 1
optionalComponents == []
```

如果 `phase` 不是 1，或 `optionalComponents` 不是空数组，第一阶段脚本必须停止，并提示该 manifest 可能来自未来版本或非第一阶段离线包，当前脚本不支持。

`packageStatus` 流转：

```text
Download 开始：incomplete
文件下载完成但未校验：incomplete
Download 内部校验通过：complete
Download 内部校验失败：failed
RegisterLocalFiles 登记后内部校验通过：complete
RegisterLocalFiles 内部校验失败：failed
```

普通 Check 永远只读，不更新 `packageStatus`。Download / RegisterLocalFiles 可以调用校验函数，但由当前模式自己负责原子写回 manifest。

manifest 写入必须原子化：

```text
写 manifest.json.tmp
重新读取 tmp 确认 JSON 可解析
备份旧 manifest 到 backups\manifest-时间戳.json
用 tmp 替换 manifest.json
```

允许写 manifest 的模式：

```text
Download
RegisterLocalFiles
Force 重新下载成功后
```

禁止写 manifest 的模式：

```text
Check
Install
Verify
```

## 10. Download 模式

用途：在联网电脑下载离线包，不安装。

流程：

```text
显示下载目录提醒，要求输入 y
读取 config.json
固定使用 Research，不解析第一阶段未开放的 Profile/可选组件
输出当前下载用 Python、pip 和目标下载平台
检查离线包所在盘：可写、非 FAT32、空间足够
扫描并处理 .part 文件
检查网络和 TLS
下载驱动、Python、VC++ Runtime、wheels
校验大小和 SHA256
写 manifest
自动运行 Check
```

目标 wheel 平台固定为：

```text
Windows x64
CPython 3.11
ABI cp311
```

Download 开始时必须输出并写入日志：

```text
当前下载用 Python：<path/version>
当前 pip：<version>
目标下载平台：win_amd64 / cp311
```

PyTorch 下载使用 PyTorch CUDA 源：

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

`torch-cu128.lock.txt` 的版本写法必须先在联网电脑实测成功，不能凭感觉写 `torch==x.x.x` 或 `torch==x.x.x+cu128`。第一版应以一次真实 `pip download` 成功结果反推 lock 写法，避免下载到 CPU wheel 或找不到 CUDA wheel。

PyTorch 下载后必须强制检查 wheel 文件名：

```text
torch wheel 文件名小写后必须包含 cu128
torchvision wheel 文件名小写后必须包含 cu128
torchaudio wheel 文件名小写后必须包含 cu128
```

实现时使用文件名小写后的包含判断，例如 `$fileName.ToLower().Contains("cu128")`。如果任一 PyTorch 核心 wheel 不含 `cu128`，直接失败，避免误用 CPU wheel。

普通包下载使用 PyPI，并同样指定 `win_amd64/cp311`。

下载规则：

- 不能因为文件存在且非空就跳过。
- 只有 manifest 记录、大小、SHA256 都匹配才跳过。
- 下载先写 `<target>.part`，校验成功后改名。
- Download 启动时发现 `.part`：交互询问删除重下；`-Force` 自动删除；`-NonInteractive` 无 `-Force` 则失败。

网络检查：

- 使用 HTTPS HEAD/GET，不只 ping。
- 检查 PyPI、PyTorch wheel 源和 config 中的下载 URL。
- PowerShell 5.1 下优先启用 TLS 1.2。

`-Force` 范围：

- 只能覆盖 Download 管理的目标文件。
- 不能删除 venv。
- 不能覆盖用户项目、数据集、模型目录。
- 不能跳过 SHA256 校验。
- 不能让 Check 写 manifest。

## 11. RegisterLocalFiles 模式（第二阶段）

用途：登记用户手动放入离线包目录的安装包。

第一阶段不实现、不出现在菜单中。命令行传入该模式时，返回“第二阶段实现，当前不可用”的中文提示。

登记 Python 安装包时，只接受目标架构 `x64/amd64` 的普通安装包，拒绝 `win32`、`x86`、`arm64`、`embed` 等不适合当前目标机的包。

流程：

```text
扫描 downloads\drivers、downloads\cuda_optional、downloads\tools_optional
显示检测到的本地文件
解释将登记成什么组件
询问用户是否登记
计算 size 和 SHA256
原子更新 manifest
```

规则：

- 只登记用户明确确认的文件。
- NVIDIA 驱动登记为 `source: manual`。
- CUDA Toolkit 必须确认是 local installer，不接受 network installer。
- `-NonInteractive` 下没有明确参数时不自动登记。

安全边界：

- NVIDIA 驱动扩展名必须是 `.exe`，文件名建议包含 `nvidia`、`studio`、`game-ready`、`geforce` 等关键词之一；文件过小时警告。
- CUDA Toolkit 小体积 network installer 直接拒绝。
- Git 安装包文件名建议包含 `Git` 或 `Git-*-64-bit`。
- 手动登记项在 manifest 中记录 `source: manual`、`registeredAt`、`registeredByMode`、`userConfirmed: true`。

## 12. Check 模式

用途：只读检查离线包是否完整。

实现时必须把内部校验函数和 Check 模式分开：

```text
Test-OfflinePackage：只检查，返回结果对象，不写文件
Invoke-CheckMode：调用 Test-OfflinePackage，只输出结果，不写 manifest
Write-ManifestAtomic：只有 Download / RegisterLocalFiles 等可写流程调用
```

Download 可以调用 `Test-OfflinePackage`，但由 Download 自己决定是否原子写回 `packageStatus`。Check 模式本身永远不能写 manifest。

规则：

- Check 永远只读。
- Check 不修改 `manifest.json`。
- Check 不登记手动文件。
- Check 不修复缺失或损坏文件。

检查内容：

```text
manifest 可解析
schemaVersion == 1
phase == 1
optionalComponents == []
packageStatus 合理
lock 文件存在且 SHA256 匹配
必需文件存在
文件大小和 SHA256 匹配
manifest.files 记录的 wheel 文件存在、大小一致、SHA256 一致
固定 Research 必需组件都出现在 manifest.files 中
```

第一阶段必需组件清单至少包括：

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

第一阶段 Check 以 `manifest.files` 为主，不自己实现复杂 wheel tag 解析器：

```text
拒绝 .tar.gz / .zip 等源码包
确认 manifest 记录的 wheel 文件存在
确认大小和 SHA256 匹配
对明显不兼容的 cp312、linux、win32 wheel 报错或警告
```

第一阶段还必须扫描重复 wheel 和版本冲突：

```text
扫描 wheels\pytorch-cu128、wheels\common、wheels\optional
同名文件重复且 SHA256 相同：允许
同名文件重复但 SHA256 不同：失败
同包同版本但文件名不同：警告
同包不同版本：失败
```

第二阶段再实现更严格的 `wheels 覆盖 lock 文件` 判定，具体到每个包：

```text
包名匹配
版本匹配
Python tag / ABI / platform 兼容 cp311 / win_amd64
存在可用 wheel
不接受只有 .tar.gz / .zip 源码包
```

输出示例：

```text
[OK] torch==x.x.x -> torch-...-cp311-win_amd64.whl
[FAIL] numpy==x.x.x -> 未找到 cp311-win_amd64 wheel
[FAIL] opencv-python==x.x.x -> 只有 cp312 wheel，不兼容目标 Python 3.11
```

## 13. Install 模式

用途：在离线电脑创建 AI 工作区和虚拟环境，离线安装依赖。

流程：

```text
读取 manifest
确认 packageStatus == complete
运行 Check
询问/确定 WorkspaceRoot
检查工作区所在盘
检查系统、nvidia-smi、VC++ Runtime、Python 3.11 x64、pip、venv
创建目录
处理已有 venv：第一阶段只支持干净安装
组合 lock 文件生成 resolved-install.lock.txt
离线安装
运行 pip check
生成 activate-dl.ps1 / activate-dl.bat
运行基础 Verify：torch import 和 CUDA available 检查
全部成功后写 install_state.json
自动 Verify 输出完整报告
```

Install 以 manifest 为事实来源：

```text
lock 文件用于生成 resolved-install.lock.txt。
manifest.files 用于确认离线包实际拥有的文件。
lock 与 manifest.files 明显不一致时直接失败。
```

第一阶段不强依赖 `pip install --dry-run`，因为旧 pip 支持不稳定。可以作为可选诊断增强；真正安装失败必须停止并保留 pip 错误日志，不能写成功状态。

`nvidia-smi` 缺失时必须给出明确提示：

```text
Install 要求 NVIDIA 驱动已安装并且 nvidia-smi 可用。
如果你还没有安装驱动，请先手动安装 downloads\drivers 中的驱动并重启。
```

Install 还要检查 GPU 名称：

```text
检测不到 NVIDIA GPU：失败。
检测到 RTX 3090：继续。
检测到 NVIDIA GPU 但不是 RTX 3090：交互警告并询问是否继续。
-NonInteractive 下 GPU 不匹配直接失败。
```

提示示例：

```text
当前检测到 GPU：NVIDIA GeForce RTX 3090
目标 GPU：NVIDIA RTX 3090
```

Python 检查必须包括：

```text
python --version == 3.11.x
Python 架构 == 64bit
python -m pip --version 可用
python -m venv --help 可用
```

如果 Python 存在但 pip/venv 不可用，提示：

```text
检测到 Python 3.11，但 pip/venv 不可用。
请重新运行 Python 安装包，选择 Modify，并启用 pip 和 venv。
```

已有 venv：

```text
[1] 删除并重建环境
[2] 退出
```

选择删除时必须输入：

```text
DELETE
```

`-Yes` 不会自动删除 venv。命令行 `-RecreateVenv` 表示用户已明确同意重建。

第一阶段不支持 `ReuseVenv`。命令行模式下，如果 venv 已存在且没有传入 `-RecreateVenv`，直接失败并提示用户显式重建。

干净 venv 规则：

```text
如果 venv 不存在：创建。
如果 venv 存在且没有 .offline_dl_ready：要求删除重建。
如果 venv 存在且有 .offline_dl_ready：仍要求输入 DELETE 后重建。
```

删除 venv 前必须进行防误删检查：

```text
VenvPath 必须等于 <WorkspaceRoot>\envs\dl-py311-cu128
要删除的目录名必须等于 dl-py311-cu128，或目录里存在 .offline_dl_installing / .offline_dl_ready
```

如果路径不在 WorkspaceRoot 内、路径不是预期 venv 路径、目录名和标记文件都不匹配，必须拒绝自动删除并提示该目录不像本脚本创建的虚拟环境。

`ReuseVenv` 属于第二阶段能力，未来复用 venv 前必须检查：

```text
venvPython 存在
venv Python 版本 == manifest.pythonMajorMinor
venv Python 架构 == 64bit
如果已安装 torch，torch.version.cuda 必须等于目标 CUDA runtime
```

未来 `ReuseVenv` 只用于补全缺失依赖。发现核心包版本冲突、CPU 版 torch 或 CUDA 不匹配时，直接失败并建议 `RecreateVenv`，不要在旧环境里强行覆盖核心包。

`installStatus = success` 只能在以下步骤全部成功后写入：

```text
venv 创建或复用检查成功
pip install 成功
pip check 成功
torch import 成功
torch.cuda.is_available() == True
```

第一阶段使用 venv 标记防止半残环境误复用：

```text
安装开始：写 <venv>\.offline_dl_installing
安装成功：删除 .offline_dl_installing，并写 <venv>\.offline_dl_ready
```

下次 Install 如果发现 `.offline_dl_installing` 存在但 `.offline_dl_ready` 不存在，说明上次安装可能中断，当前虚拟环境不可信，建议删除并重建。

中途失败时，不允许写出看起来成功的 `install_state.json`。规则固定为：

```text
Install 成功：写 install_state.json
Install 失败：写 install_state.failed.json
```

失败尝试不能覆盖已有的成功 `install_state.json`，避免一次升级失败破坏原本可用环境的验证状态。

Install 根据 manifest 组合 lock：

```text
永远包含：torch-cu128.lock.txt
第一阶段固定 Research：research.lock.txt
Visualization：第二阶段才额外加入 visualization.lock.txt
```

生成：

```text
<WorkspaceRoot>\state\resolved-install.lock.txt
```

文件头部应记录来源：

```text
# Generated by OfflineDL-Win10-3090.ps1
# Source manifest sha256: ...
# Profile: Research
# Optional components: none
# Generated at: ...
# Do not edit manually.
```

然后一次性安装：

```powershell
& $VenvPython -m pip install --no-index @FindLinksArgs -r $ResolvedLockFile
```

所有 pip 操作都必须使用：

```powershell
& $VenvPython -m pip ...
```

禁止直接调用 `pip` 或依赖 PATH 中的 pip。

`FindLinksArgs` 必须包含：

```text
wheels\pytorch-cu128
wheels\common
wheels\optional
```

VC++ Runtime 检测是启发式：

- DLL 缺失：提示安装 `downloads\runtime\VC_redist.x64.exe` 并停止。
- DLL 存在：认为可能已安装；如果后续 import 失败，提示重新安装 VC++ Runtime。

激活脚本：

```text
<WorkspaceRoot>\activate-dl.ps1
<WorkspaceRoot>\activate-dl.bat
```

`.bat` 方便小白双击进入环境。

`install_state.json` 示例：

```json
{
  "schemaVersion": 1,
  "installStatus": "success",
  "workspaceRoot": "D:\\AI",
  "venvPython": "D:\\AI\\envs\\dl-py311-cu128\\Scripts\\python.exe",
  "profile": "Research",
  "optionalComponents": [],
  "pythonMajorMinor": "3.11",
  "pythonArch": "64bit",
  "torchCudaTag": "cu128",
  "resolvedLockFile": "D:\\AI\\state\\resolved-install.lock.txt",
  "resolvedLockSha256": "...",
  "sourceManifestHash": "...",
  "installedAt": "2026-04-29T00:00:00+08:00",
  "installedByScriptVersion": "0.1.0"
}
```

## 14. Verify 模式

用途：验证驱动、PyTorch、CUDA runtime 和实际 GPU 运算。

规则：

- 优先读取 `<WorkspaceRoot>\state\install_state.json`。
- 使用 `venvPython`，不静默回退系统 Python。
- 检查 venv 目录下是否存在 `.offline_dl_ready`。
- 如果当前离线包目录存在 `manifest.json`，计算当前 manifest hash，并和 `install_state.sourceManifestHash` 比较。
- 运行 `pip check`。
- 输出 NVIDIA Driver Version、`nvidia-smi CUDA Version`、`torch.version.cuda`、GPU 名称。
- 默认运行 1024 x 1024 CUDA 矩阵乘法测试，只验证 CUDA 能跑，不做压力测试。

未来可增加 `-Stress`，再做更大的矩阵和显存压力测试。

重要说明：

```text
nvidia-smi 显示的 CUDA Version 代表驱动支持能力，不代表已安装 CUDA Toolkit。
普通 PyTorch 训练通常不需要单独安装 CUDA Toolkit。
```

判断逻辑：

```text
Driver CUDA Version >= PyTorch CUDA Runtime：OK
Driver CUDA Version < PyTorch CUDA Runtime：驱动太旧，失败
Driver CUDA Version > PyTorch CUDA Runtime：正常，不警告
```

版本比较必须解析为数字后比较，不允许字符串比较。`12.10` 应大于 `12.8`。

如果 `torch.version.cuda == None`，说明当前 PyTorch 可能是 CPU 版，Verify 必须失败并提示：

```text
当前 PyTorch 不是 CUDA 版本，torch.version.cuda == None。
请确认安装的是 cu128 wheel，而不是 CPU wheel。
```

`sourceManifestHash` 判断规则：

```text
当前 manifest 与 install_state.sourceManifestHash 一致：正常。
当前 manifest 不一致：警告，不失败。
找不到当前 manifest：继续 Verify，但提示无法确认来源。
```

警告文案：

```text
当前离线包 manifest 与安装时来源不一致，Verify 只验证当前环境可用性，不代表此环境由当前离线包安装。
```

如果缺少 `.offline_dl_ready`，Verify 不直接失败，但必须警告：

```text
未发现 .offline_dl_ready，环境可能不是由本脚本完整安装。将继续验证，但来源完整性无法确认。
```

## 15. 磁盘、文件系统和空间

Download 检查离线包所在盘。Install 检查 AI 工作区所在盘。

文件系统建议：

```text
Windows 长期使用：优先 NTFS。
需要和 macOS/Linux 交换：可用 exFAT。
不要 FAT32。
```

FAT32 必须阻止，并提示：

```text
当前磁盘是 FAT32，不适合制作或安装深度学习离线环境。
原因：FAT32 单个文件不能超过 4GB，后续 CUDA、模型或数据集可能失败。
建议使用 NTFS；如需跨平台交换文件，可使用 exFAT。
```

离线包空间建议：

```text
Minimal：20 GB
Research：30 GB
Research + Visualization：50 GB
Full + CUDA Toolkit：80 GB
```

AI 工作区空间建议：

```text
最低：50 GB
推荐：100 GB+
图像/遥感/SAR/大模型/大量 checkpoint：200 GB+
```

## 16. 日志、退出码和诊断

每次运行写日志：

```text
logs\2026-04-29_103000_Download.log
logs\2026-04-29_110000_Install.log
```

退出码：

```text
0 = 成功
1 = 一般失败
2 = manifest 校验失败
3 = 缺少必需组件
4 = Python 版本或架构不匹配
5 = CUDA / GPU 验证失败
6 = 磁盘空间或文件系统检查失败
7 = 用户取消
```

失败时输出 doctor 风格摘要，并写入日志：

```text
诊断结果：
  OS: Windows 10 x64
  PowerShell: 5.1
  Python: 3.11.9 x64
  NVIDIA: detected
  nvidia-smi: OK
  VC++ Runtime: maybe installed
  Manifest: complete
  Wheels: OK
  Venv: exists
```

日志还必须记录关键外部命令、退出码、stdout/stderr 摘要，失败时保留最后 50 行输出。重点命令包括 `pip download`、`pip install`、`pip check`、`nvidia-smi`。

第一版不自动清理日志。README 需要说明：

```text
logs 目录可定期手动清理，不影响离线包安装。
manifest、requirements、wheels、downloads 不要手动删除。
```

Doctor 模式：

- 只读，不下载、不安装、不修改文件。
- 输出系统、PowerShell、Python、NVIDIA/nvidia-smi、VC++ Runtime、manifest、wheels、工作区状态。
- 可作为第二阶段实现；失败时的 doctor 摘要第一阶段就应保留。

## 17. 自动化和安全参数

```text
-Yes：接受安全默认值，不执行删除/覆盖等破坏性操作。
-NonInteractive：禁止等待输入；缺参数或需要决策时直接失败。
-Force：重新下载/覆盖对应下载文件。
-RecreateVenv：命令行模式下明确同意重建虚拟环境。
-PersistEnvVars：将缓存环境变量写入用户环境变量。
```

第一阶段不支持 `-ReuseVenv`，如果用户传入该参数，提示该选项属于第二阶段能力。

## 18. 实现规范

- 使用 `Join-Path` 构造路径。
- 文件操作尽量使用 `-LiteralPath`。
- 外部命令使用 `&`。
- 不使用 `Invoke-Expression` 执行拼接字符串。
- 交互文案用简体中文，选项解释清楚。
- README 必须写 PowerShell 执行策略绕过方式：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\OfflineDL-Win10-3090.ps1 -Mode Check
```

README 还必须写小白推荐运行顺序：

```text
联网电脑：
1. 双击 OfflineDL-Win10-3090.bat
2. 选择 Download
3. 选择 Research
4. 等待下载完成
5. 选择 Check
6. 拷贝整个文件夹到离线电脑

离线电脑：
1. 双击 OfflineDL-Win10-3090.bat
2. 选择 Check
3. 按提示安装 NVIDIA 驱动、VC++ Runtime、Python
4. 选择 Install
5. 选择 Verify
```

README 开头必须说明：

```text
本脚本不会自动安装 NVIDIA 驱动、Python 安装包、VC++ Runtime。
第一次在离线电脑运行 Install 前，请按提示手动运行 downloads 目录中的安装包，并重启。
```

README 还必须醒目提示：

```text
拷贝到离线电脑时，请拷贝整个 Win10_3090_DeepLearning_OfflinePack 文件夹。
不要只拷贝 wheels 或 downloads 子目录。
manifest、requirements、scripts、logs 都是安装和校验所需的一部分。
```

工作区路径建议：

```text
推荐工作区路径不要包含空格或特殊字符，例如 D:\AI 或 E:\AI。
不推荐：E:\AI Workspace。
```

排错文档：

```text
docs\
  troubleshooting.md
  common-errors.md
```

覆盖 `torch.cuda.is_available() == False`、`DLL load failed`、`No matching distribution found`、`pip check failed`、`nvidia-smi not found`、PowerShell 禁止脚本等常见问题。

## 19. Git 结论

Git 不是深度学习运行环境必需组件。

第一阶段不支持 `-IncludeGit`。需要本地代码历史、本地 bare 仓库、移动硬盘/局域网 Git 同步时，在第二阶段再选择 `-IncludeGit`。

## 20. 下一步

第一阶段先跑通最小闭环：

```text
联网机 Download -> Check -> 拷贝 -> 离线机 Check -> Install -> Verify
```

第一阶段优先实现：

```text
Download / Check / Install / Verify
固定 Research
干净 venv 安装
PyTorch CUDA 12.8
Python 3.11 x64
manifest.files / 顶层 lock / SHA256 校验
隐藏未实现菜单项
```

第二阶段再完善：

```text
RegisterLocalFiles
Visualization
Doctor
CUDA Toolkit local installer 检测
VS Code
Minimal / Full / -Profile
ReuseVenv
完整依赖树 lock
复杂 hashlock / --require-hashes
```

具体下一步：

1. 创建 `config.json`。
2. 创建第一阶段顶层版本 lock 文件，并用 `manifest.files` 记录实际下载 wheel。
3. 创建 `OfflineDL-Win10-3090.ps1` 和 `OfflineDL-Win10-3090.bat`。
4. 创建验证脚本。
5. 创建 README 和 docs 排错文档。
6. 测试第一阶段最小闭环。

第一版代码实现顺序建议：

```text
1. 基础路径、参数、日志框架
2. manifest 读写、SHA256、原子写入
3. Check
4. Verify
5. Install
6. Download
```

测试顺序：

```text
先手工准备小型 wheels 测试包和 manifest，让 Check 跑通。
再在已有 Python 环境上测试 Install。
再在 3090 上测试 Verify。
最后实现真实 Download。
```

## 21. 第一阶段 P0 实现检查清单

Download：

```text
目标目录确认
非 FAT32
空间检查
TLS / 网络检查
输出当前 Python / pip / 目标平台
pip download 固定 win_amd64 / cp311
PyTorch wheel 文件名小写后包含 cu128
生成 manifest.files
SHA256 校验
manifest 原子写入
```

Check：

```text
Check 只读
manifest 可解析
schemaVersion == 1
phase == 1
optionalComponents == []
packageStatus == complete
lock SHA256 匹配
必需组件都在 manifest.files
manifest.files 文件存在 / 大小 / SHA256 匹配
拒绝源码包
扫描重复 wheel / 多版本 wheel
```

Install：

```text
packageStatus == complete
先运行 Check
nvidia-smi 存在
GPU 是 RTX 3090 或交互确认
Python 3.11 x64 / pip / venv 可用
已有 venv 必须删除重建
删除前要求 DELETE
VenvPath 必须等于 <WorkspaceRoot>\envs\dl-py311-cu128
删除目录必须是 dl-py311-cu128 或包含本脚本标记文件
写 .offline_dl_installing
pip install 成功
pip check 成功
torch import + CUDA available
写 .offline_dl_ready
写 install_state.json
```

Verify：

```text
读取 install_state.json
使用 venvPython
检查 .offline_dl_ready
pip check
torch.version.cuda 不是 None
数值比较 driver CUDA 与 torch CUDA
1024 x 1024 CUDA 矩阵乘法
```
