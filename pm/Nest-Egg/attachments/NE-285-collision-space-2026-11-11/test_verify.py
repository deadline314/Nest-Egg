import copy,json,tempfile,unittest,zipfile
from pathlib import Path
from verify import ledger
HERE=Path(__file__).resolve().parent
def payload(name,prefix):
 with zipfile.ZipFile(HERE/name) as z:
  return json.loads(z.read(prefix+"/order-ledger.json")),json.loads(z.read(prefix+"/receipt.json"))
def original_result(name,prefix,retained):
 data,receipt=payload(name,prefix)
 with tempfile.TemporaryDirectory() as td:
  p=Path(td);(p/"order-ledger.json").write_bytes(json.dumps(data).encode());(p/"receipt.json").write_bytes(json.dumps(receipt).encode())
  return ledger(p,retained)
class LedgerControls(unittest.TestCase):
 def test_rejects_independent_corruptions(self):
  original,receipt=payload("formal-contact-headless-green.zip","green")
  changes=["no_hit","no_thaw","body_removed","area_removed","wrong_space","processing","animator_advanced","source_drift"]
  with tempfile.TemporaryDirectory() as td:
   root=Path(td)
   for case in changes:
    with self.subTest(case=case):
     data=copy.deepcopy(original);r=copy.deepcopy(receipt);events=data["events"];hit=next(x for x in events if x["event"]=="hit_confirmed_inside_hit_pass")
     if case=="no_hit":data["events"]=[x for x in events if x is not hit]
     elif case=="no_thaw":data["events"]=events[:events.index(hit)+1]+[x for x in events[events.index(hit)+1:] if x["player_frozen"]]
     elif case=="body_removed":hit["target_physics"]["body_in_space"]=False
     elif case=="area_removed":hit["target_physics"]["hurtbox_space"]=0
     elif case=="wrong_space":hit["target_physics"]["expected_space"]+=1
     elif case=="processing":hit["player_physics"]["body_can_process"]=True
     elif case=="animator_advanced":next(x for x in events[events.index(hit)+1:] if x["player_frozen"])["animator_time"]+=0.1
     elif case=="source_drift":r["after"]["autoload/fx.gd"]="0"*64
     (root/"receipt.json").write_bytes(json.dumps(r).encode());(root/"order-ledger.json").write_bytes(json.dumps(data).encode())
     with self.assertRaises((AssertionError,StopIteration)):ledger(root,True)
 def test_accepts_original_red_and_final_green(self):
  self.assertEqual(original_result("formal-contact-headless-green.zip","green",True)["checks"],16)
  self.assertEqual(original_result("formal-contact-red.zip","red",False)["checks"],16)
 def test_native_checks_order_inside_the_same_physics_tick(self):
  data,receipt=payload("formal-contact-native-green.zip","native");rows=data["events"];i=next(i for i,x in enumerate(rows) if x["event"]=="hit_confirmed_inside_hit_pass");post=next(x for x in rows[i+1:] if not x["player_frozen"])
  self.assertTrue(any(x["player_frozen"] and x["order"]<post["order"] and x["physics"]==post["physics"] for x in rows[i+1:]))
if __name__=="__main__":unittest.main()
