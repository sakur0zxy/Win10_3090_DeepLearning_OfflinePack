# 常见错误速查

| 错误 | 处理 |
| --- | --- |
| `manifest.json 不存在` | 先在联网电脑运行 `Download`。 |
| `packageStatus 不是 complete` | 离线包未完整下载或校验失败，重新运行 `Download`。 |
| `optionalComponents 必须为空数组` | 当前脚本是第一阶段版本，不支持第二阶段 manifest。 |
| `文件大小不一致` / `SHA256 不一致` | 文件可能损坏，重新拷贝整个离线包，必要时重新 Download。 |
| `没有检测到 Python 3.11 x64` | 手动运行 `downloads\python` 下的 Python 安装包，启用 pip 和 venv。 |
| `没有检测到 nvidia-smi` | 手动安装 NVIDIA 驱动并重启。 |
| `虚拟环境已存在` | 第一阶段不支持复用旧环境，需要确认删除并重建。 |
| `torch.version.cuda == None` | 安装到了 CPU 版 PyTorch，重新检查 PyTorch cu128 wheels。 |
