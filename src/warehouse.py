"""Build the DuckDB warehouse by running the SQL layers in order."""

from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
SQL_DIR = ROOT / "sql"
DB_PATH = ROOT / "warehouse" / "tsm.duckdb"


def build(db_path: Path = DB_PATH) -> duckdb.DuckDBPyConnection:
    """Rebuild the warehouse from data/raw and return an open connection.

    The database file is deleted first, so every run starts from the raw
    files and nothing from a previous run can leak into the result.
    """
    db_path.parent.mkdir(parents=True, exist_ok=True)
    db_path.unlink(missing_ok=True)
    con = duckdb.connect(str(db_path))
    # The SQL reads data/raw/... with relative paths.
    con.execute(f"SET file_search_path = '{ROOT.as_posix()}'")
    for sql_file in sorted(SQL_DIR.glob("*.sql")):
        print(f"  running {sql_file.name}")
        con.execute(sql_file.read_text(encoding="utf-8"))
    return con
