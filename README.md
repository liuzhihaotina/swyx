# 后端启动

cd backend


## 步骤1：修改.env文件中 DASHSCOPE_API_KEY

## 启动后端服务
docker compose up -d --build

查看后端日志：docker logs -f swxy_api

## 关闭后端服务
docker compose down

# 前端启动（生产模式，Nginx + 80端口）

cd frontend

## 步骤1：修改.env文件中 VITE_API_BASE 为服务器公网IP
VITE_API_BASE=http://1.13.176.5:8000

## 构建并启动前端服务
docker compose --profile prod up -d --build

## 关闭前端服务
docker compose --profile prod down

# 访问服务
http://1.13.176.5/

# 开发模式（可选，本地调试用）
npm install && npm run dev   # http://localhost:5181/

# 远程转发本地
本地终端
ssh rag-agent-dev



