// iPhone and iPad: Safari ignores `user-scalable=no`, so block pinch and double-tap zoom ourselves.
// (touch-action in the CSS does most of it; these catch what Safari still lets through.)

export function disablePageZoom(): void {
  const block = (e: Event) => e.preventDefault();
  // Safari's own pinch gestures.
  for (const type of ['gesturestart', 'gesturechange', 'gestureend']) {
    document.addEventListener(type, block, { passive: false });
  }
  // Two fingers moving = a pinch.
  document.addEventListener(
    'touchmove',
    (e) => {
      if (e.touches.length > 1) e.preventDefault();
    },
    { passive: false },
  );
  // Double tap on anything that isn't a button (buttons need quick repeated taps, e.g. initials).
  let lastEnd = 0;
  document.addEventListener(
    'touchend',
    (e) => {
      const now = performance.now();
      const target = e.target as Element | null;
      if (now - lastEnd < 320 && !target?.closest?.('button, [data-act], [data-i], [data-k]')) e.preventDefault();
      lastEnd = now;
    },
    { passive: false },
  );
  document.addEventListener('dblclick', block, { passive: false });
}
