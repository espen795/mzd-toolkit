"""osm_map.py - OSM background map (tiles, cached) + route drawing in matplotlib, and Leaflet HTML.

Tiles: tile.openstreetmap.org (policy: low volume, caching, identifiable User-Agent, attribution).
Cache: ~/.cache/osm-tiles/{z}/{x}/{y}.png
"""
import math, os, io, time, json
import numpy as np
import requests
from PIL import Image

CACHE = os.path.expanduser("~/.cache/osm-tiles")
UA = "mazda-trip-report/1.0 (personal, low-volume, cached)"
TILE = 256

def ll2px(lat, lon, z):
    """WGS84 -> global pixel (web mercator) at zoom z."""
    n = TILE * 2 ** z
    x = (lon + 180.0) / 360.0 * n
    lr = np.radians(lat)
    y = (1.0 - np.log(np.tan(lr) + 1 / np.cos(lr)) / math.pi) / 2.0 * n
    return x, y

def _tile(z, x, y, sess):
    p = os.path.join(CACHE, str(z), str(x), f"{y}.png")
    if not os.path.exists(p):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        r = sess.get(f"https://tile.openstreetmap.org/{z}/{x}/{y}.png", timeout=20)
        r.raise_for_status()
        open(p, "wb").write(r.content)
        time.sleep(0.15)
    return Image.open(p).convert("RGB")

def pick_zoom(lats, lons, max_px=2400, zmax=16):
    for z in range(zmax, 3, -1):
        x0, y0 = ll2px(np.max(lats), np.min(lons), z); x1, y1 = ll2px(np.min(lats), np.max(lons), z)
        if x1 - x0 < max_px and y1 - y0 < max_px * 0.75:
            return z
    return 4

def basemap(lats, lons, z=None, pad=0.08):
    """Return (img, z, x0px, y0px) for a bbox around the points (with margin)."""
    lats, lons = np.asarray(lats), np.asarray(lons)
    if z is None: z = pick_zoom(lats, lons)
    xa, ya = ll2px(lats, lons, z)
    dx, dy = (xa.max() - xa.min()) * pad + 40, (ya.max() - ya.min()) * pad + 40
    X0, X1, Y0, Y1 = xa.min() - dx, xa.max() + dx, ya.min() - dy, ya.max() + dy
    tx0, tx1, ty0, ty1 = int(X0 // TILE), int(X1 // TILE), int(Y0 // TILE), int(Y1 // TILE)
    img = Image.new("RGB", ((tx1 - tx0 + 1) * TILE, (ty1 - ty0 + 1) * TILE), "white")
    s = requests.Session(); s.headers["User-Agent"] = UA
    for tx in range(tx0, tx1 + 1):
        for ty in range(ty0, ty1 + 1):
            img.paste(_tile(z, tx, ty, s), ((tx - tx0) * TILE, (ty - ty0) * TILE))
    crop = (int(X0 - tx0 * TILE), int(Y0 - ty0 * TILE), int(X1 - tx0 * TILE), int(Y1 - ty0 * TILE))
    return img.crop(crop), z, X0, Y0

def draw_route(ax, lats, lons, values, cmap="turbo", vmin=0, vmax=None, z=None, lw=2.6, label="km/h", show_start=True, show_end=True):
    """Draw OSM map + route (coloured by values) in ax. Returns the colorbar mappable."""
    from matplotlib.collections import LineCollection
    img, z, X0, Y0 = basemap(lats, lons, z)
    # fade slightly so the route stands out
    img = Image.blend(img, Image.new("RGB", img.size, "white"), 0.25)
    ax.imshow(img, extent=(0, img.size[0], img.size[1], 0), interpolation="lanczos")
    x, y = ll2px(np.asarray(lats), np.asarray(lons), z); x -= X0; y -= Y0
    pts = np.column_stack([x, y]).reshape(-1, 1, 2)
    segs = np.concatenate([pts[:-1], pts[1:]], axis=1)
    lc = LineCollection(segs, cmap=cmap, linewidths=lw, capstyle="round")
    lc.set_array(np.asarray(values)[:-1]); lc.set_clim(vmin, vmax if vmax else np.nanmax(values))
    ax.add_collection(LineCollection(segs, colors="k", linewidths=lw + 1.6, alpha=.55, capstyle="round"))
    ax.add_collection(lc)
    if show_start: ax.plot(x[0], y[0], "o", ms=10, mfc="#2ecc71", mec="k", zorder=5)
    if show_end: ax.plot(x[-1], y[-1], "s", ms=10, mfc="#c0392b", mec="k", zorder=5)
    ax.set_xlim(0, img.size[0]); ax.set_ylim(img.size[1], 0); ax.set_axis_off()
    ax.text(0.995, 0.005, "(c) OpenStreetMap contributors", transform=ax.transAxes, ha="right", va="bottom",
            fontsize=6.5, color="#333", bbox=dict(fc="white", ec="none", alpha=.7, pad=1.5))
    return lc, z

def leaflet_html(path, lats, lons, speeds, title, popups=None, extra_markers=None):
    """Standalone HTML map (Leaflet via CDN, tiles load in the browser)."""
    pts = [[round(float(a), 6), round(float(b), 6), round(float(v), 1)] for a, b, v in zip(lats, lons, speeds)]
    html = f"""<!doctype html><html><head><meta charset="utf-8"><title>{title}</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>html,body,#m{{height:100%;margin:0}} .lg{{background:#fff;padding:6px 8px;font:12px sans-serif;border-radius:4px;box-shadow:0 1px 4px #0004}}</style>
</head><body><div id="m"></div><script>
const P={json.dumps(pts)};
const M={json.dumps(extra_markers or [])};
const map=L.map('m');
L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png',{{maxZoom:19,attribution:'&copy; OpenStreetMap contributors'}}).addTo(map);
function col(v){{const s=[[0,'#30123b'],[30,'#4686fb'],[50,'#1ae4b6'],[80,'#a2fc3c'],[100,'#faba39'],[120,'#e4460a'],[140,'#7a0403']];
 for(let i=s.length-1;i>=0;i--) if(v>=s[i][0]) return s[i][1]; return s[0][1];}}
for(let i=1;i<P.length;i++){{L.polyline([[P[i-1][0],P[i-1][1]],[P[i][0],P[i][1]]],{{color:col(P[i][2]),weight:5,opacity:.9}})
 .bindTooltip(P[i][2]+' km/h').addTo(map);}}
L.circleMarker([P[0][0],P[0][1]],{{radius:8,color:'#000',fillColor:'#2ecc71',fillOpacity:1}}).bindPopup('Start').addTo(map);
L.circleMarker([P[P.length-1][0],P[P.length-1][1]],{{radius:8,color:'#000',fillColor:'#c0392b',fillOpacity:1}}).bindPopup('End').addTo(map);
for(const m of M) L.circleMarker([m[0],m[1]],{{radius:5,color:m[3]||'#000',fillOpacity:.8}}).bindPopup(m[2]).addTo(map);
map.fitBounds(P.map(p=>[p[0],p[1]]),{{padding:[20,20]}});
const lg=L.control({{position:'bottomleft'}});lg.onAdd=()=>{{const d=L.DomUtil.create('div','lg');
 d.innerHTML='<b>{title}</b><br>'+[0,30,50,80,100,120].map(v=>'<span style="display:inline-block;width:14px;height:8px;background:'+col(v)+'"></span> '+v+'+').join(' &nbsp;')+' km/h';return d;}};lg.addTo(map);
</script></body></html>"""
    open(path, "w").write(html)
