# 计划增量建议暂存

用途：暂存后续讨论中确认要加入计划的内容。先不继续打散主计划，等本轮建议全部讨论完后，再统一整理合并进 `PLAN.zh-CN.md` 和 `PLAN.md`。

## 合并状态

- 本文件中的 20 条增量建议已整理合并进 `PLAN.zh-CN.md` 和 `PLAN.md`。
- 合并前已备份主计划和本文件到 `backups\20260429_223608-before-final-merge`。
- 第二轮新增建议 21-36 已整理合并进 `PLAN.zh-CN.md` 和 `PLAN.md`。
- 第二轮合并前已备份主计划和本文件到 `backups\20260429_230338-before-second-merge`。
- 第三轮新增建议 37-45 已整理合并进 `PLAN.zh-CN.md` 和 `PLAN.md`。
- 第三轮合并前已备份主计划和本文件到 `backups\20260429_233957-before-third-merge`。
- 第四轮新增建议 46-57 已整理合并进 `PLAN.zh-CN.md` 和 `PLAN.md`。
- 第四轮合并前已备份主计划和本文件到 `backups\20260430_000114-before-fourth-merge`。
- 第五轮新增建议 58-68 已整理合并进 `PLAN.zh-CN.md` 和 `PLAN.md`。
- 第五轮合并前已备份主计划和本文件到 `backups\20260430_001323-before-fifth-merge`。
- 第六轮新增建议 69-80 已整理合并进 `PLAN.zh-CN.md` 和 `PLAN.md`。
- 第六轮合并前已备份主计划和本文件到 `backups\20260430_002625-before-sixth-merge`。
- 本文件保留作为讨论记录和追溯依据。

## 当前状态备注

- 主计划 `PLAN.md` / `PLAN.zh-CN.md` 已按逻辑合并当前文件中的增量建议。
- 本文件继续保留完整讨论记录，方便后续追溯为什么采纳或推迟某个设计。
- 后续如果再收到新建议，仍按“先评估必要性 -> 写入增量暂存 -> 备份主计划 -> 整理合并”的流程处理。

## 已确认，待最终合并

### 1. Check 模式只读，新增 RegisterLocalFiles

结论：采纳。

原因：

- Check 的职责应该是校验，不应该修改 `manifest.json`。
- 如果 Check 顺手登记手动文件，会让“检查动作”污染状态文件，后续排查困难。
- 手动放置的 NVIDIA 驱动、CUDA Toolkit、VS Code 等安装包应由单独模式登记。

设计：

```text
Download：自动下载并写 manifest
RegisterLocalFiles：登记手动放置文件并写 manifest
Check：只读校验，不修改、不登记、不修复
Install：按 manifest 安装
Verify：验证安装结果
```

主脚本模式增加：

```powershell
-Mode RegisterLocalFiles
```

交互菜单建议：

```text
[1] Download  在联网电脑下载离线包
[2] Register  登记你手动放进文件夹的安装包
[3] Check     只检查离线包是否完整，不修改文件
[4] Install   在离线电脑安装环境
[5] Verify    验证显卡和 PyTorch 是否可用
[6] Exit      退出
```

RegisterLocalFiles 流程：

```text
扫描 downloads\drivers、downloads\cuda_optional、downloads\tools_optional
显示检测到的本地安装包
用中文解释每个文件将登记成什么组件
询问用户是否登记
计算文件大小和 SHA256
原子更新 manifest.json
```

RegisterLocalFiles 规则：

- 只登记用户明确确认的文件。
- 登记 NVIDIA 驱动时标记 `source: manual`。
- 登记 CUDA Toolkit 时必须确认是 local installer，不接受 network installer。
- 所有 manifest 写入必须走原子写入和备份流程。
- `-NonInteractive` 模式下，如果缺少明确参数，不应自动登记任何文件。

Check 规则：

- Check 永远只读。
- Check 不修改 `manifest.json`。
- Check 不登记手动文件。
- Check 不修复缺失或损坏文件。

### 2. manifest 必须记录 lock 文件 SHA256

结论：采纳。

原因：

- lock 文件决定要安装的 Python 包和版本。
- 如果 Download 时使用 lock A 下载 wheels，之后用户手动改成 lock B，Install 会按 B 安装，但离线 wheels 仍然是按 A 下载的，容易失败。
- 因此 manifest 不只要记录下载文件，也要记录参与下载的 lock 文件本身。

manifest 增加 `lockFiles`：

```json
{
  "lockFiles": [
    {
      "name": "research.lock.txt",
      "path": "requirements/research.lock.txt",
      "sha256": "...",
      "profile": "Research"
    },
    {
      "name": "visualization.lock.txt",
      "path": "requirements/visualization.lock.txt",
      "sha256": "...",
      "optionalComponent": "Visualization"
    }
  ]
}
```

Check 规则：

- lock 文件必须存在。
- lock 文件 SHA256 必须和 manifest 一致。
- lock 对应的 wheels 必须齐全。
- 如果 lock 文件和 manifest 不一致，Check 失败。

Install 规则：

- Install 前必须确认 lock 文件未被修改。
- 如果 lock SHA256 不一致，停止安装。
- 中文提示建议：

```text
lock 文件和下载时不一致。
这通常表示 requirements 文件被修改过，但 wheels 还是旧版本。
请重新运行 Download，或恢复对应 lock 文件。
```

最终合并提示：

- 合并到主计划的 `manifest.json` 章节。
- 合并到 Check 模式规则。
- 合并到 Install 模式安装前校验规则。

### 3. 增加 `requirements\torch-cu128.lock.txt`

结论：采纳。

原因：

- PyTorch CUDA wheels 和普通 PyPI 包来源不同。
- PyTorch CUDA wheels 使用 `https://download.pytorch.org/whl/cu128`。
- 普通科研包使用 PyPI。
- 如果把 PyTorch 包混进 `research.lock.txt`，下载逻辑和目录归属会变乱。

requirements 目录应调整为：

```text
requirements\
  torch-cu128.lock.txt
  minimal.lock.txt
  research.lock.txt
  visualization.lock.txt
```

`torch-cu128.lock.txt` 内容范围：

```text
torch==...
torchvision==...
torchaudio==...
```

PyTorch CUDA wheels 下载形式：

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

规则：

- `torch-cu128.lock.txt` 专门管理 PyTorch CUDA 栈。
- `minimal.lock.txt`、`research.lock.txt`、`visualization.lock.txt` 管理普通 Python 包。
- 后续如果 CUDA tag 改为 `cu126`、`cu129` 等，应新增或替换对应 `torch-<cuda-tag>.lock.txt`。
- manifest 的 `lockFiles` 必须记录 `torch-cu128.lock.txt` 的 SHA256。

