"""Procedural textures for the gamer room. Pure stdlib (writes PNG by hand).
Run: python tools/gen_textures.py  (from project root)
Output: resorses/textures/room/*.png
Deterministic (seeded) so re-runs give identical files."""
import os
import random
import struct
import zlib

OUT = os.path.join("resorses", "textures", "room")


def write_png(path, w, h, px):
    def chunk(typ, data):
        c = struct.pack(">I", len(data)) + typ + data
        c += struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF)
        return c

    raw = b"".join(
        b"\x00" + b"".join(struct.pack("BBB", *p) for p in row) for row in px
    )
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
    print("wrote", path, w, "x", h)


def clamp255(v):
    return max(0, min(255, int(v)))


def noise(px, amt, rng):
    for y in range(len(px)):
        for x in range(len(px[0])):
            r, g, b = px[y][x]
            n = rng.randint(-amt, amt)
            px[y][x] = (clamp255(r + n), clamp255(g + n), clamp255(b + n))
    return px


def blank(w, h, color):
    return [[color for _ in range(w)] for _ in range(h)]


def floor_wood():
    w, h, rng = 512, 512, random.Random(7)
    px = blank(w, h, (0, 0, 0))
    rows = 4
    rh = h // rows
    for r in range(rows):
        base = (139 + rng.randint(-18, 18), 90 + rng.randint(-12, 12), 43 + rng.randint(-8, 8))
        off = rng.randint(0, 120)
        for y in range(r * rh, (r + 1) * rh):
            for x in range(w):
                seg = ((x + off) // 128) % 2
                v = base if seg == 0 else tuple(c - 12 for c in base)
                px[y][x] = v
        # dark seams between planks + segments
        for x in range(w):
            px[r * rh][x] = (40, 24, 12)
            px[r * rh + 1][x] = (55, 33, 17)
            sx = (128 - off) % 128
            for k in range(0, w, 128):
                xx = (k + sx) % w
                if xx < w:
                    for yy in range(r * rh, (r + 1) * rh):
                        px[yy][xx] = (45, 28, 14)
        # grain streaks
        for _ in range(26):
            gy = rng.randint(r * rh + 3, (r + 1) * rh - 3)
            dark = rng.random() < 0.7
            for x in range(w):
                if rng.random() < 0.85:
                    r0, g0, b0 = px[gy][x]
                    d = -14 if dark else 10
                    px[gy][x] = (clamp255(r0 + d), clamp255(g0 + d), clamp255(b0 + d))
    return w, h, noise(px, 6, rng)


def plaster(base, size, amt, seed):
    rng = random.Random(seed)
    return size, size, noise(blank(size, size, base), amt, rng)


def rug():
    w, h, rng = 256, 256, random.Random(21)
    px = blank(w, h, (115, 30, 40))
    for y in range(h):
        for x in range(w):
            edge = min(x, y, w - 1 - x, h - 1 - y)
            if edge < 10:
                px[y][x] = (70, 18, 25)
            elif edge < 14:
                px[y][x] = (180, 60, 70)
            elif edge < 20:
                px[y][x] = (90, 22, 32)
    cx, cy = w // 2, h // 2
    for y in range(h):
        for x in range(w):
            dd = abs(x - cx) + abs(y - cy)
            if dd < 60 and (dd // 12) % 2 == 0:
                r, g, b = px[y][x]
                px[y][x] = (clamp255(r + 25), clamp255(g + 12), clamp255(b + 14))
    return w, h, noise(px, 7, rng)


def blanket():
    w, h, rng = 256, 256, random.Random(33)
    px = blank(w, h, (153, 30, 38))
    for y in range(0, h, 32):
        for yy in range(y, min(y + 4, h)):
            for x in range(w):
                px[yy][x] = (110, 20, 28)
    for x in range(0, w, 64):
        for xx in range(x, min(x + 2, w)):
            for y in range(h):
                r, g, b = px[y][xx]
                px[y][xx] = (clamp255(r - 25), clamp255(g - 8), clamp255(b - 8))
    return w, h, noise(px, 6, rng)


def mattress():
    w, h, rng = 128, 128, random.Random(44)
    px = blank(w, h, (191, 191, 199))
    for x in range(0, w, 8):
        for y in range(h):
            r, g, b = px[y][x]
            px[y][x] = (r - 10, g - 10, b - 8)
    return w, h, noise(px, 5, rng)


def poster_invader():
    w, h, rng = 192, 256, random.Random(55)
    px = blank(w, h, (10, 12, 26))
    for _ in range(60):
        px[rng.randint(0, h - 1)][rng.randint(0, w - 1)] = (200, 210, 230)
    inv = [
        "00100000100",
        "00010001000",
        "00111111100",
        "01101110110",
        "11111111111",
        "10111111101",
        "10100000101",
        "00011011000",
    ]
    s = 12
    ox, oy = (w - len(inv[0]) * s) // 2, 60
    for j, row in enumerate(inv):
        for i, ch in enumerate(row):
            if ch == "1":
                for yy in range(j * s, (j + 1) * s):
                    for xx in range(i * s, (i + 1) * s):
                        px[oy + yy][ox + xx] = (64, 224, 255)
    # ground line + caption bar
    for x in range(w):
        px[200][x] = (64, 224, 255)
        px[201][x] = (64, 224, 255)
    for y in range(214, 232):
        for x in range(36, 156):
            px[y][x] = (64, 224, 255) if (x + y) % 2 == 0 else (10, 12, 26)
    return w, h, px


def poster_rings():
    w, h, rng = 192, 256, random.Random(66)
    px = blank(w, h, (22, 8, 26))
    cx, cy = w // 2, 110
    for y in range(h):
        for x in range(w):
            dd = abs(x - cx) + abs(y - cy) // 2
            if dd < 80 and (dd // 10) % 2 == 0:
                px[y][x] = (255, 45, 200)
    for y in range(200, 216):
        for x in range(20, w - 20):
            px[y][x] = (255, 45, 200)
    for y in range(224, 240):
        for x in range(50, w - 50):
            px[y][x] = (255, 45, 200)
    return w, h, noise(px, 4, rng)


def poster_tri():
    w, h = 192, 256
    px = blank(w, h, (16, 18, 10))
    rng = random.Random(77)

    def tri(cx, apex_y, half, color):
        for yy in range(apex_y, apex_y + half * 2):
            t = (yy - apex_y) / float(half * 2)
            spread = int(half * t)
            for xx in range(cx - spread, cx + spread + 1):
                if 0 <= xx < w and 0 <= yy < h:
                    px[yy][xx] = color

    tri(96, 30, 34, (255, 210, 40))
    tri(62, 120, 26, (255, 210, 40))
    tri(130, 120, 26, (255, 210, 40))
    for x in range(w):
        px[200][x] = (255, 210, 40)
        px[201][x] = (255, 210, 40)
    return w, h, noise(px, 4, rng)


def main():
    os.makedirs(OUT, exist_ok=True)
    jobs = [
        ("floor_wood.png", floor_wood()),
        ("wall_plaster.png", plaster((41, 38, 51), 256, 7, 8)),
        ("rug.png", rug()),
        ("blanket.png", blanket()),
        ("mattress.png", mattress()),
        ("desk_dark.png", plaster((20, 20, 26), 128, 4, 9)),
        ("ceiling.png", plaster((26, 26, 31), 128, 4, 10)),
        ("poster_invader.png", poster_invader()),
        ("poster_rings.png", poster_rings()),
        ("poster_tri.png", poster_tri()),
    ]
    for name, (w, h, px) in jobs:
        write_png(os.path.join(OUT, name), w, h, px)


if __name__ == "__main__":
    main()
