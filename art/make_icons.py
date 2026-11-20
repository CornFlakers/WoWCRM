"""Writes the three gritty icon variants as HTML pages (icon-a.html, icon-b.html, icon-c.html).
Render each to a 400 x 400 PNG with headless Edge:
  msedge --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size=400,400 --screenshot=out.png file:///.../icon-a.html
All artwork is original: no game or company logos are used.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SERIF = "'Book Antiqua', 'Palatino Linotype', Georgia, serif"

# Shared filters: film grain, a bevelled metal look, and rough worn edges.
DEFS = """
<filter id="grain" x="0" y="0" width="100%" height="100%">
  <feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="3" seed="7" result="n"/>
  <feColorMatrix in="n" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -1.4 1.05" result="a"/>
  <feComposite in="a" in2="SourceGraphic" operator="in"/>
</filter>
<filter id="blotch" x="0" y="0" width="100%" height="100%">
  <feTurbulence type="fractalNoise" baseFrequency="0.012" numOctaves="4" seed="3"/>
  <feColorMatrix type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -2.2 1.25"/>
</filter>
<filter id="rough" x="-10%" y="-10%" width="120%" height="120%">
  <feTurbulence type="fractalNoise" baseFrequency="0.06" numOctaves="2" seed="11" result="t"/>
  <feDisplacementMap in="SourceGraphic" in2="t" scale="5" xChannelSelector="R" yChannelSelector="G"/>
</filter>
<filter id="bevel" x="-20%" y="-20%" width="140%" height="140%">
  <feTurbulence type="fractalNoise" baseFrequency="0.07" numOctaves="2" seed="5" result="t"/>
  <feDisplacementMap in="SourceGraphic" in2="t" scale="3.5" xChannelSelector="R" yChannelSelector="G" result="worn"/>
  <feGaussianBlur in="worn" stdDeviation="2.2" result="blur"/>
  <feSpecularLighting in="blur" surfaceScale="5" specularConstant="1.1" specularExponent="22" lighting-color="#fff6d8" result="spec">
    <feDistantLight azimuth="235" elevation="42"/>
  </feSpecularLighting>
  <feComposite in="spec" in2="worn" operator="in" result="specIn"/>
  <feComposite in="worn" in2="specIn" operator="arithmetic" k1="0" k2="1" k3="0.9" k4="0" result="lit"/>
  <feDropShadow in="lit" dx="0" dy="4" stdDeviation="3" flood-color="#000" flood-opacity="0.8"/>
</filter>
<filter id="emboss" x="-10%" y="-10%" width="120%" height="120%">
  <feGaussianBlur in="SourceAlpha" stdDeviation="1.6" result="b"/>
  <feSpecularLighting in="b" surfaceScale="3" specularConstant="0.9" specularExponent="16" lighting-color="#ffe9b0" result="s">
    <feDistantLight azimuth="235" elevation="45"/>
  </feSpecularLighting>
  <feComposite in="s" in2="SourceAlpha" operator="in" result="sIn"/>
  <feComposite in="SourceGraphic" in2="sIn" operator="arithmetic" k1="0" k2="1" k3="0.8" k4="0"/>
</filter>
<filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
  <feGaussianBlur stdDeviation="9"/>
</filter>
<filter id="shadow" x="-20%" y="-20%" width="140%" height="150%">
  <feDropShadow dx="0" dy="5" stdDeviation="5" flood-color="#000" flood-opacity="0.75"/>
</filter>
<linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#fbe7a1"/><stop offset="0.45" stop-color="#d9a441"/>
  <stop offset="0.7" stop-color="#8a5a17"/><stop offset="1" stop-color="#e2b45a"/>
</linearGradient>
<linearGradient id="iron" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#6d6a66"/><stop offset="0.5" stop-color="#3a3836"/><stop offset="1" stop-color="#1c1b1a"/>
</linearGradient>
"""

def page(body, bg):
    return f"""<!doctype html><html><head><meta charset="utf-8">
<style>html,body{{margin:0;padding:0;width:400px;height:400px;overflow:hidden;background:{bg}}}</style></head><body>
<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400" viewBox="0 0 400 400"><defs>{DEFS}</defs>
{body}
</svg></body></html>"""

def rivets(points, r=7):
    out = []
    for x, y in points:
        out.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="url(#iron)" stroke="#0d0c0b" stroke-width="2"/>'
                   f'<circle cx="{x - 2}" cy="{y - 2}" r="{r / 3:.1f}" fill="#bdb7ad" opacity="0.7"/>')
    return "".join(out)

# ---------------------------------------------------------------- A: Iron & Ember
A = f"""
<radialGradient id="aBg" cx="50%" cy="45%" r="70%">
  <stop offset="0" stop-color="#3b2a22"/><stop offset="0.6" stop-color="#1b1411"/><stop offset="1" stop-color="#070505"/>