最终合并提示：

- 合并到离线包目录结构。
- 合并到 lock 文件计划。
- 合并到 Download 模式的 PyTorch wheel 下载规则。
- 合并到 manifest `lockFiles` 示例。

### 4. Install 根据 manifest 组合 lock 文件，生成 `resolved-install.lock.txt`

结论：采纳。

原因：

- Install 不应该只安装某一个 lock 文件，例如 `research.lock.txt`。
- Install 应根据 `manifest.json` 中记录的 Profile 和 OptionalComponents 决定要安装哪些 lock。
- 这样能保证“下载了什么，就安装什么”。

lock 组合规则：

```text
永远安装：
  torch-cu128.lock.txt

Profile = Minimal：
  minimal.lock.txt

Profile = Research：
  minimal.lock.txt
  research.lock.txt

Profile = Full：
  minimal.lock.txt
  research.lock.txt
  Git / CUDA Toolkit 属于非 Python 可选组件，不自动加入 visualization.lock.txt

OptionalComponents 包含 Visualization：
  visualization.lock.txt
```

Install 时生成：

```text
<WorkspaceRoot>\state\resolved-install.lock.txt
```

然后一次性安装：

```powershell
& $VenvPython -m pip install --no-index @FindLinksArgs -r $ResolvedLockFile
```

规则：

- `resolved-install.lock.txt` 应由 manifest 记录的 lock 文件组合生成。
- 生成前必须校验各 lock 文件 SHA256 与 manifest 一致。
- `resolved-install.lock.txt` 应写入工作区 `state` 目录，方便后续排查。
- pip 安装应继续使用统一的 `FindLinksArgs`，包含 `wheels\pytorch-cu128`、`wheels\common`、`wheels\optional`。
- 如果 lock 组合结果为空或缺少 `torch-cu128.lock.txt`，Install 必须失败。

最终合并提示：

- 合并到 Install 模式流程。
- 合并到离线 pip 安装规则。
- 合并到 AI 工作区 `state` 目录说明。
- 合并到 `install_state.json` 可追踪信息中，可记录 `resolvedLockFile` 和 `resolvedLockSha256`。

### 5. Full 档位再明确：Full 不代表所有可选 Python 可视化包

结论：采纳。

原因：

- 小白用户容易把 Full 理解成“所有东西都装”。
- 实际上 Full 应表示开发/编译能力增强，不应自动包含 MLflow、Plotly、ipywidgets 等可视化依赖。
- Visualization 应保持独立开关，避免下载体积和依赖复杂度失控。

最终定义：

```text
Minimal：最小运行环境
Research：默认科研环境
Full：Research + 开发/编译工具，例如 Git、CUDA Toolkit
Visualization：独立可选项，不属于 Full
```

示例：

```powershell
# Full 不自动包含 MLflow / Plotly / ipywidgets
.\OfflineDL-Win10-3090.ps1 -Mode Download -Profile Full

# 如果需要可视化增强，必须显式加
.\OfflineDL-Win10-3090.ps1 -Mode Download -Profile Full -IncludeVisualization
```

交互提示建议：

```text
Full：科研环境 + 开发/编译工具，不自动包含可视化增强包。
如果你还想要 MLflow、Plotly、交互图表，请另外选择“可视化增强”。
```

最终合并提示：

- 合并到 Profile 表格。
- 合并到可视化规则。
- 合并到 Download 模式选择 Profile 的中文提示。

### 6. 明确 `install_state.json` 只在 AI 工作区

结论：采纳。

原因：

- 离线包状态和某台电脑上的安装状态不能混在一起。
- `manifest.json` 描述离线包下载了什么。
- `install_state.json` 描述这个离线包安装到了哪里。
- 如果离线包目录和 AI 工作区都出现 `state\install_state.json`，会让用户和脚本都难以判断来源。

目录职责：

```text
离线包目录：
  manifest.json
  logs\
  backups\

AI 工作区：
  state\
    install_state.json
    resolved-install.lock.txt
```

文件职责：

```text
manifest.json：
  描述离线包内容，例如下载文件、大小、SHA256、Profile、可选组件、lock 文件哈希。

install_state.json：
  描述安装结果，例如 WorkspaceRoot、venvPython、Profile、安装时间、安装状态。
```

规则：

- `install_state.json` 只属于 `<WorkspaceRoot>\state\`。
- 离线包目录不放 `state\install_state.json`。
- 如果未来离线包需要额外状态，使用其他名字，例如 `package_state.json`，不要和安装状态混用。
- Verify 默认从 `<WorkspaceRoot>\state\install_state.json` 找 venv Python。

最终合并提示：

- 合并到离线包目录结构。
- 合并到目标 AI 工作区结构。
- 合并到关键文件职责。
- 合并到 Verify 模式 Python 选择规则。

### 7. Verify 不把 `nvidia-smi CUDA Version` 理解成 CUDA Toolkit 已安装

结论：采纳。

原因：

- `nvidia-smi` 中的 `CUDA Version` 很容易被误解。
- 它表示当前 NVIDIA 驱动最高支持的 CUDA Runtime 版本。
- 它不表示电脑已经安装 CUDA Toolkit。
- 它也不表示系统里有 `nvcc`。

Verify 输出中必须解释：

```text
注意：nvidia-smi 显示的 CUDA Version 代表驱动支持能力，不代表已安装 CUDA Toolkit。
普通 PyTorch 训练通常不需要单独安装 CUDA Toolkit。
```

判断逻辑：

```text
Driver CUDA Version >= PyTorch CUDA Runtime：
  OK

Driver CUDA Version < PyTorch CUDA Runtime：
  失败，提示 NVIDIA 驱动太旧

Driver CUDA Version > PyTorch CUDA Runtime：
  正常，不警告
```

规则：

- 不要求 Driver CUDA Version 和 PyTorch CUDA Runtime 完全相等。
- 驱动支持版本高于 PyTorch runtime 是正常情况。
- 只有驱动支持版本低于 PyTorch runtime 时才失败。
- 如果用户选择了 `-IncludeCudaToolkit`，CUDA Toolkit 安装状态应通过 `nvcc --version` 或安装路径另行检查，不要用 `nvidia-smi CUDA Version` 判断。

最终合并提示：

- 合并到 Verify 模式。
- 合并到 CUDA Toolkit 可选项说明。
- 合并到用户输出文案。

### 8. VC++ Runtime 检测是启发式，不是绝对保证

结论：采纳。

原因：

- 检查 `vcruntime140.dll`、`vcruntime140_1.dll`、`msvcp140.dll` 可以快速判断，但不能 100% 证明 VC++ Redistributable 正确安装。
- 某些软件可能自带 DLL。
- DLL 存在也可能版本不合适或安装不完整。

检测规则：

```text
DLL 缺失：
  强提示安装 VC_redist.x64.exe，并停止 Install。

