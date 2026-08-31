# ICP_Query 代码优化执行切片计划

> 生成日期：2026-05-15
> 依据：`icp-query-review-report.md` 深度审查报告
> 目标：在零业务链断裂风险的前提下，系统性修复 28 个已核实缺陷（P0×6, P1×12, P2×10）

---

## 一、执行原则

| 原则 | 说明 |
|------|------|
| **禁止直接生成最终代码** | 当前阶段只制定计划，不写实现代码 |
| **防腐层优先** | 破坏性改动必须设计兼容过渡层，确保外部调用不中断 |
| **逐阶段验收** | 每阶段完成后执行端到端测试，全部通过方可进入下一阶段 |
| **最小改动** | 每步只解决一个具体问题，不引入无关重构 |

---

## 二、关键依赖关系图

```
阶段零（独立基线）
       ↓
阶段一（配置与基础设施）── 后续阶段依赖 1.3 和 1.4 完成
       ↓
阶段二（核心崩溃修复）── 2.5 依赖 2.2 完成
       ↓
阶段三（并发安全加固）── 3.2 依赖 3.1、3.5 依赖 3.4
       ↓
阶段四（数据层与服务层）── 4.2 可提前与阶段三并行
       ↓
阶段五（体验优化）── 全部可并行
       ↓
阶段六（收尾与验证）── 依赖前五阶段全部验收通过
```

---

## 三、执行切片

### 阶段零：安全基线（3 个子步骤，可并行执行）

本阶段为独立改动，不涉及任何跨文件依赖，可并行推进。

#### 步骤 0.1：Dockerfile 补系统依赖（P0-4）

| 项目 | 内容 |
|------|------|
| **目的** | 修复 Pillow 和 ONNX Runtime 因缺少系统库导致的 500 崩溃 |
| **具体动作** | Dockerfile `RUN pip install` 之前增加 `RUN apt-get update && apt-get install -y libgl1-mesa-glx libglib2.0-0 && rm -rf /var/lib/apt/lists/*` |
| **影响面** | 仅 `Dockerfile` 文件，不影响任何源码 |
| **验收标准** | `docker build` 成功；容器内 `python -c "from PIL import Image"` 不报错 |

#### 步骤 0.2：消除 `not not any(...)` 冗余逻辑（P2-1）

| 项目 | 内容 |
|------|------|
| **目的** | 代码清理，提高可读性 |
| **具体动作** | `query_routes.py:49` 将 `not not any(...)` 改为 `any(...)` |
| **影响面** | 仅 `routes/query_routes.py:49` |
| **验收标准** | 行为不变（禁止后缀的查询仍返回 405）；linter 无警告 |

#### 步骤 0.3：修复 `proxy[7:]` 硬编码切片（P2-10）

| 项目 | 内容 |
|------|------|
| **目的** | 支持 `https://` 前缀代理地址，不假设固定 7 字符前缀 |
| **具体动作** | `batch_routes.py:130-131` 改用 `urllib.parse.urlparse(proxy).netloc` 提取主机名 |
| **影响面** | 仅 `routes/batch_routes.py:130-131` |
| **验收标准** | `http://` 和 `https://` 前缀的代理都能正确从 pool_cache 中剔除 |

**阶段零验收通过标志：** Docker 构建成功；两个小改动行为不变。

---

### 阶段一：配置与基础设施（4 个子步骤，严格串行）

本阶段为后续所有步骤的基础。**步骤 1.3 和 1.4 是最高风险项**，必须严格按顺序执行。

#### 步骤 1.1：修复 `load_config.py` 配置加载容错（P0-3）

| 项目 | 内容 |
|------|------|
| **目的** | 裸 `except:` 改为 `except Exception as e:`，输出具体错误信息，支持 `--config` 参数传入绝对路径 |
| **具体动作** | 1. `except:` → `except Exception as e:`，打印 `repr(e)` 和配置路径；2. 支持命令行 `--config` 参数；3. 使用 `get_resource_path()` 获取默认路径 |
| **影响面** | `load_config.py` 全文件；所有模块 import 时依赖此文件 |
| **防腐层** | 保持向后兼容：不传 `--config` 时仍从默认路径加载 |
| **验收标准** | 配置文件不存在时打印"配置加载失败: FileNotFoundError('/path/to/config.yml')"；`python icpApi.py --config /abs/path/config.yml` 可正常启动 |

