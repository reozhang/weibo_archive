#!/bin/bash
set -euo pipefail

# 抓取最新微博并发送到企业微信
# --- 配置区 ---
API_URL="https://api.weibo.com/2/statuses/user_timeline.json"
OUTPUT_FILE="$GITHUB_WORKSPACE/weibo.json"
APP_KEY="APP_KEY"  # 新增至Github Secrets

# --- 参数验证 ---
if [ -z "$USER_ID" ] || [ -z "$ACCESS_TOKEN" ] || [ -z "$WEBHOOK_URL" ]; then
  echo "##[error] 缺失必要参数：USER_ID/ACCESS_TOKEN/WEBHOOK_URL"
  exit 1
fi

# --- 创建目录 ---
mkdir -p "$(dirname "$OUTPUT_FILE")"

# 调试：显示完整请求命令
echo "调试：API请求命令"
echo "curl -G \"$API_URL\" 
--data-urlencode \"source=$APP_KEY\" 
--data-urlencode \"access_token=$ACCESS_TOKEN\" 
--data-urlencode \"uid=$USER_ID\""

# 请求微博API，抓取数据，新增source参数
HTTP_CODE=$(curl -s -o "$OUTPUT_FILE" -w "%{http_code}" -G "$API_URL" \
  --data-urlencode "source=$APP_KEY" \
  --data-urlencode "access_token=$ACCESS_TOKEN" \
  --data-urlencode "uid=$USER_ID" \
  --data-urlencode "count=20")

# 验证响应 ---
if [ "$HTTP_CODE" != "200" ]; then
  echo "##[error] API请求失败，状态码：$HTTP_CODE"
  if [ -f "$OUTPUT_FILE" ]; then
    echo "##[error] 错误详情：$(jq -c . "$OUTPUT_FILE")"
  fi
  exit 1
fi

# 新版数据结构验证（兼容移动端API）
if ! jq -e '.statuses? // .data.list?' "$OUTPUT_FILE" > /dev/null; then
  echo "##[error] 未获取到有效微博数据，原始响应："
  cat "$OUTPUT_FILE"
  exit 1
fi

# 数据解析（兼容多版本API）
LATEST_TEXT=$(jq -r '
  if .statuses then 
    .statuses[0].text 
  else 
    .data.list[0].text 
  end' "$OUTPUT_FILE" | sed 's/<[^>]*>//g')
  
# --- 构造安全JSON 企业微信消息---
MSG_JSON=$(jq -n \
  --arg title "E大微博更新提醒 - $CREATED_AT" \
  --arg desc "$LATEST_TEXT" \
  --arg url "$BLOG_URL" \
  --arg pic "$(jq -r '.statuses[0].thumbnail_pic' "$OUTPUT_FILE")" \
  '{
    msgtype: "news",
    news: {
      articles: [
        {
          title: $title,
          description: $desc,
          url: $url,
          picurl: $pic
        }
      ]
    }
  }')

# --- 发送到企业微信 ---
curl -X POST -H "Content-Type: application/json" \
  -d "$MSG_JSON" "$WEBHOOK_URL"
 