DLL 存在：
  认为“可能已安装”，继续执行。
  但提示用户：如果后续 import 失败，可以手动重装 VC++ Runtime。
```

中文提示建议：

```text
检测到 VC++ Runtime 相关 DLL，可能已经安装。
如果后续导入 torch、numpy、opencv 时出现 DLL load failed，
请手动重新运行 downloads\runtime\VC_redist.x64.exe。
```

规则：

- Install 可以把 VC++ Runtime 检测结果标记为 `maybeInstalled`。
- `maybeInstalled` 不是绝对保证。
- 如果后续 `pip check` 或 import 测试出现 DLL 相关错误，应提示用户重新安装 `VC_redist.x64.exe`。

最终合并提示：

- 合并到 Install 模式的 VC++ Runtime 检测。
- 合并到风险点/排错提示。
- 合并到 README 常见问题。

### 9. 同时生成 `activate-dl.ps1` 和 `activate-dl.bat`

结论：采纳。

原因：

- `activate-dl.ps1` 适合 PowerShell 用户。
- `.ps1` 可能被 PowerShell 执行策略拦截。
- `.bat` 对 Windows 小白用户更友好，可以双击打开环境。

Install 成功后生成：

```text
<WorkspaceRoot>\activate-dl.ps1
<WorkspaceRoot>\activate-dl.bat
```

`activate-dl.ps1` 示例：

```powershell
$env:HF_HOME = "D:\AI\cache\huggingface"
$env:TORCH_HOME = "D:\AI\cache\torch"
$env:PIP_CACHE_DIR = "D:\AI\cache\pip"

& "D:\AI\envs\dl-py311-cu128\Scripts\Activate.ps1"
```

`activate-dl.bat` 示例：

```bat
@echo off
set HF_HOME=D:\AI\cache\huggingface
set TORCH_HOME=D:\AI\cache\torch
set PIP_CACHE_DIR=D:\AI\cache\pip
call D:\AI\envs\dl-py311-cu128\Scripts\activate.bat
cmd /k
```

README 提示：

```text
如果你不熟悉 PowerShell，可以双击 activate-dl.bat 进入深度学习环境。
```

规则：

- 两个激活脚本都使用同一套 WorkspaceRoot 派生路径。
- `.bat` 不需要修改系统环境变量，只设置当前命令行窗口变量。
- `activate-dl.ps1` 和 `activate-dl.bat` 都应在重新安装或重建 venv 后更新。

最终合并提示：

- 合并到 Install 模式。
- 合并到 AI 工作区目录结构。
- 合并到环境变量和激活脚本章节。
- 合并到 README 使用说明。

### 10. 删除 venv 必须输入 `DELETE` 二次确认

结论：采纳。

原因：

- 删除虚拟环境是破坏性操作。
- 只用 `Y/n` 容易手滑误删。
- 小白用户需要更明确的危险确认。

交互流程：

```text
检测到已有虚拟环境：
D:\AI\envs\dl-py311-cu128

请选择：
[1] 复用现有环境并补全依赖
[2] 删除并重建环境
[3] 退出
```

如果用户选择 `[2]`，必须二次确认：

```text
即将删除以下虚拟环境：
D:\AI\envs\dl-py311-cu128

请输入 DELETE 确认删除：
```

规则：

- 只有输入完全等于 `DELETE` 才删除。
- `-Yes` 不会自动删除 venv。
- `-RecreateVenv` 在命令行模式下表示用户已明确同意删除。
- 交互模式选择删除时仍要求输入 `DELETE`。

最终合并提示：

- 合并到已有 venv 处理规则。
- 合并到 `-Yes` / `-RecreateVenv` 自动化规则。
- 合并到中文交互文案。

### 11. 增加主工具 `.bat` 启动器

结论：采纳。

原因：

- 主逻辑仍应保留在 `OfflineDL-Win10-3090.ps1`。
- `.ps1` 可能被执行策略拦截。
- `.bat` 更适合小白双击进入中文菜单。

新增文件：

```text
OfflineDL-Win10-3090.bat
```

职责：

```text
只负责进入脚本所在目录，调用 PowerShell 运行 OfflineDL-Win10-3090.ps1。
不写复杂业务逻辑。
```

建议内容：

```bat
@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0OfflineDL-Win10-3090.ps1" %*
pause
```

使用方式：

```text
双击 OfflineDL-Win10-3090.bat 进入中文菜单。
```

也支持转发参数：

```powershell
OfflineDL-Win10-3090.bat -Mode Check
```

和安装后的环境入口区分：

```text
OfflineDL-Win10-3090.bat：
  运行离线环境工具。

<WorkspaceRoot>\activate-dl.bat：
  进入已经安装好的深度学习环境。
```

最终合并提示：

- 合并到离线包目录结构。
- 合并到 README 使用方式。
- 合并到 PowerShell 执行策略说明附近。

### 12. Download 启动时扫描 `.part`，默认删除后重下

结论：采纳。

原因：

- `.part` 文件通常表示上次下载中断或失败。
- 不应把 `.part` 当成可安装文件。
- PowerShell 中稳定实现断点续传会增加复杂度和不确定性。
- 当前阶段选择简单可靠策略：删除 `.part` 后重新下载。

规则：

```text
Download 启动时扫描所有 .part 文件。

如果发现 .part：
  交互模式：提示用户删除后重新下载。
  -Force：自动删除 .part 并重新下载。
  -NonInteractive 且无 -Force：失败并提示需要用户处理。
```

中文提示建议：

```text
发现未完成的下载文件：
wheels\common\xxx.whl.part

这通常表示上次下载中断。
建议删除它并重新下载完整文件。