#### 步骤 1.2：消除重复代码——统一函数定义（P1-11）

| 项目 | 内容 |
|------|------|
| **目的** | 移除 `ymicp.py` 中的三个函数副本，改为从 `utils.py` 导入，确保单一数据源 |
| **具体动作** | 从 `ymicp.py` 中删除：`is_public_ipv6`（`:29-30`）、`_run_cmd_capture`（`:33-56`）、`get_local_ipv6_addresses`（`:58-93`）；在 `ymicp.py` 头部增加 `from utils import is_public_ipv6, _run_cmd_capture, get_local_ipv6_addresses` |
| **影响面** | `ymicp.py:29-93`（删除约 65 行）；`ipv6_pool.py:14`（已从 utils 导入，无需改动） |
| **防腐层** | 函数签名和返回值保持完全一致，不做任何逻辑修改 |
| **验收标准** | `ymicp.py` 行数从 735 降至约 670；`python -c "from ymicp import beian; b = beian(); print('OK')"` 不报错；查询功能正常 |

#### 步骤 1.3：P1-12 `Config.__getattr__` 渐进替换——第 1 步：扫描+显式化

| 项目 | 内容 |
|------|------|
| **目的** | 不改变 `__getattr__` 行为的前提下，将所有依赖"缺属性返回 None"隐式行为的调用点改为显式 `getattr(config, key, default)` |
| **具体动作** | 扫描全代码库中所有 `config.xxx` 访问路径，识别哪些依赖了隐式 None 返回值，逐一替换为显式 `getattr`。重点关注：<br>• `query_routes.py:101` `getattr(config, 'history', None)`<br>• `config_routes.py:63,64,74` `getattr(config.risk_avoidance, ...)`<br>• `ymicp.py` 中所有 `getattr(config, 'captcha', object())` 链<br>• `proxy_pool.py:17-18` 直接访问 `config.proxy.extra_api.xxx` |
| **影响面** | 约 20+ 处调用点，覆盖 `ymicp.py`、`query_routes.py`、`batch_routes.py`、`config_routes.py`、`proxy_pool.py`、`history_routes.py` |
| **防腐层** | **此步骤不改 `__getattr__` 本身**，仅做调用侧显式化，行为零变化 |
| **验收标准** | 1. `grep -rn "config\." --include="*.py"` 输出全部经过人工确认，无遗漏；2. 所有功能测试通过，行为零变化；3. 生成一份《config 属性完整清单》文档，列出所有被访问的属性名及其默认值 |

#### 步骤 1.4：P1-12 渐进替换——第 2 步：修改 `__getattr__` 抛异常

| 项目 | 内容 |
|------|------|
| **目的** | 将 `Config.__getattr__` 从 `return None` 改为 `raise AttributeError`，使配置缺失在第一时间暴露 |
| **具体动作** | `load_config.py:16-17` 改为：<br>`def __getattr__(self, name): raise AttributeError(f"'Config' object has no attribute '{name}'")` |
| **依赖前提** | **步骤 1.3 验收通过**——所有调用点已显式化 |
| **影响面** | `load_config.py:16-17` |
| **防腐层** | 保留步骤 1.3 中所有 `getattr(config, key, default)` 作为安全网 |
| **验收标准** | `python -c "from load_config import config; print(config.nonexistent)"` 抛 `AttributeError` 而非 `None`；所有现有功能（查询、批量、配置管理、历史记录）正常运行 |

**阶段一验收通过标志：** 配置加载有明确错误信息；重复代码已消除；`Config.__getattr__` 改为抛异常且无回归。

---

### 阶段二：核心崩溃修复（5 个子步骤，部分可并行）

本阶段修复所有 P0 级崩溃缺陷，确保核心链路不再中断。

