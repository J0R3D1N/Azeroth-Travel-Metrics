from collections import deque
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artwork" / "source"
TARGET = ROOT / "AzerothTravelTracker" / "Media"
ASSETS = {
    "att_logo_400x400.jpg": "ATTLogo.tga",
    "overview_icon.jpg": "Overview.tga",
    "by_level_icon.jpg": "ByLevel.tga",
}
SIZE = 64
MASK_SCALE = 4
CORNER_RADIUS = 14
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


def resize_premultiplied(
    image: Image.Image, size: tuple[int, int]
) -> Image.Image:
    return (
        image.convert("RGBA")
        .convert("RGBa")
        .resize(size, Image.Resampling.LANCZOS)
        .convert("RGBA")
    )


def apply_corner_mask(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    mask = Image.new("L", rgba.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        (0, 0, rgba.width - 1, rgba.height - 1),
        radius=CORNER_RADIUS * MASK_SCALE,
        fill=255,
    )
    rgba.putalpha(ImageChops.multiply(rgba.getchannel("A"), mask))
    return rgba


def build(source_name: str, target_name: str) -> None:
    with Image.open(SOURCE / source_name) as original:
        cropped = center_crop(original)
        prepared = (
            clear_edge_white(cropped)
            if target_name == "ATTLogo.tga"
            else cropped.convert("RGBA")
        )
        working_size = (SIZE * MASK_SCALE, SIZE * MASK_SCALE)
        supersampled = resize_premultiplied(prepared, working_size)
        masked = apply_corner_mask(supersampled)
        resized = resize_premultiplied(masked, (SIZE, SIZE))
        TARGET.mkdir(parents=True, exist_ok=True)
        resized.save(TARGET / target_name, format="TGA", compression=None)


def main() -> None:
    for source_name, target_name in ASSETS.items():
        build(source_name, target_name)


if __name__ == "__main__":
    main()
