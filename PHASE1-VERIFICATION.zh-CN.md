# 第一阶段验收记录

日期：2026-04-30

## 已完成范围

第一阶段已实现以下能力：

- `Download`：联网电脑下载离线包，固定目标为 Windows 10 x64 / Python 3.11 / PyTorch CUDA 12.8。
- `Check`：只读校验 `manifest.json`、lock 文件、下载文件、SHA256、必需组件、重复 wheel。
- `Install`：离线电脑创建干净 venv，离线安装 wheels，写入安装状态。
- `Verify`：只使用 `install_state.json` 里的 venv Python 验证 PyTorch CUDA，不回退系统 Python。

第一阶段明确不支持：

- `-Profile`
- `-ReuseVenv`
- Git / CUDA Toolkit / Visualization
- RegisterLocalFiles
- Doctor 独立模式

## 已跑验证

```text
PowerShell parser OK
python -m py_compile scripts\verify_torch_cuda.py
pip dry-run: torch-cu128.lock.txt 可解析为 cu128 wheels
pip dry-run: torch-cu128.lock.txt + research.lock.txt 可联合解析
Check: 缺少 manifest 时清楚失败
Verify: 缺少 install_state.json 时清楚失败，不回退系统 Python
Download: 非交互且未确认时停止
Download: 确认后缺少 NVIDIA 驱动来源时停止，不继续下载大文件
bat: 带参数运行时不 pause
```

## 关键修正

- PyTorch 与 Research wheels 改为一次性联合解析依赖，然后按核心 PyTorch wheel 与普通 wheel 分目录，避免出现同一依赖多个版本。
- `Download` 前检查 NVIDIA 驱动来源；没有本地驱动或配置 URL 时提前停止。
- `Download` 前检查旧 wheel；新 wheel 全部下载到 staging 成功后才替换旧 wheel，避免旧包混入新 manifest。
- `.ps1` 文件使用 UTF-8 BOM，兼容 Windows PowerShell 5.1 的中文脚本解析。

## 尚需真实机器验收

以下步骤必须在真实联网机和离线 Win10 + RTX 3090 电脑上完成：

```powershell
.\OfflineDL-Win10-3090.ps1 -Mode Download
.\OfflineDL-Win10-3090.ps1 -Mode Check
```

拷贝整个离线包目录到离线电脑后：

```powershell
.\OfflineDL-Win10-3090.ps1 -Mode Check
.\OfflineDL-Win10-3090.ps1 -Mode Install
.\OfflineDL-Win10-3090.ps1 -Mode Verify
```

成功标准：

- `Check` 只读通过。
- `Install` 成功创建 `<WorkspaceRoot>\envs\dl-py311-cu128`。
- `pip check` 通过。
- `torch.version.cuda` 不为空。
- `torch.cuda.is_available()` 为 True。
- 1024 x 1024 CUDA 矩阵乘法成功。
