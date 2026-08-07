#!/usr/bin/env python3

from html.parser import HTMLParser
from ipaddress import ip_address
from pathlib import Path
import sys
from urllib.parse import urlparse


class BrowserAssetParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.urls: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attribute = "src" if tag == "script" else "href" if tag == "link" else None
        if attribute is None:
            return
        for name, value in attrs:
            if name == attribute and value is not None:
                self.urls.append(value)
                break


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: find-loopback-browser-asset.py <html-file>", file=sys.stderr)
        return 2

    try:
        html = Path(sys.argv[1]).read_text(errors="replace")
    except OSError as error:
        print(f"find-loopback-browser-asset: {error}", file=sys.stderr)
        return 1

    parser = BrowserAssetParser()
    parser.feed(html)
    for url in parser.urls:
        try:
            hostname = urlparse(url).hostname
        except ValueError:
            continue
        if hostname is None:
            continue
        normalized = hostname.rstrip(".").lower()
        if normalized == "localhost":
            print(url)
            return 0
        try:
            is_loopback = ip_address(normalized).is_loopback
        except ValueError:
            is_loopback = False
        if is_loopback:
            print(url)
            return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
