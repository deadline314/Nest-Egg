from pathlib import Path
import json,sys,statistics,hashlib
folder=Path(sys.argv[1]);quality=sys.argv[2]
data=json.loads((folder/(quality+'-index.json')).read_text(encoding='utf-8'))
checks=[]
def check(name,value):
 checks.append({'name':name,'passed':bool(value)})
perf=data['perf'];pairs=perf['pairs']
check('exactly six enemy glows',perf['glowing_enemies']==6)
check('complete original sixty ordered alternating pairs',len(pairs)==60 and all(p['round']==i and p['on_first']==(i%2==0) for i,p in enumerate(pairs)))
ratio=statistics.median(p['on_ms']/p['off_ms'] for p in pairs)
check('stored raw ratio equals independent pair median',abs(ratio-perf['ratio_raw'])<1e-12)
check('unrounded original 105 percent gate',ratio<=1.05 and perf['passed'])
check('quality cap',0<=perf['active_lights']<=perf['max_lights']==(8 if quality=='low' else 24 if quality=='high' else 14))
for state in ['calm','alert','telegraph']:
 row=data['states'][state]
 for enemy in ['watchdog','heavy_gunner']:
  check(enemy+' exact '+state,row[enemy]['state']==state)
  check(enemy+' light level '+state,abs(row[enemy]['level']-{'calm':1.0,'alert':1.7,'telegraph':2.1}[state])<=.010000001)
 check('plain sweeper has no glow '+state,row['sweeper（不帶燈）']['glow'] is False)
 check('native image '+state,(folder/(quality+'-'+state+'.png')).is_file())
for enemy in ['watchdog','heavy_gunner']:
 check(enemy+' own color retained at alert',data['states']['calm'][enemy]['color']==data['states']['alert'][enemy]['color'])
 check(enemy+' telegraph differs from own color',data['states']['telegraph'][enemy]['color']!=data['states']['calm'][enemy]['color'])
death=data['death']
check('initially lit and extinguishes during original three second limit',death['initial_light_valid'] and death['passed'] and 0<=death['dark_after_seconds']<=3)
check('death contact sheet present',(folder/(quality+'-death.png')).is_file())
result=json.loads((folder/'result.json').read_text(encoding='utf-8'))
for key in ['source_unchanged','profile_under_redirected_dir','tool_sha_matches']:
 check(key,result[key])
check('natural EOF clean',result['natural_exit']==0 and result['script_errors']==0 and result['engine_error_lines']==0)
raw=(folder/'raw.log').read_text(encoding='utf-8',errors='replace')
check('native Forward+ RX9070XT', 'Forward+' in raw and '9070 XT' in raw)
report={'checks':checks,'total':len(checks),'failures':sum(not c['passed'] for c in checks),'independent_ratio_raw':ratio,'input_sha256':hashlib.sha256((folder/(quality+'-index.json')).read_bytes()).hexdigest()}
(folder/'independent.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(report,indent=2,ensure_ascii=False));sys.exit(1 if report['failures'] else 0)
