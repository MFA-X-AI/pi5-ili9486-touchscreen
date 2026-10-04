#!/usr/bin/env python3
"""Fit a libinput calibration matrix from crosshair taps (standard library only).

Reads a `libinput debug-events` log, takes one TOUCH_DOWN per tap, and fits a full
affine matrix (all 6 parameters) that maps the raw touch position onto the panel's
native coordinates. A full fit matters: on at least one MHS35 + Pi 5 setup the touch
axes are swapped relative to the display, which a scale-and-offset (diagonal) matrix
cannot represent. Taps then land mirrored across the diagonal.

Coordinates:
  raw     what `libinput debug-events` prints, in % of the touch device. On Trixie it
          prints these BEFORE any installed calibration matrix is applied (verified on
          hardware), so the fit does not depend on the matrix currently installed.
  native  the panel's unrotated output, 0..1. This is what the matrix must produce:
          the compositor then applies the output transform to touch itself.
  screen  what the user sees, 0..1, after the compositor transform.

Usage:
  touch_fit.py fit    --log FILE --transform T --targets "u,v;u,v;..." [--skip N]
  touch_fit.py check  --log FILE --transform T --targets ... --matrix "a b c d e f" [--skip N]
"""
import argparse
import os
import re
import sys

DEBOUNCE_S = 0.7   # must match the crosshair page, which ignores taps closer than this

# screen = to_screen(native) for each compositor transform. 270 is verified on an MHS35
# (rotate=90 overlay); the others follow from it by rotation and are untested.
TO_SCREEN = {
    'normal': lambda x, y: (x, y),
    '90':     lambda x, y: (1 - y, x),
    '180':    lambda x, y: (1 - x, 1 - y),
    '270':    lambda x, y: (y, 1 - x),
}
TO_NATIVE = {
    'normal': lambda u, v: (u, v),
    '90':     lambda u, v: (v, 1 - u),
    '180':    lambda u, v: (1 - u, 1 - v),
    '270':    lambda u, v: (1 - v, u),
}

LINE = re.compile(r'TOUCH_DOWN\s+\+?([0-9.]+)s.*?\s([0-9.]+)/\s*([0-9.]+)\s')


def taps(path):
    """One (x, y) raw position (0..1) per tap, dropping bounces within DEBOUNCE_S."""
    out, last = [], None
    with open(path, errors='replace') as f:
        for line in f:
            m = LINE.search(line)
            if not m:
                continue
            t, x, y = (float(g) for g in m.groups())
            if last is not None and t - last < DEBOUNCE_S:
                continue
            last = t
            out.append((x / 100, y / 100))
    return out


def solve3(a, b):
    """Solve a 3x3 linear system by Gaussian elimination with partial pivoting."""
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for c in range(3):
        p = max(range(c, 3), key=lambda r: abs(m[r][c]))
        if abs(m[p][c]) < 1e-12:
            sys.exit('touch_fit: taps are degenerate (all in a line?) — cannot fit')
        m[c], m[p] = m[p], m[c]
        for r in range(3):
            if r != c:
                k = m[r][c] / m[c][c]
                m[r] = [m[r][i] - k * m[c][i] for i in range(4)]
    return [m[i][3] / m[i][i] for i in range(3)]


def fit(raw, native):
    """Least-squares affine map raw -> native; returns [a, b, c, d, e, f]."""
    ata = [[sum(p[i] * p[j] for p in [(x, y, 1) for x, y in raw]) for j in range(3)] for i in range(3)]
    rows = []
    for k in range(2):
        atb = [sum((x, y, 1)[i] * q[k] for (x, y), q in zip(raw, native)) for i in range(3)]
        rows += solve3(ata, atb)
    return rows


def apply(mx, x, y):
    return mx[0] * x + mx[1] * y + mx[2], mx[3] * x + mx[4] * y + mx[5]


def report(mx, raw, targets, transform, label):
    """Print per-tap error on screen (in % of width/height); return (rms, landed points)."""
    errs, landed = [], []
    print(f'{label}:  tap   target(%)      landed(%)      error(%)')
    for i, ((x, y), (u, v)) in enumerate(zip(raw, targets)):
        su, sv = TO_SCREEN[transform](*apply(mx, x, y))
        landed.append((su, sv))
        du, dv = (su - u) * 100, (sv - v) * 100
        errs.append(du * du + dv * dv)
        print(f'        {i + 1:>3}   {u * 100:5.1f},{v * 100:5.1f}    {su * 100:5.1f},{sv * 100:5.1f}    {du:+5.1f},{dv:+5.1f}')
    rms = (sum(errs) / len(errs)) ** 0.5
    print(f'        rms error {rms:.2f}% of the screen')
    return rms, landed


def write_js(path, rms, good, targets, landed):
    """Results for the calibration page, which loads this file as a script."""
    pts = ','.join(f'[{u:.4f},{v:.4f},{a:.4f},{b:.4f}]' for (u, v), (a, b) in zip(targets, landed))
    with open(path + '.tmp', 'w') as f:
        f.write(f'showResults({{rms:{rms:.2f},good:{"true" if rms <= good else "false"},points:[{pts}]}});\n')
    os.replace(path + '.tmp', path)   # atomic: the page never loads a half-written file


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('mode', choices=['fit', 'check'])
    ap.add_argument('--log', required=True)
    ap.add_argument('--transform', required=True, choices=sorted(TO_SCREEN))
    ap.add_argument('--targets', required=True, help='"u,v;u,v;..." in 0..1 screen coordinates')
    ap.add_argument('--skip', type=int, default=0, help='ignore the first N taps in the log')
    ap.add_argument('--matrix', help='"a b c d e f" (check mode)')
    ap.add_argument('--js', help='check mode: also write results for the calibration page here')
    ap.add_argument('--good', type=float, default=2.5, help='check mode: rms (%%) counted as good')
    a = ap.parse_args()

    targets = [tuple(float(n) for n in t.split(',')) for t in a.targets.split(';')]
    raw = taps(a.log)[a.skip:a.skip + len(targets)]
    if len(raw) < len(targets):
        sys.exit(f'touch_fit: expected {len(targets)} taps, found {len(raw)} in {a.log}')

    if a.mode == 'fit':
        native = [TO_NATIVE[a.transform](u, v) for u, v in targets]
        mx = fit(raw, native)
        report(mx, raw, targets, a.transform, 'fit')
        print('MATRIX ' + ' '.join(f'{v:.5f}' for v in mx))
    else:
        mx = [float(v) for v in a.matrix.split()]
        rms, landed = report(mx, raw, targets, a.transform, 'check')
        if a.js:
            write_js(a.js, rms, a.good, targets, landed)
        print(f'RMS {rms:.2f}')


if __name__ == '__main__':
    main()
