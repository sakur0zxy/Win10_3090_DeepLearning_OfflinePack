# Win10 + RTX 3090 深度学习离线环境工具

这个离线包用于在另一台 Windows 10 x64 + RTX 3090 电脑上安装深度学习环境。

默认技术栈：

- Python 3.11 x64
- PyTorch CUDA 12.8
- 可选择 `Minimal` / `Research` / `Full` 档位
- 可选 Visualization 增强包
- 可选登记 Git / CUDA Toolkit / VS Code 安装包

## 推荐流程

联网电脑：

1. 双击 `OfflineDL-Win10-3090.bat`。
2. 选择 `Download`。
3. 选择档位：`Minimal`、`Research` 或 `Full`。
4. 按提示决定是否加入 Visualization、Git、CUDA Toolkit、VS Code。
5. 如果提示缺少 NVIDIA 驱动，请从 NVIDIA 官方页面下载 RTX 3090 / Windows 10 x64 驱动 exe，放到 `downloads\manual_inbox`，脚本会自动整理到对应目录。
6. 下载完成后运行 `Check`。
7. Check 通过后，拷贝整个 `Win10_3090_DeepLearning_OfflinePack` 文件夹到离线电脑。

离线电脑：

1. 先运行 `Check`，确认离线包没有损坏。
2. 按提示手动安装 NVIDIA 驱动、Python、VC++ Runtime。
3. 驱动安装后重启电脑。
4. 运行 `Install`，输入 AI 工作区路径，例如 `D:\AI`。
5. 安装完成后运行 `Verify`。

请拷贝整个文件夹，不要只拷贝 `wheels` 或 `downloads`。`manifest.json`、`requirements`、`scripts`、`logs` 都是校验和安装需要的。

## 入口

双击入口：

```text
OfflineDL-Win10-3090.bat
```

PowerShell 入口：

```powershell
powershell -ExecutionPolicy Bypass -File .\OfflineDL-Win10-3090.ps1
```

常用命令：

```powershell
.\OfflineDL-Win10-3090.ps1 -Mode Download
.\OfflineDL-Win10-3090.ps1 -Mode Download -Profile Minimal
.\OfflineDL-Win10-3090.ps1 -Mode Download -Profile Research -IncludeVisualization
.\OfflineDL-Win10-3090.ps1 -Mode Download -Profile Full
.\OfflineDL-Win10-3090.ps1 -Mode Check
.\OfflineDL-Win10-3090.ps1 -Mode RegisterLocalFiles
.\OfflineDL-Win10-3090.ps1 -Mode Install -WorkspaceRoot D:\AI
.\OfflineDL-Win10-3090.ps1 -Mode Install -WorkspaceRoot D:\AI -ReuseVenv
.\OfflineDL-Win10-3090.ps1 -Mode Verify -WorkspaceRoot D:\AI
.\OfflineDL-Win10-3090.ps1 -Mode Doctor -WorkspaceRoot D:\AI
```

## 档位说明

- `Minimal`：最小运行环境，适合只跑基础 PyTorch / numpy / pandas / scipy。
- `Research`：默认科研环境，包含 Jupyter、scikit-learn、matplotlib、OpenCV、transformers 等。
- `Full`：Research + Git / CUDA Toolkit 安装包登记。不会自动静默安装这些工具。
- `Visualization`：独立可选项，包含 seaborn、plotly、ipywidgets、mlflow。

## 手动安装包

脚本不会自动静默安装 NVIDIA 驱动、Python、VC++ Runtime、Git、CUDA Toolkit、VS Code。它只负责下载、登记、校验和离线安装 Python wheel。

手动文件放置位置：

推荐把所有手动下载的 exe 先放到统一收件箱：

```text
downloads\manual_inbox
```

运行 `Download` 或 `RegisterLocalFiles` 时，脚本会自动识别并整理到对应目录。如果你已经把 exe 放在 `downloads` 根目录，脚本也会尝试识别并整理。

整理后的目录：

```text
downloads\drivers          NVIDIA 驱动安装包
downloads\cuda_optional    CUDA Toolkit local installer
downloads\tools_optional   Git / VS Code 安装包
downloads\python           Python 安装包
downloads\runtime          VC++ Runtime 安装包
```

CUDA Toolkit 必须是离线完整安装包，不接受小体积 network installer。

## 官方下载页面

脚本在 `Download` 和 `RegisterLocalFiles` 中也会显示这些入口：

| 软件 | 官方页面 | 推荐放置位置 |
| --- | --- | --- |
| NVIDIA RTX 3090 驱动 | https://www.nvidia.com/Download/index.aspx | `downloads\manual_inbox` |
| Python 3.11.9 x64 | https://www.python.org/downloads/release/python-3119/ | `downloads\manual_inbox` |
| VC++ Runtime x64 | https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170 | `downloads\manual_inbox` |
| Git for Windows | https://git-scm.com/install/windows.html | `downloads\manual_inbox` |
| CUDA Toolkit | https://developer.nvidia.com/cuda-toolkit-archive | `downloads\manual_inbox` |
| VS Code | https://code.visualstudio.com/download | `downloads\manual_inbox` |

CUDA Toolkit 请选择 Windows / x86_64 / Windows 10 / exe (local)，不要选 network installer。

## ReuseVenv

默认安装策略是干净环境。如果目标虚拟环境已经存在：

- 不传 `-ReuseVenv`：脚本会要求删除并重建。
- 传 `-ReuseVenv`：脚本会先检查 Python 版本、64 位、pip、已有 PyTorch CUDA 版本。
- 如果检测到 CPU 版 PyTorch、CUDA 版本不匹配、torch 无法导入，脚本会停止并建议使用 `-RecreateVenv`。

## 路径建议

- 下载文件会保存到当前脚本所在文件夹。
- 如果要把离线包放到移动硬盘，请先移动整个脚本文件夹，再运行 Download。
- AI 工作区建议使用 `D:\AI` 或 `E:\AI`。
- 工作区路径尽量不要带空格或特殊字符。
- Windows 间使用移动硬盘推荐 NTFS；需要跨平台交换再考虑 exFAT；不要用 FAT32。

## 日志

日志保存在 `logs` 目录。`logs` 可以定期手动清理；不要手动删除 `manifest.json`、`requirements`、`wheels`、`downloads`。
