---
name: icp-query-may2026-refactor
description: 2026-05-17 对 ICP_Query 项目执行 25 个缺陷修复的完整记录，以及二次审核发现和修复
metadata:
  node_type: memory
  type: project
  originSessionId: 7e7c77fb-1010-44dc-82a8-80dbbc4cf702
---

# ICP_Query 2026-05-17 修复记录

## 修复依据
依据 `icp-query-optimization-plan.md` 六阶段执行计划，修复了深度审查报告中 28 个缺陷中的 25 个。阶段六（API统一格式、Swagger、测试框架）和 ymicp.py God Class 拆分留为后续迭代。

## 关键修复细节

### load_config.py 重构
- 裸 `except:` 改为 `except Exception as e:` + `print(f"加载配置文件失败: {repr(e)}")` + `sys.exit(1)`
- 新增 `get_config_path()` 支持 `--config` 命令行参数传入绝对路径
- `Config.__getattr__` 从 `return None` 改为 `raise AttributeError`，调用侧保持已有 `getattr(config, key, default)` 作为安全网

### ymicp.py 核心修复
- **P0-1**: `getbeian` 的 captcha 分支内补充 `current_ip = None` 及从 connector 提取逻辑
- **P0-2**: `check_img` 从 `req.json()` 改为 `req.text()` + 检查 `"当前访问疑似黑客攻击"` + `ujson.loads()` 手动解析
- **P0-5**: 移除硬编码过期 JWT `self.sign`，改为空字符串 `""`
- **P0-6**: `autoget` 错误处理：先检查 `not success`，再检查 `data is None`，最后 `data.get("code") == 500`
- **P1-1**: 删除全局 `ssl._create_default_https_context` 禁用
- **P1-2**: `_ipv6_lock` / `_blocked_ip_lock` 从 `threading.Lock()` → `asyncio.Lock()`，相关方法改为 `async def`
- **P1-8**: `typj.get(sp)` / `btypj.get(sp)` 添加 `is None` 防御
- **P1-11**: 删除 `is_public_ipv6`、`_run_cmd_capture`、`get_local_ipv6_addresses` 三个函数，改为 `from utils import ...`
- **P2-5**: `cleanup()` 简化为空操作（`self.session` 从未被赋值，资源由 `get_session` 上下文管理器清理）；`__del__` 移除裸 `except: pass` 和废弃 `asyncio.get_event_loop()`
- 删除未使用的 `import threading` / `import subprocess` / `import locale` / `is_public_ipv6` / `_run_cmd_capture`

### proxy_pool.py
- **P1-5**: `getproxy()` 先 `list(pool_cache.keys())` 再判断，消除 TOCTOU 竞争
- **P1-6**: 新增 `remove_proxy(address)` 方法，内部 `async with self._update_lock` 保护
- **P2-6**: `ttl=max(1, config.proxy.extra_api.timeout - config.proxy.extra_api.timeout_drop)`
- 废弃 API 修复: `asyncio.get_event_loop()` → `asyncio.get_running_loop()`

### ipv6_pool.py
- **P1-7**: 恢复 `_verify_ipv6_address` 调用，初始化和新增地址均需验证公网可达性

### database.py
- **P1-10**: 所有方法改用 `try/finally: conn.close()` 模式
- 新增 `PRAGMA journal_mode=WAL` 启用 WAL 模式，提升并发性能

### log_collector.py
- **P2-8**: `threading.Lock` → `asyncio.Lock`，`add_log`/`get_logs`/`clear` 改为 `async def`
- **CRITICAL 修复**: 新增 `add_log_sync()` 同步方法，`CollectorHandler.emit()` 改为调用 `add_log_sync()` 而非未 await 的 `add_log()`，解决日志完全丢失问题

