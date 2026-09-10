#!/usr/bin/env python3
import re, sys
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("usage: tvkids-nginx-patch-v1.py INPUT OUTPUT")
src, dst = map(Path, sys.argv[1:])
text = src.read_text()
marker = "TVKIDS_CANONICAL_ROOT_REDIRECT_v1"
if marker in text:
    dst.write_text(text)
    print("NGINX_PATCH=ALREADY_PRESENT")
    raise SystemExit(0)

def server_blocks(s):
    out=[]
    for m in re.finditer(r'(?m)^\s*server\s*\{', s):
        start=m.start()
        brace=s.find('{', m.start(), m.end()+2)
        if brace < 0:
            continue
        depth=0; quote=None; esc=False
        for i in range(brace, len(s)):
            ch=s[i]
            if quote:
                if esc:
                    esc=False
                elif ch == '\\':
                    esc=True
                elif ch == quote:
                    quote=None
                continue
            if ch in ("'", '"'):
                quote=ch
            elif ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    out.append((start, i+1, s[start:i+1]))
                    break
    return out

targets=[]
for start,end,block in server_blocks(text):
    names=[]
    for sm in re.finditer(r'\bserver_name\s+([^;]+);', block):
        names.extend(sm.group(1).split())
    if ("tvkids.studiosatweb.com.br" in names or "tvkidsweb.studiosatweb.com.br" in names):
        lm=re.search(r'location\s*=\s*/\s*\{', block)
        if lm:
            targets.append((start,end,block,lm.end()))

if not targets:
    raise SystemExit("FATAL: no TVKIDS non-www server block with location = / found")

insert = """
        # TVKIDS_CANONICAL_ROOT_REDIRECT_v1
        if ($host = tvkids.studiosatweb.com.br) {
            return 302 https://www.tvkids.studiosatweb.com.br$request_uri;
        }
        if ($host = tvkidsweb.studiosatweb.com.br) {
            return 302 https://www.tvkidsweb.studiosatweb.com.br$request_uri;
        }
"""

patched=text
count=0
for start,end,block,loc_end in reversed(targets):
    absolute=start+loc_end
    patched=patched[:absolute]+insert+patched[absolute:]
    count += 1

dst.write_text(patched)
print(f"NGINX_PATCH=PASS blocks={count}")