</radialGradient>
<linearGradient id="aBanner" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#9b1c17"/><stop offset="1" stop-color="#4a0907"/>
</linearGradient>
<rect width="400" height="400" fill="url(#aBg)"/>
<rect width="400" height="400" fill="#000" filter="url(#blotch)" opacity="0.55"/>
<ellipse cx="200" cy="190" rx="150" ry="70" fill="#ff6a1a" opacity="0.28" filter="url(#glow)"/>
<!-- iron frame -->
<rect x="14" y="14" width="372" height="372" rx="18" fill="none" stroke="#000" stroke-width="16" opacity="0.6"/>
<rect x="14" y="14" width="372" height="372" rx="18" fill="none" stroke="url(#iron)" stroke-width="12" filter="url(#rough)"/>
<rect x="26" y="26" width="348" height="348" rx="10" fill="none" stroke="#7a5a2a" stroke-width="2" opacity="0.6"/>
{rivets([(32, 32), (368, 32), (32, 368), (368, 368), (200, 22), (200, 378), (22, 200), (378, 200)])}
<!-- WoW in worn gold -->
<text x="200" y="222" text-anchor="middle" font-family="{SERIF}" font-weight="bold" font-size="132" letter-spacing="-2"
      fill="url(#gold)" stroke="#2a1606" stroke-width="5" paint-order="stroke" filter="url(#bevel)">WoW</text>
<!-- CRM on a worn leather banner -->
<g filter="url(#shadow)">
  <path d="M78 270 h-42 l18 24 l-18 24 h54 z" fill="#3b0705" stroke="#8a5a17" stroke-width="3"/>
  <path d="M322 270 h42 l-18 24 l18 24 h-54 z" fill="#3b0705" stroke="#8a5a17" stroke-width="3"/>
  <path d="M72 258 h256 v68 h-256 z" fill="url(#aBanner)" stroke="url(#gold)" stroke-width="4" filter="url(#rough)"/>
</g>
<rect x="72" y="258" width="256" height="68" fill="#000" filter="url(#grain)" opacity="0.5"/>
<text x="200" y="306" text-anchor="middle" font-family="{SERIF}" font-weight="bold" font-size="44" letter-spacing="12"
      fill="url(#gold)" stroke="#1d0402" stroke-width="3" paint-order="stroke" filter="url(#emboss)">CRM</text>
<!-- embers -->
<g fill="#ffb347">
  <circle cx="88" cy="118" r="2.2" opacity="0.9"/><circle cx="318" cy="102" r="1.8" opacity="0.8"/>
  <circle cx="300" cy="140" r="1.4" opacity="0.7"/><circle cx="110" cy="80" r="1.4" opacity="0.6"/>
  <circle cx="342" cy="232" r="1.8" opacity="0.7"/><circle cx="60" cy="226" r="1.5" opacity="0.6"/>
</g>
<rect width="400" height="400" fill="#000" filter="url(#grain)" opacity="0.35"/>
"""

# ---------------------------------------------------------------- B: Guild Ledger
B = f"""
<radialGradient id="bBg" cx="45%" cy="40%" r="75%">
  <stop offset="0" stop-color="#6b3a22"/><stop offset="0.55" stop-color="#3f1f12"/><stop offset="1" stop-color="#170a05"/>
</radialGradient>
<linearGradient id="brass" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#f3d58a"/><stop offset="0.5" stop-color="#9c6b22"/><stop offset="1" stop-color="#d9ab55"/>
</linearGradient>
<rect width="400" height="400" fill="url(#bBg)"/>
<rect width="400" height="400" fill="#000" filter="url(#blotch)" opacity="0.6"/>
<!-- tooled border lines in the leather -->
<rect x="34" y="34" width="332" height="332" rx="6" fill="none" stroke="#1a0b05" stroke-width="4" opacity="0.8"/>
<rect x="36" y="36" width="332" height="332" rx="6" fill="none" stroke="#c8954a" stroke-width="1.5" opacity="0.45"/>
<rect x="48" y="48" width="304" height="304" rx="4" fill="none" stroke="#1a0b05" stroke-width="2" opacity="0.7"/>
<rect x="49" y="49" width="304" height="304" rx="4" fill="none" stroke="#c8954a" stroke-width="1" opacity="0.35" stroke-dasharray="6 4"/>
<!-- brass corners -->
<g fill="url(#brass)" stroke="#3a2008" stroke-width="2" filter="url(#emboss)">
  <path d="M8 8 h86 l-12 12 h-62 v62 l-12 12 z"/>
  <path d="M392 8 h-86 l12 12 h62 v62 l12 12 z"/>
  <path d="M8 392 h86 l-12 -12 h-62 v-62 l-12 -12 z"/>
  <path d="M392 392 h-86 l12 -12 h62 v-62 l12 -12 z"/>
