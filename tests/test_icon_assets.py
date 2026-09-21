import hashlib
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "AzerothTravelTracker" / "Media"
BUILDER_PATH = ROOT / "tools" / "Build-IconAssets.py"
ASSET_NAMES = ("ATTLogo.tga", "Overview.tga", "ByLevel.tga")
CORNER_BOXES = (
    (range(0, 12), range(0, 12)),
    (range(52, 64), range(0, 12)),
    (range(0, 12), range(52, 64)),
    (range(52, 64), range(52, 64)),
)


def load_builder():
    spec = importlib.util.spec_from_file_location("build_icon_assets", BUILDER_PATH)
    module = importlib.util.module_from_spec(spec)
    previous = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = previous
    return module


def image_pixels(image):
    return [
        image.getpixel((x, y))
        for y in range(image.height)
        for x in range(image.width)
    ]


class IconAssetTests(unittest.TestCase):
    def test_committed_icons_have_antialiased_transparent_corners(self):
        for asset_name in ASSET_NAMES:
            with self.subTest(asset=asset_name):
                with Image.open(MEDIA / asset_name) as image:
                    self.assertEqual((64, 64), image.size)
                    self.assertEqual("RGBA", image.mode)

                    pixels = image_pixels(image)
                    alphas = [alpha for _, _, _, alpha in pixels]
                    partial_pixels = [
                        pixel for pixel in pixels if 0 < pixel[3] < 255
                    ]
                    white_fringe = [
                        pixel
                        for pixel in partial_pixels
                        if min(pixel[:3]) >= 245
                        and max(pixel[:3]) - min(pixel[:3]) <= 12
                    ]

                    self.assertEqual(
                        [0, 0, 0, 0],
                        [
                            image.getpixel((0, 0))[3],
                            image.getpixel((63, 0))[3],
                            image.getpixel((0, 63))[3],
                            image.getpixel((63, 63))[3],
                        ],
                    )
                    self.assertGreaterEqual(alphas.count(0), 80)
                    self.assertGreaterEqual(len(partial_pixels), 16)
                    for x_range, y_range in CORNER_BOXES:
                        transparent = sum(
                            image.getpixel((x, y))[3] == 0
                            for y in y_range
                            for x in x_range
                        )
                        self.assertGreaterEqual(transparent, 16)
                    self.assertEqual(255, image.getpixel((32, 32))[3])
                    self.assertEqual([], white_fringe)

    def test_rebuild_is_deterministic_and_matches_committed_assets(self):
        builder = load_builder()
        original_target = builder.TARGET
        try:
            with tempfile.TemporaryDirectory() as first_dir, tempfile.TemporaryDirectory() as second_dir:
                builder.TARGET = Path(first_dir)
                builder.main()
                first = {
                    name: (Path(first_dir) / name).read_bytes()
                    for name in ASSET_NAMES
                }

                builder.TARGET = Path(second_dir)
                builder.main()
                second = {
                    name: (Path(second_dir) / name).read_bytes()
                    for name in ASSET_NAMES
                }
        finally:
            builder.TARGET = original_target

        for asset_name in ASSET_NAMES:
            with self.subTest(asset=asset_name):
                self.assertEqual(first[asset_name], second[asset_name])
                self.assertEqual(
                    hashlib.sha256(first[asset_name]).digest(),
                    hashlib.sha256((MEDIA / asset_name).read_bytes()).digest(),
                )


if __name__ == "__main__":
    unittest.main()
