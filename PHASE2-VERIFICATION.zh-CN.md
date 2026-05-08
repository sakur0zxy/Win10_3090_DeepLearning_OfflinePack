# 第二阶段验收记录

日期：2026-04-30

## 已完成范围

第二阶段推进了两个低风险增强能力：

- `RegisterLocalFiles`：登记用户手动放入 `downloads` 子目录的安装包，并原子更新 `manifest.json`。
- `Doctor`：输出只读诊断摘要，不下载、不安装、不修改文件。

本阶段仍不实现：

- `-Profile Minimal / Full`
- `-ReuseVenv`
- `-IncludeVisualization`
- 自动安装 Git / CUDA Toolkit / VS Code

## RegisterLocalFiles 规则

扫描路径：

```text
downloads\manual_inbox
downloads\drivers
downloads\cuda_optional
downloads\tools_optional
```

用户优先把手动下载的 exe 放到 `downloads\manual_inbox`；脚本会读取并整理到对应目录。为了兼容误放，`downloads` 根目录下的 exe 也会被尝试识别和整理。

登记规则：

- NVIDIA 驱动登记为必需组件 `nvidia-driver`。
- CUDA Toolkit 登记为可选组件 `CudaToolkit`，并拒绝明显过小的 network installer。
- Git 登记为可选组件 `Git`。
- VS Code 登记为可选组件 `VSCode`。
- 手动登记文件会写入 `source: manual`、`registeredAt`、`registeredByMode: RegisterLocalFiles`、`userConfirmed: true`。

## Doctor 诊断内容

`Doctor` 会输出：

- 脚本版本、离线包目录、PowerShell 版本。
- 系统信息、磁盘空间、文件系统。
- `config.json` / `manifest.json` 状态。
- Check 错误数和警告数。
- Python / py launcher / Python 3.11 x64 状态。
- VC++ Runtime 启发式检查。
- `nvidia-smi` / GPU 状态。
- 指定 `-WorkspaceRoot` 时检查 `install_state.json` 和 `.offline_dl_ready`。

## 已跑验证

```text
PowerShell parser OK
python -m py_compile scripts\verify_torch_cuda.py
Doctor: 无 manifest 时只读输出诊断
RegisterLocalFiles: 无可登记文件时清楚失败，不写 manifest
Check: 无 manifest 时仍只读失败
Download: 缺少 NVIDIA 驱动来源时提前失败
bat: 带参数运行仍不 pause
```

## 尚需真实文件验收

以下需要在放入真实安装包后验证：

```powershell
.\OfflineDL-Win10-3090.ps1 -Mode RegisterLocalFiles
.\OfflineDL-Win10-3090.ps1 -Mode Check
```

尤其需要确认：

- 真实 NVIDIA 驱动 exe 被登记到 `manifest.files`。
- CUDA Toolkit network installer 会被拒绝。
- Git / VS Code 只登记不自动安装。