是否删除并重新下载？Y/n
```

规则补充：

- 不做复杂断点续传。
- 删除 `.part` 只影响未完成下载文件，不删除已通过 manifest 校验的完整文件。
- 如果用户选择不删除，Download 停止，避免继续产生混乱状态。

最终合并提示：

- 合并到 Download 模式完整性规则。
- 合并到 `.part` 下载规则。
- 合并到 `-Force` / `-NonInteractive` 行为规则。

### 13. manifest 原子写入和备份

结论：采纳。

原因：

- `manifest.json` 是离线包核心状态文件。
- 如果直接覆盖写入，中途失败可能导致 manifest 损坏。
- 损坏的 manifest 会影响 Check、Install 和后续排查。

写入流程：

```text
1. 读取旧 manifest。
2. 在内存中生成新 manifest 对象。
3. 写入 manifest.json.tmp。
4. 重新读取 tmp，确认 JSON 可解析。
5. 把旧 manifest 复制到 backups\manifest-时间戳.json。
6. 将 tmp 原子替换为 manifest.json。
```

失败处理：

```text
如果任何一步失败：
  保留旧 manifest。
  删除或保留 tmp 供排查，按实现策略决定。
  写入日志。
  返回失败。
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

规则：

- 每次 manifest 成功更新前，都应备份旧 manifest。
- 备份目录使用离线包 `backups\`。
- 备份文件名建议包含时间戳，例如 `manifest-20260429_220000.json`。
- `manifest.json.tmp` 不能被 Check 或 Install 当成正式 manifest。

最终合并提示：

- 合并到 manifest 章节。
- 合并到 Download 模式。
- 合并到 RegisterLocalFiles 模式。
- 合并到 Check 只读规则。

### 14. 增加 `schemaVersion`

结论：采纳。

原因：

- 后续脚本升级后，需要判断旧 `config.json`、`manifest.json`、`install_state.json` 是否兼容。
- 没有 schema version 时，很难区分旧格式、新格式和损坏文件。

涉及文件：

```text
config.json
manifest.json
<WorkspaceRoot>\state\install_state.json
```

字段：

```json
{
  "schemaVersion": 1
}
```

同时保留脚本版本字段：

```json
{
  "createdByScriptVersion": "0.1.0"
}
```

安装状态中可使用：

```json
{
  "installedByScriptVersion": "0.1.0"
}
```

兼容规则：

```text
schemaVersion 不存在：
  按旧格式处理，或提示不兼容。

schemaVersion 高于当前脚本支持：
  停止，提示升级脚本。

schemaVersion 低于当前脚本支持：
  根据兼容策略处理；如果没有迁移逻辑，则提示重新 Download。
```

中文提示建议：

```text
当前 manifest 使用的格式版本较旧，当前脚本不能安全处理。
请重新运行 Download 生成新的离线包，或使用对应版本的脚本。
```

最终合并提示：

- 合并到 `config.json` 计划。
- 合并到 `manifest.json` 示例。
- 合并到 `install_state.json` 示例。
- 合并到 Check / Install 读取 JSON 时的兼容检查。

### 15. 增加 `packageStatus`

结论：采纳。

原因：

- 防止用户拿“下载一半”的离线包去安装。
- `manifest.json` 应明确表示当前离线包是否完整可安装。

manifest 顶层字段：

```json
{
  "packageStatus": "incomplete"
}
```

状态：

```text
incomplete：下载尚未完成或尚未通过 Check。
complete：所有必需文件、lock 文件、SHA256 校验通过，可用于安装。
failed：Download 或 Check 失败，需要修复或重新下载。
```

规则：

- Download 开始或重新下载时，先将 `packageStatus` 标为 `incomplete`。
- 所有下载完成、lock 文件校验通过、自动 Check 通过后，才能标为 `complete`。
- Install 前必须检查 `packageStatus == complete`。
- 如果不是 `complete`，Install 停止。

中文提示建议：

```text
这个离线包还没有完成下载或校验，不能安装。
请先在联网电脑运行 Download，或运行 Check 查看缺失文件。
```

最终合并提示：

- 合并到 `manifest.json` 示例。
- 合并到 Download / Check / Install 规则。
- 合并到失败即停规则。

### 16. 区分离线包空间和 AI 工作区空间

结论：采纳。

原因：

- 离线包目录主要放安装包和 wheels。
- AI 工作区还会放虚拟环境、数据集、模型、checkpoint、实验输出，增长更快。
- 两者空间要求不应混为一谈。

离线包目录最低建议：

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
如果训练图像、遥感、SAR、大模型或保存大量 checkpoint：建议 200 GB+
```

规则：

- Download 检查离线包所在盘空间。
- Install 检查 `WorkspaceRoot` 所在盘空间。
- 两个检查使用不同阈值和提示。

最终合并提示：

- 合并到磁盘空间和文件系统要求。
- 合并到 Install 工作区确认提示。
- 合并到 README 的空间准备说明。

### 17. 文件系统建议：优先 NTFS，其次 exFAT，不要 FAT32

结论：采纳。

原因：

- FAT32 单文件不能超过 4GB，不适合深度学习离线包、模型和数据集。
- NTFS 更适合 Windows 长期使用、大量小文件、日志和权限。
- exFAT 适合跨平台移动硬盘，但长期可靠性和异常断电保护不如 NTFS。

建议文案：

```text
如果只在 Windows 电脑之间使用，推荐 NTFS。
如果还要和 macOS/Linux 交换文件，可以使用 exFAT。
不要使用 FAT32。
```

规则：

- FAT32：阻止 Download / Install，并给出中文解释。
- NTFS：推荐。
- exFAT：允许，但提示更适合跨平台移动硬盘。

最终合并提示：

- 合并到磁盘/文件系统检查。
- 合并到 FAT32 提示文案。
- 合并到 README。

### 18. Download 网络检查使用 HTTPS HEAD/GET，不只 ping

结论：采纳。

原因：

- 很多网络环境禁用 ping，但 HTTPS 下载正常。
- Download 真正依赖的是 HTTPS 访问 PyPI、PyTorch、NVIDIA、Python、Microsoft 等地址。

建议检查顺序：

```text
1. https://pypi.org/simple
2. https://download.pytorch.org/whl/cu128
3. config.json 中配置的 Python / VC++ / NVIDIA / CUDA URL
```

实现建议：

```powershell
Invoke-WebRequest -Method Head
```

如果 HEAD 不支持，再回退 GET。

规则：

- 不要只使用 `Test-Connection` 或 ping 判断网络。
- 网络检查失败时，用中文说明哪个 URL 不可访问。
- 网络检查只在 Download 模式需要。

最终合并提示：

- 合并到 Download 模式。
- 合并到网络检查/诊断输出。

### 19. PowerShell 5.1 TLS 1.2 设置

结论：采纳。

原因：

- Win10 自带 PowerShell 5.1。
- 老环境下载 HTTPS 时可能因为 TLS 协议设置失败。
- Download 主要在 Win11 机器运行，但长期工具应兼容 Win10/PowerShell 5.1。

