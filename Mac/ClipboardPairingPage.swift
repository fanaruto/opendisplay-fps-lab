import Foundation

/// No embedded credentials: the private address is derived on the iPad from
/// the scanned local URL. No third-party scripts, storage, or network requests.
enum ClipboardPairingPage {
    static let data = Data("""
    <!doctype html><html lang="zh-CN"><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="referrer" content="no-referrer">
    <title>连接 Mac 剪贴板 · OpenDisplay</title>
    <style>
    :root{color-scheme:light dark;font:17px/1.6 -apple-system,BlinkMacSystemFont,sans-serif}
    body{margin:0;background:Canvas;color:CanvasText}main{max-width:38rem;margin:3rem auto;padding:0 1.4rem}
    h1{font-size:1.65rem;line-height:1.3;margin:0 0 1rem}h2{font-size:1.1rem;margin:2rem 0 .5rem}
    p{margin:.6rem 0}textarea{box-sizing:border-box;width:100%;font:inherit;font-size:.85rem;padding:.7rem;
    border:1px solid GrayText;border-radius:.4rem;background:Field;color:FieldText;resize:vertical}
    button,a{font:inherit}button,.download{display:inline-block;background:#0062cc;color:white;border:0;
    padding:.65rem 1rem;border-radius:.45rem;cursor:pointer;text-decoration:none;margin:.5rem 0}
    button:focus-visible,a:focus-visible,textarea:focus-visible{outline:3px solid Highlight;outline-offset:3px}
    #result{min-height:1.6em}small{display:block;margin-top:2rem}
    </style><main>
    <h1>把 iPad 复制的文字，发送到 Mac</h1>
    <p>保留现有 OpenDisplay。两台设备接入同一局域网，USB 继续负责副屏画面。</p>
    <h2>1. 复制这台 Mac 的配对地址</h2>
    <textarea id="address" rows="4" readonly aria-label="Mac 配对地址"></textarea>
    <button id="copy" type="button">复制配对地址</button><p id="result" role="status"></p>
    <h2>2. 添加快捷指令</h2>
    <a class="download" href="shortcut" download="发送剪贴板到 Mac.shortcut">下载快捷指令</a>
    <p>打开下载的文件，添加「发送剪贴板到 Mac」。设置时，将刚复制的地址粘贴到「Mac 接收地址」。</p>
    <h2>3. 复制后，手动发送</h2>
    <p>在 iPad 复制文字或链接，运行这个快捷指令。Mac 收到后，按 ⌘V 粘贴。</p>
    <p>首次运行时，按系统提示允许访问剪贴板和本地网络。发送后可切回 OpenDisplay。</p>
    <small>仅传输文字和链接，每次最多 256 KiB。关闭 Mac 的接收开关后会停止接收。</small>
    </main><script>
    const address=document.getElementById('address');
    address.value=location.origin+location.pathname.replace(/setup$/, 'clipboard');
    document.getElementById('copy').addEventListener('click',()=>{
      address.focus();address.select();address.setSelectionRange(0,address.value.length);
      let copied=false;try{copied=document.execCommand('copy')}catch(e){}
      document.getElementById('result').textContent=copied?'已复制。接着下载并添加快捷指令。':'请长按上面的地址，选择全选并复制。';
    });
    </script></html>
    """.utf8)
}