#### 步骤 2.1：修复 `getbeian` captcha 分支缺 `current_ip`（P0-1）

| 项目 | 内容 |
|------|------|
| **目的** | 在 captcha 分支内定义 `current_ip`，避免 `:509` NameError 崩溃 |
| **具体动作** | 在 `ymicp.py:484` captcha 分支的 `async with self.get_session(proxy) as session:` 内添加：<br>`current_ip = None`<br>`if hasattr(session, '_connector') and hasattr(session._connector, '_local_addr'):`<br>`    current_ip = session._connector._local_addr[0] if session._connector._local_addr else None` |
| **影响面** | 仅 `ymicp.py:getbeian` 方法的 captcha 分支 |
| **验收标准** | 启用 captcha 模式发起查询不抛 NameError；创宇盾拦截时 IPv6 地址正确加入黑名单 |

#### 步骤 2.2：修复 `check_img` 验证码 JSON 解码（P0-2）

| 项目 | 内容 |
|------|------|
| **目的** | 创宇盾拦截返回 HTML 时不崩溃，识别拦截行为并触发 IP 黑名单 |
| **具体动作** | `ymicp.py:379-383` 改为：<br>1. `await req.text()` 获取原始文本；<br>2. 检查是否包含 `"当前访问疑似黑客攻击"`，是则调用 `self._add_blocked_ip(current_ip)` 并返回拦截错误；<br>3. 否则手动 `ujson.loads(text)` 解析 |
| **影响面** | `ymicp.py:check_img` 方法（`:377-383`） |
| **验收标准** | 创宇盾返回 HTML 时返回明确的"当前访问已被创宇盾拦截"错误；IP 被加入黑名单缓存；不再抛 ContentTypeError |

#### 步骤 2.3：修复 `get_cookie` 正则空值（P1-4）

| 项目 | 内容 |
|------|------|
| **目的** | 正则未匹配时不抛 TypeError |
| **具体动作** | `ymicp.py:286` 改为：<br>`match = re.compile("[0-9a-z]{32}").search(str(req.cookies))`<br>`return match.group(0) if match else ""` |
| **影响面** | 仅 `ymicp.py:286` |
| **验收标准** | cookie 未设置时返回空字符串而非抛 TypeError |

#### 步骤 2.4：修复 `autoget` 错误处理逻辑（P0-6）

| 项目 | 内容 |
|------|------|
| **目的** | 移除冗余条件，增加 `data is None` 防御，确保错误信息不为 None |
| **具体动作** | `ymicp.py:657-660` 改为：<br>```python<br>if not success:<br>    return {"code": 500, "message": data if data else "未知错误"}<br>if data is None:<br>    return {"code": 500, "message": "工信部返回空数据"}<br>if data.get("code") == 500:<br>    return {"code": 122, "message": "工信部服务器异常"}<br>``` |
| **影响面** | `ymicp.py:autoget` 方法（`:657-660`） |
| **验收标准** | `getbeian` 返回 `(False, None)` 时 autoget 返回 `{"code":500, "message":"未知错误"}`；不再访问 `data["code"]` 导致 None 下标崩溃 |

#### 步骤 2.5：动态获取 sign（P0-5）

| 项目 | 内容 |
|------|------|
| **目的** | 移除硬编码过期 JWT，非 captcha 模式下从 `get_token` 响应提取 sign 或采用其他认证路径 |
| **具体动作** | 1. 移除 `ymicp.py:135` `self.sign` 硬编码；<br>2. 非 captcha 模式下，从 `get_token` 响应 `t["params"]` 中提取 sign（如果存在）；<br>3. 如果 `get_token` 不提供 sign，设为空字符串，查询走无 sign 路径 |
| **依赖前提** | **步骤 2.2 验收通过**（因为 captcha 模式下 sign 已从 `check_img` 响应的 `data["params"]` 获取，需确认非 captcha 模式有等效路径） |
| **影响面** | `ymicp.py:135`（删除）、`:270-271`（get_token 提取 sign）、`:497`（getbeian 非 captcha 使用 sign）、`:619`（getblackbeian 非 captcha 使用 sign） |
| **防腐层** | 在过渡期保留 `self.sign` 作为 fallback（设为空字符串），确保旧逻辑不会因 sign 为空而中断 |
| **验收标准** | 非 captcha 模式查询正常返回结果（不被工信部因 sign 过期拒绝）；captcha 模式 sign 从验证码成功响应中动态获取 |

