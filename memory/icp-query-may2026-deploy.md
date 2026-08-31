---
name: icp-query-may2026-deploy
description: 2026-05-28 腾讯云部署状态、修复记录和全面测试结果
metadata:
  node_type: memory
  type: project
  originSessionId: bb297399-8e7d-4b80-b04c-93b8eca52297
---

## 部署状态

服务器 132.232.231.41:16181 已部署成功，使用本地最新代码构建的 Docker 镜像。

**已完成：**
- Docker 镜像已用国内阿里云 apt/pip 源重新构建
- config.yml 已挂载为 volume，`web_ui: false` 已生效
- routes 目录已挂载为 volume，支持热更新
- 新增 `/query/multi` 接口（多类型并发查询）
- **POST `/query/multi` 已修复**（2026-05-28）

**POST `/query/multi` 修复详情：**
- 根因：`@jsondump` 装饰器与 `wj`（`web.json_response`）双重包装，导致 Response 对象被二次序列化
- 同时将 `ujson.loads(raw)` 改为 `request.json()`（aiohttp 内置），自动处理编码
- 添加了 JSON 解析失败的 400 错误处理
- 移除了 `query_routes.py` 中未使用的 `import ujson`
- **注意**：其他路由文件（history/config/log/batch_routes.py）也有同样的 `@jsondump`+`wj` 双重包装问题，暂未修复

## 部署方式

- SSH: `root@132.232.231.41`，密钥 `~/.ssh/racknerd_key`
- routes 挂载：`/opt/icp-query/routes -> /icp_Api/routes`
- config 挂载：`/opt/icp-query/config.yml -> /icp_Api/config.yml`
- 更新 routes 文件后需 `docker restart ymicp` 使更改生效

## 2026-05-28 全面测试结果

### 单条查询 `/query/{type}`

| 类型 | GET | POST | 状态 |
|------|-----|------|------|
| web | 200, 1条结果 | 200, 1条结果 | 正常 |
| app | 200 | 200 | 正常 |
| mapp | 200 | 200 | 正常 |
| kapp | 200 | 200 | 正常 |
| bweb | 200 | - | 正常 |
| bapp | 200 | - | 正常 |

### 多类型查询 `/query/multi`

| 场景 | 结果 |
|------|------|
| GET 单类型 `types=web` | 正常 |
| GET 全类型 `types=web,app,mapp,kapp` | 正常 |
| POST 正常 JSON | 正常（已修复） |
| POST 默认 types | 正常，默认 `web,mapp,kapp` |

### 批量任务

| 接口 | 结果 |
|------|------|
| POST `/create/task` | 创建成功，3个域名全部查询完成 |
| GET `/query/task` | 进度 100%，结果正确 |
| GET `/batch/tasks` | 返回任务列表 |

### 其他端点

| 端点 | 结果 |
|------|------|
| GET `/config` | 正常返回配置 |
| GET `/logs/realtime` | 正常返回日志 |
| POST `/logs/clear` | 正常清空 |
| OPTIONS 跨域 | CORS headers 正确 |
| GET `/history` | 正常（当前无历史记录） |

### 边界和错误处理

| 场景 | 结果 |
|------|------|
| 无 search 参数 | `{"code": 101}` 参数错误 |
| 无效类型 | `{"code": 102}` 不支持 |
| search=null/空 | `{"code": 101}` |
| 无效 JSON body | `{"code": 400}` 无法解析 |
| pageSize=100 | 自动限制为 40 |
| 多余字段 | 正常忽略 |
| 5个并发请求 | 全部 200，~1s 完成 |

### 服务器日志

验证码滑块匹配正常工作（0.006s 完成），无异常错误。