建议在 Download 网络请求前设置：

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```

如需尝试 TLS 1.3，必须用 try/catch，因为旧 .NET 可能不认识 `Tls13`。

规则：

- 先启用 TLS 1.2。
- TLS 设置失败时写日志，并继续给出可理解错误。
- 不把 TLS 问题伪装成“文件不存在”或“网络断开”。

最终合并提示：

- 合并到 Download 模式实现注意事项。
- 合并到 README 排错。

### 20. 失败时输出 doctor 风格诊断摘要

结论：采纳。

原因：

- 用户失败时需要知道问题在哪一层，而不是只看到一条报错。
- 诊断摘要方便后续排查，也适合小白截图求助。

建议在失败时输出：

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

规则：

- 不一定单独增加 Doctor 模式，先在失败时输出摘要。
- 摘要也写入日志。
- 不显示过多技术堆栈，先给用户能理解的状态。
- 如果后续需要，可以再增加 `-Mode Doctor`。

最终合并提示：

- 合并到日志和失败处理。
- 合并到 Check / Install / Verify 失败路径。

## 待最终合并

以上 20 条均已确认，待统一整理合并进 `PLAN.zh-CN.md` 和 `PLAN.md`。

## 第二轮新增建议，已确认待合并

### 21. lock 文件必须是完整依赖锁

结论：采纳。

规则：

- lock 文件必须包含直接依赖和间接依赖。
- 所有包都应固定版本。
- 不建议只写 `torch`、`numpy`、`transformers` 这类顶层包。
- 复杂的 `--require-hashes` / hashlock 暂列未来增强，不进入当前第一版实现。

原因：

- 顶层包版本不变时，间接依赖解析结果仍可能随时间变化。
- 完整依赖锁才能支撑离线可复现。

### 22. Check 的 wheels 覆盖判定必须具体化

结论：采纳。

对每个 lock 文件中的包，Check 必须确认：

```text
1. wheels 目录中存在对应 wheel。
2. 包名匹配。
3. 版本匹配。
4. Python tag / ABI / platform 兼容 cp311 / win_amd64。
5. 不接受只有源码包 .tar.gz / .zip。
```

输出示例：

```text
[OK] torch==x.x.x -> torch-...-cp311-win_amd64.whl
[FAIL] numpy==x.x.x -> 未找到 cp311-win_amd64 wheel
[FAIL] opencv-python==x.x.x -> 只有 cp312 wheel，不兼容目标 Python 3.11
```

### 23. manifest 记录 pip / setuptools / wheel 版本

结论：采纳。

manifest 增加：

```json
{
  "toolchain": {
    "downloadPython": "3.11.x",
    "pip": "xx.x",
    "setuptools": "xx.x",
    "wheel": "xx.x"
  }
}
```

原因：

- `pip download` 的解析和 wheel 选择行为可能随 pip 版本变化。
- 记录工具链版本有助于长期排查。

### 24. packageStatus 状态流转必须精确

结论：采纳。

状态流转：

```text
Download 开始：packageStatus = incomplete
文件下载完成但未校验：packageStatus = incomplete
Download 内部校验通过：packageStatus = complete
Download 内部校验失败：packageStatus = failed
RegisterLocalFiles 登记后内部校验通过：packageStatus = complete
RegisterLocalFiles 内部校验失败：packageStatus = failed
```

规则：

- 普通 Check 永远只读，不更新 `packageStatus`。
- Download / RegisterLocalFiles 可以调用校验函数，但由 Download / RegisterLocalFiles 自己原子写 manifest。
- Install 只接受 `packageStatus == complete`。

### 25. `-Force` 的破坏范围必须受限

结论：采纳。

规则：

- `-Force` 只能覆盖 Download 管理的目标文件。
- `-Force` 不能删除 venv。
- `-Force` 不能覆盖用户项目、数据集、模型目录。
- `-Force` 不能跳过 SHA256 校验。
- `-Force` 不能让 Check 写 manifest。

### 26. RegisterLocalFiles 要防止误登记错误文件

结论：采纳。

规则：

```text
NVIDIA 驱动：
  扩展名必须是 .exe。
  文件名建议包含 nvidia / studio / game-ready / geforce 等关键词之一。
  文件过小时警告，可能不是完整驱动。

CUDA Toolkit：
  必须是 local installer。
  小体积 network installer 直接拒绝。

Git：
  文件名建议包含 Git 或 Git-*-64-bit。
```

manifest 手动登记项增加：

```json
{
  "source": "manual",
  "registeredAt": "...",
  "registeredByMode": "RegisterLocalFiles",
  "userConfirmed": true
}
```

### 27. Verify 的 CUDA 版本比较必须数值解析

结论：采纳。

规则：

- 不允许直接字符串比较版本。
- `12.10` 必须大于 `12.8`。
- 解析成 `major/minor` 后比较。
- 如果 `torch.version.cuda == None`，说明可能安装了 CPU 版 PyTorch，Verify 直接失败并提示安装 cu128 wheel。

中文提示：

```text
当前 PyTorch 不是 CUDA 版本，torch.version.cuda == None。
请确认安装的是 cu128 wheel，而不是 CPU wheel。
```

### 28. 所有 pip 操作必须使用 `<VenvPython> -m pip`

结论：采纳。

规则：

- 禁止直接调用 `pip`。
- 禁止依赖 PATH 中的 pip。
- venv 创建后，所有安装、检查、查询都使用：

```powershell
& $VenvPython -m pip ...
```

原因：

- Windows 上容易调到系统 pip 或其他环境 pip。

### 29. ReuseVenv 前必须检查环境是否匹配

结论：采纳。

复用前检查：

```text
venvPython 存在。
venv Python 版本 == manifest.pythonMajorMinor。
venv Python 架构 == 64bit。
如果已安装 torch：
  torch.version.cuda 必须为空或等于目标 CUDA runtime。
  如果是 CPU 版 torch 或 CUDA 不匹配，建议 RecreateVenv。