**阶段二验收通过标志：** 6 个 P0 问题全部修复。执行端到端测试：单查询（web+app）返回 code=200；captcha 模式启用/禁用均正常；创宇盾拦截正确处理。

---

### 阶段三：并发安全加固（7 个子步骤，部分有依赖）

本阶段修复所有线程安全和并发竞争问题。**改动范围跨越多个文件，需重点测试。**

#### 步骤 3.1：给 ProxyPool 添加公开方法 `remove_proxy(address)`（P1-6 前置）

| 项目 | 内容 |
|------|------|
| **目的** | 为 batch_routes 提供安全的代理移除接口，内部加 `_update_lock` 保护 |
| **具体动作** | `proxy_pool.py` 新增方法：<br>```python<br>async def remove_proxy(self, address: str):<br>    async with self._update_lock:<br>        if address in pool_cache:<br>            del pool_cache[address]<br>            logger.info(f"安全移除代理: {address}")<br>``` |
| **影响面** | 仅 `proxy_pool.py` 新增方法 |
| **验收标准** | `await pool.remove_proxy("1.2.3.4:8080")` 能安全移除；与 `_update()` 并发时不冲突 |

#### 步骤 3.2：迁移 batch_routes 的 pool_cache 直接操作（P1-6）

| 项目 | 内容 |
|------|------|
| **目的** | 绕过模块级 `pool_cache` 直接操作，改为通过 ProxyPool 类公开方法 |
| **具体动作** | `batch_routes.py:129-132` 改为：<br>`if proxy:`<br>`    proxy_host = urllib.parse.urlparse(proxy).netloc`<br>`    await request.app.proxypool.remove_proxy(proxy_host)` |
| **依赖前提** | **步骤 3.1 验收通过** |
| **影响面** | `routes/batch_routes.py:129-132`；需从 `proxy_pool import ProxyPool`（不再 import `pool_cache`） |
| **防腐层** | 保留 `pool_cache` 模块级变量（ProxyPool 内部仍使用），仅移除外部直接引用 |
| **验收标准** | 代理剔除功能正常；不再有绕过 ProxyPool 类的直接 `del pool_cache[...]` |

#### 步骤 3.3：修复代理池 TTL 可能为负（P2-6）

| 项目 | 内容 |
|------|------|
| **目的** | 防止 `timeout < timeout_drop` 时 TTLCache 行为异常 |
| **具体动作** | `proxy_pool.py:18` 改为：<br>`ttl=max(1, config.proxy.extra_api.timeout - config.proxy.extra_api.timeout_drop)` |
| **影响面** | `proxy_pool.py:18` |
| **验收标准** | 即使配置 `timeout=5, timeout_drop=10`，TTLCache 正常创建（ttl=1） |

#### 步骤 3.4：`threading.Lock` → `asyncio.Lock`（P1-2 + P2-8）

| 项目 | 内容 |
|------|------|
| **目的** | 将同步锁改为异步锁，避免阻塞事件循环 |
| **具体动作** | 1. `ymicp.py:142` `_ipv6_lock = threading.Lock()` → `_ipv6_lock = asyncio.Lock()`；<br>2. `ymicp.py:155` `_blocked_ip_lock = threading.Lock()` → `_blocked_ip_lock = asyncio.Lock()`；<br>3. `log_collector.py:16` `self.lock = threading.Lock()` → `self.lock = asyncio.Lock()`；<br>4. 所有 `with self._xxx_lock:` 改为 `async with self._xxx_lock:` |
| **影响面** | `ymicp.py:142,155`（定义）+ `:162,170,178,264,514,635`（使用处）；`log_collector.py:16,19,28,34` |
| **防腐层** | 锁的语义不变，仅类型和语法变化 |
| **验收标准** | 高并发查询（10 并发持续 1 分钟）不阻塞、不死锁、不抛 `RuntimeError: Task got bad yield` |

