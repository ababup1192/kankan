#!/usr/bin/env python3
"""書き出した build/web/index.html を、スマホの見えている範囲に収まる形へ直す（export-web の後に流す）。

viewport-fit=cover を外し、canvas の高さをブラウザのツールバーを除いた高さ（visualViewport）にそろえる。
"""
import pathlib
import re
import shutil
import sys

page = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build/web/index.html")
html = page.read_text(encoding="utf-8")
html = html.replace(", viewport-fit=cover", "")

fit = """<style>
  html, body { position: fixed; inset: 0; width: 100%; height: 100%; cursor: pointer; }
  body.fge-portrait-design:not(.fge-pad-on) #fge-canvas { top: var(--fit-top, 0px) !important; height: var(--fit-height, 100dvh) !important; }
</style>
<script>
(function () {
  function fit() {
    var v = window.visualViewport;
    var root = document.documentElement.style;
    root.setProperty("--fit-height", Math.min(v ? v.height : Infinity, window.innerHeight, document.documentElement.clientHeight || Infinity) + "px");
    root.setProperty("--fit-top", (v ? v.offsetTop : 0) + "px");
    window.scrollTo(0, 0);
  }
  // iOS は押せる物でない所のタップに click を出さないので、「タップで始める」の間だけ指の pointerup と touchend を click へ替える。
  // WhyNot: pointerdown にしない — 指の pointerdown は操作に数えられず、音を起こせない。マウスは click が来るので読み飛ばす。
  function tapStart(e) {
    if (e.pointerType === "mouse") return;
    var start = document.getElementById("fge-start");
    if (start && getComputedStyle(start).display !== "none") window.dispatchEvent(new MouseEvent("click"));
  }
  window.addEventListener("pointerup", tapStart);
  document.addEventListener("touchend", tapStart, { passive: true });
  fit();
  window.addEventListener("resize", fit);
  window.addEventListener("orientationchange", fit);
  if (window.visualViewport) {
    window.visualViewport.addEventListener("resize", fit);
    window.visualViewport.addEventListener("scroll", fit);
  }
})();
</script>
"""
html = re.sub(r"<style>\n  html, body \{ position: fixed.*?</script>\n", "", html, flags=re.S)
icon = '<link rel="icon" type="image/png" href="favicon.png">\n<link rel="apple-touch-icon" href="favicon.png">\n'
if "favicon.png" not in html:
    html = html.replace("</head>", icon + "</head>", 1)
shutil.copy(pathlib.Path(__file__).parent.parent / "assets/favicon.png", page.with_name("favicon.png"))
html = html.replace("</head>", fit + "</head>", 1)
page.write_text(html, encoding="utf-8")
print("fit-page:", page)
