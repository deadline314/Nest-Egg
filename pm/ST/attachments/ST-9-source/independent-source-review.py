import hashlib
import importlib.util
import itertools
import json
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path('C:/tmp/Nest-Egg-ch1-formal-story')
sys.dont_write_bytecode = True
sys.path.insert(0, str(root / 'tools/story'))
import ch1_closure as closure
import build_ch1_story as current

source = closure.build_source()
assert not closure.validate_source(source)
accepted = {}
for bits in itertools.product((False, True), repeat=5):
    ids = {ident for ident, enabled in zip(closure.MEAL_RECEIPTS, bits) if enabled}
    try:
        state = closure.author_account_state(ids)
        assert closure.author_account_state(ids | {'ch1.daily_dinner', 'ch1.commission.settled'}) == state
        accepted[tuple(sorted(ids))] = state
    except ValueError:
        pass
assert len(accepted) == 6
papers = []
for index, (ident, document) in enumerate(source.documents.items()):
    path = root / 'data/story_items' / (ident + '.tres')
    text = path.read_text(encoding='utf-8')
    # Order is presentation metadata, kept in the authored source resource.
    order = int(next(line.split(' = ')[1] for line in text.splitlines() if line.startswith('order = ')))
    assert text == closure.render_document_resource(ident, document, order)
    papers.append(ident)
loaded = [root / 'data/story/ch1_kasa.json', *sorted((root / 'data/cutscene/stages').glob('*.json'))]
before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in loaded}
assert current.main(['--production']) == 2
assert before == {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in loaded}
original_text = subprocess.run(['git', 'show', '53664537:tools/story/build_ch1_story.py'], cwd=root,
                              check=True, capture_output=True, text=True, encoding='utf-8').stdout
with tempfile.TemporaryDirectory(prefix='ne-ch1-root-', dir='C:/tmp') as temp:
    temp = Path(temp)
    old_path = temp / 'original.py'
    old_path.write_text(original_text, encoding='utf-8')
    spec = importlib.util.spec_from_file_location('original_ch1', old_path)
    original = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(original)
    outputs = []
    for name, module in [('original', original), ('current', current)]:
        folder = temp / name
        folder.mkdir()
        module.ROOT = str(root)
        module.OUT = str(folder / 'story.json')
        module.STAGE_DIR = str(folder / 'stages')
        module.main([]) if name == 'current' else module.main()
        assert len(module.SCENES) == 36
        assert module.build() is None
        assert len(module.SCENES) == 36
        outputs.append({str(path.relative_to(folder)): json.loads(path.read_text(encoding='utf-8'))
                        for path in folder.rglob('*.json')})
    assert outputs[0] == outputs[1]
assert before == {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in loaded}
print(json.dumps({'segments': len(source.segments), 'decisions': sum(bool(x.options) for x in source.segments.values()),
                  'quest_semantics': len(source.quests), 'legal_meal_subsets': len(accepted), 'rejected_meal_subsets': 26,
                  'papers': papers, 'legacy_scenes_unchanged': 36, 'legacy_stage_outputs_unchanged': len(outputs[0])-1,
                  'loaded_files_unchanged': len(loaded), 'runtime_verified': False}, ensure_ascii=False))
