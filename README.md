# Win10 + RTX 3090 深度学习离线环境工具

这个离线包用于在另一台 Windows 10 x64 + RTX 3090 电脑上安装深度学习环境：

- Python 3.11 x64
- PyTorch CUDA 12.8
- Research 常用科研包
- 干净虚拟环境 `dl-py311-cu128`

当前版本支持 `Download / Check / RegisterLocalFiles / Install / Verify / Doctor`。

当前版本仍不支持：`Visualization / ReuseVenv / 多 Profile`，也不会自动安装 Git、CUDA Toolkit、VS Code。`RegisterLocalFiles` 只负责把你手动放入文件夹的安装包登记进 `manifest.json`。

## 联网电脑推荐流程

1. 双击 `OfflineDL-Win10-3090.bat`。
2. 选择 `Download`，按提示输入 `y` 确认下载到当前脚本所在文件夹。
3. 如果提示缺少 NVIDIA 驱动，请从 NVIDIA 官方驱动页面下载 RTX 3090 / Windows 10 x64 驱动 exe，放到 `downloads\drivers`。
4. 可选择运行 `RegisterLocalFiles`，把手动放入的驱动登记进 `manifest.json`。
5. 再运行 `Download`。
6. 下载完成后选择 `Check`。
7. Check 通过后，把整个 `Win10_3090_DeepLearning_OfflinePack` 文件夹拷贝到离线电脑。

请拷贝整个文件夹，不要只拷贝 `wheels` 或 `downloads`。`manifest.json`、`requirements`、`scripts`、`logs` 都是校验和安装需要的。

## 离线电脑推荐流程

1. 双击 `OfflineDL-Win10-3090.bat`。
2. 先选择 `Check`，确认离线包没有损坏。
3. 按提示手动安装 NVIDIA 驱动、Python、VC++ Runtime。
4. 驱动安装后请重启电脑。
5. 再选择 `Install`，输入 AI 工作区路径，例如 `D:\AI`。
6. 安装完成后选择 `Verify`。

本脚本不会自动静默安装 NVIDIA 驱动、Python 安装包、VC++ Runtime。第一次安装时请按提示手动运行对应安装包。

## PowerShell 运行方式

如果双击 `.ps1` 被系统阻止，可以使用：

```powershell
powershell -ExecutionPolicy Bypass -File .\OfflineDL-Win10-3090.ps1
```

也可以直接双击：

```text
OfflineDL-Win10-3090.bat
```

## 命令行示例

```powershell
.\OfflineDL-Win10-3090.ps1 -Mode Download
.\OfflineDL-Win10-3090.ps1 -Mode Check
.\OfflineDL-Win10-3090.ps1 -Mode RegisterLocalFiles
.\OfflineDL-Win10-3090.ps1 -Mode Install -WorkspaceRoot D:\AI
.\OfflineDL-Win10-3090.ps1 -Mode Verify -WorkspaceRoot D:\AI
.\OfflineDL-Win10-3090.ps1 -Mode Doctor -WorkspaceRoot D:\AI
```

当前版本不支持 `-Profile`、`-ReuseVenv`、`-IncludeGit`、`-IncludeCudaToolkit`、`-IncludeVisualization`。传入这些参数会直接提示暂不可用。

## 手动登记文件

`RegisterLocalFiles` 会扫描：

```text
downloads\drivers          NVIDIA 驱动安装包
downloads\cuda_optional    CUDA Toolkit local installer，可选登记
downloads\tools_optional   Git / VS Code 安装包，可选登记
```

注意：登记不等于安装。Git、CUDA Toolkit、VS Code 仍需要你按需手动安装。

## 路径建议

- 离线包会保存到当前脚本所在文件夹。
- AI 工作区建议使用 `D:\AI` 或 `E:\AI`。
- 工作区路径尽量不要带空格或特殊字符。
- 如果只在 Windows 间使用移动硬盘，推荐 NTFS；需要跨平台交换再考虑 exFAT；不要用 FAT32。

## 日志

日志保存在 `logs` 目录。`logs` 可以定期手动清理；不要手动删除 `manifest.json`、`requirements`、`wheels`、`downloads`。
