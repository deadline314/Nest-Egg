"""Draw a proposed neutral side torso construction guide, never a game texture."""
import json
import hashlib
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent/'silhouette-guide'
OUT.mkdir(exist_ok=True)
start = (35,40)
curves = [
    [(35,40),(44,41),(55,45),(62,48)],
    [(62,48),(62,61),(64,73),(65,82)],
    [(65,82),(82,93),(91,106),(109,116)],
    [(109,116),(128,122),(138,126),(147,134)],
    [(147,134),(166,147),(181,166),(184,188)],
    [(184,188),(188,209),(166,226),(144,235)],
    [(144,235),(143,264),(145,301),(143,336)],
    [(143,336),(113,336),(69,336),(38,336)],
    [(38,336),(40,320),(43,306),(43,291)],
    [(43,291),(43,276),(40,260),(35,247)],
    [(35,247),(29,231),(25,220),(22,211)],
    [(22,211),(14,194),(9,170),(5,149)],
    [(5,149),(1,133),(6,115),(8,106)],
    [(8,106),(15,94),(24,91),(25,86)],
    [(25,86),(30,71),(33,51),(35,40)],
]
points = []
for curve in curves:
    for step in range(31):
        t = step/30
        points.append(tuple(sum(curve[i][axis]*[(1-t)**3,3*(1-t)**2*t,3*(1-t)*t*t,t**3][i] for i in range(4)) for axis in range(2)))
image = Image.new('RGB',(864,1408),'white')
draw = ImageDraw.Draw(image)
scaled = [(round(x*4)+32,round(y*4)+32) for x,y in points]
draw.polygon(scaled, fill='#dedede')
draw.line(scaled+[scaled[0]], fill='#202020', width=8)
image.save(OUT/'neutral-torso-silhouette-proposal.png')
svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 336"><rect width="200" height="336" fill="white"/><path d="M35 40 '
svg += ' '.join('C '+' '.join(f'{x},{y}' for x,y in curve[1:]) for curve in curves)
svg += ' Z" fill="#dedede" stroke="#202020" stroke-width="2"/></svg>'
(OUT/'neutral-torso-silhouette-proposal.svg').write_text(svg)
record = {'status':'PROPOSED_CONSTRUCTION_GUIDE_NOT_ANATOMY_ACCEPTANCE_OR_GAME_ART',
          'reference_crop':[200,336], 'output':[864,1408], 'margin_pixels':32,
          'purpose':'Constrain a new torso contour; preserve formal rest attachment axes, do not warp approved art.',
          'formal_neck_axis_local':[47,90], 'formal_waist_axis_local':[55,306],
          'formal_shoulder_pivot_local':[15,124],
          'axis_source':'approved rin_side spec minus formal crop offset [357,124]',
          'contour':'manual proposed construction, requires full-color anatomy review before use',
          'sha256':hashlib.sha256((OUT/'neutral-torso-silhouette-proposal.png').read_bytes()).hexdigest()}
(OUT/'guide.json').write_text(json.dumps(record,indent=2))
assert image.size==(864,1408) and all(0 <= x <= 200 and 0 <= y <= 336 for curve in curves for x,y in curve)
print(record)
