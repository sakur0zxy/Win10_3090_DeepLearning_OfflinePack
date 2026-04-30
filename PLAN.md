# Win10 + RTX 3090 Deep Learning Offline Environment Plan

## Goal

Build a reproducible, verifiable, maintainable offline deep learning package for a Windows 10 x64 + NVIDIA RTX 3090 machine.

Usage model:

```text
Online PC: download the offline package only.
Offline PC: check, install, and verify the environment.
```

Default stack:

- Python 3.11 x64
- PyTorch CUDA 12.8
- NVIDIA RTX 3090 driver installer
- Microsoft VC++ Runtime
- Offline Python wheels

## Supported Capabilities

Entry points:

```text
OfflineDL-Win10-3090.ps1
OfflineDL-Win10-3090.bat
```

Modes:

```powershell
-Mode Download
-Mode Check
-Mode RegisterLocalFiles
-Mode Install
-Mode Verify
-Mode Doctor
```

Parameters:

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

## Profiles

- `Minimal`: smallest runtime with basic scientific packages.
- `Research`: default research profile with Jupyter, scikit-learn, matplotlib, OpenCV, transformers, and related tools.
- `Full`: Research plus manual Git / CUDA Toolkit installer registration.
- `Visualization`: independent optional component with seaborn, plotly, ipywidgets, and mlflow.

`Full` does not automatically include Visualization.

## Directory Layout

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

## Workspace Layout

Install asks for a single workspace root. Recommended default:

```text
D:\AI
```

Derived layout:

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

## Core Principles

- Unified entry, isolated stages.
- Download never installs.
- Check is read-only and never modifies `manifest.json`.
- Install treats `manifest.json` as the source of truth.
- Verify treats `install_state.json` as the source of truth and never falls back to system Python.
- Package versions are pinned in lock files.
- `manifest.json` records file size and SHA256 for package integrity.
- Required component gaps, hash mismatches, wrong Python architecture, and wrong CUDA runtime fail fast.
- User-facing interactive text is simple Simplified Chinese.

## Download

Download:

1. Confirms that files will be saved to the current script folder.
2. Resolves Profile and optional components.
3. Checks disk space, filesystem, TLS, and network endpoints.
4. Downloads Python, VC++ Runtime, and Python wheels.
5. Requires a local or configured NVIDIA driver source.
6. Validates PyTorch wheel filenames contain `cu128`.
7. Generates `manifest.json`.
8. Runs internal validation and writes `packageStatus = complete` on success.

Git, CUDA Toolkit, and VS Code are manual installer registrations. They are not silently installed.

## Check

Check is read-only. It validates:

- manifest parseability.
- schemaVersion and phase compatibility.
- packageStatus is complete.
- lock file SHA256 values.
- all manifest files exist and match size/SHA256.
- required components for the selected Profile are present.
- optional installer records exist when optional components are selected.
- no source archives or zip packages are accepted.
- duplicate wheel names and package version conflicts are detected.

## RegisterLocalFiles

RegisterLocalFiles scans manual installer folders:

```text
downloads\drivers
downloads\cuda_optional
downloads\tools_optional
```

It asks for confirmation, then atomically updates `manifest.json`.

## Install

Install:

1. Runs Check first.
2. Checks NVIDIA GPU and `nvidia-smi`.
3. Checks Python 3.11 x64, pip, and venv.
4. Checks VC++ Runtime heuristically.
5. Creates or explicitly reuses the venv.
6. Combines `manifest.lockFiles` into `resolved-install.lock.txt`.
7. Installs with `--no-index --find-links`.
8. Runs `pip check`.
9. Confirms torch import and CUDA availability.
10. Writes `.offline_dl_ready` and `install_state.json`.
11. Runs Verify.

`-ReuseVenv` is opt-in. It checks venv Python, 64-bit architecture, pip, and existing torch CUDA state. CPU-only torch or CUDA mismatch fails and recommends `-RecreateVenv`.

## Verify

Verify:

- Reads `state\install_state.json`.
- Uses the recorded venvPython.
- Runs `pip check`.
- Runs `scripts\verify_torch_cuda.py`.
- Reports NVIDIA driver version, driver CUDA capability, PyTorch CUDA runtime, and GPU name.
- Runs a 1024x1024 CUDA matrix multiplication test.

## Completed

```text
Download / Check / Install / Verify
RegisterLocalFiles
Doctor
Minimal / Research / Full Profile
Visualization optional package set
Git / CUDA Toolkit / VS Code manual installer registration
ReuseVenv safe reuse path
README standard naming
GitHub push
```

## Future Enhancements

```text
complete dependency-tree locks
--require-hashes
more framework-specific profiles
stricter wheel tag compatibility parsing
```
