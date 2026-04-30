# 第一阶段执行计划：Win10 + RTX 3090 深度学习离线环境工具

## 1. 执行目标

把当前总设计落地成第一版可运行工具，先跑通最小闭环：

```text
联网机 Download -> Check -> 拷贝整个目录 -> 离线机 Check -> Install -> Verify
```

第一阶段只支持：

```text
Download / Check / Install / Verify
固定 Research
Python 3.11 x64
PyTorch CUDA 12.8
干净 venv 安装
```

第一阶段不支持：

```text
-Profile
-ReuseVenv
Git / CUDA Toolkit / Visualization
RegisterLocalFiles
Doctor 独立模式
```

## 2. 交付物

```text
OfflineDL-Win10-3090.ps1
OfflineDL-Win10-3090.bat
config.json
manifest.json
requirements\torch-cu128.lock.txt
requirements\research.lock.txt
scripts\verify_torch_cuda.py
README.md
docs\troubleshooting.md
docs\common-errors.md
```

## 3. Wave 1：脚手架、参数、路径、日志

目标：先搭出可靠命令入口和基础工具函数，后续模式都复用。

任务：

1. 创建 `OfflineDL-Win10-3090.ps1` 参数入口。
2. 只接受 `-Mode Download|Check|Install|Verify`。
3. 对 `-Profile`、`-ReuseVenv`、`-IncludeGit`、`-IncludeCudaToolkit`、`-IncludeVisualization` 返回“第二阶段暂不可用”。
4. 创建 `OfflineDL-Win10-3090.bat`，负责进入脚本目录并调用 PowerShell。
5. 实现中文菜单。
6. 实现 `Join-Path` / `-LiteralPath` 路径封装。
7. 实现 `Start-Transcript` 日志和退出码。
8. 实现磁盘可写、FAT32、剩余空间检查。

验收：

```text
无参数运行显示中文菜单
-Mode Check 可进入 Check 流程
第二阶段参数会明确拒绝，不静默忽略
logs 目录产生带时间戳日志
路径中有空格时不会拼接命令字符串
```

## 4. Wave 2：配置、manifest、SHA256、原子写入

目标：先完成所有模式共用的数据层。

任务：

1. 创建 `config.json`。
2. 创建 `requirements\torch-cu128.lock.txt`。
3. 创建 `requirements\research.lock.txt`。
4. 实现 SHA256 计算。
5. 实现 JSON 读取、写入、校验。
6. 实现 manifest 原子写入：写 tmp、重读校验、备份旧文件、替换正式文件。
7. manifest 顶层固定 `schemaVersion: 1`、`phase: 1`、`optionalComponents: []`。
8. `manifest.files` 支持 `component/group/kind/required/profile/path/fileName/size/sha256/sourceUrl/source/downloadedAt`。
9. `manifest.downloadCommands` 记录 pip download 摘要。

验收：

```text
能生成合法 manifest.json
manifest 写坏时不覆盖旧 manifest
manifest.files 能记录 installer / wheel / lock / script / doc
Check / Install 能拒绝 phase != 1 或 optionalComponents 非空的 manifest
```

## 5. Wave 3：Check 模式

目标：先让只读校验可靠，后续 Download 和 Install 都依赖它。

任务：

1. 实现 `Test-OfflinePackage`，只返回结果对象，不写文件。
2. 实现 `Invoke-CheckMode`，只输出结果，不改 manifest。
3. 校验 manifest 可解析。
4. 校验 `schemaVersion == 1`、`phase == 1`、`optionalComponents == []`。
5. 校验 `packageStatus == complete`。
6. 校验 lock 文件 SHA256。
7. 校验固定 Research 必需组件都在 `manifest.files`。
8. 校验 `manifest.files` 文件存在、大小、SHA256。
9. 拒绝 `.tar.gz`、`.zip` 源码包。
10. 扫描重复 wheel、多版本 wheel。
11. 输出中文 OK / FAIL 报告。

验收：

```text
Check 不修改任何文件
缺 Python installer / VC++ / torch wheel 会失败
manifest 记录文件哈希错误会失败
optionalComponents 非空会失败
重复 wheel 同名不同 SHA256 会失败
```

## 6. Wave 4：Verify 模式

目标：独立验证安装结果，先不依赖 Download。

任务：

1. 创建 `scripts\verify_torch_cuda.py`。
2. Verify 优先读取 `<WorkspaceRoot>\state\install_state.json`。
3. 使用 `venvPython`，不回退系统 Python。
4. 检查 `.offline_dl_ready`，缺失时警告但继续。
5. 运行 `pip check`。
6. 调用 `nvidia-smi` 输出 Driver Version 和 CUDA Version。
7. 输出 `torch.__version__`、`torch.version.cuda`、GPU 名称。
8. `torch.version.cuda == None` 时失败。
9. 数值比较 driver CUDA 和 torch CUDA，不做字符串比较。
10. 执行 1024 x 1024 CUDA 矩阵乘法。
11. 对比 `sourceManifestHash`，不一致时警告。

验收：

```text
系统 Python 未安装 torch 时不会被误用
CPU 版 PyTorch 会失败
driver CUDA 高于 torch CUDA 不报警
driver CUDA 低于 torch CUDA 会失败
1024 矩阵乘法成功时输出明确通过
```

## 7. Wave 5：Install 模式

目标：在离线机上创建干净工作区和 venv，离线安装 wheels。

