"""Backup, restore and restore rehearsal for the OmniAssist database (Task 40).

    python infra/scripts/backup_restore.py backup   --url URL --out omni.dump
    python infra/scripts/backup_restore.py restore  --url URL --file omni.dump
    python infra/scripts/backup_restore.py rehearse --url URL

`rehearse` dumps the database, restores it into a scratch database next to it, checks
that every table has the same row count and the same migration version, then drops the
scratch database. Run it after schema changes and at least quarterly (Spec 10.5).

Needs pg_dump, pg_restore and psql on PATH, or their folder in PG_BIN. URLs look like
postgresql://user:password@host:port/dbname; the user must be able to create databases
for `rehearse`. Passwords go through PGPASSWORD, never the command line.
"""

import argparse
import os
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit


def tool(name: str) -> str:
    folder = os.environ.get("PG_BIN")
    return str(Path(folder) / name) if folder else name


def conn(url: str) -> tuple[list[str], dict[str, str]]:
    """Connection flags plus an environment carrying the password."""
    u = urlsplit(url)
    flags = ["-h", u.hostname or "localhost", "-p", str(u.port or 5432),
             "-U", u.username or "postgres", "-d", u.path.lstrip("/")]  # fmt: skip
    env = {**os.environ, "PGPASSWORD": u.password or ""}
    return flags, env


def run(cmd: list[str], env: dict[str, str]) -> str:
    out = subprocess.run(cmd, env=env, check=True, capture_output=True, text=True)
    return out.stdout


def backup(url: str, out: str) -> None:
    flags, env = conn(url)
    run([tool("pg_dump"), *flags, "-Fc", "--no-owner", "-f", out], env)


def restore(url: str, file: str) -> None:
    flags, env = conn(url)
    run([tool("pg_restore"), *flags, "--clean", "--if-exists", "--no-owner",
         "--exit-on-error", file], env)  # fmt: skip


def counts(url: str) -> dict[str, int]:
    flags, env = conn(url)
    tables = run([tool("psql"), *flags, "-At", "-c",
                  "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY 1"],
                 env).split()  # fmt: skip
    result = {}
    for t in tables:
        n = run([tool("psql"), *flags, "-At", "-c", f'SELECT count(*) FROM "{t}"'], env)
        result[t] = int(n.strip())
    return result


def version(url: str) -> str:
    flags, env = conn(url)
    return run([tool("psql"), *flags, "-At", "-c",
                "SELECT version_num FROM alembic_version"], env).strip()  # fmt: skip


def rehearse(url: str) -> bool:
    u = urlsplit(url)
    scratch = f"omni_restore_check_{uuid.uuid4().hex[:8]}"
    admin = urlunsplit(u._replace(path="/postgres"))
    target = urlunsplit(u._replace(path=f"/{scratch}"))
    flags, env = conn(admin)
    with tempfile.TemporaryDirectory() as tmp:
        dump = str(Path(tmp) / "omni.dump")
        backup(url, dump)
        run([tool("psql"), *flags, "-c", f'CREATE DATABASE "{scratch}"'], env)
        try:
            restore(target, dump)
            src, dst = counts(url), counts(target)
            same = src == dst and version(url) == version(target)
            for t in sorted(src):
                mark = "ok" if src[t] == dst.get(t) else "MISMATCH"
                print(f"{t:28} {src[t]:>8} {dst.get(t, '-'):>8}  {mark}")
            print(f"migration version {version(url)} -> {version(target)}")
            print("REHEARSAL PASSED" if same else "REHEARSAL FAILED")
            return same
        finally:
            run([tool("psql"), *flags, "-c", f'DROP DATABASE IF EXISTS "{scratch}"'], env)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("backup")
    b.add_argument("--url", required=True)
    b.add_argument("--out", required=True)
    r = sub.add_parser("restore")
    r.add_argument("--url", required=True)
    r.add_argument("--file", required=True)
    h = sub.add_parser("rehearse")
    h.add_argument("--url", required=True)
    a = p.parse_args()
    if a.cmd == "backup":
        backup(a.url, a.out)
    elif a.cmd == "restore":
        restore(a.url, a.file)
    else:
        return 0 if rehearse(a.url) else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
