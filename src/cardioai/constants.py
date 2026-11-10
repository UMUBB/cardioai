"""Shared domain constants for the PTB-XL data and inference contracts."""

from __future__ import annotations

from collections.abc import Mapping
from types import MappingProxyType
from typing import Final

DATASET_NAME: Final = "ptb-xl"
DATASET_VERSION: Final = "1.0.3"
LEADS: Final[tuple[str, ...]] = (
    "I",
    "II",
    "III",
    "aVR",
    "aVL",
    "aVF",
    "V1",
    "V2",
    "V3",
    "V4",
    "V5",
    "V6",
)
N_LEADS: Final = 12
SUPERCLASSES: Final[tuple[str, ...]] = ("NORM", "MI", "STTC", "CD", "HYP")
QUALITY_LABELS: Final[tuple[str, ...]] = (
    "static_noise",
    "burst_noise",
    "baseline_drift",
    "electrode_problem",
)
SAMPLING_RATES: Final[tuple[int, ...]] = (100, 500)
RECORD_SECONDS: Final = 10
SPLIT_FOLDS: Final[Mapping[str, tuple[int, ...]]] = MappingProxyType(
    {"train": (1, 2, 3, 4, 5, 6, 7, 8), "val": (9,), "test": (10,)}
)
QUALITY_STATUSES: Final = ("ACCEPT", "WARN", "REJECT")
RESPONSE_STATUSES: Final = ("OK", "ABSTAIN", "REJECTED")


def n_samples(sampling_rate: int) -> int:
    """Return the number of samples in a record at the given rate in Hz."""
    return sampling_rate * RECORD_SECONDS


def split_of_fold(fold: int) -> str:
    """Return the official split containing a stratification fold.

    Args:
        fold: PTB-XL strat_fold value in the inclusive range 1 to 10.

    Returns:
        The split name from SPLIT_FOLDS.

    Raises:
        ValueError: If the fold does not belong to an official split.
    """
    for split, folds in SPLIT_FOLDS.items():
        if fold in folds:
            return split
    raise ValueError(f"Invalid strat_fold {fold!r}: expected a fold from 1 to 10.")
