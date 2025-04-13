#!/bin/bash
set -euo pipefail

# --- 配置区 ---
API_URL="https://m.weibo.cn/api/container/getIndex"  # 更新为有效API地址
OUTPUT_FILE="$GITHUB_WORKSPACE/weibo.json"
USER_ID="$USER_ID"  # 要监控的微博用户UID
WEBHOOK_URL="$WEBHOOK_URL"
COOKIE="SUB=_2A25K82oTDeRhGedL7FsW8y3Nwz6IHXVmcePbrDV8PUNbmtAbLXHBkW9NVIHMLwNIRyQFBudNtKS2bRU4I_RGBopR; SUBP=0033WrSXqPxfM725Ws9jqgMF55529P9D9W58SbVGVkK3ivfE9Smzfy6Z5NHD95QpSKM4S0e0eKnEWs4Dqcj6i--ci-zRiKnfi--RiKy2i-zNi--fiKnfiKn0i--fi-z4i-zXi--Xi-zRiKn7i--Ni-iWi-isi--NiK.XiKLs; "  # 必须配置

# --- 请求参数验证 ---
if [ -z "$COOKIE" ] || [ -z "$USER_ID" ]; then
  echo "##[error] 必需参数缺失"
  exit 1
fi

# --- 创建目录 ---
mkdir -p "$(dirname "$OUTPUT_FILE")"

# --- 抓取数据（带反爬措施）---
sleep $((RANDOM % 10 + 5))  # 随机延迟5-15秒

HTTP_CODE=$(curl -v -s -o "$OUTPUT_FILE" -w "%{http_code}" -L --max-redirs 3 \
  -H "Cookie: $COOKIE" \
  -H "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Weibo (iPhone13,3__weibo__12.5.0__iphone__os15.0)" \
  -H "Referer: https://m.weibo.cn/u/$USER_ID" \
  "${API_URL}?uid=${USER_ID}&page=1&feature=0")

# --- 响应验证 ---
if [ "$HTTP_CODE" != "200" ]; then
  echo "##[error] 请求失败，状态码：$HTTP_CODE"
  echo "调试信息："
  grep -E '^< HTTP|Location:' "$OUTPUT_FILE"
  exit 1
fi

# --- 数据解析（新增重定向检测）---
if grep -q 'login.sina.com.cn' "$OUTPUT_FILE"; then
  echo "##[error] 需要重新登录（Cookie失效）"
  exit 1
fi

# 添加Cookie失效自动通知
if grep -q 'login.sina.com.cn' "$OUTPUT_FILE"; then
  curl -X POST -H "Content-Type: application/json" \
    -d '{"msgtype":"text","text":{"content":"微博Cookie已失效，请及时更新！"}}' \
    "$WEBHOOK_URL"
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
