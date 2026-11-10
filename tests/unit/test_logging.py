"""Exercise logging from a fresh application entry point without test handlers."""

from __future__ import annotations

import os
import subprocess
import sys

import pytest


@pytest.mark.parametrize(
    ("env_level", "argument", "debug_visible", "info_visible"),
    [(None, None, False, True), ("debug", None, True, True), ("DEBUG", "WARNING", False, False)],
)
def test_console_logging_levels(
    env_level: str | None,
    argument: str | None,
    debug_visible: bool,
    info_visible: bool,
) -> None:
    env = os.environ.copy()
    env.pop("CARDIOAI_LOG_LEVEL", None)
    if env_level is not None:
        env["CARDIOAI_LOG_LEVEL"] = env_level
    result = subprocess.run(
        [
            sys.executable,
            "-c",
            "from cardioai.utils.logging import get_logger, setup_logging\n"
            f"setup_logging({argument!r})\n"
            "logger = get_logger('cardioai.smoke')\n"
            "logger.debug('debug-message')\n"
            "logger.info('info-message')\n"
            "logger.warning('warning-message')\n",
        ],
        env=env,
        capture_output=True,
        text=True,
        check=True,
    )
    assert result.stdout == ""
    assert ("DEBUG cardioai.smoke: debug-message" in result.stderr) == debug_visible
    assert ("INFO cardioai.smoke: info-message" in result.stderr) == info_visible
    assert result.stderr.count("WARNING cardioai.smoke: warning-message") == 1
