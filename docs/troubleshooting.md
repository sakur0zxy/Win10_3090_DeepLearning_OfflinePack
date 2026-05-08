# 排错指南

## running scripts is disabled on this system

用 bat 入口运行：

```text
OfflineDL-Win10-3090.bat
```

或者在 PowerShell 里运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\OfflineDL-Win10-3090.ps1
```

## nvidia-smi not found

说明 NVIDIA 驱动未安装或未重启。请手动运行 `downloads\drivers` 里的驱动安装包，安装完成后重启电脑。

官方下载页面：

```text
https://www.nvidia.com/Download/index.aspx
```

选择 GeForce RTX 30 Series / GeForce RTX 3090 / Windows 10 64-bit。

## DLL load failed

通常是 VC++ Runtime 缺失或不完整。请手动运行：

```text
downloads\runtime\VC_redist.x64.exe
```

官方下载页面：

```text
https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170
```

## No matching distribution found

通常是 wheel 与目标 Python / 平台不匹配。第一版目标固定为：

```text
Python 3.11
cp311
win_amd64
```

请重新在联网电脑运行 `Download`，不要手动替换 wheels。

## pip check failed

说明依赖版本有冲突或缺失。请保留 `logs` 目录里的日志，重新运行 `Check`，确认离线包完整。

## torch.cuda.is_available() == False

常见原因：

- NVIDIA 驱动未安装或太旧。
- 安装了 CPU 版 PyTorch。
- CUDA wheel 不是 cu128。

Verify 会检查 `torch.version.cuda`，并运行 1024x1024 CUDA 矩阵乘法。

## RegisterLocalFiles 没有发现文件

请确认文件已放到统一收件箱，脚本会自动整理到正确目录：

```text
downloads\manual_inbox
```

整理前会显示移动清单，并要求输入 `y` 确认。

如果已经整理完成，对应目录如下：

```text
downloads\drivers          NVIDIA 驱动 exe
downloads\cuda_optional    CUDA Toolkit local installer
downloads\tools_optional   Git / VS Code 安装包
```

登记只会写入 manifest，不会自动安装这些程序。

官方下载页面：

```text
NVIDIA 驱动: https://www.nvidia.com/Download/index.aspx
CUDA Toolkit: https://developer.nvidia.com/cuda-toolkit-archive
Git for Windows: https://git-scm.com/install/windows.html
VS Code: https://code.visualstudio.com/download
```

## 不知道哪里出问题

先运行只读诊断：

```powershell
.\OfflineDL-Win10-3090.ps1 -Mode Doctor
```

如果要诊断安装后的工作区：

```powershell
.\OfflineDL-Win10-3090.ps1 -Mode Doctor -WorkspaceRoot D:\AI
```
