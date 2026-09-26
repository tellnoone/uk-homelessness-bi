import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from src import warehouse  # noqa: E402


@pytest.fixture(scope="session")
def con(tmp_path_factory):
    """A fresh warehouse built from data/raw, separate from the one run_all.py writes."""
    db = tmp_path_factory.mktemp("warehouse") / "test.duckdb"
    connection = warehouse.build(db)
    yield connection
    connection.close()


@pytest.fixture
def scratch_con(tmp_path):
    """A throwaway warehouse for tests that corrupt data on purpose."""
    connection = warehouse.build(tmp_path / "scratch.duckdb")
    yield connection
    connection.close()
