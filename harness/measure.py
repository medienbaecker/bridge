#!/usr/bin/env python3
"""Runs of colour along one scanline of a PNG, so a case can measure what was
drawn rather than what was computed. Usage: measure.py <png> <y> [min_run]
Prints one run per line: x_start x_end r g b (x_end exclusive).
Or: measure.py <png> region <x0> <y0> <x1> <y1> prints a digest of that pixel
rectangle and its distinct-colour count, so two shots can be compared there."""
import struct, sys, zlib

def rows(path, y_max):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'not a png'
    pos, idat, width, height, depth, ctype = 8, [], 0, 0, 8, 6
    while pos < len(data):
        length, kind = struct.unpack('>I4s', data[pos:pos + 8]); body = data[pos + 8:pos + 8 + length]; pos += 12 + length
        if kind == b'IHDR': width, height, depth, ctype = struct.unpack('>IIBB', body[:10])
        elif kind == b'IDAT': idat.append(body)
        elif kind == b'IEND': break
    assert depth == 8 and ctype in (2, 6), f'unsupported png (depth {depth}, type {ctype})'
    bpp = 4 if ctype == 6 else 3
    stride = width * bpp
    d = zlib.decompressobj()
    raw = bytearray()
    needed = (y_max + 1) * (stride + 1)
    for chunk in idat:
        raw += d.decompress(chunk)
        if len(raw) >= needed: break
    prev = bytearray(stride)
    for row in range(y_max + 1):
        off = row * (stride + 1)
        f, line = raw[off], bytearray(raw[off + 1:off + 1 + stride])
        if f == 1:
            for i in range(bpp, stride): line[i] = (line[i] + line[i - bpp]) & 255
        elif f == 2:
            for i in range(stride): line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride): line[i] = (line[i] + ((line[i - bpp] if i >= bpp else 0) + prev[i]) // 2) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0; b = prev[i]; c = prev[i - bpp] if i >= bpp else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
        yield row, width, [(line[i], line[i + 1], line[i + 2]) for i in range(0, stride, bpp)]

def scanline(path, y):
    for row, width, px in rows(path, y):
        if row == y: return width, px

if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[2] == 'crop':
        # A magnified crop, nearest neighbour, for looking at borders, corners and padding:
        # measure.py <png> crop <x0> <y0> <x1> <y1> <zoom> <out.png>
        path, x0, y0, x1, y1, zoom, out = sys.argv[1], *map(int, sys.argv[3:8]), sys.argv[8]
        lines = []
        for row, width, px in rows(path, y1 - 1):
            if row < y0: continue
            line = b''.join(bytes(p) * zoom for p in px[x0:x1])
            lines += [line] * zoom
        w, h = (x1 - x0) * zoom, len(lines)
        raw = b''.join(b'\x00' + l for l in lines)
        def chunk(kind, body): return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body) & 0xffffffff)
        png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
        open(out, 'wb').write(png); print(out, w, h); sys.exit()
    if len(sys.argv) > 2 and sys.argv[2] == 'column':
        # Colour runs down one column: measure.py <png> column <x> <y0> <y1> [min_run]
        path, x, y0, y1 = sys.argv[1], *map(int, sys.argv[3:6]); min_run = int(sys.argv[6]) if len(sys.argv) > 6 else 2
        col = []
        for row, width, px in rows(path, y1 - 1):
            if row >= y0: col.append(px[x])
        start = 0
        for i in range(1, len(col) + 1):
            if i == len(col) or col[i] != col[start]:
                if i - start >= min_run: print(y0 + start, y0 + i, *col[start])
                start = i
        sys.exit()
    if len(sys.argv) > 2 and sys.argv[2] == 'columns':
        # Clusters of columns holding a pixel darker than the threshold, in a band:
        # where the glyphs are, so two shots can be compared for position.
        path, x0, y0, x1, y1, thr = sys.argv[1], *map(int, sys.argv[3:8])
        dark = [False] * (x1 - x0)
        for row, width, px in rows(path, y1 - 1):
            if row < y0: continue
            for i, p in enumerate(px[x0:x1]):
                if not dark[i] and sum(p) < thr * 3: dark[i] = True
        out, start = [], None
        for i, d in enumerate(dark + [False]):
            if d and start is None: start = i
            if not d and start is not None:
                if i - start >= 3: out.append(f"{x0 + start}-{x0 + i}")
                start = None
        print(' '.join(out)); sys.exit()
    if len(sys.argv) > 2 and sys.argv[2] == 'region':
        import hashlib
        path, x0, y0, x1, y1 = sys.argv[1], *map(int, sys.argv[3:7])
        h, seen = hashlib.sha1(), set()
        for row, width, px in rows(path, y1 - 1):
            if row < y0: continue
            for p in px[x0:x1]: h.update(bytes(p)); seen.add(p)
        print(h.hexdigest()[:12], len(seen)); sys.exit()
    path, y = sys.argv[1], int(sys.argv[2]); min_run = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    width, px = scanline(path, y)
    start = 0
    for x in range(1, width + 1):
        if x == width or px[x] != px[start]:
            if x - start >= min_run: print(start, x, *px[start])
            start = x
