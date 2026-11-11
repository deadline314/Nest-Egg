import copy,json,unittest,zipfile
from verify import HERE,actor_checks,safe_member,verify

class EvidenceControls(unittest.TestCase):
 def actor(self):
  with zipfile.ZipFile(HERE/'raw.zip') as archive:return json.loads(archive.read('original-actor-controls/boss-drops.json'))
 def test_real_packet_rechecks_offline(self):self.assertEqual(verify()['candidate_independent_checks'],607)
 def test_janus_health_signal_is_not_silently_relabelled_as_no_death(self):
  data=self.actor();next(r for r in data['records'] if r.get('actor')=='janus')['health_died_signals']=0
  with self.assertRaises(AssertionError):actor_checks(data)
 def test_missing_drop_positive_control_is_rejected(self):
  data=self.actor();next(r for r in data['records'] if r.get('actor')=='grunt-positive-control')['published_credit_pickups']=[]
  with self.assertRaises(AssertionError):actor_checks(data)
 def test_repeated_reward_is_not_accepted(self):
  data=self.actor();next(r for r in data['records'] if 'transaction' in r)['after_second']+=120
  with self.assertRaises(AssertionError):actor_checks(data)
 def test_unsafe_archive_paths_are_rejected(self):
  for name in ['../escape','/absolute','C:/escape','folder\\..\\escape']:
   with self.assertRaises(AssertionError):safe_member(name)

if __name__=='__main__':unittest.main()
