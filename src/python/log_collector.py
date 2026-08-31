# -*- coding: utf-8 -*-
"""
日志收集器模块
用于收集和管理系统运行时日志
"""
from collections import deque
import asyncio
from datetime import datetime
import logging


class LogCollector:
    """实时日志收集器"""
    def __init__(self, maxlen=1000):
        self.logs = deque(maxlen=maxlen)
        self.lock = asyncio.Lock()

    async def add_log(self, message, level='INFO'):
        """添加日志"""
        async with self.lock:
            self.logs.append({
                'time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                'message': message,
                'level': level
            })

    def add_log_sync(self, message, level='INFO'):
        """同步添加日志（供 logging.Handler 调用）"""
        self.logs.append({
            'time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'message': message,
            'level': level
        })

    async def get_logs(self, limit=500):
        """获取日志列表"""
        async with self.lock:
            logs_list = list(self.logs)
            return logs_list[-limit:] if len(logs_list) > limit else logs_list

    async def clear(self):
        """清空日志"""
        async with self.lock:
            self.logs.clear()


class CollectorHandler(logging.Handler):
    """自定义日志处理器，将日志添加到LogCollector"""
    def __init__(self, collector):
        super().__init__()
        self.collector = collector

    def emit(self, record):
        try:
            msg = self.format(record)
            if 'aiohttp.access' not in record.name:
                self.collector.add_log_sync(msg, record.levelname)
        except Exception:
            self.handleError(record)


# 创建全局日志收集器实例
log_collector = LogCollector()

