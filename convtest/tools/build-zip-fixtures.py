#!/usr/bin/env python3
"""ZIP fixtures: mixed.zip (nested folders, supported + unsupported +
junk + a nested archive), zipslip.zip (path-escape entry that must be
rejected), toomany.zip (over the entry cap).
Usage: build-zip-fixtures.py <samples-dir>
"""
import io, sys, zipfile
from pathlib import Path

OUT = Path(sys.argv[1])

# ---- mixed.zip ----
with zipfile.ZipFile(OUT / "mixed.zip", "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("docs/note.txt", "A note inside the archive.\nSecond line.\n")
    z.writestr("docs/report.html", "<h1>Zipped Report</h1><p>It has <b>bold</b> text.</p>")
    z.writestr("data/budget.csv", "item,cost\npen,2\nbook,12\n")
    z.writestr("image.png", b"\x89PNG\r\n\x1a\nnot really pixels")   # unsupported
    inner = io.BytesIO()
    with zipfile.ZipFile(inner, "w") as nested:
        nested.writestr("inner.txt", "should never be read")
    z.writestr("nested.zip", inner.getvalue())                        # nested archive
    z.writestr("__MACOSX/docs/._note.txt", b"resource fork junk")     # junk
    z.writestr(".DS_Store", b"finder junk")                           # junk
    z.writestr("docs/.hidden.txt", "hidden, must be ignored")         # hidden
print("wrote mixed.zip")

# ---- zipslip.zip ----
with zipfile.ZipFile(OUT / "zipslip.zip", "w") as z:
    z.writestr("ok.txt", "fine")
    z.writestr("../evil.txt", "escaped the extraction dir")
print("wrote zipslip.zip")

# ---- toomany.zip (1001 entries, tiny) ----
with zipfile.ZipFile(OUT / "toomany.zip", "w") as z:
    for i in range(1001):
        z.writestr(f"n/{i}.txt", "x")
print("wrote toomany.zip")
