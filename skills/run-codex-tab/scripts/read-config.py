#!/usr/bin/env python3
"""Read the deliberately small, top-level YAML config used by spawn-codex-tab."""

from __future__ import annotations

import ast
import re
import shlex
import sys
from pathlib import Path
from typing import NoReturn


FIELDS = {
    "name": "NAME",
    "cwd": "CWD",
    "prompt_file": "PROMPT_FILE",
    "result_file": "RESULT_FILE",
    "task": "ROLE",
    "model": "MODEL",
    "effort": "EFFORT",
    "sandbox": "SANDBOX",
    "timeout": "TIMEOUT",
    "parent": "PARENT",
}


def fail(message: str) -> NoReturn:
    print(f"config error: {message}", file=sys.stderr)
    raise SystemExit(2)


def scalar(value: str, line: int) -> str:
    value = value.strip()
    if not value:
        fail(f"line {line}: a scalar value is required")

    if value in {"true", "True", "TRUE"}:
        return "true"
    if value in {"false", "False", "FALSE"}:
        return "false"

    if value[:1] in {"'", '"'}:
        try:
            parsed = ast.literal_eval(value)
        except (SyntaxError, ValueError) as exc:
            fail(f"line {line}: invalid quoted value ({exc})")
        if not isinstance(parsed, str):
            fail(f"line {line}: only string scalars are supported")
        return parsed

    # A comment is recognized only when it starts after whitespace, so paths
    # and names containing a literal '#' remain usable.
    value = re.split(r"\s+#", value, maxsplit=1)[0].rstrip()
    return value


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: read-config.py <config.yaml>")

    path = Path(sys.argv[1])
    try:
        content = path.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"cannot read config file {path}: {exc}")

    values: dict[str, str] = {}
    for line_number, raw in enumerate(content.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if raw[:1].isspace():
            fail(f"line {line_number}: nested YAML is not supported")
        if ":" not in line:
            fail(f"line {line_number}: expected key: value")

        key, raw_value = line.split(":", 1)
        key = key.strip()
        if key not in FIELDS and key != "no_wait":
            fail(f"line {line_number}: unknown key: {key}")
        if key in values:
            fail(f"line {line_number}: duplicate key: {key}")
        values[key] = scalar(raw_value, line_number)

    for required in ("task", "model", "effort"):
        if required not in values:
            fail(f"{required} is required")
    if values["task"] not in {"impl", "review", "consult"}:
        fail("task must be impl, review, or consult")

    for key, variable in FIELDS.items():
        if key in values:
            print(f"{variable}={shlex.quote(values[key])}")

    if "no_wait" in values:
        if values["no_wait"] not in {"true", "false"}:
            fail("no_wait must be true or false")
        print(f"WAIT_DONE={'0' if values['no_wait'] == 'true' else '1'}")


if __name__ == "__main__":
    main()
