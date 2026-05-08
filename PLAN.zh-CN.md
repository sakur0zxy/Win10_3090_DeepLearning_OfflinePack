# Win10 + RTX 3090 深度学习离线环境计划

## 目标

为离线 Windows 10 x64 + NVIDIA RTX 3090 电脑准备一个可复现、可校验、可长期维护的深度学习环境离线包。

使用方式：

```text
联网电脑：只下载离线包，不安装。
离线电脑：检查、安装、验证环境。
```

默认技术栈：

- Python 3.11 x64
- PyTorch CUDA 12.8
- NVIDIA RTX 3090 驱动安装包
- VC++ Runtime
- Python wheel 离线包

## 当前已支持能力

入口脚本：

```text
OfflineDL-Win10-3090.ps1
OfflineDL-Win10-3090.bat
```

支持模式：

```powershell
-Mode Download
-Mode Check
-Mode RegisterLocalFiles
-Mode Install
-Mode Verify
-Mode Doctor
```

支持参数：

```powershell
-Profile Minimal
-Profile Research
-Profile Full
-IncludeVisualization
-IncludeGit
-IncludeCudaToolkit
-IncludeVSCode
-ReuseVenv
-RecreateVenv
```

## 档位

- `Minimal`：最小运行环境，包含基础科学计算包。
- `Research`：默认科研环境，包含 Jupyter、scikit-learn、matplotlib、OpenCV、transformers 等。
- `Full`：Research + Git / CUDA Toolkit 安装包登记。
- `Visualization`：独立可选项，包含 seaborn、plotly、ipywidgets、mlflow。

`Full` 不自动包含 Visualization。Visualization 需要单独选择。

## 目录结构

```text
Win10_3090_DeepLearning_OfflinePack\
  OfflineDL-Win10-3090.ps1
  OfflineDL-Win10-3090.bat
  config.json
  manifest.json
  README.md
  PLAN.md
  PLAN.zh-CN.md

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
    minimal.lock.txt
    research.lock.txt
    visualization.lock.txt

  scripts\
  docs\
  logs\
  backups\
```

## 工作区结构

安装时只让用户输入一个 AI 工作区根目录，默认建议：

```text
D:\AI
```

派生结构：

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
    install_state.failed.json
    resolved-install.lock.txt
  cache\huggingface\
  cache\torch\
  cache\pip\
  activate-dl.ps1
  activate-dl.bat
```

## 核心原则

- 统一入口，阶段隔离。
- Download 只下载，不安装。
- Check 只读，不修改 manifest。
- Install 以 manifest 为事实来源。
- Verify 以 install_state 为事实来源，不回退系统 Python。
- 版本使用 lock 文件固定。
- manifest 记录文件大小和 SHA256。
- 必需组件缺失、哈希不一致、Python 位数不对、CUDA 版本不对时直接停止。
- 交互界面使用简单中文。

## Download

Download 会：

1. 提醒用户所有文件都会保存到当前脚本所在文件夹。
2. 让用户输入 `y` 确认。
3. 选择 Profile 和可选组件。
4. 检查磁盘空间、文件系统、网络。
5. 下载 Python、VC++ Runtime、Python wheels。
6. 检查 PyTorch wheel 文件名必须包含 `cu128`。
7. 生成 `manifest.json`。
8. 调用内部校验函数，成功后写 `packageStatus = complete`。

如果选择 Git / CUDA Toolkit / VS Code，脚本只登记本地安装包，不会自动下载安装它们。用户可以把对应 exe 统一放到：

```text
downloads\manual_inbox
```

运行 `Download` 或 `RegisterLocalFiles` 时，脚本会自动识别并整理到 `downloads\tools_optional`、`downloads\cuda_optional` 等对应目录。移动前必须显示移动清单，并要求用户输入 `y` 确认。为了兼容误放，脚本也会尝试识别 `downloads` 根目录下的 exe。

## Check

Check 永远只读。它会检查：

- manifest 可解析。
- schemaVersion / phase 匹配。
- packageStatus 是 complete。
- lock 文件 SHA256 正确。
- manifest.files 中的文件都存在、大小一致、SHA256 一致。
- 必需组件都已登记。
- 不接受源码包或 zip 包。
- wheel 目录没有同包多版本冲突。

## RegisterLocalFiles

RegisterLocalFiles 用于登记用户手动放进目录的安装包：

- NVIDIA 驱动
- CUDA Toolkit local installer
- Git
- VS Code

推荐用户把这些 exe 先放到 `downloads\manual_inbox`，由脚本整理后再登记。

该模式会原子更新 manifest；普通 Check 仍然只读。

## Install

Install 会：

1. 先运行 Check。
2. 检查 NVIDIA GPU 和 `nvidia-smi`。
3. 检查 Python 3.11 x64、pip、venv。
4. 检查 VC++ Runtime。
5. 创建或复用虚拟环境。
6. 从 manifest.lockFiles 生成 `resolved-install.lock.txt`。
7. 使用 `--no-index --find-links` 离线安装。
8. 运行 `pip check`。
9. 验证 torch import 和 CUDA available。
10. 写入 `.offline_dl_ready` 和 `install_state.json`。
11. 自动运行 Verify。

默认不复用旧虚拟环境。只有传入 `-ReuseVenv` 时才会复用，并先检查：

- venv Python 是 3.11 x64。
- venv pip 可用。
- 如果已有 torch，必须是 CUDA 12.8。
- CPU 版 torch 或 CUDA 版本不匹配时直接失败。

## Verify

Verify 会：

- 读取工作区 `state\install_state.json`。
- 使用 install_state 中记录的 venvPython。
- 运行 `pip check`。
- 运行 `scripts\verify_torch_cuda.py`。
- 输出 NVIDIA Driver、Driver CUDA capability、PyTorch CUDA runtime、GPU 名称。
- 做 1024x1024 CUDA 矩阵乘法测试。

## 已完成状态

已完成：

```text
Download / Check / Install / Verify
RegisterLocalFiles
Doctor
Minimal / Research / Full Profile
Visualization 可选包
Git / CUDA Toolkit / VS Code 手动安装包登记
ReuseVenv 安全复用
README 标准命名
GitHub 仓库推送
```

未来可选增强：

```text
完整依赖树 lock
--require-hashes
更多框架专用 Profile
更细的 wheel tag 兼容性解析
```
