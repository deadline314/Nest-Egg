"""CLI-level CPU regression: existing limb-zone runtime setting survives source rebuilds."""
import contextlib,io,json,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
import numpy as np
from PIL import Image
import cut_layers as cut

class LimbZoneTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.work=self.root/'source';(self.work/'07_refined').mkdir(parents=True)
        image=np.zeros((16,16,4),np.uint8);image[2:15,3:13]=[75,96,109,255];Image.fromarray(image).save(self.work/'base_rgba.png');Image.fromarray(image).save(self.work/'07_refined/pelvis.png')
        self.spec={'id':'example','display_name':'Example','scale':1,'tex_px_per_wp':1,'illustration_px_per_wp':1,'ground_y':16,'joints':{'hip':[8,8],'bottom':[8,15]},'parts':{'pelvis':{'from':'hip','to':'bottom','mode':'upright','uses':[{'name':'pelvis','bone':'hip','z':0}]}},'bones':[{'name':'hip','parent':''}],'glow':{},'weapon_anchor':{'bone':'hip','from':'hip','to':'bottom','dx':0,'dy':0,'reach':1}}
        self.output=contextlib.redirect_stdout(io.StringIO());self.output.__enter__();self.addCleanup(self.output.__exit__,None,None,None)
    def execute(self,spec,name,module=cut):
        spec_path=self.root/f'{name}.json';spec_path.write_text(json.dumps(spec),encoding='utf8');out=self.root/name;out.mkdir(exist_ok=True)
        argv=['cut_layers.py','--spec',str(spec_path),'--work',str(self.work),'--char',str(out/'character'),'--rig',str(out/'rig.json')]
        with patch.object(sys,'argv',argv):module.main()
        return out
    def test_unset_outputs_preserve_original_delivery(self):
        # Frozen e6017a0fc output; HEAD would compare the converter to itself after commit.
        expected = Path(__file__).parent / 'fixtures/limb_zone_defaults'
        actual = self.execute(self.spec, 'after')
        self.assertEqual((actual/'rig.json').read_bytes().replace(b'\r\n', b'\n'), (expected/'rig.json').read_bytes().replace(b'\r\n', b'\n'))
        self.assertEqual((actual/'character/character.json').read_bytes().replace(b'\r\n', b'\n'), (expected/'character.json').read_bytes().replace(b'\r\n', b'\n'))
        with Image.open(actual/'character/parts/pelvis.png') as result, Image.open(expected/'pelvis.png') as original:
            self.assertEqual(result.mode, original.mode)
            self.assertEqual(result.size, original.size)
            self.assertEqual(result.tobytes(), original.tobytes())
    def test_runtime_range_values_are_exported(self):
        for value in [.05,.2,.4,.6]:
            with self.subTest(value=value):
                out=self.execute(self.spec|{'limb_zone':value},f'valid{value}')
                self.assertEqual(json.loads((out/'rig.json').read_text(encoding='utf8'))['limb_zone'],value)
    def test_invalid_data_does_not_replace_existing_delivery(self):
        for index,value in enumerate([True,False,None,'0.2',[],{},float('nan'),float('inf'),float('-inf'),.049,.601,-1]):
            with self.subTest(value=value):
                name=f'bad{index}';out=self.root/name;(out/'character/parts').mkdir(parents=True);rig=out/'rig.json';rig.write_text('retained rig');part=out/'character/parts/retained.png';part.write_bytes(b'retained material')
                with self.assertRaisesRegex(ValueError,'spec.limb_zone'):
                    self.execute(self.spec|{'limb_zone':value},name)
                self.assertEqual(rig.read_text(),'retained rig');self.assertEqual(part.read_bytes(),b'retained material');self.assertFalse((out/'character/parts.tmp').exists())

if __name__=='__main__':unittest.main()
