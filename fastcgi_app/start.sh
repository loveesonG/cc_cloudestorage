#!/bin/bash

# 启动 Redis
redis-server --daemonize yes
echo "Redis 已启动"

# 等待 Redis 就绪
sleep 1

# 提前创建 FastDFS 客户端日志目录：
# fdfs_client_init 初始化时需要向该目录写日志，目录不存在会导致进程初始化崩溃
# （必须在 chunk_merge 等使用 FastDFS 的 CGI 启动之前创建）
mkdir -p /fastdfs_data_and_log/client

# 启动 9 个 FastCGI 进程
echo -n "登录："
spawn-fcgi -a 0.0.0.0 -p 10000 -f /app/bin_cgi/login
echo -n "注册："
spawn-fcgi -a 0.0.0.0 -p 10001 -f /app/bin_cgi/register
echo -n "上传："
spawn-fcgi -a 0.0.0.0 -p 10002 -f /app/bin_cgi/upload
echo -n "MD5："
spawn-fcgi -a 0.0.0.0 -p 10003 -f /app/bin_cgi/md5
echo -n "MyFile："
spawn-fcgi -a 0.0.0.0 -p 10004 -f /app/bin_cgi/myfiles
echo -n "DealFile："
spawn-fcgi -a 0.0.0.0 -p 10005 -f /app/bin_cgi/dealfile
echo -n "ShareList："
spawn-fcgi -a 0.0.0.0 -p 10006 -f /app/bin_cgi/sharefiles
echo -n "DealShare："
spawn-fcgi -a 0.0.0.0 -p 10007 -f /app/bin_cgi/dealsharefile
echo -n "SharePicture："
spawn-fcgi -a 0.0.0.0 -p 10008 -f /app/bin_cgi/sharepicture

echo -n "ChunkInit："
spawn-fcgi -a 0.0.0.0 -p 10009 -f /app/bin_cgi/chunk_init
echo -n "ChunkUpload："
spawn-fcgi -a 0.0.0.0 -p 10010 -f /app/bin_cgi/chunk_upload

# 创建分片临时目录（清理上次可能残留的孤儿分片）
rm -rf /tmp/chunks
mkdir -p /tmp/chunks

# chunk_merge 启动时需要连接 tracker，等待 tracker 就绪
echo -n "等待 tracker(172.30.0.3:22122) 就绪..."
for i in $(seq 1 30); do
    if fdfs_monitor /etc/fdfs/client.conf >/dev/null 2>&1; then
        echo "OK"
        break
    fi
    sleep 1
done
# chunk_merge 启动后可能因依赖未就绪而退出，spawn-fcgi 无监督机制，
# 需要校验 10011 端口确实在监听，未成功则重试
echo -n "ChunkMerge："
for i in $(seq 1 15); do
    spawn-fcgi -a 0.0.0.0 -p 10011 -f /app/bin_cgi/chunk_merge >/dev/null 2>&1
    sleep 2
    if lsof -i :10011 >/dev/null 2>&1; then
        echo "启动成功 (第 ${i} 次尝试)"
        break
    fi
    echo -n "重试${i}..."
    sleep 2
done
if ! lsof -i :10011 >/dev/null 2>&1; then
    echo "[警告] chunk_merge 启动失败，分片合并功能不可用，请进入容器手动排查"
fi

# AI 智能检索：多个 worker 允许重建时并行处理独立文件。
mkdir -p /data/faiss
AI_FCGI_WORKERS="${AI_FCGI_WORKERS:-4}"
echo -n "AI（${AI_FCGI_WORKERS} workers）："
spawn-fcgi -a 0.0.0.0 -p 10012 -F "${AI_FCGI_WORKERS}" -f /app/bin_cgi/ai

# 所有 FastCGI 程序已启动
echo "所有 FastCGI 程序已启动"

# 保持容器运行
tail -f /dev/null
