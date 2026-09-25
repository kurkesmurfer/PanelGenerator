#!/usr/bin/env python3
"""Turn an SVG into a PanelGenerator stamp (.pgstamp).

The app imports SVG perfectly well; this exists so a stamp that *ships with the
repository* can be regenerated from its source artwork rather than hand-edited
as JSON. It handles the subset the shipped marks use — M/L/H/V/Z with
translate/scale/rotate — and refuses anything else rather than importing it
wrong. For everything else, use File > Import SVG and Edit > Add Selection to
Palette.

  Scripts/svg-to-stamp.py in.svg out.pgstamp [--role decoration]
"""
import json, math, re, sys, uuid
import xml.etree.ElementTree as ET

MM_PER_PX = 25.4 / 75.0
NUM = re.compile(r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?')


def numbers(s):
    return [float(m.group()) for m in NUM.finditer(s)]


def mat(a, b, c, d, e, f):
    return (a, b, c, d, e, f)


IDENTITY = mat(1, 0, 0, 1, 0, 0)


def mul(m, n):
    """m applied after n — i.e. the child's transform n runs first."""
    a1, b1, c1, d1, e1, f1 = m
    a2, b2, c2, d2, e2, f2 = n
    return mat(a1 * a2 + c1 * b2, b1 * a2 + d1 * b2,
               a1 * c2 + c1 * d2, b1 * c2 + d1 * d2,
               a1 * e2 + c1 * f2 + e1, b1 * e2 + d1 * f2 + f1)


def apply(m, x, y):
    a, b, c, d, e, f = m
    return (a * x + c * y + e, b * x + d * y + f)


def parse_transform(s):
    out = IDENTITY
    for name, args in re.findall(r'(\w+)\s*\(([^)]*)\)', s or ''):
        v = numbers(args)
        if name == 'translate':
            t = mat(1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0)
        elif name == 'scale':
            t = mat(v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0)
        elif name == 'rotate':
            r = math.radians(v[0])
            t = mat(math.cos(r), math.sin(r), -math.sin(r), math.cos(r), 0, 0)
            if len(v) == 3:
                t = mul(mul(mat(1, 0, 0, 1, v[1], v[2]), t), mat(1, 0, 0, 1, -v[1], -v[2]))
        elif name == 'matrix':
            t = mat(*v[:6])
        else:
            raise SystemExit(f"unsupported transform: {name}")
        out = mul(out, t)
    return out


def subpaths(d):
    """Absolute point lists. Only the straight-line commands — a curve would
    need flattening, and silently flattening artwork is how a mark stops being
    the mark."""
    toks = re.findall(r'[MmLlHhVvZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?', d)
    paths, cur = [], []
    x = y = sx = sy = 0.0
    i, cmd = 0, None
    while i < len(toks):
        t = toks[i]
        if t.isalpha():
            cmd, i = t, i + 1
        if cmd in 'Zz':
            if cur:
                paths.append(cur)
            cur, x, y = [], sx, sy
            continue
        need = {'M': 2, 'm': 2, 'L': 2, 'l': 2, 'H': 1, 'h': 1, 'V': 1, 'v': 1}
        if cmd not in need:
            raise SystemExit(f"unsupported path command: {cmd}")
        v = [float(z) for z in toks[i:i + need[cmd]]]
        i += need[cmd]
        if cmd == 'M':
            if cur:
                paths.append(cur)
            x, y = v
            sx, sy, cur = x, y, [(x, y)]
        elif cmd == 'm':
            if cur:
                paths.append(cur)
            x, y = x + v[0], y + v[1]
            sx, sy, cur = x, y, [(x, y)]
        else:
            if cmd == 'L':   x, y = v
            elif cmd == 'l': x, y = x + v[0], y + v[1]
            elif cmd == 'H': x = v[0]
            elif cmd == 'h': x = x + v[0]
            elif cmd == 'V': y = v[0]
            elif cmd == 'v': y = y + v[0]
            cur.append((x, y))
        if cmd == 'M':
            cmd = 'L'
        elif cmd == 'm':
            cmd = 'l'
    if cur:
        paths.append(cur)
    return paths


def px(v, unit):
    """SVG length to panel pixels (Rack authors at 75 dpi)."""
    return v / MM_PER_PX if unit == 'mm' else v


def colour(hexstr):
    h = hexstr.lstrip('#')
    return {'r': int(h[0:2], 16) / 255, 'g': int(h[2:4], 16) / 255,
            'b': int(h[4:6], 16) / 255, 'a': 1.0}


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    root = ET.parse(src).getroot()

    def length(attr):
        raw = root.get(attr, '')
        m = re.match(r'\s*([-+0-9.eE]+)\s*(mm|px)?', raw)
        if not m:
            raise SystemExit(f"{src}: no usable {attr}")
        return px(float(m.group(1)), m.group(2) or 'px')

    vb = numbers(root.get('viewBox') or '')
    if len(vb) != 4:
        raise SystemExit(f"{src}: a viewBox is required")
    wpx, hpx = length('width'), length('height')
    # viewBox user units to panel pixels.
    view = mul(mat(1, 0, 0, 1, 0, 0),
               mul(mat(wpx / vb[2], 0, 0, hpx / vb[3], 0, 0),
                   mat(1, 0, 0, 1, -vb[0], -vb[1])))

    elements = []

    def walk(node, ctm, fill):
        tag = node.tag.split('}')[-1]
        ctm = mul(ctm, parse_transform(node.get('transform')))
        fill = node.get('fill', fill)
        if tag == 'path':
            pts = [[apply(ctm, x, y) for (x, y) in sub] for sub in subpaths(node.get('d', ''))]
            flat = [p for sub in pts for p in sub]
            if not flat:
                return
            xs = [p[0] for p in flat]
            ys = [p[1] for p in flat]
            box = (min(xs), min(ys), max(max(xs) - min(xs), 0.5), max(max(ys) - min(ys), 0.5))
            d = ''.join(
                'M%s %s' % (f(  (sub[0][0] - box[0]) / box[2]), f((sub[0][1] - box[1]) / box[3]))
                + ''.join('L%s %s' % (f((x - box[0]) / box[2]), f((y - box[1]) / box[3]))
                          for (x, y) in sub[1:])
                + 'Z'
                for sub in pts if sub)
            elements.append({
                'kind': 'path', 'id': str(uuid.uuid4()), 'name': '',
                'x': round(box[0], 6), 'y': round(box[1], 6),
                'w': round(box[2], 6), 'h': round(box[3], 6),
                'rotation': 0, 'fill': colour(fill or '#000000'),
                'strokeWidth': 1, 'pathData': d, 'role': 'decoration',
                'enumName': '', 'widgetSource': 'stock', 'rotatesWithValue': True,
            })
        for child in node:
            walk(child, ctm, fill)

    def f(v):
        return ('%.6f' % v).rstrip('0').rstrip('.') or '0'

    for child in root:
        walk(child, view, root.get('fill'))

    if not elements:
        raise SystemExit(f"{src}: nothing importable found")

    with open(dst, 'w') as fh:
        json.dump(elements, fh, indent=2, sort_keys=True)
    print("%s: %d element(s), %.2f x %.2f mm -> %s"
          % (src, len(elements), wpx * MM_PER_PX, hpx * MM_PER_PX, dst))


if __name__ == '__main__':
    main()
