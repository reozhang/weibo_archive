#!/bin/bash
# 抓取最新微博并发送到企业微信
API_URL="https://api.weibo.com/2/statuses/user_timeline.json"
OUTPUT_FILE="/tmp/weibo.json"

# 抓取最新10条微博
curl -s -G "$API_URL" \
  --data-urlencode "access_token=$ACCESS_TOKEN" \
  --data-urlencode "uid=$USER_ID" \
  --data-urlencode "count=10" \
  -o $OUTPUT_FILE

# 提取最新微博内容
LATEST_TEXT=$(jq -r '.statuses[0].text' $OUTPUT_FILE | sed 's/<[^>]*>//g') 
CREATED_AT=$(jq -r '.statuses[0].created_at' $OUTPUT_FILE)
BLOG_URL="https://weibo.com/u/$USER_ID/$(jq -r '.statuses[0].id' $OUTPUT_FILE)"

# 构造企业微信消息
MSG_JSON=$(cat <<EOF
{
  "msgtype": "news",
  "news": {
    "articles": [
      {
        "title": "微博更新提醒 - $CREATED_AT",
        "description": "$LATEST_TEXT",
        "url": "$BLOG_URL",
        "picurl": "$(jq -r '.statuses[0].thumbnail_pic' $OUTPUT_FILE)"
      }
    ]
  }
}
EOF
)

# 发送到企业微信
curl -X POST -H "Content-Type: application/json" \
  -d "$MSG_JSON" $WEBHOOK_URL