#### 步骤 3.5：token 读写加锁保护（P1-3）

| 项目 | 内容 |
|------|------|
| **目的** | 保护 `self.token` 和 `self.token_expire` 的并发读写，避免半写入状态 |
| **具体动作** | 1. `ymicp.py` 新增 `_token_lock = asyncio.Lock()`；<br>2. `get_token:274-275` 写入 token 时 `async with self._token_lock:` 保护；<br>3. `get_token:243` 检查过期时 `async with self._token_lock:` 保护读取 |
| **依赖前提** | **步骤 3.4 验收通过**（统一使用 asyncio.Lock） |
| **影响面** | `ymicp.py` 新增 `_token_lock` 定义；`get_token` 方法读取和写入处 |
| **验收标准** | 两个并发请求同时刷新 token 时，不会出现半写入状态或旧 token 被误用 |

#### 步骤 3.6：修复代理池 `getproxy()` 并发竞争（P1-5）

| 项目 | 内容 |
|------|------|
| **目的** | 消除 TOCTOU（Time-of-Check-Time-of-Use）竞争条件 |
| **具体动作** | `proxy_pool.py:149-156` 改为：<br>```python<br>while True:<br>    keys = list(pool_cache.keys())<br>    if keys:<br>        break<br>    if asyncio.get_event_loop().time() - start_time > timeout:<br>        raise TimeoutError("等待代理超时")<br>    await asyncio.sleep(0.1)<br>random_key = f"http://{random.choice(keys)}"<br>``` |
| **影响面** | `proxy_pool.py:149-156` |
| **验收标准** | 代理池在 TTL 边界快速过期时不抛 `IndexError` |

#### 步骤 3.7：恢复 IPv6 地址可达性验证（P1-7）

| 项目 | 内容 |
|------|------|
| **目的** | 新增 IPv6 地址加入池前经过可达性验证，避免不可达地址导致批量请求失败 |
| **具体动作** | 取消 `ipv6_pool.py:77-84` 的注释，恢复 `_verify_ipv6_address` 调用：<br>```python<br>if await self._verify_ipv6_address(addr):<br>    self.active_addresses[addr] = time.time()<br>    verified_count += 1<br>    logger.info(f"✓ IPv6地址可用: {addr}")<br>    return True<br>else:<br>    logger.warning(f"✗ IPv6地址不可用: {addr}")<br>    return False<br>``` |
| **影响面** | `ipv6_pool.py:65-84` |
| **验收标准** | 新增 IPv6 地址加入池前通过 `_verify_ipv6_address` 可达性验证；不可达地址不被加入池 |

**阶段三验收通过标志：** 所有并发安全问题已修复。执行 10 并发持续 1 分钟压力测试，无死锁、无 IndexError、无半写入状态。

---

### 阶段四：数据层与服务层（3 个子步骤，可并行执行）

#### 步骤 4.1：SQLite 连接改用上下文管理器（P1-10）

| 项目 | 内容 |
|------|------|
| **目的** | 异常时连接正确关闭，避免连接泄漏 |
| **具体动作** | `database.py` 所有方法改为 `with sqlite3.connect(self.db_path) as conn:` 模式，自动 commit（成功时）或 rollback（异常时），`finally` 中关闭连接。或者使用 `contextlib.closing` 包装：<br>```python<br>try:<br>    with sqlite3.connect(self.db_path) as conn:<br>        cursor = conn.cursor()<br>        # ... 执行操作<br>except Exception as e:<br>    logger.error(f"xxx: {e}")<br>    return None<br>``` |
| **影响面** | `database.py` 全部 12 个数据库操作方法 |
| **防腐层** | 保持同步操作模式（不引入 aiosqlite），仅改变连接生命周期管理 |
| **验收标准** | 异常时连接正确关闭；所有历史查询和批量任务功能正常；`sqlite3` 无 "database is locked" 错误 |

#### 步骤 4.2：移除全局 SSL 禁用（P1-1）

