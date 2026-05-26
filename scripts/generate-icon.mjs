import { deflateSync } from "node:zlib";
import { mkdirSync, writeFileSync } from "node:fs";

const size = 1024;
const output = "src-tauri/icons/icon.png";
const data = Buffer.alloc((size * 4 + 1) * size);

function clamp(value, min = 0, max = 1) {
  return Math.max(min, Math.min(max, value));
}

function mix(a, b, t) {
  return a + (b - a) * t;
}

function smoothstep(edge0, edge1, value) {
  const x = clamp((value - edge0) / (edge1 - edge0));
  return x * x * (3 - 2 * x);
}

function roundedRectAlpha(x, y, cx, cy, width, height, radius) {
  const qx = Math.abs(x - cx) - width / 2 + radius;
  const qy = Math.abs(y - cy) - height / 2 + radius;
  const outside = Math.hypot(Math.max(qx, 0), Math.max(qy, 0));
  const inside = Math.min(Math.max(qx, qy), 0);
  const distance = outside + inside - radius;
  return 1 - smoothstep(-1.5, 1.5, distance);
}

function segmentAlpha(px, py, ax, ay, bx, by, width) {
  const vx = bx - ax;
  const vy = by - ay;
  const wx = px - ax;
  const wy = py - ay;
  const t = clamp((wx * vx + wy * vy) / (vx * vx + vy * vy));
  const x = ax + vx * t;
  const y = ay + vy * t;
  return 1 - smoothstep(width - 1.5, width + 1.5, Math.hypot(px - x, py - y));
}

function circleAlpha(px, py, cx, cy, radius) {
  return 1 - smoothstep(radius - 1.5, radius + 1.5, Math.hypot(px - cx, py - cy));
}

function over(base, color, alpha) {
  const a = clamp(alpha);
  return [
    Math.round(mix(base[0], color[0], a)),
    Math.round(mix(base[1], color[1], a)),
    Math.round(mix(base[2], color[2], a)),
    Math.round(255 * clamp(base[3] / 255 + a * (1 - base[3] / 255)))
  ];
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, body) {
  const typeBuffer = Buffer.from(type);
  const length = Buffer.alloc(4);
  length.writeUInt32BE(body.length);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuffer, body])));
  return Buffer.concat([length, typeBuffer, body, crc]);
}

for (let y = 0; y < size; y += 1) {
  const row = y * (size * 4 + 1);
  data[row] = 0;

  for (let x = 0; x < size; x += 1) {
    const offset = row + 1 + x * 4;
    const nx = x / (size - 1);
    const ny = y / (size - 1);
    const shell = roundedRectAlpha(x, y, size / 2, size / 2, 850, 850, 210);
    const inner = roundedRectAlpha(x, y, size / 2, size / 2, 760, 760, 168);
    const sheen = clamp(1 - Math.hypot(nx - 0.24, ny - 0.16) * 1.5);
    const depth = clamp(Math.hypot(nx - 0.74, ny - 0.82));

    let pixel = [
      Math.round(mix(245, 226, depth) + sheen * 8),
      Math.round(mix(247, 234, depth) + sheen * 7),
      Math.round(mix(250, 242, depth) + sheen * 5),
      Math.round(shell * 255)
    ];

    pixel = over(pixel, [217, 224, 233, 255], shell * (1 - inner) * 0.28);

    const left = segmentAlpha(x, y, 342, 710, 342, 314, 52);
    const diag = segmentAlpha(x, y, 342, 314, 682, 710, 58);
    const right = segmentAlpha(x, y, 682, 710, 682, 314, 52);
    const mark = Math.max(left, diag, right);
    const blueLight = clamp(1 - Math.hypot(nx - 0.62, ny - 0.31) * 2.1);
    const markColor = [
      Math.round(mix(22, 37, blueLight)),
      Math.round(mix(54, 103, blueLight)),
      Math.round(mix(91, 236, blueLight))
    ];

    pixel = over(pixel, markColor, mark * 0.94);

    const nodeColor = [255, 255, 255, 255];
    pixel = over(pixel, nodeColor, circleAlpha(x, y, 342, 314, 32) * 0.82);
    pixel = over(pixel, nodeColor, circleAlpha(x, y, 682, 710, 32) * 0.82);
    pixel = over(pixel, [45, 112, 255, 255], circleAlpha(x, y, 704, 302, 42) * 0.95);
    pixel = over(pixel, [255, 255, 255, 255], circleAlpha(x, y, 704, 302, 15) * 0.86);

    data[offset] = pixel[0];
    data[offset + 1] = pixel[1];
    data[offset + 2] = pixel[2];
    data[offset + 3] = pixel[3];
  }
}

const signature = Buffer.from("89504e470d0a1a0a", "hex");
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(size, 0);
ihdr.writeUInt32BE(size, 4);
ihdr[8] = 8;
ihdr[9] = 6;

const png = Buffer.concat([
  signature,
  chunk("IHDR", ihdr),
  chunk("IDAT", deflateSync(data)),
  chunk("IEND", Buffer.alloc(0))
]);

mkdirSync("src-tauri/icons", { recursive: true });
writeFileSync(output, png);
console.log(`Generated ${output}`);
