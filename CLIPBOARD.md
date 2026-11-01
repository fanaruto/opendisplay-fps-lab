# iPad → Mac 剪贴板：文字和链接

第一版采用手动发送：iPad 保留原版 OpenDisplay，使用系统「快捷指令」读取用户刚复制的内容，发送到 Mac，然后在 Mac 按 ⌘V 粘贴。不同 Apple 账号可以使用；两台设备须在同一局域网，USB 副屏连接照常使用。

## 首次配对

1. Mac 打开 OpenDisplay FPS Lab，在「剪贴板」开启「接收 iPad 剪贴板（手动发送）」，点击「iPad 配对…」。
2. iPad 用相机扫描二维码。配对页面先复制本机地址，再下载快捷指令。
3. 打开下载文件，添加「发送剪贴板到 Mac」。在「Mac 接收地址」问题中粘贴完整地址。
4. 首次运行时，按系统提示允许访问剪贴板及本地网络。

也可以从 Mac 导出快捷指令，通过隔空投送发到自己的 iPad。添加时仍需填写 Mac 的配对地址。导出的文件是通用模板，不包含本机密钥。

## 日常使用

在 iPad 复制文字或网址，运行「发送剪贴板到 Mac」。快捷指令会显示 Mac 返回的结果；收到后在 Mac 按 ⌘V。发送完成可切回 OpenDisplay。Mac 设置中可查看最近接收时间和本次接收次数。

每次接收最多 256 KiB UTF-8 文字。原样保留换行、空格及 Unicode 字符；独立网址同时写入 Mac 的文字与 URL 剪贴板类型。Mac 上的接收开关可以随时关闭。

页面打不开时，先确认 Mac 接收开关已打开、设备在同一局域网，并按系统提示允许本地网络访问。发送报错时重新扫码核对完整地址；更改 Mac 主机名或重建配对配置后，需要更新快捷指令中的地址。

## 实现与构建

- Mac 使用 `NWListener`，默认端口 `43187`；每个请求用随机配对密钥认证。密钥仅保存在本机 `~/Library/Application Support/OpenDisplay FPS Lab/Clipboard/pairing-key`，目录权限 `0700`，文件权限 `0600`。
- `GET /<key>/setup` 提供本地配对页面，`GET /<key>/shortcut` 提供已签名通用模板，`POST /<key>/clipboard` 接收 `application/json` 的 `{"text":"内容"}`，也接受 UTF-8 `text/plain`。
- 请求头最多 8 KiB，请求体小于 1 MiB，文字最多 256 KiB；连接有超时与并发上限。拒绝错误配对地址、浏览器跨来源请求、重复请求头及不支持的传输格式。
- 内容校验通过后，在主线程写入系统剪贴板，再返回成功结果。接收服务不记录复制内容或配对地址。带独立传输 UUID 的完整消息支持有界去重；每次手动运行快捷指令视为一次新的发送。
- iPad OpenDisplay 应用和视频流协议均未修改。视频帧率与画质配置沿用原版实验设置。

模板源码是 `scripts/build-clipboard-shortcut.py`。需要更新模板时，在仓库根目录执行：

```sh
python3 scripts/build-clipboard-shortcut.py build/clipboard/SendClipboardToMac.unsigned.shortcut
shortcuts sign --mode anyone \
  --input build/clipboard/SendClipboardToMac.unsigned.shortcut \
  --output Resources/SendClipboardToMac.shortcut
xcodegen generate
```

签名模板仅含占位地址；真实配对地址在 iPad 导入时本地填写。[Apple 说明签名流程会提交快捷指令进行校验](https://support.apple.com/guide/shortcuts-mac/apd455c82f02/mac)，因此不要将真实密钥写进待签名模板或公开仓库。更新 Mac 应用继续使用项目约定的包标识与签名要求。

## 2026-11-01 验证结果

- 53 项测试全部通过：12 项剪贴板数据、写入及 HTTP 测试，41 项原有流配置回归测试。
- 用系统快捷指令实际执行「构造测试文字 → POST → Mac 独立测试剪贴板 → 读取回执」，中文、换行和网址内容逐字一致。自动测试未覆盖日常系统剪贴板。
- 本地配对页在 834×1194 和 390×844 视口检查，无横向溢出；下载的中文文件名正确，文件与打包模板的 SHA-256 一致。
- Mac 更新已安装，主应用及依赖签名校验通过；仍只有一个发送进程，原生清晰与 120 帧目标保留，屏幕录制和辅助功能权限复用。
- iPad 用户按扫码流程添加快捷指令，复制文字并在 Mac 粘贴后，明确确认「已成功粘贴」。独立网址的 Mac 类型和 HTTP 测试通过，尚未另作 iPad 网址单项验收。本轮未重新测量视频帧率。

结构化记录见 [CLIPBOARD_TEST_RESULTS.json](CLIPBOARD_TEST_RESULTS.json)。
