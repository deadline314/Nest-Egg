"""Fail-closed real per-bus PCM/sample-clock loader. No silent truncation."""
import json, math, pathlib, wave
import numpy as np

READER_VERSION = 'ne261-capture-reader-v2-chunked'

def verify_content(index):
    assert index.get('content_contract')=='ne261-actual-actions-v1','missing actual action/target content contract; segment labels alone are not hit evidence'
    assert index['content_problems']==[],'actual action/content producer rejected'
    segments=index['segments']
    expected={('ref',p) for p in ('silence','pistol','pistol_hit','walk')}|{(w,p) for w in ('blade','dagger','glaive','maul','whip') for p in ('idle','combo_miss','combo_hit','holster')}
    assert len(segments)==24 and {(s['weapon'],s['part']) for s in segments}==expected,'not the actual complete 24 segments'
    for segment in segments:
        key=(segment['weapon'],segment['part']);data=segment['content']
        assert data['closed'] and data['physics_end']>=data['physics_start'],('unpublished content boundary',key)
        assert all(segment['bus_start_frames'][n]<=v<=segment['bus_end_frames'][n] for n,v in data['sample_end_frames'].items()),('content observation outside PCM interval',key)
        if segment['part'] in ('pistol_hit','combo_hit'):
            assert len(data['targets_start'])==len(data['targets_end'])==1,('real live target required',key)
            start=data['targets_start'][0];end=data['targets_end'][0]
            assert start['id']==end['id'] and start['can_process'] and start['spaces'],('target identity/process',key)
            assert all(s['space']!=0 for s in start['spaces']),('collider has no physics space',key)
            assert start['health']-end['health']==sum(e['amount'] for e in data['damage'])>0,('actual health delta/callback mismatch',key)
            assert len(data['hit_confirmed'])==len(data['damage'])>0,('actual hit-confirmed/callback mismatch',key)
            source='player_pistol' if segment['part']=='pistol_hit' else 'melee'
            assert all(e['source_id']==source for e in data['damage']),('wrong true damage source',key)
            assert start['material']=='armor' and 'mat_armor' in segment['sounds'],('actual target material callback absent',key)
            if segment['part']=='pistol_hit':assert len(data['damage'])==3,('reference shots must all hit',key)
            else:
                for event in data['audio_calls']:
                    if event['id'].startswith('melee_'+segment['weapon']+'_hit'):
                        assert any(e['attack_index']==event['attack_index'] and e['physics_frame']<=event['physics_frame'] for e in data['damage']),('hit layer without actual prior same-attack damage',key,event)
                    elif event['id'].startswith('melee_'+segment['weapon']+'_swing'):
                        assert not event['pose']['landed'],('swing despite already-landed strike',key,event)
                assert any(e['id'].startswith('melee_'+segment['weapon']+'_hit') for e in data['audio_calls']),('actual weapon-hit layer absent',key)
        elif segment['part'] in ('pistol','combo_miss'):
            assert not data['targets_start'] and not data['damage'] and not data['hit_confirmed'],('miss segment actually hit',key)
            assert not any('_hit' in e['id'] or e['id']=='mat_armor' for e in data['audio_calls']),('hit sound in miss segment',key)
        elif segment['part']=='idle':assert data['hum_end']=='melee_'+segment['weapon']+'_idle',('wrong actual idle voice',key)
        elif segment['part']=='holster':assert data['hum_end']=='',('actual idle voice did not stop',key)
    return {'segments':len(segments),'actual_damage_events':sum(len(s['content']['damage']) for s in segments),'material_scope':'one actual armor target; no all-materials or held-mode claim'}

