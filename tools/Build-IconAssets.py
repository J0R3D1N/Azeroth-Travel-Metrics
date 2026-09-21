from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artwork" / "source"
TARGET = ROOT / "AzerothTravelTracker" / "Media"
ASSETS = {
    "azeroth_travel_metrics.jpg": {
        "target": "ATTLogo.tga",
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
}
SIZE = 64
MASK_SCALE = 4
CORNER_RADIUS = 14
CIRCLE_INSET = 5


def isolate_boot(image: Image.Image) -> Image.Image:
    rgb = image.convert("RGB")
    pixels = rgb.load()
    width, height = rgb.size

    def belongs_to_boot(pixel: tuple[int, int, int]) -> bool:
        red, green, blue = pixel
        is_brown = (
            red - green >= 18
            and green >= blue
            and red >= 55
            and blue <= 125
        )
        is_outline = max(pixel) <= 65
        return is_brown or is_outline

    visited: set[tuple[int, int]] = set()
    components: list[list[tuple[int, int]]] = []
    for y in range(height):
        for x in range(width):
            point = (x, y)
            if point in visited or not belongs_to_boot(pixels[x, y]):
                continue

            component = []
            pending = [point]
            visited.add(point)
            while pending:
                current_x, current_y = pending.pop()
                component.append((current_x, current_y))
                for neighbor_y in range(
                    max(0, current_y - 1),
                    min(height, current_y + 2),
                ):
                    for neighbor_x in range(
                        max(0, current_x - 1),
                        min(width, current_x + 2),
                    ):
                        neighbor = (neighbor_x, neighbor_y)
                        if (
                            neighbor not in visited
                            and belongs_to_boot(pixels[neighbor_x, neighbor_y])
                        ):
                            visited.add(neighbor)
                            pending.append(neighbor)

            components.append(component)

    if not components:
        raise ValueError("boot crop does not contain a recognizable boot")

    boot = max(components, key=len)
    alpha = Image.new("L", rgb.size, 0)
    alpha_pixels = alpha.load()
    for point in boot:
        alpha_pixels[point] = 255

    output = rgb.convert("RGBA")
    output.putalpha(alpha)
    return output


def center_crop(image: Image.Image) -> Image.Image:
    edge = min(image.size)
    left = (image.width - edge) // 2
    top = (image.height - edge) // 2
    return image.crop((left, top, left + edge, top + edge))


def normalized_crop(
    image: Image.Image, box: tuple[float, float, float, float]
) -> Image.Image:
    left, top, right, bottom = box
    return image.crop(
        (
            round(left * image.width),
            round(top * image.height),
            round(right * image.width),
            round(bottom * image.height),
        )
    )


def resize_premultiplied(
    image: Image.Image, size: tuple[int, int]
) -> Image.Image:
    return (
        image.convert("RGBA")
        .convert("RGBa")
        .resize(size, Image.Resampling.LANCZOS)
        .convert("RGBA")
    )


def circular_mask(size: int, scale: int = MASK_SCALE) -> Image.Image:
    large = Image.new("L", (size * scale, size * scale), 0)
    draw = ImageDraw.Draw(large)
    inset = CIRCLE_INSET * scale
    draw.ellipse(
        (inset, inset, size * scale - inset - 1, size * scale - inset - 1),
        fill=255,
    )
    return large.resize((size, size), Image.Resampling.LANCZOS)


def rounded_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        (0, 0, size - 1, size - 1),
        radius=CORNER_RADIUS * MASK_SCALE,
        fill=255,
    )
    return mask


def apply_alpha_mask(
    image: Image.Image, mask: Image.Image
) -> Image.Image:
    rgba = image.convert("RGBA")
    rgba.putalpha(ImageChops.multiply(rgba.getchannel("A"), mask))
    return rgba


def build(source_name: str, config: dict) -> None:
    with Image.open(SOURCE / source_name) as original:
        crop = config.get("crop")
        cropped = (
            normalized_crop(original, crop)
            if crop is not None
            else center_crop(original)
        )
        if config.get("isolate") == "boot":
            cropped = isolate_boot(cropped)
        mask_kind = config["mask"]
        if mask_kind == "circle":
            resized = resize_premultiplied(cropped, (SIZE, SIZE))
            mask = circular_mask(SIZE)
            output = apply_alpha_mask(resized, mask)
        elif mask_kind == "rounded":
            working_size = SIZE * MASK_SCALE
            supersampled = resize_premultiplied(
                cropped,
                (working_size, working_size),
            )
            mask = rounded_mask(working_size)
            output = resize_premultiplied(
                apply_alpha_mask(supersampled, mask),
                (SIZE, SIZE),
            )
        else:
            raise ValueError(f"unsupported mask kind: {mask_kind}")
        TARGET.mkdir(parents=True, exist_ok=True)
        output.save(
            TARGET / config["target"],
            format="TGA",
            compression=None,
        )


def main() -> None:
    for source_name, config in ASSETS.items():
        build(source_name, config)


if __name__ == "__main__":
    main()
