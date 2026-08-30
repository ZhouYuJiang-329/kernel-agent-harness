# Boujoy Harness 便携分享版验收说明

## 本版修复

- 使用显式包根目录与一次性文件夹恢复，处理 macOS App Translocation 和移动 App 后的相对路径失效。
- 产品网关新增就绪检查；启动页在 WebKit 就绪后再轮询，采用最长 45 秒的退避等待，不再强制停留两秒。
- 缺失的独立知识库预览脚本会静默降级，不会阻塞主界面。
- Agent 审批/提问返回 `not-pending` 时会丢弃过期项并继续队列；其他传输失败会关闭弹窗、保留可重试提示。
- 专家、风格与调用表单的关闭/取消按钮不再触发必填校验。

## 已验证

- 隔离网关、路径约束、WebSocket、中继、会话删除、记录 CRUD、启动器根目录传递：自动回归通过。
- JavaScript 语法、Python 隔离测试、Swift 原生编译、App 临时签名与包内资源一致性均应在打包时复核。

## 分发边界

- 当前是 Apple Silicon 的 macOS 13+ 测试分享版。
- 包内不应含用户的 API Key、个人会话或个人知识库。
- ad-hoc 签名不等于 Apple 公证；面向公开互联网下载仍需 Developer ID 与 notarization。
