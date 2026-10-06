import * as THREE from 'three';

// Procedural canvas textures (no external image assets needed for the grey-box stage).

function canvas(w: number, h: number): [HTMLCanvasElement, CanvasRenderingContext2D] {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  return [c, c.getContext('2d')!];
}

function finish(c: HTMLCanvasElement, repeat = true, srgb = true): THREE.CanvasTexture {
  const t = new THREE.CanvasTexture(c);
  if (repeat) t.wrapS = t.wrapT = THREE.RepeatWrapping;
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  return t;
}

function noise(g: CanvasRenderingContext2D, w: number, h: number, amount: number, alpha: number): void {
  for (let i = 0; i < amount; i++) {
    const v = Math.random() * 255;
    g.fillStyle = `rgba(${v},${v},${v},${alpha})`;
    g.fillRect(Math.random() * w, Math.random() * h, 1 + Math.random() * 2, 1 + Math.random() * 2);
  }
}

/**
 * Carriageway texture: u spans the road width (-6..6 m), v repeats every 12 m.
 * Dutch motorway markings: solid edge lines, 3 m dash / 9 m gap between lanes.
 */
export function roadTexture(): THREE.CanvasTexture {
  const W = 512;
  const H = 512;
  const [c, g] = canvas(W, H);
  g.fillStyle = '#3b3c3f';
  g.fillRect(0, 0, W, H);
  noise(g, W, H, 26000, 0.08);
  // Tyre tracks in lane centres.
  const m = (d: number) => ((d + 6) / 12) * W;
  g.fillStyle = 'rgba(20,20,22,0.18)';
  for (const lane of [-2.75, 0.75]) {
    g.fillRect(m(lane - 1.1), 0, m(0.5) - m(0), H);
    g.fillRect(m(lane + 0.6), 0, m(0.5) - m(0), H);
  }
  // Shoulder (outside the rails) a touch lighter.
  g.fillStyle = 'rgba(120,120,110,0.25)';
  g.fillRect(0, 0, m(-5.5), H);
  g.fillRect(m(5.5), 0, W - m(5.5), H);
  g.fillStyle = '#e9e9e2';
  const line = (d: number, wid: number, dash = false) => {
    if (dash) g.fillRect(m(d) - (m(wid) - m(0)) / 2, 0, m(wid) - m(0), H * 0.25);
    else g.fillRect(m(d) - (m(wid) - m(0)) / 2, 0, m(wid) - m(0), H);
  };
  line(-4.5, 0.15);
  line(-1.0, 0.15, true);
  line(2.5, 0.2);
  return finish(c);
}

export function grassTexture(): THREE.CanvasTexture {
  const [c, g] = canvas(256, 256);
  g.fillStyle = '#4f6f2a';
  g.fillRect(0, 0, 256, 256);
  for (let i = 0; i < 9000; i++) {
    const h = 70 + Math.random() * 40;
    const l = 22 + Math.random() * 18;
    g.fillStyle = `hsla(${h},45%,${l}%,0.5)`;
    g.fillRect(Math.random() * 256, Math.random() * 256, 1, 2 + Math.random() * 3);
  }
  return finish(c);
}

export function fieldTexture(): THREE.CanvasTexture {
  // Large-scale patchwork of Twente fields, used on the ground plane.
  const [c, g] = canvas(1024, 1024);
  const colors = ['#5a7a2e', '#6b8a35', '#4e6b28', '#8a8a3a', '#6f7f30', '#7d6a3c', '#557833'];
  for (let y = 0; y < 1024; y += 128) {
    for (let x = 0; x < 1024; x += 128) {
      const ox = Math.random() * 30 - 15;
      g.fillStyle = colors[Math.floor(Math.random() * colors.length)];
      g.fillRect(x + ox, y, 128 + 30, 128);
    }
  }
  g.strokeStyle = 'rgba(40,55,20,0.6)';
  g.lineWidth = 3;
  for (let i = 0; i <= 1024; i += 128) {
    g.beginPath();
    g.moveTo(i, 0);
    g.lineTo(i, 1024);
    g.stroke();
  }
  noise(g, 1024, 1024, 60000, 0.05);
  return finish(c);
}

export function concreteTexture(): THREE.CanvasTexture {
  const [c, g] = canvas(256, 256);
  g.fillStyle = '#9c9a94';
  g.fillRect(0, 0, 256, 256);
  noise(g, 256, 256, 12000, 0.12);
  return finish(c);
}

export function checkerTexture(): THREE.CanvasTexture {
  const [c, g] = canvas(256, 64);
  for (let y = 0; y < 2; y++) {
    for (let x = 0; x < 8; x++) {
      g.fillStyle = (x + y) % 2 ? '#111' : '#f2f2f2';
      g.fillRect(x * 32, y * 32, 32, 32);
    }
  }
  return finish(c, false);
}

