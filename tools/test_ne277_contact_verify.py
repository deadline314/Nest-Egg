import copy
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image
from ne277_contact_verify import verify_contacts, overlap
import numpy as np


class ContactEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        art = {'texture':'res://art/weapons/melee/melee_maul.png','size':[10,4],'grip':[0,2]}
        self.write('source/data/weapon_art/melee.json', {'weapons':{'melee_maul':art}})
        self.definition = {'active':.2,'damage':2,'hits':[{'at':0,'length':.2}],'sounds':{'hit':'impact'}}
        self.spec = {'mode':'repeat','attack':'test'}
        self.write('source/data/melee/hydraulic_maul.json', {'attacks':{'test':self.definition},'hold':self.spec,'contact_span':[5,10]})
        image = Image.new('RGBA', (10,4))
        for x in range(5,10):
            for y in range(4): image.putpixel((x,y), (220,90,30,255))
        path = self.root/'source/art/weapons/melee/melee_maul.png'
        path.parent.mkdir(parents=True)
        image.save(path)
        mesh = [[5,-2],[10,-2],[10,2],[5,-2],[10,2],[5,2]]
        hit = {'current':mesh,'previous':copy.deepcopy(mesh),'target_transform':[1,0,0,1,7,0],'target_size':[1,2], 'target_area_in_space':True,
               'phase':2,'mesh_tick':1,'tick':1,'previous_tick':1,'progress':.55,'visual_progress':.55,'attacker_matches':True,'team':0,'source':'melee',
               'from_fraction':0,'to_fraction':1,'window':0,'resolved_from':.08,'resolved_to':.1,'time':.1,'amount':2,'weak':False,'part':'',
               'contact_span':[5,10],'draw_transform':[1,0,0,1,0,0],'point':[7,0]}
        self.data = {'checks':2,'failures':[],'rows':[{'name':'maul/1/test','weapon':'maul','move':'test','held':False,'contact_control':'',
                    'contact_definition':self.definition,'contact_hold_spec':self.spec,'contact_hits':[hit],'contact_sounds':[{'matching':True,'id':'impact'}]}]}

    def write(self, name, value):
        path = self.root/name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(json.dumps(value).encode())

    def verify(self, data):
        return verify_contacts(data, {'maul/1/test'}, self.root)

    def test_valid_source_head_contact(self):
        self.assertEqual([], self.verify(self.data))

    def test_fail_closed_missing_and_corrupt_observations(self):
        mutations = [lambda d:d.update(rows=[]), lambda d:d.update(failures=['broken']),
                     lambda d:d['rows'][0].update(contact_hits=[]),lambda d:d['rows'][0].update(contact_control='early-broad'),
                     lambda d:d['rows'][0].update(contact_sounds=[])]
        bad_fields = {'mesh_tick':0,'visual_progress':.4,'target_area_in_space':False,'attacker_matches':False,'source':'bullet',
                      'phase':3,'amount':99,'weak':True,'point':[100,0],'resolved_from':.3,'from_fraction':-.1,
                      'current':[],'contact_span':[-512,512],'time':float('nan'),'target_transform':[0]*6}
        for field, value in bad_fields.items():
            mutations.append(lambda d,k=field,v=value:d['rows'][0]['contact_hits'][0].update({k:v}))
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                bad = copy.deepcopy(self.data); mutate(bad)
                self.assertTrue(self.verify(bad))

    def test_cannot_fill_transparent_hole_or_claim_shaft(self):
        path = self.root/'source/art/weapons/melee/melee_maul.png'
        image = Image.open(path).convert('RGBA'); image.putpixel((7,1),(0,0,0,0)); image.save(path)
        self.assertTrue(self.verify(self.data))

    def test_fast_crossing_sweep_uses_both_poses(self):
        from ne277_contact_verify import swept_contact
        hit = self.data['rows'][0]['contact_hits'][0]
        hit['previous'] = [[x-10,y] for x,y in hit['current']]
        half = np.asarray(hit['target_size'])/2
        self.assertFalse(overlap(np.array(hit['previous'][:3])-[7,0], half))
        self.assertTrue(swept_contact(hit))
        hit['from_fraction'] = 0; hit['to_fraction'] = .1
        self.assertFalse(swept_contact(hit))


if __name__ == '__main__':
    unittest.main()
