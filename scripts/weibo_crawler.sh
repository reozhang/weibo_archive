#!/bin/bash
set -euo pipefail

# --- 配置区 ---
API_URL="https://weibo.com/ajax/statuses/mymblog"  # 更改为移动端API
OUTPUT_FILE="$GITHUB_WORKSPACE/weibo.json"
USER_ID="$USER_ID"  # 要监控的微博用户UID
WEBHOOK_URL="$WEBHOOK_URL"

# --- 参数验证 ---
if [ -z "$USER_ID" ] || [ -z "$WEBHOOK_URL" ]; then
  echo "##[error] 缺失必要参数：USER_ID/WEBHOOK_URL"
  exit 1
fi

# --- 创建目录 ---
mkdir -p "$(dirname "$OUTPUT_FILE")"

# --- 抓取公开微博数据 ---
HTTP_CODE=$(curl -s -o "$OUTPUT_FILE" -w "%{http_code}" \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  "${API_URL}?uid=${USER_ID}&page=1&feature=0")

# --- 响应验证 ---
if [ "$HTTP_CODE" != "200" ]; then
  echo "##[error] API请求失败，状态码：$HTTP_CODE"
  exit 1
fi

if ! jq -e '.data.list | length > 0' "$OUTPUT_FILE" > /dev/null; then
  echo "##[error] 未获取到有效微博数据"
  echo "可能原因："
  echo "1. 用户ID错误"
  echo "2. 用户微博设置为私密"
  echo "3. 微博服务器限制（需添加延迟）"
  exit 1
fi

# --- 数据解析 ---
LATEST_TEXT=$(jq -r '.data.list[0].text_raw' "$OUTPUT_FILE" | sed 's/<\/\?[^>]\+>//g')  # 去除HTML标签
CREATED_AT=$(jq -r '.data.list[0].created_at' "$OUTPUT_FILE" | awk '{print substr($0,1,19)}') # 时间格式化
WEIBO_ID=$(jq -r '.data.list[0].id' "$OUTPUT_FILE")
BLOG_URL="https://weibo.com/$USER_ID/$WEIBO_ID"

# --- 图片处理 ---
PIC_URL=$(jq -r '.data.list[0].pic_infos | to_entries[0].value.original.url // ""' "$OUTPUT_FILE")

# --- 构造企业微信消息 ---
MSG_JSON=$(jq -n \
  --arg title "E大微博更新提醒 - $(date -d "$CREATED_AT" '+%Y-%m-%d %H:%M')" \
  --arg desc "${LATEST_TEXT:0:200}" \  # 限制描述长度
  --arg url "$BLOG_URL" \
  --arg pic "${PIC_URL:-https://example.com/default.jpg}" \
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
