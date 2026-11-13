import unittest
from PIL import Image
from verify_comparison_pages import exact_crop,contiguous
class PageControls(unittest.TestCase):
 def test_exact_source_pixels(self):
  source=Image.new('RGB',(2,2),'red');page=Image.new('RGB',(5,5),'black');page.paste(source,(1,1));exact_crop(page,source,[1,1,2,2])
 def test_shift_and_changed_pixel_rejected(self):
  source=Image.new('RGB',(2,2),'red');page=Image.new('RGB',(5,5),'black');page.paste(source,(1,1))
  with self.assertRaises(AssertionError):exact_crop(page,source,[2,1,2,2])
  page.putpixel((1,1),(255,0,1))
  with self.assertRaises(AssertionError):exact_crop(page,source,[1,1,2,2])
 def test_missing_and_nonconsecutive_frames_rejected(self):
  frames=[{'readback':{'tick':i}} for i in range(6)];contiguous(frames)
  for changed in [frames[:5],frames[:3]+[{'readback':{'tick':9}}]+frames[4:]]:
   with self.subTest(changed=changed),self.assertRaises(AssertionError):contiguous(changed)
if __name__=='__main__':unittest.main()
