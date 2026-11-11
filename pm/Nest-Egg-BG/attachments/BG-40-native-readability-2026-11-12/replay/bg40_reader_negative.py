"""Fail-closed controls mutate a parsed copy, never original native evidence."""
from pathlib import Path
import argparse, json, sys
import verify_bg40_native as reader

p=argparse.ArgumentParser();p.add_argument('folder',type=Path);p.add_argument('kind',choices=['box','owner']);a=p.parse_args()
original=json.loads
mutations=[]
def altered(value,*args,**kwargs):
    data=original(value,*args,**kwargs)
    if isinstance(data,dict) and 'shots' in data:
        for shot in data['shots']:
            for record in shot['bg40']['records']:
                if not record.get('player_visible'): continue
                if a.kind=='box': record['player']['screen_rect'][0]+=1
                else: record['held']['lighting_owners']['valid']=False
                mutations.append(dict(level=data['level'],column=shot['column'],row=shot['row'],label=record['label'],kind=a.kind))
                return data
    return data
reader.json.loads=altered
try:
    reader.verify(a.folder)
except AssertionError as error:
    assert mutations
    print(json.dumps(dict(expected_rejection=True,mutation=mutations[0],original_files_unchanged=True,error=str(error))))
    sys.exit(1)
raise SystemExit('negative was unexpectedly accepted')
