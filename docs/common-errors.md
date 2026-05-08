# 常见错误速查

| 错误 | 处理 |
| --- | --- |
| `manifest.json 不存在` | 先在联网电脑运行 `Download`。 |
| `packageStatus 不是 complete` | 离线包未完整下载或校验失败，重新运行 `Download`。 |
| `optionalComponents 必须为空数组` | 这是旧版 phase 1 manifest 限制。请确认当前脚本版本是 0.3.0 或更新。 |
| `文件大小不一致` / `SHA256 不一致` | 文件可能损坏，重新拷贝整个离线包，必要时重新 Download。 |
| `没有检测到 Python 3.11 x64` | 手动运行 `downloads\python` 下的 Python 安装包，启用 pip 和 venv。官方下载页：https://www.python.org/downloads/release/python-3119/ |
| `没有检测到 nvidia-smi` | 手动安装 NVIDIA 驱动并重启。官方下载页：https://www.nvidia.com/Download/index.aspx |
| `虚拟环境已存在` | 默认会要求删除并重建；如果确认要复用，请使用 `-ReuseVenv`，脚本会先检查 Python / pip / PyTorch CUDA。 |
| `torch.version.cuda == None` | 安装到了 CPU 版 PyTorch，重新检查 PyTorch cu128 wheels。 |
| `没有发现可登记的本地文件` | 先把 NVIDIA 驱动放到 `downloads\drivers`，或把 CUDA/Git/VS Code 安装包放入对应 optional 目录。脚本会显示官方下载页面。 |
| `CUDA Toolkit 文件体积偏小` | 很可能是 network installer，不适合离线电脑；请从 https://developer.nvidia.com/cuda-toolkit-archive 下载 local installer。 |
