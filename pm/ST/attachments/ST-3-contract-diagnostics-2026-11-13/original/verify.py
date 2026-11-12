"""Read-only portable packet verification; this packet deliberately preserves a RED local run."""
from pathlib import Path
from collections import Counter
import ast, hashlib, json, re, zipfile

ROOT=Path(__file__).resolve().parent
BAD=re.compile(r"^ERROR:|SCRIPT ERROR|Parse Error|^FAIL(?:\s|:)|handle_crash:|Program crashed|leaked at exit|resources still in use|Leaked instance:|Resource still in use:")
def require(value,message):
    if not value:raise ValueError(message)
def load(z,name):return json.loads(z.read(name))
def main():
    index=json.loads((ROOT/'archive-index.json').read_bytes())
    for name,row in index.items():
        data=(ROOT/name).read_bytes();require(len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256'],name+': archive mismatch')
        with zipfile.ZipFile(ROOT/name) as z:
            require(z.testzip() is None,name+': CRC')
            require(len(z.infolist())==len(row['members']),name+': member count')
            require({i.filename for i in z.infolist()}=={r['path'] for r in row['members']},name+': inventory')
            for member in row['members']:
                info=z.getinfo(member['path']);raw=z.read(info)
                require(info.file_size==member['bytes'] and f'{info.CRC:08x}'==member['crc32'] and hashlib.sha256(raw).hexdigest()==member['sha256'],name+': '+member['path'])
    candidate=json.loads((ROOT/'candidate.json').read_bytes())
    require(candidate['base']=='b2abac978cf6a14feaf254bb608b3779299fa89f' and len(candidate['files'])==7,'candidate scope')
    with zipfile.ZipFile(ROOT/'source.zip') as source,zipfile.ZipFile(ROOT/'raw.zip') as raw:
        before,after=load(raw,'source-before.json'),load(raw,'source-after.json')
        require(before==after and len(before)==4057,'source projection drift')
        for row in candidate['files']:
            data=source.read(row['path']);require(b'\r' not in data and len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256']==before[row['path']]['sha256'],row['path']+': frozen source')
        expected_tables={}
        for row in candidate['files']:
            if '/run_' not in row['path']:continue
            tree=ast.parse(source.read(row['path']))
            for node in tree.body:
                if isinstance(node,ast.Assign) and any(isinstance(n,ast.Name) and n.id=='EXPECTED_DIAGNOSTICS' for n in node.targets):expected_tables[Path(row['path']).name]=ast.literal_eval(node.value)
        inventory=load(raw,'mutation-inventory.json');require(len(inventory)==22,'mutation inventory')
        for item in inventory:
            require(expected_tables[Path(item['runner']).name][item['mode']]==tuple(item['expected_diagnostics']) and item['expected_count']==1,'independent caller table')
        total=green=red=0
        for runner,count in [('run_patroller_completion',8),('run_ch2_evidence_completion',14),('run_ch2_reading_completion',8)]:
            receipt=load(raw,runner+'/receipt.json');require(len(receipt['cases'])==count,runner+': case count')
            for case in receipt['cases']:
                mode=case['mode'];lines=raw.read(runner+'/'+mode+'.log').decode('utf8','replace').splitlines()
                observed=[line.strip() for line in lines if BAD.search(line)]
                expected=Counter(expected_tables[runner+'.py'].get(mode,()))
                require(len(observed)==case['diagnostic_count'] and case['diagnostics']==[line[:512] for line in observed[:32]],mode+': raw diagnostics')
                require(case['expected_diagnostics']==dict(expected),mode+': caller expectation')
                data=load(raw,runner+'/'+mode+'/result.json');require(data==case['result'],mode+': result')
                exit_code=int(raw.read(runner+'/'+mode+'.exit'));require(exit_code==case['exit'],mode+': exit')
                verdict=exit_code==0 and not case['timeout'] and Counter(observed)==expected and type(data.get('checks')) is int and data['checks']>0 and data['failures']==[]
                require(verdict==case['passed'],mode+': verdict')
                total+=1;green+=int(verdict);red+=int(not verdict)
                if not verdict:require(mode=='rumor--accepted' and data['checks']==26 and case['unexpected_diagnostic_count']==3 and expected==Counter(),'unexpected local failure')
        require((total,green,red)==(30,29,1),'local run scope')
        end=load(raw,'exit.json');require(end['passed'] is False and end['all_commands_completed'] is False and end['source_fixed'] is True,'preserved RED exit')
        baseline=load(raw,'baseline-contract-red/receipt.json');require(baseline['passed'] is False and baseline['diagnostic_count']==1 and baseline['result']['checks']==10 and baseline['result']['failures']==[],'original contract red')
        control=load(raw,'rumor-baseline-original-helper/receipt.json');require(control['passed'] is True and control['diagnostic_count']==0 and control['result']['checks']==26 and control['result']['failures']==[],'single original-helper control')
        unit=raw.read('unit-posix-stdout.log').decode();require('Ran 20 tests' in unit and 'OK' in unit and 'skipped=' not in unit,'actual Ubuntu twenty tests')
        require(all(row['exit']==0 for row in end['commands'][:4]),'unit/selector/changed exits')
        require('沒有受影響的測試' in raw.read('changed-stdout.log').decode('utf8'),'changed zero groups')
    print(json.dumps({'packet_integrity':'PASS','source_files':7,'source_projection':4057,'ubuntu_unit_tests':20,'local_cases':30,'local_green':29,'local_red':1,'full_98_completed':False,'next_requirement':'Root original safe CI; no local full-green claim'},indent=2))
if __name__=='__main__':main()
