import io,unittest,wave
from verify import expected,extract,pcm_payload
class PacketControls(unittest.TestCase):
 def test_expected_matrix_does_not_derive_acceptance_from_observed_rows(self):
  profile={'combo':['first','second'],'extension':{'attack':'tail'},'hold':{'attack':'held'}}
  normal=expected(profile,'test');feedback=expected(profile,'test',True)
  self.assertEqual(len(normal),8);self.assertEqual(len(feedback),8)
  self.assertIn('test/-1/held-held',normal)
  self.assertIn('test/1/second/reduced-true',feedback)
 def test_unsafe_zip_name_rejected_before_extract(self):
  class Archive:
   extracted=False
   def namelist(self):return ['../escaped.txt']
   def extractall(self,target):self.extracted=True
  archive=Archive()
  with self.assertRaises(AssertionError):extract(archive,None)
  self.assertFalse(archive.extracted)
 def test_actual_pcm_format_required(self):
  for channels in [1,2]:
   memory=io.BytesIO()
   with wave.open(memory,'wb') as stream:
    stream.setnchannels(channels);stream.setsampwidth(2);stream.setframerate(48000);stream.writeframes(b'\0\0'*channels*4)
   if channels==2:self.assertEqual(len(pcm_payload(memory.getvalue())),16)
   else:
    with self.assertRaises(AssertionError):pcm_payload(memory.getvalue())
if __name__=='__main__':unittest.main()
