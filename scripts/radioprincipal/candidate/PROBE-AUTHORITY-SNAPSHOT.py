#!/usr/bin/env python3
# Nome: PROBE-AUTHORITY-SNAPSHOT.py
# Versão: 1.0 / 2026-09-17
# Owner: Rádio
# Safety class: read-only
# Change ID: RADIOPRINCIPAL-NS1-C04-PROBE
# Propósito: inspecionar formato, freshness e alinhamento playlist/playback sem alterar produção.
import json, os, sys, time
from pathlib import Path
from datetime import datetime, timezone

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else '/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current')
FILES = ['playlist.json','schedule.json','librarymanifest.json','playback.json','heartbeat.json']

def load(name):
    p = ROOT / name
    st = p.stat()
    doc = json.loads(p.read_text(encoding='utf-8'))
    return p, st, doc

def data(doc):
    x = doc.get('payload', doc) if isinstance(doc, dict) else doc
    return x.get('data', x) if isinstance(x, dict) else x

def pathval(d):
    if not isinstance(d, dict): return ''
    for k in ('filename','file','path','source_path','source','fn','FILENAME','FILE','PATH','SOURCE_PATH','FN'):
        v=d.get(k)
        if isinstance(v,str) and v.strip(): return v.strip()
    for k,v in d.items():
        if isinstance(v,str) and ('path' in k.casefold() or 'file' in k.casefold()) and v.strip():
            return v.strip()
    return ''

def short(v, n=220):
    s=str(v).replace('\n',' ').replace('\r',' ')
    return s if len(s)<=n else s[:n]+'…'

def scalar_candidates(obj, prefix='', depth=0, in_bulk=False, out=None):
    if out is None: out=[]
    if depth>7: return out
    if isinstance(obj, dict):
        for k,v in obj.items():
            p = f'{prefix}.{k}' if prefix else str(k)
            key=str(k).casefold()
            bulk = in_bulk or key in ('tracks','items','files','entries','songs')
            if isinstance(v,(str,int,float,bool)) or v is None:
                if (not bulk and any(t in key for t in ('program','playlist','name','title','id','station','file'))) and len(str(v))<500:
                    out.append((p,v))
            else:
                scalar_candidates(v,p,depth+1,bulk,out)
    elif isinstance(obj, list) and len(obj)<=5:
        for i,v in enumerate(obj):
            scalar_candidates(v,f'{prefix}[{i}]',depth+1,in_bulk,out)
    return out

def list_candidates(obj, prefix='', depth=0, out=None):
    if out is None: out=[]
    if depth>8:return out
    if isinstance(obj, list):
        if obj and all(isinstance(x,dict) for x in obj):
            refs=sum(bool(pathval(x)) for x in obj)
            if refs:
                out.append((prefix or '<root>',len(obj),refs,obj))
        for i,v in enumerate(obj[:3]):
            list_candidates(v,f'{prefix}[{i}]',depth+1,out)
    elif isinstance(obj, dict):
        for k,v in obj.items():
            p=f'{prefix}.{k}' if prefix else str(k)
            list_candidates(v,p,depth+1,out)
    return out

def pick_ref_list(doc):
    cs=list_candidates(data(doc))
    return max(cs,key=lambda x:(x[2],x[1])) if cs else None

def iso_age(s):
    if not s:return None
    try:
        dt=datetime.fromisoformat(str(s).replace('Z','+00:00'))
        if dt.tzinfo is None: dt=dt.replace(tzinfo=timezone.utc)
        return (datetime.now(timezone.utc)-dt.astimezone(timezone.utc)).total_seconds()
    except Exception:
        return None

print('AUTHORITY_SNAPSHOT_PROBE=START')
print('UTC_NOW='+datetime.now(timezone.utc).isoformat())
print('ROOT='+str(ROOT))

