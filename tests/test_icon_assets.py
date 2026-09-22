import hashlib
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "AzerothTravelMetrics" / "Media"
BUILDER_PATH = ROOT / "tools" / "Build-IconAssets.py"
ASSET_NAMES = ("ATMLogo.tga", "Overview.tga", "ByLevel.tga")
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
    def test_builder_uses_normalized_boot_crop_and_preserves_tab_sources(self):
        builder = load_builder()

        self.assertEqual(
            {
                "azeroth_travel_metrics.jpg": {
                    "target": "ATMLogo.tga",
                    "mask": "circle",
                    "isolate": "boot",
                    "crop": (
                        540 / 2048,
                        810 / 2048,
                        880 / 2048,
                        1150 / 2048,
                    ),
                },
                "overview_icon.jpg": {
                    "target": "Overview.tga",
                    "mask": "rounded",
                },
                "by_level_icon.jpg": {
                    "target": "ByLevel.tga",
                    "mask": "rounded",
                },
            },
            builder.ASSETS,
        )

    def test_atm_logo_retains_boot_contrast_at_actual_minimap_size(self):
        with Image.open(MEDIA / "ATMLogo.tga") as source:
            image = (
                source.convert("RGBA")
                .convert("RGBa")
                .resize((20, 20), Image.Resampling.LANCZOS)
                .convert("RGBA")
            )

        opaque = {
            (x, y): image.getpixel((x, y))
            for y in range(image.height)
            for x in range(image.width)
            if image.getpixel((x, y))[3] >= 128
        }
        dark_outline = {
            point
            for point, pixel in opaque.items()
            if max(pixel[:3]) <= 75
        }
        boot_brown = {
            point
            for point, pixel in opaque.items()
            if pixel[0] - pixel[1] >= 24
            and pixel[1] - pixel[2] >= 4
            and 45 <= sum(pixel[:3]) / 3 <= 180
        }
        brown_next_to_outline = {
            (x, y)
            for x, y in boot_brown
            if any(
                (x + dx, y + dy) in dark_outline
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
            )
        }
        adjacent_contrasts = [
            sum(abs(pixel[channel] - opaque[neighbor][channel]) for channel in range(3))
            / 3
            for (x, y), pixel in opaque.items()
            for neighbor in ((x + 1, y), (x, y + 1))
            if neighbor in opaque
        ]

        self.assertGreaterEqual(len(dark_outline) / len(opaque), 0.15)
        self.assertGreaterEqual(len(boot_brown) / len(opaque), 0.20)
        self.assertGreaterEqual(len(brown_next_to_outline) / len(opaque), 0.10)
        self.assertGreaterEqual(
            sum(contrast >= 35 for contrast in adjacent_contrasts)
            / len(adjacent_contrasts),
            0.15,
        )

    def test_atm_logo_excludes_terrain_colors_at_small_sizes(self):
        with Image.open(MEDIA / "ATMLogo.tga") as source:
            for size in (20, 32):
                with self.subTest(size=size):
                    image = (
                        source.convert("RGBA")
                        .convert("RGBa")
                        .resize((size, size), Image.Resampling.LANCZOS)
                        .convert("RGBA")
                    )
                    terrain = [
                        pixel
                        for pixel in image.get_flattened_data()
                        if pixel[3] >= 128
                        and pixel[1] - pixel[0] >= 5
                        and pixel[1] - pixel[2] >= 3
                    ]

                    self.assertEqual([], terrain)

    def test_atm_logo_excludes_fish_blue_from_upper_region_at_small_sizes(self):
        with Image.open(MEDIA / "ATMLogo.tga") as source:
            for size in (20, 32):
                with self.subTest(size=size):
                    image = (
                        source.convert("RGBA")
                        .convert("RGBa")
                        .resize((size, size), Image.Resampling.LANCZOS)
                        .convert("RGBA")
                    )
                    opaque = {
                        (x, y): image.getpixel((x, y))
                        for y in range(image.height)
                        for x in range(image.width)
                        if image.getpixel((x, y))[3] >= 128
                    }
                    upper = {
                        point: pixel
                        for point, pixel in opaque.items()
                        if point[1] < round(size * 0.65)
                    }
                    fish_blue = {
                        point
                        for point, pixel in upper.items()
                        if pixel[2] >= 70
                        and pixel[2] - pixel[0] >= 12
                        and pixel[2] - pixel[1] >= 5
                    }
                    fish_cyan = {
                        point
                        for point, pixel in upper.items()
                        if pixel[1] >= 75
                        and pixel[2] >= 75
                        and pixel[1] - pixel[0] >= 8
                        and pixel[2] - pixel[0] >= 8
                    }
                    boot_brown = {
                        point
                        for point, pixel in opaque.items()
                        if pixel[0] - pixel[1] >= 20
                        and pixel[1] - pixel[2] >= 3
                        and 45 <= sum(pixel[:3]) / 3 <= 190
                    }
                    dark_outline = {
                        point
                        for point, pixel in opaque.items()
                        if max(pixel[:3]) <= 80
                    }

                    self.assertEqual(set(), fish_blue | fish_cyan)
                    self.assertGreaterEqual(
                        len(boot_brown) / len(opaque),
                        0.45,
                    )
                    self.assertGreaterEqual(
                        len(dark_outline) / len(opaque),
                        0.30,
                    )

    def test_atm_logo_uses_circular_alpha_mask(self):
        with Image.open(MEDIA / "ATMLogo.tga") as source:
            image = source.convert("RGBA")

        self.assertEqual((64, 64), image.size)
        self.assertEqual("RGBA", image.mode)
        self.assertEqual(
            [0, 0, 0, 0],
            [
                image.getpixel((0, 0))[3],
                image.getpixel((63, 0))[3],
                image.getpixel((0, 63))[3],
                image.getpixel((63, 63))[3],
            ],
        )
        pixels = image_pixels(image)
        self.assertGreater(
            sum(pixel[3] == 0 for pixel in pixels),
            400,
        )
        self.assertEqual(255, image.getpixel((32, 32))[3])

        white_fringe = [
            pixel
            for pixel in pixels
            if 0 < pixel[3] < 255
            and min(pixel[:3]) >= 245
            and max(pixel[:3]) - min(pixel[:3]) <= 12
        ]
        self.assertEqual([], white_fringe)

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
