import unittest
from verify import transform_rect,intersects,reproject
class TransformControls(unittest.TestCase):
 def test_nonzero_axes_and_origin(self):self.assertEqual(transform_rect([1,2,3,4],[2,0,0,3,10,-7]),[12,-1,6,12])
 def test_true_wrong_position(self):
  self.assertTrue(intersects([416,196,146,34],[479,202,184,14]))
  self.assertFalse(intersects([416,196,146,34],[619,206,192,15]))
 def test_stale_transform_and_missing_records_rejected(self):
  for rows in [[],[{'actual_row':[1,2,3,4],'canvas':[2,0,0,3,10,-7],'row_screen':[13,-1,6,12]}]]:
   with self.subTest(rows=rows),self.assertRaises(AssertionError):reproject(rows)
if __name__=='__main__':unittest.main()
