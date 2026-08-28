#!/bin/bash

git add .
git commit -m "fix"
git push

set -e

# ============================================
# 声动AI口语 - Flutter Web 编译部署脚本
# ============================================

# 配置项
PROJECT_DIR="/Users/zhaosongqiang/Documents/code_other/github_code/ielts-spoken/flutter-app"
PEM_FILE="/Users/zhaosongqiang/macbook-login-pem.pem"
SSH_PORT="45600"
SERVER_USER="ecs-user"
SERVER_IP="121.40.78.62"
API_BASE_URL="https://www.nineduck.com"

echo "========== [1/4] 进入编译目录 =========="
cd "$PROJECT_DIR" || { echo "错误: 目录不存在 - $PROJECT_DIR"; exit 1; }
echo "当前目录: $(pwd)"

echo "========== [2/4] 编译 Flutter Web =========="
flutter build web --release --dart-define=API_BASE_URL="$API_BASE_URL"
if [ $? -ne 0 ]; then
    echo "错误: Flutter 编译失败"
    exit 1
fi
echo "编译完成"

echo "========== [3/4] 上传编译结果到服务器 =========="
scp -P "$SSH_PORT" -i "$PEM_FILE" -r build/web/ "${SERVER_USER}@${SERVER_IP}:/home/${SERVER_USER}/web"
if [ $? -ne 0 ]; then
    echo "错误: SCP 上传失败"
    exit 1
fi
echo "上传完成"

echo "========== [4/4] 部署静态资源 =========="
ssh -p "$SSH_PORT" -i "$PEM_FILE" "${SERVER_USER}@${SERVER_IP}" << 'REMOTE_COMMANDS'
    sudo rm -rf /var/www/html/
    sudo cp -r /home/ecs-user/web /var/www/html
    sudo nginx -s reload
    sudo rm -rf /home/ecs-user/web
    echo "部署完成，Nginx 已重载"
REMOTE_COMMANDS

echo "========================================="
echo "全部部署完成！"
echo "========================================="
