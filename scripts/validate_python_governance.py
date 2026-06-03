#!/usr/bin/env python3
"""Python quality/governance gate for public furniture-ops scripts.

AWF-190 goals:
- Compile every Python script so syntax/runtime-import drift is caught in CI.
- Apply a small lint pass for obvious whitespace hazards.
- Enforce that scripts mutating core CRM/business tables also reference
  agent_action_log, unless they carry an explicit governance exemption.

This intentionally avoids requiring a heavyweight linter/typechecker in the
public portfolio repo. If ruff is installed locally, this script will run it;
CI remains deterministic without it.
"""
from __future__ import annotations

import ast
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = ROOT / "scripts"

MUTATION_RE = re.compile(
    r"\b(INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.("
    r"contacts|contact_roles|conversation_threads|conversation_messages|"
    r"listings|listing_price_history|inventory|pickups_deliveries|cash_flows"
    r")\b",
    re.IGNORECASE,
)
EXEMPTION_RE = re.compile(r"governance:\s*agent_action_log-not-required\b", re.IGNORECASE)


def python_files() -> list[Path]:
    return sorted(SCRIPT_DIR.glob("*.py"))


def fail(msg: str) -> None:
    print(f"python governance gate failed: {msg}", file=sys.stderr)
    raise SystemExit(1)


def compile_and_parse(paths: list[Path]) -> None:
    for path in paths:
        text = path.read_text()
        try:
            ast.parse(text, filename=str(path))
            compile(text, str(path), "exec")
        except SyntaxError as exc:
            fail(f"{path.relative_to(ROOT)} syntax error: {exc}")


def whitespace_lint(paths: list[Path]) -> None:
    for path in paths:
        for lineno, line in enumerate(path.read_text().splitlines(), start=1):
            if line.rstrip() != line:
                fail(f"{path.relative_to(ROOT)}:{lineno} trailing whitespace")
            if "\t" in line:
                fail(f"{path.relative_to(ROOT)}:{lineno} tab character")


def governance_lint(paths: list[Path]) -> None:
    for path in paths:
        text = path.read_text()
        mutates_core_tables = bool(MUTATION_RE.search(text))
        has_audit_reference = "agent_action_log" in text
        exempt = bool(EXEMPTION_RE.search(text))
        if mutates_core_tables and not (has_audit_reference or exempt):
            fail(
                f"{path.relative_to(ROOT)} mutates core CRM/business tables "
                "but does not reference agent_action_log or an explicit governance exemption"
            )


def optional_ruff(paths: list[Path]) -> None:
    ruff = shutil.which("ruff")
    if not ruff:
        print("python governance gate: ruff not installed; skipped optional ruff lint")
        return
    proc = subprocess.run([ruff, "check", *map(str, paths)], cwd=ROOT, text=True)
    if proc.returncode != 0:
        raise SystemExit(proc.returncode)


def main() -> int:
    paths = python_files()
    if not paths:
        fail("no Python files found under scripts/")
    compile_and_parse(paths)
    whitespace_lint(paths)
    governance_lint(paths)
    optional_ruff(paths)
    print(f"python governance gate: ok ({len(paths)} scripts checked)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