| 项目 | 内容 |
|------|------|
| **目的** | 移除模块级全局 SSL 上下文修改，仅在连接器级别禁用验证 |
| **具体动作** | 1. 删除 `ymicp.py:26` `ssl._create_default_https_context = ssl._create_unverified_context()`；<br>2. 确认连接器配置 `:150` `'ssl': False` 足够；<br>3. 移除 `import ssl`（如果无其他引用） |
| **影响面** | `ymicp.py:26`（删除）、`ymicp.py:19-21`（可能移除 ssl 和 subprocess/locale 导入，需检查是否仍被 `_run_cmd_capture` 使用） |
| **防腐层** | 连接器级别已配置 `'ssl': False`，移除全局设置不影响现有行为 |
| **验收标准** | 所有 HTTPS 请求正常；不影响第三方代理 API 请求；`ssl` 模块无全局污染 |

#### 步骤 4.3：完善 `__del__` 和 `cleanup()`（P2-5）

| 项目 | 内容 |
|------|------|
| **目的** | 在 `cleanup()` 中真正关闭残留 session/connector，避免资源泄漏 |
| **具体动作** | `ymicp.py:698-700` `cleanup()` 方法中添加实际的资源清理逻辑（关闭残留连接等）；`__del__` 中调用 `cleanup()` |
| **影响面** | `ymicp.py:698-707` |
| **验收标准** | 服务停止时无残留连接；日志显示"beian资源清理完成，已关闭 N 个活跃连接" |

**阶段四验收通过标志：** SQLite 连接无泄漏；全局 SSL 已移除；资源清理正常工作。

---

### 阶段五：体验优化与边缘修复（5 个子步骤，可并行执行）

本阶段为低风险改动，每个步骤都是单点修改，互相无依赖，可并行推进。

#### 步骤 5.1：P2-7 给 `limit` 参数加上限

| 项目 | 内容 |
|------|------|
| **目的** | 防止用户传入 `limit=999999` 导致大量数据查询 |
| **具体动作** | `history_routes.py:17` 改为 `limit = min(int(request.query.get("limit", 50)), 500)` |
| **影响面** | `routes/history_routes.py:17` |
| **验收标准** | `limit=999999` 时返回最多 500 条 |

#### 步骤 5.2：P2-4 中间件异常信息脱敏

| 项目 | 内容 |
|------|------|
| **目的** | 防止 `str(e)` 泄露内部路径、堆栈信息给前端 |
| **具体动作** | `middlewares.py:81` 改为返回通用错误消息，详细错误仅记日志 |
| **影响面** | `middlewares.py:81` |
| **验收标准** | 前端收到 `{"code": 500, "msg": "服务器内部错误"}`；日志中保留完整 `str(e)` |

#### 步骤 5.3：P1-8 类型映射防御

| 项目 | 内容 |
|------|------|
| **目的** | sp 超出 0-3 范围时返回友好错误而非崩溃 |
| **具体动作** | `ymicp.py:470` 增加 `template is None` 检查 |
| **影响面** | `ymicp.py:470` |
| **验收标准** | sp=99 时返回 `False, "不支持的查询类型"` 而非抛 TypeError |

#### 步骤 5.4：P1-9 Linux 路径重启优化

| 项目 | 内容 |
|------|------|
| **目的** | Linux 路径在 `os.execv` 前优雅关闭 aiohttp app，避免残留连接 |
| **具体动作** | `config_routes.py:218-220` Linux 路径在 `os.execv` 前先调用 `await app.shutdown()` 和 `await app.cleanup()` |
| **影响面** | `routes/config_routes.py:218-220`（仅 Linux 路径，Windows 路径不受影响） |
| **验收标准** | Linux 重启时数据库连接正确关闭，无残留进程 |

#### 步骤 5.5：P2-2/P2-3 类型映射重构（可选，架构优化）

