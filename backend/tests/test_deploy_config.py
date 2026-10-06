"""Vercel installs from pyproject.toml, local runs from requirements.txt: keep them in step."""

import re
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Needed locally (test runner, dev server) but not inside the Vercel function.
DEV_ONLY = {"pytest", "uvicorn"}


def _name(requirement: str) -> str:
    return re.split(r"[\[=<>~! ]", requirement, maxsplit=1)[0].lower()


def test_pyproject_lists_every_runtime_requirement_with_the_same_pin():
    pyproject = tomllib.loads((ROOT / "pyproject.toml").read_text())
    deployed = set(pyproject["project"]["dependencies"])
    local = {
        line.strip()
        for line in (ROOT / "requirements.txt").read_text().splitlines()
        if line.strip() and not line.startswith("#")
    }
    runtime = {r for r in local if _name(r) not in DEV_ONLY}
    assert deployed == runtime
