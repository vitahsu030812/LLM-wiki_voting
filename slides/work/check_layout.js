// 關卡 D（版面）：在瀏覽器開啟簡報後，於主控台或自動化工具執行本檔內容。
// 回傳 { mode, viewport, problems: [...] }；problems 為空即通過。
// 桌機模式（寬 > 820）：每頁內容不得超出投影片、不得壓到頁尾、圖表不得超出左欄。
// 手機模式（寬 ≤ 820）：不得出現水平捲動、元素不得超出視窗寬度。
(function () {
  var problems = [];
  var mobile = innerWidth <= 820;
  var slides = [].slice.call(document.querySelectorAll('.slide'));
  slides.forEach(function (s) {
    var id = s.dataset.id;
    var was = s.classList.contains('active');
    s.classList.add('active');
    var sr = s.getBoundingClientRect();
    var sc = mobile ? 1 : sr.height / 720;
    var folio = s.querySelector('.folio');
    var ft = folio ? folio.getBoundingClientRect().top : sr.bottom;
    s.querySelectorAll('*').forEach(function (el) {
      if (folio && (el === folio || folio.contains(el))) return;
      var r = el.getBoundingClientRect();
      if (!r.width || !r.height) return;
      if (el.closest('svg') && el.tagName !== 'svg') return;
      var name = el.tagName.toLowerCase() + (el.className && el.className.baseVal === undefined ? '.' + String(el.className).split(' ')[0] : '');
      if (mobile) {
        if (r.right > innerWidth + 1) problems.push(id + ' 超出視窗寬度：' + name);
      } else {
        if (!s.classList.contains('cover') && r.bottom > ft + 1) problems.push(id + ' 壓到頁尾：' + name + ' 底部 ' + Math.round((r.bottom - sr.top) / sc));
        if (r.right > sr.right + 1) problems.push(id + ' 超出右邊界：' + name);
      }
      if (el.scrollHeight > el.clientHeight + 2 && getComputedStyle(el).overflowY === 'hidden' && el !== s) problems.push(id + ' 內容被截斷：' + name);
    });
    var fig = s.querySelector('.fig');
    if (fig && !mobile) {
      var fr = fig.getBoundingClientRect();
      fig.querySelectorAll('*').forEach(function (el) {
        var r = el.getBoundingClientRect();
        if (r.width && r.right > fr.right + 2) problems.push(id + ' 圖表超出左欄：' + el.tagName.toLowerCase());
      });
    }
    // 文字互相重疊：以每個文字節點實際字形的外框（Range）兩兩比對（含 SVG text）
    var leaves = [], tw = document.createTreeWalker(s, NodeFilter.SHOW_TEXT), tn;
    while ((tn = tw.nextNode())) {
      if (!tn.textContent.trim()) continue;
      var pe = tn.parentElement;
      if (!pe || (folio && folio.contains(pe)) || pe.closest('title')) continue;
      var rg = document.createRange(); rg.selectNodeContents(tn);
      [].forEach.call(rg.getClientRects(), function (rr) { if (rr.width && rr.height) leaves.push({ el: pe, r: rr }); });
    }
    for (var a = 0; a < leaves.length; a++) for (var b = a + 1; b < leaves.length; b++) {
      var A = leaves[a], B = leaves[b];
      if (A.el === B.el) continue;
      var ox = Math.min(A.r.right, B.r.right) - Math.max(A.r.left, B.r.left);
      var oy = Math.min(A.r.bottom, B.r.bottom) - Math.max(A.r.top, B.r.top);
      if (ox > 2 && oy > 2) problems.push(id + ' 文字重疊：「' + A.el.textContent.trim().slice(0, 12) + '」×「' + B.el.textContent.trim().slice(0, 12) + '」');
    }
    if (!was) s.classList.remove('active');
  });
  if (mobile && document.documentElement.scrollWidth > innerWidth + 1) problems.push('頁面出現水平捲動');
  var seen = {}, uniq = problems.filter(function (p) { var k = p.replace(/[:：].*$/, ''); return seen[p] ? false : (seen[p] = 1); });
  return { mode: mobile ? 'mobile' : 'desktop', viewport: innerWidth + 'x' + innerHeight, problems: uniq.slice(0, 60), total: uniq.length };
})();