for name in FILES:
    try:
        p,st,doc=load(name)
    except Exception as e:
        print(f'FILE={name} ERROR={e!r}')
        continue

    recv=doc.get('received_at_utc') if isinstance(doc,dict) else None
    print('\n===',name,'===')
    print('PATH='+str(p))
    print(f'MTIME_AGE_SEC={time.time()-st.st_mtime:.3f}')
    print('RECEIVED_AT_UTC='+str(recv))
    age=iso_age(recv)
    print('RECEIVED_AGE_SEC='+('NA' if age is None else f'{age:.3f}'))

    if isinstance(doc,dict):
        print('TOP_KEYS='+','.join(sorted(map(str,doc.keys()))))
        if isinstance(doc.get('payload'),dict):
            print('PAYLOAD_KEYS='+','.join(sorted(map(str,doc['payload'].keys()))))

    d=data(doc)
    if isinstance(d,dict):
        print('DATA_KEYS='+','.join(sorted(map(str,d.keys()))))

    if name=='playlist.json':
        c=pick_ref_list(doc)
        if c:
            path,count,refs,L=c
            print(f'PLAYLIST_LIST_PATH={path}')
            print(f'PLAYLIST_ITEM_COUNT={count}')
            print(f'PLAYLIST_REF_COUNT={refs}')
            for i in range(min(3,len(L))):
                x=L[i]
                print(f'ITEM[{i}].REF={pathval(x)}')
                print(f'ITEM[{i}].TITLE={short(x.get("ITEMTITLE") or x.get("TITLE") or x.get("Title") or "")}')
        else:
            print('PLAYLIST_LIST_PATH=UNRESOLVED')

        print('IDENTITY_CANDIDATES:')
        seen=set()
        for pth,v in scalar_candidates(doc):
            q=(pth,str(v))
            if q in seen: continue
            seen.add(q)
            print(f'  {pth}={short(v)}')

    elif name=='playback.json':
        dd=d if isinstance(d,dict) else {}
        cur=dd.get('current') if isinstance(dd.get('current'),dict) else {}
        nxt=dd.get('next') if isinstance(dd.get('next'),dict) else {}
        print('STATE='+str(dd.get('state')))
        print('PLAYLISTPOS='+str(dd.get('playlistpos')))
        print('POS_MS='+str(dd.get('pos_ms')))
        print('LEN_MS='+str(dd.get('len_ms')))
        print('SOURCE_TIMESTAMP='+str(dd.get('timestamp')))
        print('CURRENT_REF='+pathval(cur))
        print('CURRENT_TITLE='+short(cur.get('ITEMTITLE') or cur.get('TITLE') or cur.get('Title') or ''))
        print('NEXT_REF='+pathval(nxt))
        print('NEXT_TITLE='+short(nxt.get('ITEMTITLE') or nxt.get('TITLE') or nxt.get('Title') or ''))

    elif name=='heartbeat.json':
        print('HEARTBEAT_DATA='+json.dumps(d,ensure_ascii=False,sort_keys=True)[:2000])

    elif name=='schedule.json':
        print('SCHEDULE_IDENTITY_CANDIDATES:')
        for pth,v in scalar_candidates(doc)[:50]:
            print(f'  {pth}={short(v)}')

try:
    _,_,pl=load('playlist.json')
    _,_,pb=load('playback.json')
    c=pick_ref_list(pl)
    pd=data(pb)
    pos=int(pd.get('playlistpos')) if isinstance(pd,dict) and pd.get('playlistpos') is not None else None
    cur=pathval(pd.get('current') if isinstance(pd,dict) and isinstance(pd.get('current'),dict) else {})
    nxt=pathval(pd.get('next') if isinstance(pd,dict) and isinstance(pd.get('next'),dict) else {})

    if c and pos is not None:
        L=c[3]
        print('\n=== ALIGNMENT ===')
        for idx in range(max(0,pos-2),min(len(L),pos+3)):
            print(f'PLAYLIST[{idx}].REF={pathval(L[idx])}')
        at=pathval(L[pos]) if 0<=pos<len(L) else ''
        after=pathval(L[pos+1]) if 0<=pos+1<len(L) else ''
        print('CURRENT_MATCHES_PLAYLISTPOS='+str(bool(at and cur and at.casefold()==cur.casefold())).upper())
        print('NEXT_MATCHES_PLAYLISTPOS_PLUS_1='+str(bool(after and nxt and after.casefold()==nxt.casefold())).upper())
except Exception as e:
    print('ALIGNMENT_ERROR='+repr(e))

print('\nAUTHORITY_SNAPSHOT_PROBE=END')
