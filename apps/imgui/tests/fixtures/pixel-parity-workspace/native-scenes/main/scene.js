(() => {
  const canvas = document.querySelector('[data-remake-export]');
  const ctx = canvas.getContext('2d');
  const duration = 13.26;
  function seek(time) { ctx.clearRect(0, 0, canvas.width, canvas.height); }
  window.__remake = { duration, seek, playFrom: seek, pause() {}, getExportCanvas: () => canvas };
  seek(0);
})();
