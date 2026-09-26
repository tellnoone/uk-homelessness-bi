"""The raw files are exactly the ones recorded in data/PROVENANCE.md."""

import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw" / "tsm-2025"


def _provenance_hashes() -> dict[str, str]:
    text = (ROOT / "data" / "PROVENANCE.md").read_text(encoding="utf-8")
    return dict(re.findall(r"\| `(TSM_2025_Full_Data[^`]+\.csv)` \| `([0-9a-f]{64})` \|", text))


def test_every_raw_file_is_recorded():
    recorded = _provenance_hashes()
    on_disk = {p.name for p in RAW.glob("*.csv")}
    assert len(recorded) == 8
    assert set(recorded) == on_disk


def test_raw_files_are_unchanged():
    for name, expected in _provenance_hashes().items():
        actual = hashlib.sha256((RAW / name).read_bytes()).hexdigest()
        assert actual == expected, f"{name} has changed since it was recorded"
