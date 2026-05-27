#!/usr/bin/env python3
"""Read wealthtrack.nginx from repo dir, strip SSL server block,
and output an HTTP-only config suitable for initial deploy (pre-certbot).

Usage: python3 deploy/strip_ssl.py < deploy/wealthtrack.nginx
"""

import sys
import re

def extract_location_content(block, name):
    """Extract content INSIDE a location block by name, returns lines without the wrapper."""
    start = block.find(f'location {name} {{')
    if start == -1:
        return None

    brace_start = block.index('{', start) + 1
    depth = 1
    i = brace_start
    while depth > 0 and i < len(block):
        if block[i] == '{':
            depth += 1
        elif block[i] == '}':
            depth -= 1
        i += 1

    content = block[brace_start:i - 1]  # exclude closing brace
    # Strip leading/trailing whitespace
    lines = [l.rstrip() for l in content.split('\n')]
    return '\n'.join(lines).strip()


def main():
    content = sys.stdin.read()

    # Split into server blocks
    blocks = []
    depth = 0
    current = []
    in_block = False
    for char in content:
        if char == '{':
            depth += 1
            in_block = True
        elif char == '}':
            depth -= 1
        if in_block:
            current.append(char)
        if in_block and depth == 0:
            blocks.append(''.join(current))
            current = []
            in_block = False

    # Find HTTP block and SSL block
    http_meta = None  # lines before first server block
    http_block = None
    ssl_block = None
    for block in blocks:
        if '{' not in block:
            http_meta = block
        elif 'listen 80' in block and 'listen 443' not in block:
            http_block = block
        elif 'listen 443' in block:
            ssl_block = block

    if not ssl_block:
        print("Error: no SSL server block found", file=sys.stderr)
        sys.exit(1)

    # Build HTTP-only config from SSL block content
    root_content = extract_location_content(ssl_block, '/')
    static_content = extract_location_content(ssl_block, '/static/')

    lines = ['server {']
    lines.append('    listen 80;')

    # Extract server_name from SSL block
    sn_match = re.search(r'server_name\s+(.+?);', ssl_block)
    if sn_match:
        lines.append(f'    server_name {sn_match.group(1)};')
    else:
        lines.append('    server_name wealthtrack.filla.id;')

    lines.append('')
    lines.append('    location / {')
    if root_content:
        for line in root_content.split('\n'):
            stripped = line.strip()
            if stripped:
                lines.append(f'        {stripped}')
    lines.append('    }')

    if static_content:
        lines.append('')
        lines.append('    location /static/ {')
        for line in static_content.split('\n'):
            stripped = line.strip()
            if stripped:
                lines.append(f'        {stripped}')
        lines.append('    }')

    lines.append('}')

    print('\n'.join(lines))


if __name__ == '__main__':
    main()
