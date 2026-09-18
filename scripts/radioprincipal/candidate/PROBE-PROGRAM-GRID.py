#!/usr/bin/env python3
# Nome: PROBE-PROGRAM-GRID.py
# Versão: 1.0 / 2026-09-17
# Owner: Rádio
# Safety class: read-only
# Change ID: RADIOPRINCIPAL-NS1-C05-PROBE
# Propósito: inspecionar grade futura, playlist_definitions e schedule recebidos do RadioBOSS sem alterar produção.

import json, sys
from pathlib import Path
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

ROOT=Path(sys.argv[1] if len(sys.argv)>1 else '/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current')

def load(name):
    return json.loads((ROOT/name).read_text(encoding='utf-8'))

def data(doc):
    x=doc.get('payload',doc) if isinstance(doc,dict) else doc
    return x.get('data',x) if isinstance(x,dict) else x

def short(x,n=260):
    s=str(x).replace('\r',' ').replace('\n',' ')
    return s if len(s)<=n else s[:n]+'…'

def pathval(d):
    if not isinstance(d,dict): return ''
    for k in ('filename','file','path','source_path','source','fn','FILENAME','FILE','PATH','SOURCE_PATH','FN'):
        v=d.get(k)
        if isinstance(v,str) and v.strip(): return v.strip()
    return ''

def xml_strings(obj, path=''):
    out=[]
    if isinstance(obj,str):
        s=obj.strip()
        if s.startswith('<'):
            try:
                r=ET.fromstring(s)
                out.append((path,r))
            except Exception:
                pass
    elif isinstance(obj,dict):
        for k,v in obj.items():
            out.extend(xml_strings(v,f'{path}.{k}' if path else str(k)))
    elif isinstance(obj,list):
        for i,v in enumerate(obj):
            out.extend(xml_strings(v,f'{path}[{i}]'))
    return out

def summarize_obj(obj, prefix='', depth=0, limit=160, out=None):
    if out is None: out=[]
    if len(out)>=limit or depth>7:return out
    if isinstance(obj,dict):
        for k,v in obj.items():
            if len(out)>=limit:break
            p=f'{prefix}.{k}' if prefix else str(k)
            if isinstance(v,(str,int,float,bool)) or v is None:
                out.append((p,short(v)))
            elif isinstance(v,list):
                out.append((p,f'<LIST len={len(v)}>'))
                for i,x in enumerate(v[:6]):
                    summarize_obj(x,f'{p}[{i}]',depth+1,limit,out)
            elif isinstance(v,dict):
                out.append((p,f'<DICT keys={",".join(map(str,list(v.keys())[:20]))}>'))
                summarize_obj(v,p,depth+1,limit,out)
    elif isinstance(obj,list):
        out.append((prefix,f'<LIST len={len(obj)}>'))
        for i,x in enumerate(obj[:6]):
            summarize_obj(x,f'{prefix}[{i}]',depth+1,limit,out)
    return out

def show_xml(label, doc):
    xs=xml_strings(doc)
    print(f'{label}_XML_OBJECTS={len(xs)}')
    for n,(p,r) in enumerate(xs[:20]):
        print(f'{label}_XML[{n}].PATH={p}')
        print(f'{label}_XML[{n}].ROOT={r.tag}')
        print(f'{label}_XML[{n}].ATTRS={json.dumps(r.attrib,ensure_ascii=False,sort_keys=True)}')
        tracks=list(r.findall('.//TRACK'))
        items=list(r.findall('.//item'))
        print(f'{label}_XML[{n}].TRACKS={len(tracks)}')
        print(f'{label}_XML[{n}].ITEMS={len(items)}')
        for i,t in enumerate(tracks[:3]):
            a=dict(t.attrib)
            for c in list(t):
                if c.tag not in a: a[c.tag]=c.text or ''
            print(f'{label}_XML[{n}].TRACK[{i}].REF={pathval(a)}')
            print(f'{label}_XML[{n}].TRACK[{i}].ATTRS={short(json.dumps(a,ensure_ascii=False,sort_keys=True),500)}')
        for i,e in enumerate(items[:8]):
            a=dict(e.attrib)
            for c in list(e):
                if c.tag not in a:a[c.tag]=c.text or ''
            print(f'{label}_XML[{n}].ITEM[{i}]={short(json.dumps(a,ensure_ascii=False,sort_keys=True),700)}')

print('PROGRAM_GRID_PROBE=START')
print('UTC_NOW='+datetime.now(timezone.utc).isoformat())
print('ROOT='+str(ROOT))

for fn in ('playlist.json','schedule.json','librarymanifest.json','heartbeat.json'):
    print('\n================',fn,'================')
    try:
        d=load(fn)
    except Exception as e:
        print('ERROR='+repr(e));continue
    print('RECEIVED_AT_UTC='+str(d.get('received_at_utc') if isinstance(d,dict) else None))
    print('REVISION='+str(d.get('revision') if isinstance(d,dict) else None))
    payload=d.get('payload',{}) if isinstance(d,dict) else {}
    if isinstance(payload,dict):
        print('RADIOBOSS_ONLINE='+str(payload.get('radioboss_online')))
        print('MACHINE='+str(payload.get('machine')))
        print('AGENT_VERSION='+str(payload.get('agent_version')))
    dd=data(d)
    if isinstance(dd,dict):
        print('DATA_KEYS='+','.join(map(str,dd.keys())))
    show_xml(fn.replace('.json','').upper(),d)

    if fn=='librarymanifest.json' and isinstance(dd,dict):
        defs=dd.get('playlist_definitions')
        print('\n--- PLAYLIST_DEFINITIONS ---')
        print('TYPE='+type(defs).__name__)
        if isinstance(defs,(list,dict)):
            for p,v in summarize_obj(defs,prefix='playlist_definitions',limit=260):
                print(f'{p}={v}')
        else:
            print('VALUE='+short(defs))

        print('\n--- LOGICAL_REFERENCES ---')
        refs=dd.get('logical_references')
        print('TYPE='+type(refs).__name__)
        if isinstance(refs,(list,dict)):
            for p,v in summarize_obj(refs,prefix='logical_references',limit=120):
                print(f'{p}={v}')
        else:
            print('VALUE='+short(refs))

    if fn=='schedule.json':
        print('\n--- SCHEDULE_STRUCTURE ---')
        for p,v in summarize_obj(dd,prefix='schedule',limit=260):
            print(f'{p}={v}')

print('\nPROGRAM_GRID_PROBE=END')
