# Boujoy Harness 便携分享版

这是一个完整的 macOS 本地包。请始终保留同一文件夹里的 `Boujoy Harness.app`、`runtime/` 和 `vault/`，不要单独复制其中任何一项。

## 正确启动方式

1. 先把 ZIP **完整解压**到桌面、下载或文稿等任意位置。
2. 双击根目录的 **`启动 Boujoy Harness.command`**。
3. 首次启动会拉起本地引擎，等几秒后再开始对话。

这个启动器会把包的真实位置交给 App，避免未签名 App 被 macOS App Translocation 隔离后找不到同级 `runtime/`、`vault/` 的问题。

如果误双击了 `Boujoy Harness.app`，新版会提示你选择已解压的整个 Boujoy Harness 文件夹；选择后会记住该位置。不要根据网上命令强行绕过系统安全提示。

## 系统与边界

- 仅支持 macOS 13+、Apple Silicon（M 系列）；不支持 Intel Mac。
- `vault/` 是本地 Markdown 知识库；`runtime/` 是已内置的 Harness 与 Python 运行时。
- 首次对话前，在 App 的「设置 → 模型」中配置自己的模型凭证。凭证和会话保存在本机。
- 当前包使用 ad-hoc 本地签名，适合测试和朋友分享；公开互联网发布仍需要 Developer ID 签名与 Apple notarization。

## 常见情况

**启动后提示找不到组件**：确认没有把 App、`runtime/` 或 `vault/` 分开；回到完整解压后的根目录，双击 `启动 Boujoy Harness.command`。

**启动页停留较久**：本地运行时正在冷启动。新版最多等待 45 秒；如果仍失败，请重新保持完整目录后启动，并把提示截图发给分发者。

**知识库预览服务未出现**：不影响 Harness 主界面、Markdown 浏览、搜索和 Agent。独立预览服务在此便携包中是可选组件。

## 目录

```text
DAY1-Clean/
├── 启动 Boujoy Harness.command  # 推荐入口
├── Boujoy Harness.app
├── runtime/
├── vault/
└── src/                         # 对应开源源码快照
```
