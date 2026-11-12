import unittest
import numpy as np
from reader import point,segments,region

class Geometry(unittest.TestCase):
 def actor(self):
  return {'id':'fixture','main_enabled':True,'draw_to_viewport':[2,0,0,-3,50,80],'parts':[{'id':'head','offset':[1,2],'size':[8,10],'mult':1.5,'enabled':True},{'id':'arm','offset':[12,2],'size':[4,6],'mult':1,'enabled':True}]}
 def test_nonzero_origin_and_negative_axis(self):
  np.testing.assert_array_equal(point([2,0,0,-3,50,80],[1,2]),[52,74])
 def test_exact_original_corner_count(self):
  self.assertEqual(len(segments(self.actor(),True)),8)
 def test_debug_contains_weak_and_ordinary_rects(self):
  lines=segments(self.actor(),False);self.assertEqual(len(lines),8);self.assertEqual(sum(l['weak'] for l in lines),4)
 def test_disabled_debug_part_excluded_but_legacy_not_per_part_gated(self):
  actor=self.actor();actor['parts'][0]['enabled']=False
  self.assertEqual(len(segments(actor,False)),4);self.assertEqual(len(segments(actor,True)),8)
 def test_main_hurtbox_disables_original_corner(self):
  actor=self.actor();actor['main_enabled']=False;self.assertEqual(segments(actor,True),[])
 def test_wrong_projection_rejected_without_modifying_pixels(self):
  line=segments(self.actor(),True)[0]
  region(line,200,200)
  with self.assertRaises(AssertionError):region(line,200,200,1000)

if __name__=='__main__':unittest.main()
