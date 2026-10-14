"""python3 tools/preview_spritesolid.py <dir> <out.png> [slot]
Software-renders the exported body from 8 yaws (orthographic-ish, z-buffered,
nearest-texel, vertex shade) so geometry, smoothing and texture projection can
be judged without LOVE. Matches the in-game convention: y up, +z forward."""
import sys, math
import numpy as np
from PIL import Image

d, out = sys.argv[1], sys.argv[2]
slot = int(sys.argv[3]) if len(sys.argv) > 3 else 1
aw, ah = map(int, open(f"{d}/atlas.txt").read().split())
atlas = np.frombuffer(open(f"{d}/atlas.rgba", "rb").read(), np.uint8).reshape(ah, aw, 4)
V, T = [], []
for line in open(f"{d}/mesh{slot}.txt"):
    p = line.split()
    if p[0] == "v": V.append([float(x) for x in p[1:]])
    else: T.append([int(x) for x in p[1:]])
V = np.array(V); T = np.array(T); V[:, 5] = np.abs(V[:, 5])  # shader: vShade = abs(VertexShade) per vertex
SZ, S = 220, 6.2

def render(yaw):
    c, s = math.cos(yaw), math.sin(yaw)
    x, y, z = V[:, 0], V[:, 1], V[:, 2]
    xr = x * c + z * s; zr = -x * s + z * c       # Mat4.rotateY
    # camera at +z looking toward -z: screen x = xr, depth = -zr (nearer = larger zr)
    sx = SZ / 2 + xr * S; sy = SZ - 14 - y * S
    img = np.zeros((SZ, SZ, 3), np.float32); img[:] = (0.80, 0.86, 0.92)
    zb = np.full((SZ, SZ), -1e9)
    for a, b, cc in T:
        pts = np.array([[sx[a], sy[a]], [sx[b], sy[b]], [sx[cc], sy[cc]]])
        x0, x1 = int(max(pts[:, 0].min(), 0)), int(min(pts[:, 0].max() + 1, SZ - 1))
        y0, y1 = int(max(pts[:, 1].min(), 0)), int(min(pts[:, 1].max() + 1, SZ - 1))
        if x1 < x0 or y1 < y0: continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + .5, np.arange(y0, y1 + 1) + .5)
        d0 = (pts[1,1]-pts[2,1])*(pts[0,0]-pts[2,0]) + (pts[2,0]-pts[1,0])*(pts[0,1]-pts[2,1])
        if abs(d0) < 1e-9: continue
        w0 = ((pts[1,1]-pts[2,1])*(gx-pts[2,0]) + (pts[2,0]-pts[1,0])*(gy-pts[2,1])) / d0
        w1 = ((pts[2,1]-pts[0,1])*(gx-pts[2,0]) + (pts[0,0]-pts[2,0])*(gy-pts[2,1])) / d0
        w2 = 1 - w0 - w1
        m = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
        if not m.any(): continue
        zz = w0 * zr[a] + w1 * zr[b] + w2 * zr[cc]
        u = w0 * V[a,3] + w1 * V[b,3] + w2 * V[cc,3]
        v = w0 * V[a,4] + w1 * V[b,4] + w2 * V[cc,4]
        sh = np.abs(w0 * V[a,5] + w1 * V[b,5] + w2 * V[cc,5])
        ii, jj = np.nonzero(m)
        for i, j in zip(ii, jj):
            px, py = x0 + j, y0 + i
            if zz[i, j] > zb[py, px]:
                tx = min(int(u[i, j] * aw), aw - 1); ty = min(int(v[i, j] * ah), ah - 1)
                t = atlas[ty, tx]
                if t[3] < 128: continue
                zb[py, px] = zz[i, j]
                img[py, px] = t[:3] / 255.0 * sh[i, j]
    return (np.clip(img, 0, 1) * 255).astype(np.uint8)

yaws = [0, 45, 90, 135, 180, 225, 270, 315]
tiles = [render(math.radians(a)) for a in yaws]
sheet = np.concatenate([np.concatenate(tiles[:4], 1), np.concatenate(tiles[4:], 1)], 0)
Image.fromarray(sheet).save(out)
print("wrote", out)
