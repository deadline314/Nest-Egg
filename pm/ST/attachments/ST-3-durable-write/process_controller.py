from pathlib import Path
import subprocess, json, hashlib, os, time, uuid, shutil

ROOT=Path('C:/tmp/Nest-Egg-story-durable-write')
GODOT='C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe'
OUT=Path('C:/tmp/st3-durable-native-matrix')
OUT.mkdir(parents=True,exist_ok=True)
ENV=dict(os.environ,APPDATA='C:/tmp/st3-durable-probe-private-user')
SCENE='res://tools/story_durable_write_probe.tscn'
records=[]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def command(directory,mode,*args):
    return [GODOT,'--headless','--path',str(ROOT),SCENE,'--','--mode='+mode,'--save-dir='+directory.as_posix(),*args]
def run(directory,mode,label,*args):
    log=OUT/(label+'.log')
    with log.open('wb') as stream:
        result=subprocess.run(command(directory,mode,*args),cwd=ROOT,env=ENV,stdout=stream,stderr=subprocess.STDOUT,timeout=60)
    text=log.read_text(encoding='utf-8')
    (OUT/(label+'.exit')).write_text(str(result.returncode),encoding='utf-8')
    assert result.returncode==0,(label,result.returncode,text)
    assert not any(x in text for x in ['SCRIPT ERROR','Parse Error','Compile Error','FAIL ']),(label,text)
    print(label+' EOF0',flush=True)
    return {'mode':mode,'exit':result.returncode,'log':str(log),'sha256':sha(log)}
def seed(label):
    directory=Path('C:/tmp')/('ne-story-durable-'+label+'-'+uuid.uuid4().hex[:10])
    assert not directory.exists()
    result=run(directory,'seed',label+'-seed')
    return directory,result
def checked_kill(pid,parent):
    # Only the process identified by this writer's flushed barrier can be killed.
    script=f"$p=Get-CimInstance Win32_Process -Filter 'ProcessId={int(pid)}'; if ($null -eq $p) {{exit 21}}; $p | Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine | ConvertTo-Json -Compress"
    info=subprocess.check_output(['powershell','-NoProfile','-Command',script],text=True,encoding='utf-8')
    data=json.loads(info)
    assert data['ProcessId']==pid and (pid==parent or data['ParentProcessId']==parent),data
    assert Path(data['ExecutablePath']).name.startswith('Godot_v4.7.2-stable_win64'),data
    assert str(ROOT).replace('\\','/') in data['CommandLine'].replace('\\','/'),data
    assert SCENE in data['CommandLine'],data
    os.kill(pid,9)  # Windows TerminateProcess; never normal Godot quit / Main._quit.
    return data

for linked in [False,True]:
    for index,phase in enumerate(['temp_closed','backup_removed','primary_rotated','primary_committed']):
        label=('hardlink-' if linked else 'standard-')+phase
        directory,initial=seed(label)
        slot=directory/'slot.json'
        old=slot.read_bytes(); backup=Path(str(slot)+'.bak')
        assert backup.exists()
        old_backup=backup.read_bytes()
        tmp=Path(str(slot)+'.tmp')
        fixture={'hardlink':linked}
        if linked:
            assert not tmp.exists()
            os.link(slot,tmp)
            assert os.path.samefile(slot,tmp)
            fixture.update({'before_samefile':True,'old_file_id':os.stat(slot).st_ino,'tmp_file_id':os.stat(tmp).st_ino})
        log=OUT/(label+'-write.log')
        with log.open('wb') as stream:
            writer=subprocess.Popen(command(directory,'write','--phase='+phase,'--barrier-timeout-ms=15000'),cwd=ROOT,env=ENV,stdout=stream,stderr=subprocess.STDOUT)
            barrier=None; until=time.monotonic()+25
            while time.monotonic()<until and writer.poll() is None:
                file=directory/'barrier.json'
                if file.exists():
                    try: barrier=json.loads(file.read_text(encoding='utf-8'))
                    except (OSError,json.JSONDecodeError): pass
                    if barrier:break
                time.sleep(.02)
            assert barrier is not None,(label,'no barrier',writer.poll())
            assert barrier['version']==1 and barrier['phase']==index and barrier['slot']==slot.as_posix(),barrier
            if index==0:
                assert slot.read_bytes()==old and backup.read_bytes()==old_backup,'old authoritative bytes changed before commit'
                if linked:
                    assert not os.path.samefile(slot,tmp),'tmp was not detached before WRITE'
                    fixture['at_temp_closed_samefile']=False
                    fixture['new_tmp_file_id']=os.stat(tmp).st_ino
            process=checked_kill(barrier['pid'],writer.pid)
            code=writer.wait(timeout=15)
            assert code!=0,(label,'forced writer unexpectedly natural success')
        text=log.read_text(encoding='utf-8')
        assert not any(x in text for x in ['SCRIPT ERROR','Parse Error','Compile Error','external kill did not occur']),text
        (OUT/(label+'-forced.exit')).write_text(str(code),encoding='utf-8')
        expected='new' if index==3 else 'old'
        reader=run(directory,'read',label+'-fresh-read','--expect='+expected)
        record={'label':label,'directory':str(directory),'seed':initial,'fixture':fixture,'barrier':barrier,
                'killed_process':process,'forced_writer_exit':code,'writer_log':str(log),'writer_log_sha256':sha(log),
                'expected':expected,'reader':reader,'whole_run_fresh_read':True,'no_Main':True}
        records.append(record)
        print(label+' forced OS termination + complete fresh '+expected+' verified',flush=True)

for kind in ['tmp_primary','tmp_backup','tmp_external','primary_backup','tmp_primary_open_fail','tmp_symlink','tmp_dangling']:
    label='alias-'+kind
    directory,initial=seed(label)
    slot=directory/'slot.json'; bak=Path(str(slot)+'.bak'); tmp=Path(str(slot)+'.tmp')
    target=slot
    if kind=='tmp_backup':target=bak
    if kind=='tmp_external':
        target=directory/'external.json';shutil.copyfile(slot,target)
    if kind=='primary_backup':
        bak.unlink();os.link(slot,bak);assert os.path.samefile(slot,bak)
    elif kind in ['tmp_symlink','tmp_dangling']:
        target=slot if kind=='tmp_symlink' else directory/'absent-target.json'
        try:os.symlink(target,tmp)
        except OSError as error:
            records.append({'label':label,'directory':str(directory),'seed':initial,'status':'SKIP not validated',
                            'winerror':error.winerror,'message':str(error)})
            print(label+' SKIP not validated '+str(error),flush=True)
            continue
    else:
        os.link(target,tmp);assert os.path.samefile(target,tmp)
    result=run(directory,'alias_check',label+'-native','--alias='+kind)
    expected='old' if kind in ['primary_backup','tmp_primary_open_fail','tmp_symlink','tmp_dangling'] else 'new'
    reader=run(directory,'read',label+'-fresh-read','--expect='+expected)
    records.append({'label':label,'directory':str(directory),'seed':initial,'status':'native verified','native':result,'reader':reader,'expected':expected})

manifest={'baseline':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
          'engine':'Godot 4.7.2 Windows native headless','source_freeze':'st3-durable-json-boundary-source-sha.json',
          'scope':'existing-run prepared writer only; real Windows hardlinks and forced-process termination; no production Main/world/producer installation, no power-loss proof',
          'standard_windows':4,'hardlink_windows':4,'alias_native_cases':5,'symbolic_cases':'not validated if skipped for Windows privileges',
          'records':records}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('COMPLETE: eight forced-process windows, five native aliases; symbolic permissions reported separately.',flush=True)
