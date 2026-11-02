"""Keep new chapter save ownership explicit and reject unsafe author declarations."""
import copy
import unittest
from build_ch2_story import spec
from build_ch3_story import spec as third_spec
from chapter_compiler import compile_chapter, CompileError

class ChapterPolicies(unittest.TestCase):
    def test_actual_source_enables_only_declared_producers(self):
        source=spec()
        original=copy.deepcopy(source)
        scenes=compile_chapter(source)['scenes']
        self.assertEqual({key:value['completion_policy'] for key,value in scenes.items() if 'completion_policy' in value},source.completion_policies)
        self.assertEqual(source,original)
        self.assertEqual(scenes['ch2_t_s05_gate']['results'],[{'kind':'flag','id':'ch2_gate_checked','value':True}])

    def test_other_chapter_uses_its_own_explicit_ownership(self):
        source=third_spec()
        scenes=compile_chapter(source)['scenes']
        self.assertEqual({key:value['completion_policy'] for key,value in scenes.items() if 'completion_policy' in value},source.completion_policies)

    def test_missing_producer_is_rejected(self):
        source=spec(); source.completion_policies={'missing':'main_terminal_results_v1'}
        with self.assertRaisesRegex(CompileError,'missing'):compile_chapter(source)

    def test_unknown_policy_is_rejected(self):
        for policy in ['atomic_v1',True,[],{}]:
            source=spec(); source.completion_policies={'ch2_t_s05_gate':policy}
            with self.subTest(policy=policy),self.assertRaisesRegex(CompileError,'ch2_t_s05_gate'):compile_chapter(source)

    def test_dispatcher_cannot_claim_a_terminal_result(self):
        source=spec(); source.completion_policies={'ch2_dispatch_patroller':'main_terminal_results_v1'}
        with self.assertRaisesRegex(CompileError,'ch2_dispatch_patroller'):compile_chapter(source)

    def test_choice_cannot_claim_a_terminal_result(self):
        source=spec()
        ident=next(key for key,value in source.source.segments.items() if value.options)
        source.completion_policies={ident:'main_terminal_results_v1'}
        with self.assertRaisesRegex(CompileError,ident):compile_chapter(source)

if __name__=='__main__':unittest.main()
