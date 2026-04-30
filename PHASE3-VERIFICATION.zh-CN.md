# Phase 3 Verification

本阶段目标：完成剩余计划项，让脚本支持多档位、可视化可选包、手动工具安装包登记，以及安全复用虚拟环境。

## 已实现

- `-Profile Minimal / Research / Full`
- `-IncludeVisualization`
- `-IncludeGit`
- `-IncludeCudaToolkit`
- `-IncludeVSCode`
- `-ReuseVenv`
- `requirements\minimal.lock.txt`
- `requirements\visualization.lock.txt`
- Install 根据 `manifest.lockFiles` 生成 `resolved-install.lock.txt`
- Download 根据 Profile / optional components 写入 manifest
- README 与中英文计划更新为当前能力

## 验证

- PowerShell parser：通过
- `config.json` JSON 解析：通过
- `scripts\verify_torch_cuda.py` 编译：通过
- `.bat -Mode Doctor`：通过
- `-Mode Check` 缺少 manifest 时按预期失败：通过
- `-Mode Download -Profile Minimal` 能识别档位，并在缺少 NVIDIA 驱动时提前停止：通过
- `-Mode Download -IncludeVisualization` 能识别可选组件，并在缺少 NVIDIA 驱动时提前停止：通过
- `-Mode Check -IncludeVisualization` 参数范围校验：通过
- `-Mode Install -ReuseVenv -RecreateVenv` 冲突校验：通过
- PyTorch cu128 版本索引检查：通过
- Minimal / Research / Visualization 组合依赖 dry-run：通过
- 带 `torch-cu128.lock.txt` 的完整组合 dry-run：通过，解析结果包含 `torch-2.11.0+cu128`、`torchvision-0.26.0+cu128`、`torchaudio-2.11.0+cu128`

## 未实际执行

- 未运行完整 Download，因为当前目录没有 NVIDIA 驱动 exe，脚本按设计停止。
- 未运行完整 Install / Verify，因为当前电脑不是目标 Win10 + RTX 3090 离线机，且没有 Python 3.11 x64 目标环境。