def load(folder,index):
    folder=pathlib.Path(folder)
    assert index.get('sample_clock',{}).get('schema')=='ne261-capture-pcm-v1','Legacy/Record/wall-time index is not a Capture PCM sample-clock recording; explicit new capture schema required'
    clock=index['sample_clock'];rate=clock['mix_rate']
    # Ordinary probe output has no external runner receipt. If supplied, a red
    # receipt must still reject; formal delivery verification requires it.
    if (folder/'exit.json').exists():
        receipt=json.loads((folder/'exit.json').read_text(encoding='utf8'))
        assert receipt['exit_code']==0 and not receipt['diagnostic_lines'] and not receipt['gpu_log_rejected'] and receipt['source_unchanged'],'producer process rejected'
    assert index['runtime']['audio_driver'].strip() and index['runtime']['audio_driver'].lower()!='dummy','not actual audio driver'
    assert type(rate) is int and rate>0 and clock['problems']==[] and clock['cleanup']=={'already_cleaned':False,'removed':4}, 'producer clock problems'
    assert set(clock['buses'])=={'Master','SFX','Music','Ambience'},'missing independent bus'
    audio={};lengths={}
    for name,bus in clock['buses'].items():
        base=bus['base'];end=bus['end']
        pushed=end['pushed']-base['pushed'];discarded=end['discarded']-base['discarded']
        assert discarded==0 and pushed>0,'Capture discard/empty bus'
        assert pushed==bus['pushed_delta']==bus['capture_frames']==bus['wav_frames'],'bus frame count mismatch'
        assert bus['pcm_source']=='AudioEffectCapture' and bus['float_format']=='stereo_f32le' and bus['after_save_counter']==end,'wrong PCM authority or capture advanced after stop'
        assert bus['discarded_delta']==0 and bus['save_error']==0 and bus['capture_save_error']==0,'bus drop/save failure'
        raw=(folder/('bus-'+name+'.f32')).read_bytes()
        assert len(raw)==pushed*8,'float PCM size mismatch'
        floats=np.frombuffer(raw,dtype='<f4')
        with wave.open(str(folder/('bus-'+name+'.wav')),'rb') as wav:
            assert (wav.getnchannels(),wav.getsampwidth(),wav.getframerate(),wav.getnframes())==(2,2,rate,pushed),'Capture-derived WAV format/size mismatch'
            pcm=wav.readframes(pushed)
        actual=np.frombuffer(pcm,dtype='<i2')
        assert actual.size==floats.size,'Capture-derived WAV sample count'
        # Fixed bounded temporaries; never allocate millions of Python floats
        # or individual packed-byte objects for a whole recording.
        for start in range(0,floats.size,65536):
            block=floats[start:start+65536]
            assert np.isfinite(block).all(),'nonfinite capture'
            scaled=np.multiply(block,32768.0,dtype=np.float64)
            np.clip(scaled,-32768.0,32767.0,out=scaled)
            expected=scaled.astype('<i2')
            assert np.array_equal(actual[start:start+65536],expected),'Capture-derived WAV quantization/sample mismatch'
        gain=bus['gain_db'];assert math.isfinite(gain),'invalid bus gain'
        assert bus['gain_check_count']>0 and [x['kind'] for x in bus['gain_observations']]==['first','last'] and all(x['gain_db']==gain and x['send']==bus['send'] for x in bus['gain_observations']),'bus gain/send changed or publication missing'
        if name!='Master':assert bus['send']=='Master','bed/SFX not direct Master children'
        assert clock['stop']['frames'][name]==pushed,'end not actual stop sample'
        lengths[name]=pushed;audio[name]={'raw_f32':raw,'pcm_s16':pcm,'gain':10**(gain/20)}
    assert len(set(lengths.values()))==1,'bus epoch lengths differ'
    previous=None
    for segment in index['segments']:
        starts=segment['bus_start_frames'];ends=segment['bus_end_frames']
        assert set(starts)==set(lengths) and set(ends)==set(lengths),'segment missing bus anchors'
        assert len(set(starts.values()))==len(set(ends.values()))==1,'bus segment epochs differ'
        for name,count in lengths.items():
            start,end=starts[name],ends[name]
            assert type(start) is int and type(end) is int and 0<=start<end<=count,'segment exceeds actual PCM'
            if previous is not None:assert start==previous[name],'segment discontinuity'
        previous=ends
    assert previous==clock['stop']['frames'],'last segment is not stop boundary'
    return rate,audio

if __name__=='__main__':
    import argparse
    ap=argparse.ArgumentParser();ap.add_argument('folder');args=ap.parse_args()
    folder=pathlib.Path(args.folder);rate,audio=load(folder,json.loads((folder/'melee-index.json').read_text(encoding='utf8')))
    print(json.dumps({'reader_version':READER_VERSION,'mix_rate':rate,'bus_frames':{n:len(a['raw_f32'])//8 for n,a in audio.items()},'scope':'PCM/counter input contract only; no loudness or listening acceptance'},indent=2))
