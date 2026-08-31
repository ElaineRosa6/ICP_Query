# 云端同步记录（2026-08-31）

- 原分支：`main`
- 同步分支：`codex/cloud-sync-20260831`
- 上游：`origin/main`；个人 fork：`fork`。
- 已快进吸收上游 8 个提交（Python 源码迁至 `src/python`，新增 Rust/MCP 实现）。
- 冲突归并原则：以上游新目录和线程安全/MCP 实现为基线，迁移本地 IPv6、代理池、异步日志、查询增强与错误脱敏修复。
- 可再生扫描输出 `.audit-results-incremental/` 已加入 `.gitignore`。
- 验证：`python -m pytest -q`（9 passed）、`cargo test --locked`、Python compileall、路由注册检查。
- 回滚引用：`refs/codex/cloud-sync-pre-20260831/main`；stash `7dd89efe2f2f6e82363d163b51e55e8bce6d6189` 暂留作二次保险。
