FROM python:3.11-slim

WORKDIR /icp_Api

# Python 源码
COPY src/python/ /icp_Api/
# 共享资源（配置 / 前端）
COPY config.yml /icp_Api/config.yml
COPY templates/ /icp_Api/templates/
COPY static/ /icp_Api/static/

# 保留本地部署约定，同时兼容 Debian 新旧 sources 配置。
RUN if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
      sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources; \
    elif [ -f /etc/apt/sources.list ]; then \
      sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list; \
    fi \
    && apt-get update \
    && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 16181

CMD ["python3", "icpApi.py"]
