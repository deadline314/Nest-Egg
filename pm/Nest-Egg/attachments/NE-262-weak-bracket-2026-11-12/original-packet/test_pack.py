import io,unittest,zipfile,hashlib
from pathlib import Path
from tempfile import TemporaryDirectory
from verify_pack import validate_archive,expect_rejected

class FailClosed(unittest.TestCase):
 def test_unexpected_acceptance_is_not_called_a_negative_pass(self):
  with self.assertRaises(AssertionError):expect_rejected(lambda:None,'deliberate nonfailure')
 def test_wrong_rejection_reason_is_refused(self):
  def fail():raise AssertionError('wrong thing')
  with self.assertRaises(AssertionError):expect_rejected(fail,'fixture','expected actual fault')
 def test_corrupt_archive_refused(self):
  with TemporaryDirectory() as directory:
   path=Path(directory)/'raw.zip';path.write_bytes(b'invalid archive')
   with self.assertRaises(AssertionError):validate_archive(path,{'sha256':'0'*64,'bytes':path.stat().st_size,'members':{}})
 def test_safe_archive_and_extra_member_rejected(self):
  with TemporaryDirectory() as directory:
   path=Path(directory)/'raw.zip'
   with zipfile.ZipFile(path,'w') as z:z.writestr('one',b'x')
   data=path.read_bytes();m={'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'members':{'one':{'sha256':hashlib.sha256(b'x').hexdigest(),'bytes':1}}}
   validate_archive(path,m).close()
   m['members']={}
   with self.assertRaises(AssertionError):validate_archive(path,m)

if __name__=='__main__':unittest.main()
