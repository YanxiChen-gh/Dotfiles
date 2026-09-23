#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
exec python3 - "$ROOT" <<'PY'
import importlib.util
import io
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("prompt_input", Path(sys.argv[1]) / "herdr/prompt-input.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

for cancel in (b"\x03", b"\x1b[99;5u", b"\x1b[99;5:1u", b"\x1b[27;5;99~"):
    reader, writer = os.pipe()
    try:
        os.write(writer, b"an unfinished problem" + cancel + b"\x13")
        os.close(writer)
        text, status = module.collect_prompt(reader, io.StringIO())
        assert (text, status) == ("", 130), f"Cancel {cancel!r} submitted problem data: {(text, status)!r}"
    finally:
        os.close(reader)
print("PASS: prompt cancellation discards input under legacy and negotiated keyboard protocols")
PY