/** Blue Dutch motorway sign (ANWB style) with a red route shield. */
export function signTexture(lines: string[], route: string): THREE.CanvasTexture {
  const [c, g] = canvas(512, 256);
  g.fillStyle = '#123f8c';
  g.fillRect(0, 0, 512, 256);
  g.strokeStyle = '#f2f2f2';
  g.lineWidth = 6;
  g.strokeRect(10, 10, 492, 236);
  g.fillStyle = '#ffffff';
  g.font = 'bold 54px "Arial Narrow", Arial, sans-serif';
  lines.forEach((t, i) => g.fillText(t, 36, 90 + i * 72));
  // Route shield
  g.fillStyle = '#c4161c';
  g.fillRect(390, 168, 96, 56);
  g.strokeStyle = '#fff';
  g.lineWidth = 4;
  g.strokeRect(392, 170, 92, 52);
  g.fillStyle = '#fff';
  g.font = 'bold 38px Arial, sans-serif';
  g.textAlign = 'center';
  g.fillText(route, 438, 210);
  // Arrow
  g.beginPath();
  g.moveTo(438, 40);
  g.lineTo(468, 80);
  g.lineTo(448, 80);
  g.lineTo(448, 140);
  g.lineTo(428, 140);
  g.lineTo(428, 80);
  g.lineTo(408, 80);
  g.closePath();
  g.fill();
  return finish(c, false);
}

/** Dutch place-name sign: blue with white border. */
export function placeSignTexture(name: string, sub = ''): THREE.CanvasTexture {
  const [c, g] = canvas(512, 224);
  g.fillStyle = '#123f8c';
  g.fillRect(0, 0, 512, 224);
  g.strokeStyle = '#fff';
  g.lineWidth = 10;
  g.strokeRect(14, 14, 484, 196);
  g.fillStyle = '#fff';
  g.textAlign = 'center';
  g.font = 'bold 78px "Arial Narrow", Arial, sans-serif';
  g.fillText(name, 256, sub ? 120 : 140);
  if (sub) {
    g.font = 'bold 40px Arial, sans-serif';
    g.fillText(sub, 256, 180);
  }
  return finish(c, false);
}

export function bannerTexture(text: string): THREE.CanvasTexture {
  const [c, g] = canvas(1024, 160);
  const grd = g.createLinearGradient(0, 0, 1024, 0);
  grd.addColorStop(0, '#ff3d00');
  grd.addColorStop(1, '#ffb300');
  g.fillStyle = grd;
  g.fillRect(0, 0, 1024, 160);
  for (let x = 0; x < 1024; x += 40) {
    g.fillStyle = (x / 40) % 2 ? '#111' : '#fff';
    g.fillRect(x, 0, 40, 18);
    g.fillStyle = (x / 40) % 2 ? '#fff' : '#111';
    g.fillRect(x, 142, 40, 18);
  }
  g.fillStyle = '#fff';
  g.font = 'italic bold 92px Impact, "Arial Black", sans-serif';
  g.textAlign = 'center';
  g.strokeStyle = '#111';
  g.lineWidth = 8;
  g.strokeText(text, 512, 114);
  g.fillText(text, 512, 114);
  return finish(c, false);
}

/** Apartment/office facade: a window grid, some windows lit (returns colour + emissive maps). */
export function facadeTextures(seed: number, wall: string): { map: THREE.CanvasTexture; glow: THREE.CanvasTexture } {
  let r = seed * 9301 + 49297;
  const rand = () => ((r = (r * 9301 + 49297) % 233280) / 233280);
  const W = 128;
  const H = 256;
  const [c, g] = canvas(W, H);
  const [c2, g2] = canvas(W, H);
  g.fillStyle = wall;
  g.fillRect(0, 0, W, H);
  noise(g, W, H, 1500, 0.06);
  g2.fillStyle = '#000';
  g2.fillRect(0, 0, W, H);
  const cols = 6;
  const rows = 12;
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      const px = 6 + x * (W - 12) / cols;
      const py = 6 + y * (H - 12) / rows;
      const w = (W - 12) / cols - 6;
      const h = (H - 12) / rows - 8;
      const lit = rand() < 0.35;
      g.fillStyle = lit ? '#ffd9a0' : '#1c2733';
      g.fillRect(px, py, w, h);
      if (lit) {
        g2.fillStyle = '#ffb860';
        g2.fillRect(px, py, w, h);
      }
    }
  }
  return { map: finish(c), glow: finish(c2) };
}

/**
 * Single-carriageway N-road (N35): edge lines, and the Dutch "groene as" in the centre:
 * two solid lines with green paint between them. Same width/UV layout as roadTexture.
 */
export function singleRoadTexture(): THREE.CanvasTexture {
  const W = 512;
  const H = 512;
  const [c, g] = canvas(W, H);
  g.fillStyle = '#3e3f42';
  g.fillRect(0, 0, W, H);
  noise(g, W, H, 26000, 0.08);
  const m = (d: number) => ((d + 6) / 12) * W;
  g.fillStyle = 'rgba(20,20,22,0.18)';
  for (const lane of [-2.75, 0.75]) {
    g.fillRect(m(lane - 1.1), 0, m(0.5) - m(0), H);
    g.fillRect(m(lane + 0.6), 0, m(0.5) - m(0), H);
  }
  // Paved shoulder outside the edge lines, a little lighter.
  g.fillStyle = 'rgba(120,120,110,0.22)';
  g.fillRect(0, 0, m(-4.5), H);
  g.fillRect(m(2.6), 0, W - m(2.6), H);
  // Green centre strip between two solid lines.
  g.fillStyle = '#3f7d3a';
  g.fillRect(m(-1.25), 0, m(-0.75) - m(-1.25), H);
  g.fillStyle = '#e9e9e2';
  const line = (d: number, wid: number) => g.fillRect(m(d) - (m(wid) - m(0)) / 2, 0, m(wid) - m(0), H);
  line(-1.25, 0.12);
  line(-0.75, 0.12);
  line(-4.5, 0.15);
  line(2.55, 0.15);
  return finish(c);
}
