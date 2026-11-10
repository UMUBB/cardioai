"""Check that the installed scaffold preserves the public domain contract."""

from __future__ import annotations

from itertools import combinations

import pytest

import cardioai
import cardioai_api
from cardioai.constants import LEADS, N_LEADS, SPLIT_FOLDS, SUPERCLASSES, n_samples, split_of_fold


def test_packages_are_importable() -> None:
    assert cardioai.__version__ == "0.1.0"
    assert cardioai_api.__name__ == "cardioai_api"


def test_lead_names_are_unique() -> None:
    assert len(LEADS) == len(set(LEADS)) == N_LEADS == 12


def test_superclass_order() -> None:
    assert SUPERCLASSES == ("NORM", "MI", "STTC", "CD", "HYP")


def test_official_folds_partition_the_dataset() -> None:
    assert set(SPLIT_FOLDS) == {"train", "val", "test"}
    fold_sets = [set(folds) for folds in SPLIT_FOLDS.values()]
    assert set.union(*fold_sets) == set(range(1, 11))
    for left, right in combinations(fold_sets, 2):
        assert left.isdisjoint(right)


@pytest.mark.parametrize(("sampling_rate", "expected"), [(100, 1000), (500, 5000)])
def test_sample_count(sampling_rate: int, expected: int) -> None:
    assert n_samples(sampling_rate) == expected


@pytest.mark.parametrize(
    ("fold", "expected"),
    [(fold, "train") for fold in range(1, 9)] + [(9, "val"), (10, "test")],
)
def test_fold_lookup(fold: int, expected: str) -> None:
    assert split_of_fold(fold) == expected


@pytest.mark.parametrize("fold", [-1, 0, 11])
def test_invalid_fold(fold: int) -> None:
    with pytest.raises(ValueError, match="Invalid strat_fold"):
        split_of_fold(fold)
