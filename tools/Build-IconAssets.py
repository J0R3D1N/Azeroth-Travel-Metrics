from collections import deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artwork" / "source"
TARGET = ROOT / "AzerothTravelTracker" / "Media"
ASSETS = {
    "att_logo_400x400.jpg": "ATTLogo.tga",
    "overview_icon.jpg": "Overview.tga",
    "by_level_icon.jpg": "ByLevel.tga",
}
SIZE = 64
WHITE_MINIMUM = 235
WHITE_CHANNEL_RANGE = 24


def center_crop(image: Image.Image) -> Image.Image:
    edge = min(image.size)
    left = (image.width - edge) // 2
    top = (image.height - edge) // 2
    return image.crop((left, top, left + edge, top + edge))


def clear_edge_white(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    queue = deque()
    seen = set()

    for x in range(width):
        queue.append((x, 0))
        queue.append((x, height - 1))
    for y in range(height):
        queue.append((0, y))
        queue.append((width - 1, y))

    while queue:
        x, y = queue.popleft()
        if (x, y) in seen:
            continue
        seen.add((x, y))

        red, green, blue, _ = pixels[x, y]
        if (
            min(red, green, blue) < WHITE_MINIMUM
            or max(red, green, blue) - min(red, green, blue)
            > WHITE_CHANNEL_RANGE
        ):
            continue

        pixels[x, y] = (red, green, blue, 0)
        if x > 0:
            queue.append((x - 1, y))
        if x + 1 < width:
            queue.append((x + 1, y))
        if y > 0:
            queue.append((x, y - 1))
        if y + 1 < height:
            queue.append((x, y + 1))

    return rgba


def build(source_name: str, target_name: str) -> None:
    with Image.open(SOURCE / source_name) as original:
        cropped = center_crop(original)
        transparent = clear_edge_white(cropped)
        resized = transparent.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
        if target_name == "ATTLogo.tga":
            # WoW does not mask minimap textures, so keep logo corners transparent.
            corners = (
                (0, 0),
                (SIZE - 1, 0),
                (0, SIZE - 1),
                (SIZE - 1, SIZE - 1),
            )
            for corner in corners:
                red, green, blue, _ = resized.getpixel(corner)
                resized.putpixel(corner, (red, green, blue, 0))
        TARGET.mkdir(parents=True, exist_ok=True)
        resized.save(TARGET / target_name, format="TGA", compression=None)


def main() -> None:
    for source_name, target_name in ASSETS.items():
        build(source_name, target_name)


if __name__ == "__main__":
    main()
