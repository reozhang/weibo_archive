#!/bin/bash
set -euo pipefail

# --- 配置区 ---
API_URL="https://m.weibo.cn/api/container/getIndex"  # 更新为有效API地址
OUTPUT_FILE="$GITHUB_WORKSPACE/weibo.json"
USER_ID="$USER_ID"  # 要监控的微博用户UID
WEBHOOK_URL="$WEBHOOK_URL"
COOKIE="SUB=_2A25K-PAUDeRhGedL7FsW8y3Nwz6IHXVmdA3crDV6PUJbktAbLVPtkW1NVIHML4psSgJa6KrNJkyvcDMHsc2a_0k7; SUBP=0033WrSXqPxfM725Ws9jqgMF55529P9D9W58SbVGVkK3ivfE9Smzfy6Z5JpX5KzhUgL.Fo2fS0.Ne0ep1hz2dJLoI0YLxKqLBonL1h-LxKnL12BLBoMLxK-L1h-L1heLxK-LBo.LBoBLxKBLBonL1h5LxKMLB.2LB.qLxKML1KBL1-qt; SSOLoginState=1744601158"  # 必须配置

# --- 容器ID生成（增加备用方案）---
CONTAINER_ID="230567$USER_ID"  # 新格式容器ID
# CONTAINER_ID="100505$USER_ID"  # 旧格式备用

# --- 请求参数验证 ---
if [ -z "$COOKIE" ] || [ -z "$USER_ID" ]; then
  echo "##[error] 必需参数缺失"
  exit 1
fi

# --- 创建目录 ---
mkdir -p "$(dirname "$OUTPUT_FILE")"

# --- 抓取数据（反爬措施）---
sleep $((RANDOM % 20 + 10))  # 延长至10-25秒延迟

# --- 请求数据 ---
HTTP_CODE=$(curl -v -s -o "$OUTPUT_FILE" -w "%{http_code}" -L \
  -H "Cookie: $COOKIE" \
  -H "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Weibo (iPhone15,3__weibo__16.2.0__iphone__os17.6)" \
  -H "X-Requested-With: XMLHttpRequest" \
  -H "Referer: https://m.weibo.cn/u/$USER_ID" \
  "${API_URL}?containerid=$CONTAINER_ID&page=1&luicode=10000011")

# --- 响应验证 ---
if [ "$HTTP_CODE" != "200" ]; then
  echo "##[error] 请求失败，状态码：$HTTP_CODE"
  echo "调试信息："
  grep -E '^< (HTTP|Location):' "$OUTPUT_FILE"
  exit 1
fi

# --- 新版数据解析 ---
if ! jq -e '.data.cards[] | select(.card_type == 11)' "$OUTPUT_FILE" > /dev/null; then
  echo "##[error] 未找到新版卡片数据，尝试旧版解析..."
  if ! jq -e '.data.cards[] | select(.card_type == 9)' "$OUTPUT_FILE" > /dev/null; then
    echo "##[error] 无有效微博数据"
    exit 1
  fi
  # 旧版数据处理
  LATEST_TEXT=$(jq -r '.data.cards[] | select(.card_type == 9) | .mblog.text' "$OUTPUT_FILE" | head -n1 | sed 's/<[^>]*>//g')
  CREATED_AT=$(jq -r '.data.cards[] | select(.card_type == 9) | .mblog.created_at' "$OUTPUT_FILE" | head -n1)
else
  # 新版数据处理
  LATEST_TEXT=$(jq -r '.data.cards[] | select(.card_type == 11) | .mblog.text' "$OUTPUT_FILE" | head -n1 | sed 's/<[^>]*>//g')
  CREATED_AT=$(jq -r '.data.cards[] | select(.card_type == 11) | .mblog.created_at' "$OUTPUT_FILE" | head -n1)
fi

# --- 时间格式处理 ---
FORMATTED_TIME=$(date -d "$(echo $CREATED_AT | sed 's/... ..:..//')" '+%Y-%m-%d %H:%M')

# 提取最新微博（card_type=9为原创微博）
LATEST_TEXT=$(jq -r '.data.cards[] | select(.card_type == 9) | .mblog.text' "$OUTPUT_FILE" | head -n1 | sed 's/<[^>]*>//g')
WEIBO_ID=$(jq -r '.data.cards[] | select(.card_type == 9) | .mblog.id' "$OUTPUT_FILE" | head -n1)
BLOG_URL="https://m.weibo.cn/status/$WEIBO_ID"

# --- 微博ID和链接 ---
WEIBO_ID=$(jq -r '[.data.cards[] | .mblog.id | select(. != null)] | first' "$OUTPUT_FILE")
BLOG_URL="https://m.weibo.cn/detail/$WEIBO_ID"

# --- 图片处理 ---
PIC_URL=$(jq -r '[.data.cards[] | .mblog.pics?[].url // empty][0]' "$OUTPUT_FILE")

# --- 消息构造 ---
MSG_JSON=$(jq -n \
  --arg title "微博更新提醒 - $FORMATTED_TIME" \
  --arg desc "${LATEST_TEXT:0:200}" \
  --arg url "$BLOG_URL" \
  --arg pic "${PIC_URL:-https://placehold.co/600x400?text=暂无图片}" \
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
  
