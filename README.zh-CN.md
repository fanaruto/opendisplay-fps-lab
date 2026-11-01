# OpenDisplay FPS Lab

基于 [OpenDisplay](https://github.com/peetzweg/opendisplay) 的独立实验项目，探索 Mac 端简体中文界面与 iPad 扩展屏帧率调节。保留上游 GPL-3.0 许可证和原作者归属。此项目为非官方分支。

## 当前状态

- Mac 端新增 60、90、120 帧实验选项，并翻译部分常用界面；接收端 iPad 应用没有修改。
- 90 和 120 帧绕过 iPad 接收端宣告的 60 帧能力限制，仅供实验，不能保证设备稳定或实际达到目标帧率。
- 第二轮优化后，快速画质下90帧接收样本约89–90，120帧连续窗口中位数约119；最佳画质60帧约59–60。数据、方法与局限见 [开发日志](DEVELOPMENT_LOG.md)。
- 实验版自动更新已关闭，避免被上游版本覆盖。请不要把实验版当作正式发布版。

## 构建与使用

需要 macOS 14+、Xcode、XcodeGen，以及安装了上游 OpenDisplay 接收端的 iPad。执行 `./generate.sh`，再通过 Xcode 构建 `OpenSidecarMac` 的 Debug 配置；本项目的 Debug 产品名称为 `OpenDisplay FPS Lab`。构建后可通过 `./run.sh` 启动；首次使用请按 macOS 提示授予屏幕录制权限。脚本为 ad-hoc 签名设置稳定的指定要求。

本地测试为了复用原中文版的权限，沿用 `com.peetzweg.opensidecar.mac.debug` 标识和相同的 ad-hoc designated requirement。多个相同标识的副本应轮流运行；首次授权是否复用、更新后是否需要再次授权由 macOS 实际判定，不能保证。

更多上游功能、依赖、贡献方式及许可证见原始 [README](README.md) 和 [LICENSE](LICENSE)。

高帧率使用建议：在「帧率（实验）」选择90或120帧，画质选择「快速」。60帧可以使用「最佳」画质。高帧率会自动优先使用H.264，以减少当前Mac的编码开销；降低画质也会降低文字清晰度。