任务：

1. 读取 manifest。
2. 先运行 Check。
3. 要求用户输入或确认 `WorkspaceRoot`，建议 `D:\AI`。
4. 检查工作区盘空间、文件系统、可写性。
5. 检查 `nvidia-smi`，缺失时提示手动安装驱动并重启。
6. 检查 GPU 名称：RTX 3090 继续，非 3090 交互确认，`-NonInteractive` 失败。
7. 检查 Python 3.11 x64、`python -m pip --version`、`python -m venv --help`。
8. 检查 VC++ Runtime，缺失时提示手动安装。
9. 只支持干净 venv：已有 venv 必须 DELETE 后重建。
10. 删除前验证 `VenvPath == <WorkspaceRoot>\envs\dl-py311-cu128`。
11. 删除前验证目录名或 `.offline_dl_installing/.offline_dl_ready` 标记。
12. 创建 venv 后写 `.offline_dl_installing`。
13. 生成 `resolved-install.lock.txt`，包含 `torch-cu128.lock.txt` 和 `research.lock.txt`。
14. 使用所有 wheels 目录执行 `python -m pip install --no-index --find-links ...`。
15. 运行 `pip check`。
16. 运行基础 Verify：torch import + CUDA available。
17. 写 `.offline_dl_ready`。
18. 写 `install_state.json`，失败时只写 `install_state.failed.json`。
19. 生成 `activate-dl.ps1` 和 `activate-dl.bat`。
20. 自动运行完整 Verify。

验收：

```text
已有 venv 不会被复用
没有 DELETE 不会删除 venv
路径不在 WorkspaceRoot 内拒绝删除
pip install 失败不会写 install_state.json
安装成功后存在 .offline_dl_ready
install_state.json 包含 sourceManifestHash 和 resolvedLockSha256
```

## 8. Wave 6：Download 模式

目标：联网机下载第一阶段离线包，生成可校验 manifest。

任务：

1. 启动前提示下载到脚本所在目录，要求输入 `y`。
2. 输出当前下载用 Python、pip、目标平台 `win_amd64 / cp311`。
3. 检查离线包所在盘可写、非 FAT32、空间足够。
4. 检查 HTTPS / TLS / PyPI / PyTorch 源。
5. 处理 `.part` 文件。
6. 下载 Python 3.11 x64 installer。
7. 下载 VC++ Runtime installer。
8. 下载 NVIDIA Studio Driver installer，或在 config 中保留固定 URL/手动放置说明。
9. 使用 PyTorch cu128 源下载 `torch-cu128.lock.txt`。
10. 使用 PyPI 下载 `research.lock.txt`。
11. 每个下载先写 `.part`，校验后改名。
12. PyTorch 核心 wheel 文件名小写后必须包含 `cu128`。
13. 计算并记录所有文件 SHA256。
14. 写 manifest，`packageStatus` 从 incomplete 到 complete。
15. 自动调用 `Test-OfflinePackage`，由 Download 自己写最终 status。

验收：

```text
下载中断不会留下假完成文件
cu128 检查能阻止 CPU wheel
manifest.files 覆盖必需组件
manifest.downloadCommands 记录下载摘要
Download 完成后 Check 通过
Download 不会尝试安装任何东西
```

## 9. Wave 7：README、排错文档、最终验收

目标：让小白能照文档完成联网机和离线机流程。

任务：

1. 编写 `README.md`。
2. 写清 PowerShell 执行策略绕过方式。
3. 写清联网机推荐流程。
4. 写清离线机推荐流程。
5. 写清必须拷贝整个离线包目录。
6. 写清 NVIDIA 驱动、Python、VC++ Runtime 需要手动安装。
7. 写清工作区路径不建议带空格。
8. 写清 logs 可手动清理，manifest / requirements / wheels / downloads 不要删。
9. 创建 `docs\troubleshooting.md`。
10. 创建 `docs\common-errors.md`。

验收：

```text
README 能指导用户完成 Download -> Check -> 拷贝 -> Check -> Install -> Verify
常见错误有对应处理：nvidia-smi not found、DLL load failed、No matching distribution found、pip check failed、PowerShell 禁止脚本
文档没有暗示脚本会自动安装驱动 / Python / VC++
```

## 10. 最终验收

必须通过：

```text
联网机：
  .\OfflineDL-Win10-3090.ps1 -Mode Download
  .\OfflineDL-Win10-3090.ps1 -Mode Check

离线机：
  .\OfflineDL-Win10-3090.ps1 -Mode Check
  .\OfflineDL-Win10-3090.ps1 -Mode Install
  .\OfflineDL-Win10-3090.ps1 -Mode Verify
```

成功标准：

```text
Check 只读
Install 只写工作区 state，不改 manifest
Verify 使用 venvPython
torch.cuda.is_available() == True
GPU 名称为 RTX 3090 或用户已确认继续
CUDA 1024 x 1024 矩阵乘法成功
日志记录关键命令、退出码、失败摘要
```

## 11. 执行顺序建议

```text
Wave 1 -> Wave 2 -> Wave 3 -> Wave 4 -> Wave 5 -> Wave 6 -> Wave 7
```

原因：

```text
Check 和 manifest 是 Download / Install 的共同基础。
Verify 可先独立开发，降低 Install 调试难度。
Download 依赖 manifest / SHA256 / Check，最后写最稳。
```
