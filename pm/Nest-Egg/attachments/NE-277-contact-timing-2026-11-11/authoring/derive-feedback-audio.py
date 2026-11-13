"""Derive exact PCM segments from the immutable final native feedback archive."""
from pathlib import Path
import io,json,hashlib,wave,zipfile,shutil
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'pm/Nest-Egg/attachments/NE-277-contact-timing-2026-11-11'
RAW=ROOT/'work/ne277-feedback-final-native-v6/raw.zip'
def sha(data):return hashlib.sha256(data).hexdigest()
def main():
 target=OUT/'native-feedback-final.zip'
 if target.exists():assert sha(target.read_bytes())==sha(RAW.read_bytes())
 else:shutil.copyfile(RAW,target)
 with zipfile.ZipFile(RAW) as z:
  assert z.testzip() is None
  names=z.namelist()
  def read(name):return z.read(next(n for n in names if n==name or n.endswith('/'+name)))
  result=json.loads(read('result.json'));master=read('master.wav')
 with wave.open(io.BytesIO(master),'rb') as w:
  rate,channels,width,count=w.getframerate(),w.getnchannels(),w.getsampwidth(),w.getnframes()
  pcm=w.readframes(count)
 assert width==2 and channels==2 and rate==48000
 samples=np.frombuffer(pcm,dtype='<i2').reshape(-1,channels).astype(float)/32768
 assert np.isfinite(samples).all() and np.any(samples)
 clips=OUT/'audio-clips';clips.mkdir(exist_ok=True)
 rows=[]
 for row in result['rows']:
  start=int(row['start_seconds']*rate);end=min(int(row['end_seconds']*rate),count)
  assert 0<=start<end<=count
  data=pcm[start*channels*width:end*channels*width]
  name=row['name'].replace('/','-')+'.wav';path=clips/name
  with wave.open(str(path),'wb') as w:
   w.setnchannels(channels);w.setsampwidth(width);w.setframerate(rate);w.writeframes(data)
  with wave.open(str(path),'rb') as w:assert w.readframes(w.getnframes())==data
  values=samples[start:end]
  rows.append({'name':row['name'],'file':'audio-clips/'+name,'source_start_sample':start,'source_end_sample_exclusive':end,'pcm_sha256':sha(data),'wav_sha256':sha(path.read_bytes()),'peak':float(np.abs(values).max()),'rms':float(np.sqrt(np.mean(values**2)))})
 report={'scope':'Exact contiguous original master-mix PCM segments. Includes ambience/music/shared hits; no human listening, isolated-layer loudness or timing-latency claim. Original master and event facts remain in native-feedback-final.zip.','raw_sha256':sha(RAW.read_bytes()),'master_sha256':sha(master),'pcm_sha256':sha(pcm),'sample_rate':rate,'channels':channels,'sample_width_bytes':width,'seconds':count/rate,'checks':result['checks'],'failures':result['failures'],'rows':rows}
 (OUT/'feedback-audio-provenance.json').write_bytes((json.dumps(report,indent=2)+'\n').encode())
 print(json.dumps({'segments':len(rows),'seconds':count/rate,'checks':result['checks'],'failures':result['failures'],'raw_sha256':report['raw_sha256']}))
if __name__=='__main__':main()