| 项目 | 内容 |
|------|------|
| **目的** | 将数字 key 映射改为字符串 key，从 typj/btypj 自动生成 appth/bappth 注册映射，降低新增查询类型的扩展成本 |
| **具体动作** | 1. `ymicp.py:97-116` typj/btypj 改为字符串 key（`"web"→{...}`, `"app"→{...}`）；<br>2. `icpApi.py:71-84` 从 typj/btypj 自动生成 appth/bappth；<br>3. 路由中的字符串 `"web"/"app"` 直接对应 |
| **影响面** | `ymicp.py:97-116`、`icpApi.py:71-84`、`getbeian:469-470` 调用处需同步适配 |
| **防腐层** | 在过渡期保留数字 key 兼容层：`typj` 同时支持数字和字符串 key 访问 |
| **验收标准** | 新增查询类型只需改 typj/btypj，路由注册自动同步；现有查询功能零回归 |

**阶段五验收通过标志：** 所有 P2 问题已修复；类型映射重构通过测试。

---

### 阶段六：收尾与验证（3 个子步骤，串行执行）

#### 步骤 6.1：统一 API 响应格式

| 项目 | 内容 |
|------|------|
| **目的** | 所有接口返回 `{code, msg, data}` 一致结构，前端无需针对不同接口做特殊处理 |
| **具体动作** | 审查所有路由返回值，统一为 `{code, msg, data}` 结构；单查询当前返回 `{"code":200, "params":{...}}` 改为 `{"code":200, "data":{...}}` |
| **依赖前提** | 前五阶段全部验收通过 |
| **影响面** | 所有路由返回值；前端页面需同步适配 |
| **验收标准** | 所有 API 端点返回一致的 `{code, msg, data}` 结构；前端页面正常工作 |

#### 步骤 6.2：添加 OpenAPI/Swagger 文档

| 项目 | 内容 |
|------|------|
| **目的** | 生成 API 文档，降低对接成本 |
| **具体动作** | 引入 aiohttp-swagger3 或类似库，为所有路由添加注解，生成 `/api/docs` 端点 |
| **影响面** | 新增文档端点，不影响现有业务路由 |
| **验收标准** | 可通过 `http://host:port/api/docs` 访问 Swagger UI；所有 API 端点有描述 |

#### 步骤 6.3：添加测试框架骨架

| 项目 | 内容 |
|------|------|
| **目的** | 建立 pytest 基础设施，为核心链路添加至少一个冒烟测试 |
| **具体动作** | 1. 创建 `tests/` 目录；<br>2. 配置 `pytest.ini` 或 `pyproject.toml`；<br>3. 编写核心链路冒烟测试：单查询返回 code=200、批量任务创建成功 |
| **影响面** | 新增 `tests/` 目录和配置文件 |
| **验收标准** | `pytest tests/` 可运行；至少覆盖"正常查询返回 code=200"；后续 PR 必须包含测试 |

**阶段六验收通过标志：** API 响应格式统一；Swagger 文档可访问；测试框架可运行。

---

## 四、建议执行节奏

| 阶段 | 预计耗时 | 关键里程碑 |
|------|----------|-----------|
| 阶段零 | 0.5 天 | Docker 构建成功 |
| 阶段一 | 1-2 天 | Config.__getattr__ 改为抛异常且无回归 |
| 阶段二 | 1 天 | P0 全部修复，端到端测试通过 |
| 阶段三 | 2-3 天 | 10 并发压力测试通过 |
| 阶段四 | 1 天 | SQLite 无泄漏，SSL 全局移除 |
| 阶段五 | 1 天 | P2 全部修复 |
| 阶段六 | 1-2 天 | API 统一、文档、测试框架就位 |
| **合计** | **7-10 天** | 28 个缺陷全部修复，项目质量显著提升 |

---

## 五、回退策略

每个阶段完成后提交一次 Git Commit。如果某阶段验收未通过：

1. **阶段零**：回退单步 commit，不影响其他代码
2. **阶段一**：回退 1.4（最高风险项），保留 1.1-1.3
3. **阶段二**：回退单步 commit，P0 问题仍存在但不引入新 bug
4. **阶段三**：回退整个阶段（锁类型不兼容），保留阶段零至二
5. **阶段四**：回退单步 commit，不影响其他阶段
6. **阶段五/六**：低风险，可直接修复
