#!/usr/bin/env python3
"""Embed the pinned KaTeX WOFF2 fonts without changing @font-face boundaries.

Usage: npm pack katex@0.19.1 && python3 scripts/vendor_katex.py katex-0.19.1.tgz
"""

import argparse
import base64
import hashlib
from pathlib import Path
import re
import tarfile


ARCHIVE_SHA256 = "24da5a599eb2fcede2e270b99a6ff48bca816beecc95feeb84e8cccbd1bb34fd"
RESOURCES = Path(__file__).resolve().parents[1] / "Project/Sources/Neon Vision Editor/Resources/KaTeX"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    if hashlib.sha256(args.archive.read_bytes()).hexdigest() != ARCHIVE_SHA256:
        raise SystemExit("Expected the unmodified katex@0.19.1 npm archive")

    with tarfile.open(args.archive) as archive:
        css = archive.extractfile("package/dist/katex.min.css").read().decode("utf-8")
        faces = re.findall(r"@font-face\{[^}]*\}", css)
        if len(faces) != 20:
            raise SystemExit("Expected 20 upstream font-face rules")

        def embed(face):
            block = face.group()
            font = re.search(r'url\((fonts/[^)]+\.woff2)\) format\("woff2"\)', block)
            if font is None:
                raise SystemExit("Missing upstream WOFF2 source")
            data = archive.extractfile("package/dist/" + font[1]).read()
            encoded = base64.b64encode(data).decode("ascii")
            # A final CSS declaration may end at }, without a trailing semicolon.
            return re.sub(r"src:[^;}]+", lambda _: 'src:url(data:font/woff2;base64,' + encoded + ') format("woff2")', block)

        embedded = re.sub(r"@font-face\{[^}]*\}", embed, css)

    rules = re.findall(r"@font-face\{[^}]*\}", embedded)
    if len(rules) != 20 or any(rule.count("font-family:") != 1 or rule.count("src:") != 1 for rule in rules):
        raise SystemExit("Embedding changed font-face boundaries")
    if "url(fonts/" in embedded:
        raise SystemExit("An external font source remains")
    (RESOURCES / "katex.min.css").write_text(embedded, encoding="utf-8")
    print("Embedded 20 independent KaTeX font faces")


if __name__ == "__main__":
    main()
