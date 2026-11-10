"""Check installed native dependencies and binary availability for target platforms."""

from __future__ import annotations

import importlib
import importlib.util
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest


@pytest.mark.slow
@pytest.mark.parametrize(
    "module",
    [
        "numpy",
        "pandas",
        "pyarrow",
        "scipy",
        "sklearn",
        "wfdb",
        "yaml",
        "pydantic",
        "matplotlib",
        "dotenv",
        "torch",
        "fastapi",
        "uvicorn",
        "python_multipart",
        "pydantic_settings",
        "captum",
        "onnx",
        "onnxruntime",
        "lightgbm",
        "mlflow",
    ],
)
def test_installed_dependency_loads(module: str, monkeypatch: pytest.MonkeyPatch) -> None:
    """Detect missing shared libraries that a successful package install can hide."""
    if importlib.util.find_spec(module) is None:
        if module in {
            "numpy",
            "pandas",
            "pyarrow",
            "scipy",
            "sklearn",
            "wfdb",
            "yaml",
            "pydantic",
            "matplotlib",
            "dotenv",
        }:
            pytest.fail(f"Required base dependency {module} is not installed")
        pytest.skip(f"Optional dependency {module} is not installed in this environment")
    monkeypatch.setenv("MLFLOW_DISABLE_AGENT_HINT", "1")
    importlib.import_module(module)


@pytest.mark.parametrize(
    ("target", "extra"),
    [
        ("aarch64-apple-darwin", "cpu"),
        ("x86_64-unknown-linux-gnu", "cpu"),
        ("aarch64-unknown-linux-gnu", "cpu"),
        ("x86_64-pc-windows-msvc", "cpu"),
        ("x86_64-pc-windows-msvc", "cuda"),
        ("x86_64-unknown-linux-gnu", "cuda"),
    ],
)
def test_locked_dependencies_have_target_wheels(target: str, extra: str, tmp_path: Path) -> None:
    """Validate the lockfile offline without downloading or cross-building packages."""
    uv = shutil.which("uv")
    if uv is None:
        pytest.skip("uv is required to validate the platform lockfile")
    root = Path(__file__).resolve().parents[2]
    result = subprocess.run(
        [
            uv,
            "sync",
            "--locked",
            "--offline",
            "--dry-run",
            "--no-build",
            "--no-install-project",
            "--python",
            sys.executable,
            "--python-platform",
            target,
            "--extra",
            extra,
            "--extra",
            "all",
        ],
        cwd=root,
        env={
            **os.environ,
            "UV_CACHE_DIR": str(tmp_path / "cache"),
            "UV_PROJECT_ENVIRONMENT": str(tmp_path / "venv"),
            "MACOSX_DEPLOYMENT_TARGET": "14.0",
        },
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
