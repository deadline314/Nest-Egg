from pathlib import Path
import hashlib, json

work=Path(__file__).resolve().parent
root=work.parents[1]
current=(root/'tools/texture_route_probe.gd').read_text(encoding='utf-8')
def save(text, expected, label):
    data=text.encode('utf-8')
    actual=hashlib.sha256(data).hexdigest()
    assert actual==expected,(label,actual,expected)
    (work/('tool-'+label+'.gd.txt')).write_bytes(data)

evidence=Path('C:/NE/evidence-20261117/bg32')
save(current,json.loads((evidence/'isolated-D3/report.json').read_text())['tool_sha256'],'D3-D4')
old=current
start=old.index('\t# Every real Level creates ForegroundLayer.')
end=old.index('\tif data.environment != null:',start)
old=old[:start]+old[end:]
old='\n'.join(line for line in old.split('\n') if '"a real current Level foreground strip is not an unused sky"' not in line)
save(old,json.loads((evidence/'isolated-D1/report.json').read_text())['tool_sha256'],'D1-D2')

start=old.index('static func _unexpected_backdrop(')
end=old.index('static func _neighbor_inventory(',start)
old=old[:start]+old[end:]
old='\n'.join(line for line in old.split('\n') if not any(marker in line for marker in [
    'record["unexpected_backdrop"]', '_check(_unexpected_backdrop(', '_check(not _unexpected_backdrop(',
    'report["runtime"] =', '\tvar sync_play_ms :=']))
old=old.replace(', "sync_play_ms": sync_play_ms','')
save(old,json.loads((evidence/'isolated-A1/report.json').read_text())['tool_sha256'],'A1-B1-C1-A2-C2')
print('Reconstructed intermediate snapshots exactly match all recorded tool hashes; final snapshot exact bytes')
