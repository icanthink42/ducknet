#!/usr/bin/env python3
"""Build a single-file DuckNet installer for a GitHub release."""

from pathlib import Path
import json
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "install.lua"
OUTPUT = ROOT / "dist" / "ducknet-installer.lua"


def lua_long_string(value: str) -> str:
    equals = ""
    while f"]{equals}]" in value:
        equals += "="
    return f"[{equals}[{value}]{equals}]"


def main() -> None:
    version = sys.argv[1] if len(sys.argv) > 1 else "development"
    source = INSTALLER.read_text(encoding="utf-8")
    paths = sorted({
        path for path in re.findall(r'{\s*"([^"\n]+\.lua)"\s*,', source)
        if not path.startswith("/")
    })
    if not paths:
        raise SystemExit("installer manifest contains no Lua files")

    entries = []
    for relative in paths:
        path = ROOT / relative
        if not path.is_file():
            raise SystemExit(f"manifest file does not exist: {relative}")
        entries.append(f"  [{json.dumps(relative)}] = {lua_long_string(path.read_text(encoding='utf-8'))},")

    bundle = "local BUNDLED_FILES = {\n" + "\n".join(entries) + "\n}"
    source = source.replace("local BUNDLED_FILES = nil", bundle, 1)
    source = source.replace(
        "local BUNDLED_VERSION = nil",
        f"local BUNDLED_VERSION = {json.dumps(version)}",
        1,
    )
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(source, encoding="utf-8")
    print(f"built {OUTPUT.relative_to(ROOT)} with {len(paths)} files for {version}")


if __name__ == "__main__":
    main()
