"""Portable read-only verification of raw short evidence; no engine/worktree."""
import hashlib,json,pathlib,zipfile
R=pathlib.Path(__file__).resolve().parent
index=json.loads((R/'short-index.json').read_text(encoding='utf8'))
def sha(stream):
    h=hashlib.sha256()
    for block in iter(lambda:stream.read(1048576),b''):h.update(block)
    return h.hexdigest()
with (R/index['archive']['name']).open('rb') as stream:assert sha(stream)==index['archive']['sha256']
with zipfile.ZipFile(R/index['archive']['name']) as z:
    assert set(z.namelist())==set(index['members'])
    for name,meta in index['members'].items():
        info=z.getinfo(name)
        assert info.file_size==meta['bytes'] and info.CRC==meta['crc32'],name
        with z.open(name) as stream:assert sha(stream)==meta['sha256'],name
    def data(name):return json.loads(z.read(name))
    m=data('candidate-v4/manifest.json')
    assert m==json.loads((R/'manifest.json').read_text(encoding='utf8'))
    for name,meta in m['files'].items():
        assert hashlib.sha256(z.read('candidate-v4/source/'+name)).hexdigest()==meta['sha256']
        assert hashlib.sha256((R/'source'/name).read_bytes()).hexdigest()==meta['sha256']
    for kind,row in m['short'].items():
        root=row['path'];receipt=data(root+'/receipt.json')
        assert receipt['exit']==0 and receipt['script_errors']==0 and receipt['source_fixed'] and receipt['completed'],kind
        for name,meta in m['files'].items():assert receipt['source_after'][name]==meta['sha256'],(kind,name)
    assert m['short']['local']['result']=={'checks':140,'failures':0}
    matrix=data(m['short']['matrix']['path']+'/results.json')
    assert matrix['comparisons']==5764 and matrix['conditions']==524 and matrix['failures']==0 and matrix['extra_callback_reads']==3742 and matrix['no_state_mutation']
    for row in matrix['rows']:
        assert not row['schema_error'] and row['old_default']==row['new_default']
        assert all(v['equal'] and v['old']==v['new'] and v['new_reads']==row['leaf_occurrences'] for v in row['results'])
    facts=data(m['short']['run']['path']+'/results.json')
    assert facts['confirmed_counterexamples']==0 and facts['controls_failed']==0 and facts['restored']
    assert facts['state_before']==facts['state_after']
    for kind in ['derived','alias']:
        result=data(m['short'][kind]['path']+'/results.json')
        assert result['checks']==8 and result['failures']==0 and all(r['actual']==r['expected'] for r in result['rows'])
    admission=data(m['short']['admission']['path']+'/results.json')
    assert admission['checks']==3 and admission['failures']==0 and admission['state_restored'] and admission['actual_producers_restored'] and admission['reports_and_resource_cache_reset']
    for root,failures in [('run-1794480844882894100',14),('derived-1794483473719688800',5),('alias-1794483879213912700',5)]:
        receipt=data(root+'/receipt.json');result=data(root+'/results.json')
        assert receipt['exit']==1 and receipt['script_errors']==0 and receipt['source_fixed']
        assert result.get('confirmed_counterexamples',result.get('failures'))==failures
    print('PASS: archive SHA/CRC; final3-source provenance;140/0;5764/0 with3742 intentional extra reads;23rows;derived/alias8/0;load_all3/0; original14+5+5 red observations retained. Long affected is separate.')
