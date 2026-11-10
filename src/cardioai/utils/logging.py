"""Standard logging entry points shared by scripts and library modules."""

from __future__ import annotations

import logging
import os


def get_logger(name: str) -> logging.Logger:
    """Return a named logger without configuring handlers or emitting output."""
    return logging.getLogger(name)


def setup_logging(level: str | None = None) -> None:
    """Configure console logging once at an application entry point.

    Args:
        level: Logging level name; defaults to CARDIOAI_LOG_LEVEL or INFO.

    Raises:
        ValueError: If the selected logging level name is invalid.
    """
    resolved_level = level if level is not None else os.environ.get("CARDIOAI_LOG_LEVEL", "INFO")
    logging.basicConfig(
        level=resolved_level.upper(),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
