export function step(x, v, k, damping, dt = 1 / 60) {
  const a = -k * x - damping * v;
  v += a * dt;
  x += v * dt;
  return [x, v];
}