### routes/
- **query_routes.py:49**: `not not any(...)` → `any(...)`
- **batch_routes.py**: `proxy[7:]` 改为 `proxy.replace("http://", "").replace("https://", "")`；`del pool_cache[...]` 改为 `await request.app.proxypool.remove_proxy(proxy_host)`
- **config_routes.py**: Linux `os.execv` 前调用 `await request.app.shutdown()`；标注 `os.execv` 不返回
- **history_routes.py**: `limit = min(int(...), 500)`
- **middlewares.py**: 异常消息统一为 `"服务器内部错误"`（含 JSON 序列化失败路径）
- **log_routes.py**: `await` log_collector 异步方法

### Dockerfile
- **P0-4**: 新增 `RUN apt-get update && apt-get install -y libgl1-mesa-glx libglib2.0-0 && rm -rf /var/lib/apt/lists/*`

## 二次审核发现及修复 (2026-05-17)

### CRITICAL (已修复)
1. **log_collector.py CollectorHandler.emit()** — `add_log` 改为 async 后，同步调用 `self.collector.add_log()` 返回 coroutine 但从未 await，导致所有日志静默丢失。修复：新增 `add_log_sync()` 直接写入 deque，`emit()` 改为调用同步版本。

### HIGH (已修复)
2. **ymicp.py check_img()** — `current_ip` 提取在 `async with get_session` 块之外，session 已关闭。修复：将 `current_ip` 提取移入 `async with` 块内。
3. **ymicp.py __del__** — 裸 `except: pass` + 废弃 `asyncio.get_event_loop()` + `self.session` 空操作。修复：简化 `__del__` 为 pass，`cleanup()` 移除无效的 session 检查。

### MEDIUM (已修复)
4. **ymicp.py** — 未使用的 `is_public_ipv6`、`_run_cmd_capture` 导入。修复：移除。
5. **proxy_pool.py** — `asyncio.get_event_loop()` 废弃 API。修复：改为 `asyncio.get_running_loop()`。
6. **database.py** — 缺少 WAL 模式。修复：`init_db()` 中添加 `PRAGMA journal_mode=WAL`。
7. **ipv6_pool.py _add_addresses()** — 新地址跳过可达性验证，与 P1-7 修复意图矛盾。修复：恢复 `await self._verify_ipv6_address(new_addr)` 验证。
8. **config_routes.py** — `os.execv` 后的死代码。修复：添加注释标注不返回。
9. **middlewares.py** — JSON 序列化失败泄露 `str(e)`。修复：统一为 `"服务器内部错误"`。

### LOW (已知，暂不处理)
10. 非验证码路径发送空 `sign` — 需确认工信部 API 是否接受，运行时验证。
11. `proxy_pool._check_and_add_proxies` 中 `len(pool_cache)` 检查无锁 — 软限制，影响不大。
12. Dockerfile `libgl1-mesa-glx` 在新版 Debian 中废弃 — 当前基础镜像可用，未来升级时需改为 `libgl1`。

## 需要注意的潜在风险点
1. `Config.__getattr__` 改为 `raise AttributeError` 后，运行时若配置有新增属性访问路径未覆盖到 `getattr(config, key, default)` 模式，会抛异常而非静默失败——这是期望行为，但需留意
2. `log_collector.add_log_sync()` 绕过了 asyncio.Lock，因为 deque.append 是线程安全的原子操作且仅在事件循环内调用，但如果未来引入多线程需重新评估
3. `ymicp._add_blocked_ip` / `_is_ip_blocked` / `_get_next_ipv6` 改为 `async def` 后，所有调用点均已 `await`，但如果外部代码直接调用这些方法，需要更新
4. 全局 SSL 禁用已移除，连接器级别 `'ssl': False` 仍保留——如果工信部 API 强制要求证书验证，需要调整
5. 非验证码路径 `sign` 为空字符串，需运行时确认工信部 API 是否接受

## 未执行的优化（后续迭代）
- 阶段六：API 响应格式统一、Swagger/OpenAPI 文档、pytest 测试框架
- God Class 拆分：`ymicp.py`（~600行）拆分为 query_service / captcha_service / session_manager
- 配置热加载：当前 `os.execv` 重启方式改为优雅热加载
