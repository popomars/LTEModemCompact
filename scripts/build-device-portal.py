#!/usr/bin/env python3
"""Create an offline USB installation entry image, with no executable or autorun."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
dist = root / 'dist'
dist.mkdir(exist_ok=True)
stage = Path(tempfile.mkdtemp(prefix='.portal-', dir=dist))
try:
    releases = 'https://github.com/popomars/LTEModemCompact/releases'
    (stage / 'Download LTEModemCompact.webloc').write_bytes(plistlib.dumps({'URL': releases}))
    (stage / 'START HERE.html').write_text('''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light"><title>LTEModemCompact · 开始使用</title>
<style>body{margin:0;background:#f4f7fb;color:#152d46;font:16px/1.7 -apple-system,BlinkMacSystemFont,sans-serif}main{max-width:720px;margin:9vh auto;padding:40px}small{color:#347fa0;letter-spacing:2px}h1{font-size:38px;line-height:1.2;letter-spacing:-1px}p{color:#61758a}.card{background:white;padding:30px;border-radius:20px;margin:30px 0}a.button{display:inline-block;background:#165d7c;color:white;text-decoration:none;padding:13px 24px;border-radius:12px;font-weight:600}li{margin:12px 0}footer{font-size:13px;color:#61758a}a{color:#165d7c}</style>
<main><small>LTE / MAC</small><h1>LTEModemCompact</h1><p>你的模块已连接。只用网卡上网时，无需安装应用。</p>
<div class="card"><h2>短信、流量与连接管理</h2><p>安装原生 Mac 应用，查看流量、收发短信并接收新短信提醒。</p>
<a class="button" href="https://github.com/popomars/LTEModemCompact/releases">前往 GitHub 下载安装包 ↗</a>
<ol><li>在发布页下载最新的 macOS arm64 DMG（适用于 Apple Silicon）。</li><li>打开 DMG，将应用拖入 Applications，再从“应用程序”打开。</li><li>在设置中按需开启短信通知和“插入模块时启动”。</li></ol></div>
<footer>这是只读安装入口，未安装或自动执行任何程序；下载需要互联网连接。<br>
macOS 13+；开发预览版，尚未进行 Apple 公证。首次打开可能需要在“隐私与安全性”中点“仍要打开”。<br>
如果 GitHub 暂不可用，可改用可访问 GitHub 的网络后重试。请勿将短信或 SIM 标识提交到公开仓库。</footer></main></html>''', encoding='utf-8')
    (stage / 'README.txt').write_text('''LTEModemCompact — Mac installation entry

打开 START HERE.html 查看中文指引，或双击 Download LTEModemCompact.webloc 打开 GitHub 发布页。
Open START HERE.html, or double-click Download LTEModemCompact.webloc.

https://github.com/popomars/LTEModemCompact/releases

只用 ECM 网卡上网无需应用；短信、通知和流量统计需要应用运行。
此盘不会自动运行代码、下载或安装软件。下载需要可访问 GitHub 的网络。
请下载 Apple Silicon arm64 DMG，拖入 Applications 后打开。
''', encoding='utf-8')
    output = dist / 'LTEModemCompact-Install-Portal.iso'
    subprocess.run(['hdiutil', 'makehybrid', '-iso', '-joliet', '-default-volume-name', 'LTE MODEM',
                    '-o', str(output), str(stage), '-ov'], check=True)
    print(output)
finally:
    shutil.rmtree(stage)
