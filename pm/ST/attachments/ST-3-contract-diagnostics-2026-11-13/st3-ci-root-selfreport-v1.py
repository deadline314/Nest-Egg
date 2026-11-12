from pathlib import Path
from unittest.mock import Mock,patch
import hashlib,json,sys,tempfile

TOOLS=Path('D:/NestEggVerification/st3-ci-contracts-20261113/tools')
sys.path.insert(0,str(TOOLS))
from runtime_probe import run_case

ERROR='ERROR: [StoryContracts] res://data/story/ch2_heron.json/scenes/ch2_t_s05_gate: live content differs from independent contract'
source=(TOOLS/'runtime_probe.py').read_bytes()
rows=[]
for label,lines,expected,wanted in [
 ('producer cannot authorize its own ERROR',[ERROR],(),False),
 ('producer cannot hide an extra SCRIPT',[ERROR,'SCRIPT ERROR: unrelated'],(ERROR,),False),
 ('producer cannot invent a missing ERROR',[],(ERROR,),False),
 ('independent exact declaration authorizes only actual ERROR',[ERROR],(ERROR,),True),
]:
 with tempfile.TemporaryDirectory(prefix='st3-root-untrusted-result-') as temporary:
  folder=Path(temporary)
  def start(command,**kwargs):
   out=Path(next(arg[6:] for arg in command if arg.startswith('--out=')));out.mkdir()
   # These producer-controlled fields must not grant a diagnostic exception.
   result={'checks':3,'failures':[],'passed':True,'diagnostics':[],
           'diagnostic_count':0,'expected_diagnostics':[ERROR,'SCRIPT ERROR: unrelated'],
           'observed_expected_diagnostics':{ERROR:1},'unexpected_diagnostic_count':0}
   (out/'result.json').write_text(json.dumps(result),encoding='utf-8')
   kwargs['stdout'].write('\n'.join(lines)+'\n')
   process=Mock(pid=123);process.wait.return_value=0;process.poll.return_value=0
   return process
  with patch('runtime_probe.subprocess.Popen',side_effect=start):
   result=run_case('fixture',folder/'unused',folder,5,project=folder,
                   scene='res://fixture.tscn',slot=folder/'slot',expected_diagnostics=expected)
  assert result['passed'] is wanted,(label,result)
  rows.append({'case':label,'expected_pass':wanted,'actual_pass':result['passed'],
               'actual_diagnostic_count':result['diagnostic_count'],
               'unexpected_diagnostic_count':result['unexpected_diagnostic_count']})
assert (TOOLS/'runtime_probe.py').read_bytes()==source
print(json.dumps({'scope':'Root independent mocked process/result controls; no engine or source edits',
                  'checks':4,'failures':0,'runtime_probe_sha256':hashlib.sha256(source).hexdigest(),
                  'source_unchanged':True,'rows':rows},indent=2))
