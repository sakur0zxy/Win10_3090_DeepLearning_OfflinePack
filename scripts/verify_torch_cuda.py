import re
import subprocess
import sys


def fail(message: str) -> None:
    print(f"[失败] {message}")
    sys.exit(1)


def ok(message: str) -> None:
    print(f"[OK] {message}")


def warn(message: str) -> None:
    print(f"[警告] {message}")


def parse_version(value: str):
    parts = re.findall(r"\d+", value or "")
    if not parts:
        return None
    major = int(parts[0])
    minor = int(parts[1]) if len(parts) > 1 else 0
    return major, minor


def parse_nvidia_smi():
    try:
        proc = subprocess.run(
            ["nvidia-smi"],
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError:
        fail("没有找到 nvidia-smi。请先安装 NVIDIA 驱动并重启。")

    if proc.returncode != 0:
        fail("nvidia-smi 执行失败。")

    output = proc.stdout
    driver = re.search(r"Driver Version:\s*([0-9.]+)", output)
    cuda = re.search(r"CUDA Version:\s*([0-9.]+)", output)
    return {
        "driver": driver.group(1) if driver else "",
        "driver_cuda": cuda.group(1) if cuda else "",
        "raw": output,
    }


def main() -> int:
    smi = parse_nvidia_smi()
    if smi["driver"]:
        ok(f"NVIDIA Driver Version: {smi['driver']}")
    else:
        warn("没有从 nvidia-smi 输出中解析到 Driver Version。")

    if smi["driver_cuda"]:
        ok(f"nvidia-smi CUDA Version: {smi['driver_cuda']}")
        print("说明：nvidia-smi 的 CUDA Version 表示驱动最高支持的 CUDA Runtime，不代表已安装 CUDA Toolkit。")
    else:
        warn("没有从 nvidia-smi 输出中解析到 CUDA Version。")

    try:
        import torch
    except Exception as exc:
        fail(f"导入 torch 失败：{exc}")

    ok(f"torch.__version__: {torch.__version__}")
    torch_cuda = torch.version.cuda
    if torch_cuda is None:
        fail("当前 PyTorch 不是 CUDA 版本，torch.version.cuda == None。请确认安装的是 cu128 wheel。")
    ok(f"torch.version.cuda: {torch_cuda}")

    if smi["driver_cuda"]:
        driver_cuda = parse_version(smi["driver_cuda"])
        torch_cuda_v = parse_version(torch_cuda)
        if driver_cuda and torch_cuda_v and driver_cuda < torch_cuda_v:
            fail(f"驱动最高支持 CUDA {smi['driver_cuda']}，低于 PyTorch CUDA Runtime {torch_cuda}。请升级 NVIDIA 驱动。")
        if driver_cuda and torch_cuda_v:
            ok("驱动 CUDA Runtime 支持范围满足 PyTorch。")

    if not torch.cuda.is_available():
        fail("torch.cuda.is_available() == False。")

    gpu_name = torch.cuda.get_device_name(0)
    ok(f"GPU: {gpu_name}")

    a = torch.randn(1024, 1024, device="cuda")
    b = torch.randn(1024, 1024, device="cuda")
    c = a @ b
    torch.cuda.synchronize()
    ok(f"CUDA 1024x1024 矩阵乘法成功，结果均值：{c.mean().item():.6f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