```

规则：

- `ReuseVenv` 只用于补全缺失依赖。
- 发现核心包版本冲突时直接失败，建议 `RecreateVenv`。
- 不在复用环境里强行覆盖一堆核心包。

### 30. `resolved-install.lock.txt` 应记录来源

结论：采纳。

文件头部建议：

```text
# Generated by OfflineDL-Win10-3090.ps1
# Source manifest sha256: ...
# Profile: Research
# Optional components: Visualization
# Generated at: ...
# Do not edit manually.
```

### 31. `.bat` 入口保留 exit code，带参数时不 pause

结论：采纳。

建议内容：

```bat
@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0OfflineDL-Win10-3090.ps1" %*
set EXITCODE=%ERRORLEVEL%
if "%1"=="" pause
exit /b %EXITCODE%
```

原因：

- 双击时暂停，方便小白看结果。
- 命令行带参数时不阻塞自动化。
- 保留 PowerShell 退出码。

### 32. README 增加推荐运行顺序

结论：采纳。

README 应给小白明确流程：

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

### 33. 增加 `-Mode Doctor`

结论：采纳为计划项，但可作为第二阶段实现。

Doctor 只读，不下载、不安装、不修改文件。

输出：

```text
系统信息
PowerShell 版本
Python 检测结果
NVIDIA / nvidia-smi
VC++ Runtime 检测
manifest 状态
wheels 状态
工作区状态
```

### 34. 日志记录外部命令和退出码

结论：采纳。

日志必须记录：

```text
执行了什么命令
外部命令 exit code
stdout / stderr 摘要
失败时最后 50 行输出
```

重点命令：

```text
pip download
pip install
pip check
nvidia-smi
```

### 35. 增加 docs 排错文档

结论：采纳。

新增目录：

```text
docs\
  troubleshooting.md
  common-errors.md
