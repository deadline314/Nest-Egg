"""Point prompts are constraints, not proof of whole-part ownership."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from PIL import Image
import sam_masks


class PointMaskValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sam-point-validation-')
        self.root = Path(self.temp.name)
        self.source = self.root / 'source.png'
        Image.new('RGB', (4, 4), 'gray').save(self.source)
        self.out = self.root / 'published'
        self.out.mkdir()
        self.old = self.out / 'hand.png'
        self.old.write_bytes(b'previous-reviewed-mask')
        self.jobs = {'hand': {'pos': [(1, 1)], 'neg': [(2, 2)]},
                     'boot': {'pos': [(1, 1)], 'neg': [(2, 2)]}}
        self.bad = None
        self.size = (4, 4)

    def tearDown(self):
        self.temp.cleanup()

    def run_model(self, graph, job):
        paths = []
        for i, name in enumerate(self.jobs):
            mask = Image.new('L', self.size)
            mask.putpixel((1, 1), 255)
            if name == 'boot' and self.bad == 'negative':
                mask.putpixel((2, 2), 255)
            if name == 'boot' and self.bad == 'positive':
                mask.putpixel((1, 1), 0)
            path = self.root / f'{job}_s{i}_0.png'
            mask.save(path)
            paths.append(path)
        return list(reversed(paths))

    def segment(self):
        with patch.object(sam_masks, 'run', self.run_model), \
                patch.object(sam_masks, 'upload', return_value='source'), \
                patch.object(sam_masks.comfy_guard, 'ensure_server'):
            return sam_masks.segment_points(str(self.source), str(self.out), self.jobs)

    def assert_rejected_atomically(self, message):
        with self.assertRaisesRegex(ValueError, message):
            self.segment()
        self.assertEqual(self.old.read_bytes(), b'previous-reviewed-mask')
        self.assertFalse((self.out / 'boot.png').exists())

    def test_valid_batch_maps_execution_order(self):
        result = self.segment()
        self.assertEqual(list(result), ['hand', 'boot'])
        for path in result.values():
            with Image.open(path) as mask:
                self.assertEqual(mask.getpixel((1, 1)), 255)
                self.assertEqual(mask.getpixel((2, 2)), 0)

    def test_one_wrong_negative_pixel_rejects_whole_batch(self):
        self.bad = 'negative'
        self.assert_rejected_atomically(r'boot.*neg.*2.*2')

    def test_one_missing_positive_pixel_rejects_whole_batch(self):
        self.bad = 'positive'
        self.assert_rejected_atomically(r'boot.*pos.*1.*1')

    def test_wrong_native_mask_dimensions_reject_whole_batch(self):
        self.size = (5, 4)
        self.assert_rejected_atomically(r'hand.*size')

    def test_out_of_bounds_point_rejects_before_gpu(self):
        self.jobs['boot']['neg'] = [(4, 2)]
        with patch.object(sam_masks.comfy_guard, 'ensure_server') as server:
            self.assert_rejected_atomically(r'boot.*neg.*outside')
            server.assert_not_called()

    def test_classifier_threshold_does_not_modify_raw_mask(self):
        def soft_mask(graph, job):
            paths = self.run_model(graph, job)
            for path in paths:
                with Image.open(path) as image:
                    mask = image.copy()
                mask.putpixel((1, 1), 128)
                mask.putpixel((2, 2), 127)
                mask.save(path)
            return paths
        with patch.object(sam_masks, 'run', soft_mask), \
                patch.object(sam_masks, 'upload', return_value='source'), \
                patch.object(sam_masks.comfy_guard, 'ensure_server'):
            result = sam_masks.segment_points(str(self.source), str(self.out), self.jobs)
        for path in result.values():
            with Image.open(path) as mask:
                self.assertEqual(mask.getpixel((1, 1)), 128)
                self.assertEqual(mask.getpixel((2, 2)), 127)


if __name__ == '__main__':
    unittest.main()
