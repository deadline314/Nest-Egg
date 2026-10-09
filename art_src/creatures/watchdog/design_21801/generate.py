from pathlib import Path
import hashlib, json, os, sys
from PIL import Image

root = Path(__file__).resolve().parents[4]
work = root / 'art_src/creatures/watchdog/design_21801'
work.mkdir(parents=True, exist_ok=True)
os.environ['OUT_DIR'] = str(work / '_gen')
sys.path.insert(0, str(root / 'tools/comfyui'))
from comfy_api import qwen, QWEN_UNET, QWEN_CLIP, QWEN_VAE

prompt = ('A native RGBA game character illustration on completely transparent alpha-zero background. '
          'One complete quadrupedal armored robotic guard dog in strict lateral side view facing right, '
          'a low canine silhouette with a long horizontal torso, angular wolf-like snout and small sensor ears. '
          'Exactly four separate mechanical legs, two front legs and two rear legs, each with clearly distinct '
          'round hip or shoulder axle, one upper segment, one lower segment, one compact rubber paw. '
          'All four paws rest on the same floor height, far-side legs are offset slightly so their complete '
          'silhouettes can be read. Calm neutral standing pose, slightly bent articulations with natural canine '
          'proportions; rear upper thighs slope forward and the rear shin folds back. '
          'Matte slate-blue and off-white corporate armor, black exposed joint mechanisms, small restrained '
          'red sensor and circuit lights. One small dorsal gun turret with barrel pointing right, visibly '
          'separate from the dog head. One short mechanical tail on the rear. '
          'Hand-drawn 2D anime cyberpunk cel art: decisive thin black ink contours, simple two-tone hard '
          'shadow shapes, clean purposeful panel designs and modest wear. Readable, economical detail, '
          'no photorealism, airbrush gradients, shiny plastic, rendering noise or generic intricate greebles. '
          'No person, human hand, human boots, biped posture, additional limb, duplicate paw, ground line, '
          'cast shadow, background, checkerboard, magenta backdrop, text or watermark. '
          'Leave empty transparent margin around the entire head, tail, barrel and all four feet.')
record = {'status': 'UNACCEPTED SOURCE CANDIDATE', 'seed': 21801, 'steps': 30,
          'prompt': prompt, 'models': [QWEN_UNET, QWEN_CLIP, QWEN_VAE],
          'requested_canvas': [1536, 1024], 'references': [],
          'scope': 'appearance only; no story, encounter or gameplay edits'}
meta = work / 'source.json'
meta.write_text(json.dumps(record, indent=2) + '\n', encoding='utf8')
raw = qwen(prompt, w=1536, h=1024, steps=30, seed=21801, prefix='watchdog_design_21801')[0]
im = Image.open(raw)
assert im.size == (1536, 1024), im.size
record['output'] = {'path': str(raw.relative_to(root)), 'sha256': hashlib.sha256(raw.read_bytes()).hexdigest(),
                    'size': list(im.size), 'mode': im.mode}
if im.info.get('prompt'):
    raw.with_suffix('.workflow.json').write_text(json.dumps(json.loads(im.info['prompt']), indent=2) + '\n', encoding='utf8')
meta.write_text(json.dumps(record, indent=2) + '\n', encoding='utf8')
print(record['output'])