```

覆盖常见问题：

```text
torch.cuda.is_available() == False
DLL load failed
No matching distribution found
pip check failed
nvidia-smi not found
PowerShell script disabled
```

### 36. 明确实施优先级，先跑通最小闭环

结论：采纳。

第一阶段优先实现：

```text
Download / Check / Install / Verify
Research Profile
PyTorch CUDA 12.8
manifest / lock / SHA256 校验
```

第二阶段再实现或完善：

```text
RegisterLocalFiles
Visualization
Doctor
CUDA Toolkit local installer 检测
VS Code
复杂 hashlock / --require-hashes
```

目标：

```text
联网机 Download -> Check -> 拷贝 -> 离线机 Check -> Install -> Verify
```

不要继续无限扩设计，先把最小闭环稳定跑通。

## 第三轮新增建议，已确认待合并

### 37. 第一阶段菜单隐藏未实现功能

结论：采纳。

原因：

- RegisterLocalFiles、Doctor、Visualization、CUDA Toolkit local installer 检测等已规划为第二阶段。
- 第一阶段菜单显示未实现功能，会让小白用户误点。

第一阶段菜单只显示：

```text
[1] Download  在联网电脑下载离线包
[2] Check     只检查离线包是否完整，不修改文件
[3] Install   在离线电脑安装环境
[4] Verify    验证显卡和 PyTorch 是否可用
[5] Exit      退出
```

规则：

- 第一阶段不在交互菜单显示 Register/Doctor。
- 如果命令行传入 `-Mode RegisterLocalFiles` 或 `-Mode Doctor`，返回中文提示：该模式计划在第二阶段实现，当前版本暂不可用。
- 主计划仍保留第二阶段设计，但要明确第一阶段不暴露。

### 38. 修正 `packageStatus failed` 语义

结论：采纳。

规则：

```text
failed：Download 或 RegisterLocalFiles 流程中的内部校验失败。
```

普通 Check 失败：

- 只返回错误码。
- 只写日志。
- 不修改 manifest。
- 不修改 `packageStatus`。

### 39. PyTorch cu128 lock 写法必须实测

结论：采纳。

原因：

- PyTorch CUDA wheel 对版本写法和 index URL 比较敏感。
- `torch==x.x.x` 和 `torch==x.x.x+cu128` 哪个可用，不能凭感觉。

规则：

- `torch-cu128.lock.txt` 不能手写猜测。
- 必须在联网机上用目标下载命令真实 `pip download` 成功后，再把成功版本写入 lock。
- 如果官方命令风格要求不带 `+cu128`，就按实测结果写。
- 如果必须带 `+cu128`，也必须以实测为准。

### 40. `install_state.json` 成功写入时机更严格

结论：采纳。

只有以下全部成功后，才能写：

```json
{
  "installStatus": "success"
}
```

成功条件：

```text
venv 创建成功
pip install 成功
pip check 成功
torch import 成功
torch.cuda.is_available() == True
```

如果失败：

- 不写成功状态。
- 可以写 `installStatus: failed` 和 `failedAtStep`，或写单独 `install_state.failed.json`。
- 不能让半残安装看起来像成功安装。

### 41. 第一版不强求完整依赖树 lock

结论：采纳并调整当前计划措辞。

第一版策略：

```text
requirements/*.lock.txt：
  固定顶层包版本。

manifest.files：
  记录实际下载到的所有 wheel 文件、size、SHA256。

Check：
  以 manifest.files 为离线包完整性的最终依据。
```

长期增强：

```text
完整依赖树 lock
pip-tools / pip-compile
--require-hashes
hashlock
```

说明：

- 第一版仍然需要 lock 文件，但不要求手工维护完整依赖树。
- 第一版的可复现重点放在已下载 wheels 的 manifest 哈希上。

### 42. Check 第一版以 manifest.files 校验为主

结论：采纳。

第一版 Check：

```text
禁止 .tar.gz / .zip 源码包。
manifest 记录的 wheel 文件必须存在。
文件大小必须一致。
SHA256 必须一致。
文件名明显不兼容目标平台时提示失败或警告。
```

复杂 wheel tag 解析放第二阶段：

```text
packaging.tags
完整 Python tag / ABI / platform 兼容性判断
```

### 43. Python 安装包记录 x64/amd64

结论：采纳。

manifest Python 安装包条目应记录：

```json
{
  "component": "Python",
  "version": "3.11.x",
  "arch": "x64",
  "installer": "python-3.11.x-amd64.exe"
}
```

规则：

- 第一版只支持 Windows x64 / amd64。
- RegisterLocalFiles 登记 Python 安装包时拒绝 win32、x86、arm64、embed 版本。

### 44. Verify 默认使用小矩阵测试

结论：采纳。

第一版 CUDA 验证使用：

```python
a = torch.randn(1024, 1024, device="cuda")
b = torch.randn(1024, 1024, device="cuda")
c = a @ b
torch.cuda.synchronize()
```

原因：

- 验证目标是确认 CUDA 能跑，不是压力测试。
- 小矩阵更快、更稳定。

未来可增加：

```powershell
-Mode Verify -Stress
```

### 45. Doctor 和 Visualization 放第二阶段

结论：采纳。

第一阶段：

- 不暴露 Doctor 菜单。
- 不实现 Visualization 下载/安装。
- 失败时保留 doctor 风格摘要。

第二阶段：

- 实现独立 `Doctor` 模式。
- 实现 `-IncludeVisualization`。
- 实现 RegisterLocalFiles、CUDA Toolkit local installer 检测等增强项。

## 第四轮新增建议，已确认待合并

### 46. 第一阶段参数也要跟菜单一样收敛

结论：采纳。

第一阶段只支持：

```text
-Mode Download / Check / Install / Verify
-Profile Research
Python 3.11
PyTorch CUDA 12.8
```

第一阶段显式不支持：

```text
-IncludeGit
-IncludeCudaToolkit
-IncludeVisualization
-Profile Full
```

如果用户传入第二阶段参数，脚本必须明确提示：

```text
该选项属于第二阶段能力，当前版本暂不可用。
```

不能静默忽略，避免用户以为已经下载了 Git、CUDA Toolkit 或 Visualization 包。

### 47. 分离内部校验函数和 Check 模式

结论：采纳。

实现时应明确区分：

```text
Test-OfflinePackage：只检查，返回结果对象，不写文件
Invoke-CheckMode：调用 Test-OfflinePackage，只输出结果，不写 manifest
Write-ManifestAtomic：只有 Download / RegisterLocalFiles 等可写流程调用
```

Download 可以调用内部校验函数后，由 Download 自己决定是否原子写回 `packageStatus`。

Check 模式永远只读，不能在函数内部顺手更新 manifest。

### 48. `manifest.files` 增加文件类型和组件字段

结论：采纳。

`manifest.files` 不应只记录 path/sha256，建议记录：

```json
{
  "component": "torch",
  "kind": "wheel",
  "required": true,
  "profile": "Research",
  "path": "wheels/pytorch-cu128/torch-xxx.whl",
  "fileName": "torch-xxx.whl",
  "size": 123456,
  "sha256": "...",
  "sourceUrl": "...",
  "source": "download",
  "downloadedAt": "..."
}
```

`kind` 至少包括：

```text
installer
wheel
lock
script
doc
```

这样 Check 可以输出更清楚的中文错误，例如缺少必需 wheel、缺少 Python 安装包、缺少 VC++ Runtime。

### 49. 明确 lock 文件和 manifest.files 不一致时的规则

结论：采纳。

规则：

```text
Install 以 manifest 为事实来源。
lock 文件用于生成 resolved-install.lock.txt。
manifest.files 用于确认离线包实际拥有的文件。
两者不一致时直接失败。
```

第一阶段不强依赖 `pip install --dry-run`，因为旧 pip 支持不稳定。可以作为可选诊断增强；真正安装失败必须停止，并保留 pip 错误日志，不能写成功状态。

### 50. 扫描重复 wheel 和版本冲突

结论：采纳。

Download / Check 后应扫描：

```text
wheels\pytorch-cu128
wheels\common
wheels\optional
```

规则：

```text
同名文件重复且 SHA256 相同：允许
同名文件重复但 SHA256 不同：失败
同包同版本但文件名不同：警告
同包不同版本：失败
```

目的：避免 pip 在多个 `--find-links` 目录中看到不稳定候选。

### 51. Python 安装检测必须检查 pip 和 venv

结论：采纳。

Install 阶段不能只检查 `python.exe` 存在，还必须检查：

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

### 52. nvidia-smi 缺失时给出明确驱动提示

结论：采纳。

Install 第一阶段要求 NVIDIA 驱动已安装并且 `nvidia-smi` 可用。若不可用，应明确提示：

```text
Install 要求 NVIDIA 驱动已安装并且 nvidia-smi 可用。
如果你还没有安装驱动，请先手动安装 downloads\drivers 中的驱动并重启。
```

这是有意的安全策略，不应让用户误以为脚本坏了。

### 53. Verify 检查 sourceManifestHash

结论：采纳。

Verify 读取 `install_state.json` 后，如果当前离线包目录存在 `manifest.json`：

```text
计算当前 manifest hash
与 install_state.sourceManifestHash 比较
```

规则：

```text
一致：正常
不一致：警告，不失败
找不到当前 manifest：继续 Verify，但提示无法确认来源
```

警告文案：

```text
当前离线包 manifest 与安装时来源不一致，Verify 只验证当前环境可用性，不代表此环境由当前离线包安装。
```

### 54. Install 失败状态写入单独 failed 文件

结论：采纳。

规则：

```text
Install 成功：写 install_state.json
Install 失败：写 install_state.failed.json
```

失败尝试不能覆盖已有的成功 `install_state.json`，避免一次升级失败破坏原本可用环境的验证状态。

### 55. README 建议工作区路径不要带空格

结论：采纳。

README 增加提示：

```text
推荐工作区路径不要包含空格或特殊字符，例如 D:\AI 或 E:\AI。
不推荐：E:\AI Workspace。
```

原因：Windows `.bat`、PowerShell 参数转发、外部工具在带空格路径下更容易踩坑。

### 56. README 提醒必须拷贝整个离线包目录

结论：采纳。

README 需要醒目提示：

```text
拷贝到离线电脑时，请拷贝整个 Win10_3090_DeepLearning_OfflinePack 文件夹。
不要只拷贝 wheels 或 downloads 子目录。
manifest、requirements、scripts、logs 都是安装和校验所需的一部分。
```

### 57. 第一版实现顺序按最小闭环来

结论：采纳。

实现顺序建议改为：

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

原因：Download 依赖 manifest、SHA256、Check 逻辑，最后写更稳。

## 第五轮新增建议，已确认待合并

### 58. 第一阶段 manifest 示例使用空可选组件

结论：采纳。

第一阶段不支持 Visualization / Git / CUDA Toolkit，因此 manifest 示例必须改成：

```json
"optionalComponents": []
```

不要在第一阶段示例中出现：

```json
"optionalComponents": ["Visualization"]
```

避免实现时误以为第一阶段会安装可视化增强包。

### 59. 第一版不暴露 `-Profile`

结论：采纳。

第一版参数只暴露：

```powershell
-Mode Download / Check / Install / Verify
```

内部固定：

```powershell
$Profile = "Research"
```

`-Profile Minimal`、`-Profile Full`、`-Profile Research` 都不作为第一版公开参数。若用户传入 `-Profile`，明确提示该参数属于第二阶段能力。

### 60. lock 文件不要重复声明 PyTorch 核心包

结论：采纳。

第一阶段 lock 文件职责：

```text
torch-cu128.lock.txt：只放 torch / torchvision / torchaudio
research.lock.txt：放科研常用包，不重复写 torch / torchvision / torchaudio
```

原因：避免未来 PyTorch 版本改动时两个 lock 文件约束不一致。

### 61. PyTorch wheel 文件名强制检查 cu128

结论：采纳。

下载 PyTorch 后，必须检查：

```text
torch wheel 文件名包含 cu128
torchvision wheel 文件名包含 cu128
torchaudio wheel 文件名包含 cu128
```

如果下载到不含 `cu128` 的 wheel，直接失败，避免误用 CPU wheel。

### 62. manifest 记录下载命令摘要

结论：采纳。

manifest 建议增加：

```json
"downloadCommands": [
  {
    "component": "pytorch",
    "lockFile": "requirements/torch-cu128.lock.txt",
    "targetDir": "wheels/pytorch-cu128",
    "indexUrl": "https://download.pytorch.org/whl/cu128",
    "pythonVersion": "311",
    "abi": "cp311",
    "platform": "win_amd64"
  }
]
```

用于长期追溯离线包如何生成。

### 63. Check 增加必需组件清单检查

结论：采纳。

Check 第一阶段分两层：

```text
1. manifest.files 中记录的文件存在、大小和 SHA256 正确。
2. 当前固定 Research 环境必需组件都出现在 manifest.files 中。
```

必需组件至少包括：

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

避免 manifest 自己漏项但 Check 仍然通过。

### 64. Install 检查目标 GPU 名称

结论：采纳。

Install 通过 `nvidia-smi` 检查当前 GPU：

```text
检测不到 NVIDIA GPU：失败。
检测到 RTX 3090：继续。
检测到 NVIDIA GPU 但不是 RTX 3090：交互警告并询问是否继续。
NonInteractive 下 GPU 不匹配直接失败。
```

避免把环境误装到非目标机器上。

### 65. venv 增加 installing / ready 标记

结论：采纳。

安装开始时写：

```text
<venv>\.offline_dl_installing
```

安装成功后删除 installing，并写：

```text
<venv>\.offline_dl_ready
```

下次 Install 如果发现 installing 存在但 ready 不存在，提示上次安装可能中断，当前虚拟环境不可信，建议删除并重建。

### 66. 第一版不支持 `ReuseVenv`

结论：强烈采纳。

第一阶段只支持干净安装：

```text
如果 venv 已存在：
  交互模式：建议删除重建
  命令行模式：除非 -RecreateVenv，否则失败
```

`ReuseVenv` 放到第二阶段。这样能避免旧环境污染、CPU torch、CUDA 版本不匹配、残留依赖等玄学问题。

### 67. README 强调驱动 / Python / VC++ 手动安装

结论：采纳。

README 开头需要写清楚：

```text
本脚本不会自动安装 NVIDIA 驱动、Python 安装包、VC++ Runtime。
第一次在离线电脑运行 Install 前，请按提示手动运行 downloads 目录中的安装包，并重启。
```

### 68. 第一阶段最终范围进一步收窄

结论：采纳。

第一阶段支持：

```text
Download
Check
Install
Verify
固定 Research
干净 venv 安装
PyTorch CUDA 12.8
Python 3.11 x64
```

第一阶段暂不支持：

```text
Minimal / Full
Visualization
Git
CUDA Toolkit
RegisterLocalFiles
Doctor 独立模式
ReuseVenv
-Profile
```

## 第六轮新增建议，已确认待合并

### 69. 第一阶段 requirements 只读取两个 lock 文件

结论：采纳。

第一阶段只读取：

```text
requirements\torch-cu128.lock.txt
requirements\research.lock.txt
```

`minimal.lock.txt`、`visualization.lock.txt` 可以作为第二阶段预留，但第一阶段 Check / Install 不能扫描整个 requirements 目录并把预留文件当成必需文件。

### 70. `manifest.files` 增加 `group`

结论：采纳。

`manifest.files` 条目增加：

```json
"group": "pytorch"
```

建议分组：

```text
driver
python
runtime
pytorch
research
script
doc
```

用于让 Check 输出更清楚，例如 `[OK] pytorch: torch wheel`。

### 71. PyTorch wheel 文件名检查使用小写包含 `cu128`

结论：采纳。

实现规则：

```powershell
$fileName.ToLower().Contains("cu128")
```

不要强制匹配 `+cu128`，避免文件名规范或编码差异导致误判。

### 72. 第一阶段强制 `optionalComponents` 为空

结论：采纳。

Check / Install 第一阶段必须要求：

```text
manifest.optionalComponents 是空数组。
```

如果不为空，提示该 manifest 可能来自未来版本或非第一阶段包，当前脚本不支持。

### 73. manifest 增加 `phase: 1`

结论：采纳。

manifest 顶层增加：

```json
"phase": 1
```

Install / Check 要求：

```text
schemaVersion == 1
phase == 1
```

将来第二阶段 manifest 结构变复杂时，第一阶段脚本看到 `phase: 2` 应提示升级脚本，而不是继续安装。

### 74. Download 输出当前 Python / pip / 目标平台

结论：采纳。

Download 开始时输出并写入日志：

```text
当前下载用 Python：...
当前 pip：...
目标下载平台：win_amd64 / cp311
```

让用户明确联网机系统和显卡不会污染目标 wheel 下载。

### 75. 干净 venv 规则进一步明确

结论：采纳。

第一阶段规则：

```text
如果 venv 不存在：创建。
如果 venv 存在且没有 .offline_dl_ready：要求删除重建。
如果 venv 存在且有 .offline_dl_ready：仍要求输入 DELETE 后重建。
```

第一阶段只要目标 venv 已存在，就不复用。

### 76. 删除 venv 前确认路径位于 WorkspaceRoot 内

结论：强烈采纳。

删除前必须确认：

```text
VenvPath 必须等于 <WorkspaceRoot>\envs\dl-py311-cu128
```

防止变量拼错、路径为空或误删其他目录。

### 77. 删除 venv 前检查目录名或标记文件

结论：强烈采纳。

删除已有 venv 前至少满足一个条件：

```text
目录名等于 dl-py311-cu128
或者目录里存在 .offline_dl_installing / .offline_dl_ready
```

如果都不满足，拒绝自动删除并提示该目录不像本脚本创建的虚拟环境。

### 78. Verify 检查 `.offline_dl_ready`

结论：采纳。

Verify 使用 `install_state.json` 后，还要检查 venv 目录下是否存在：

```text
.offline_dl_ready
```

如果没有，警告环境可能不是由本脚本完整安装，继续验证但提示来源不完整。

### 79. 日志目录不自动清理

结论：采纳。

第一版保留全部日志，不自动删除。README 说明：

```text
logs 目录可定期手动清理，不影响离线包安装。
manifest、requirements、wheels、downloads 不要手动删除。
```

避免误删排错证据。

### 80. 第一阶段 P0 实现检查清单

结论：采纳。

把 Download / Check / Install / Verify 的 P0 必做检查清单加入计划，作为实现和验收依据。
