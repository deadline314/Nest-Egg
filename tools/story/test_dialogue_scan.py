"""Self-check for dialogue_scan.py: python tools/story/test_dialogue_scan.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dialogue_scan as ds

assert ds.fragment_reason("門開了。下去看看。"), "two bare short sentences"
assert ds.fragment_reason("地點，倉庫，目標，盤。"), "comma-chopped noun list"
assert not ds.fragment_reason("老 K 每次都問：帶傘了嗎。"), "space inside a name is not a clause break"
assert not ds.fragment_reason("葉的手背上寫著一行字：「他叫阿翰。你愛他。」"), "quoted words are not the speaker's clauses"
assert not ds.fragment_reason("這次要去碼頭倉庫，把保險箱裡的資料盤拿回來。")
total, _, findings, _ = ds.scan(0)
assert total > 1000 and all(f[0] in ("fragment", "long", "voice") for f in findings)
assert any(r["level"] == "ch1_street" for r in ds.areas())
print("dialogue_scan ok:", total, "lines,", len(findings), "findings")