</g>
{rivets([(24, 24), (376, 24), (24, 376), (376, 376)], r=5)}
<!-- ornament -->
<g stroke="#d9ab55" stroke-width="2" fill="none" opacity="0.8">
  <path d="M130 108 q70 -30 140 0"/><circle cx="200" cy="96" r="5" fill="#d9ab55"/>
  <path d="M130 292 q70 30 140 0"/><circle cx="200" cy="304" r="5" fill="#d9ab55"/>
</g>
<!-- gold leaf stamped into the leather -->
<text x="200" y="206" text-anchor="middle" font-family="{SERIF}" font-weight="bold" font-size="120" letter-spacing="-1"
      fill="url(#gold)" stroke="#1a0b05" stroke-width="3" paint-order="stroke" filter="url(#bevel)">WoW</text>
<line x1="112" y1="228" x2="288" y2="228" stroke="#d9ab55" stroke-width="2" opacity="0.8"/>
<text x="200" y="272" text-anchor="middle" font-family="{SERIF}" font-weight="bold" font-size="40" letter-spacing="16"
      fill="url(#gold)" stroke="#1a0b05" stroke-width="2" paint-order="stroke" filter="url(#emboss)">CRM</text>
<rect width="400" height="400" fill="#000" filter="url(#grain)" opacity="0.4"/>
"""

# ---------------------------------------------------------------- C: Sealed Charter
C = f"""
<radialGradient id="cParch" cx="50%" cy="45%" r="65%">
  <stop offset="0" stop-color="#f1dfb4"/><stop offset="0.65" stop-color="#d8bb82"/><stop offset="1" stop-color="#8f6a35"/>
</radialGradient>
<radialGradient id="cWax" cx="40%" cy="35%" r="70%">
  <stop offset="0" stop-color="#d23a2c"/><stop offset="0.6" stop-color="#8e1414"/><stop offset="1" stop-color="#4a0606"/>
</radialGradient>
<rect width="400" height="400" fill="#140c07"/>
<!-- the parchment, with scorched edges -->
<g filter="url(#rough)">
  <rect x="22" y="22" width="356" height="356" rx="8" fill="#3a1d0b"/>
  <rect x="28" y="28" width="344" height="344" rx="6" fill="url(#cParch)"/>
</g>
<rect x="28" y="28" width="344" height="344" fill="#5a3410" filter="url(#blotch)" opacity="0.45"/>
<!-- ink rule lines -->
<g stroke="#4a2a10" stroke-width="2" opacity="0.6" filter="url(#rough)">
  <line x1="70" y1="78" x2="330" y2="78"/><line x1="70" y1="86" x2="330" y2="86" stroke-width="1"/>
</g>
<!-- WoW in old ink -->
<text x="200" y="196" text-anchor="middle" font-family="{SERIF}" font-weight="bold" font-size="128" letter-spacing="-2"
      fill="#2b1608" opacity="0.92" filter="url(#rough)">WoW</text>
<!-- wax seal -->
<g filter="url(#shadow)">
  <path d="M200 222 c22 -4 34 6 44 14 c12 8 26 10 28 30 c3 20 -10 26 -14 40 c-5 16 -18 28 -40 26 c-18 2 -26 -10 -42 -14
           c-16 -5 -32 -12 -32 -34 c0 -20 12 -26 18 -38 c8 -16 18 -22 38 -24 z" fill="url(#cWax)" filter="url(#rough)"/>
</g>
<circle cx="204" cy="282" r="40" fill="none" stroke="#5a0808" stroke-width="3" opacity="0.8"/>
<circle cx="204" cy="282" r="33" fill="none" stroke="#e05a48" stroke-width="1.5" opacity="0.5"/>
<text x="204" y="295" text-anchor="middle" font-family="{SERIF}" font-weight="bold" font-size="30" letter-spacing="2"
      fill="#ffd2bf" stroke="#3a0404" stroke-width="2.5" paint-order="stroke" filter="url(#emboss)">CRM</text>
<!-- ribbon under the seal -->
<g opacity="0.95">
  <path d="M176 318 l-14 52 l16 -10 l10 16 l8 -52 z" fill="#7d1010"/>
  <path d="M232 318 l14 52 l-16 -10 l-10 16 l-8 -52 z" fill="#6a0c0c"/>
</g>
<rect x="28" y="28" width="344" height="344" fill="#000" filter="url(#grain)" opacity="0.28"/>
"""

for name, body, bg in (("a", A, "#070505"), ("b", B, "#170a05"), ("c", C, "#140c07")):
    with open(os.path.join(HERE, f"icon-{name}.html"), "w", encoding="utf-8", newline="\n") as f:
        f.write(page(body, bg))
print("written")
