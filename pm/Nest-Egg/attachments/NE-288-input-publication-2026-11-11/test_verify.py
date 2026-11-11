import unittest
from verify import cause
class CauseControls(unittest.TestCase):
 def events(self):
  return [{'event':'put_down','carry_phase':1,'held':True,'physics':1,'process':1,'buttons':{'dash':[False,True],**{n:[False,False] for n in ['melee','block','shoot','interact']}},'stack':[{'function':n,'source':'res://game/player/'+('player_carry.gd' if n=='handle_input' else 'player.gd')} for n in ['put_down','handle_input','_process_normal','_physics_process']]},{'event':'after_phase_change_from_0','carry_phase':0,'held':False,'physics':1,'process':1}]
 def test_actual_cause(self):self.assertEqual(cause(self.events())['event'],'put_down')
 def test_missing_edge_rejected(self):
  events=self.events();events[0]['buttons']['dash']=[False,False]
  with self.assertRaises(AssertionError):cause(events)
 def test_wrong_caller_and_missing_transition_rejected(self):
  for what in ['caller','source','transition']:
   events=self.events()
   if what=='caller':events[0]['stack']=[]
   elif what=='source':events[0]['stack'][1]['source']='res://unrelated.gd'
   else:events=events[:1]
   with self.subTest(what=what),self.assertRaises(AssertionError):cause(events)
if __name__=='__main__':unittest.main()
