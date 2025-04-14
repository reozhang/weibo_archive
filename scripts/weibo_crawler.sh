#!/bin/bash
set -euo pipefail

# --- 配置区 ---
API_URL="https://m.weibo.cn/api/container/getIndex"  # 更新为有效API地址
OUTPUT_FILE="$GITHUB_WORKSPACE/weibo.json"
USER_ID="$USER_ID"  # 要监控的微博用户UID
WEBHOOK_URL="$WEBHOOK_URL"
COOKIE="SUB=_2A25K-PAUDeRhGedL7FsW8y3Nwz6IHXVmdA3crDV6PUJbktAbLVPtkW1NVIHML4psSgJa6KrNJkyvcDMHsc2a_0k7; SUBP=0033WrSXqPxfM725Ws9jqgMF55529P9D9W58SbVGVkK3ivfE9Smzfy6Z5JpX5KzhUgL.Fo2fS0.Ne0ep1hz2dJLoI0YLxKqLBonL1h-LxKnL12BLBoMLxK-L1h-L1heLxK-LBo.LBoBLxKBLBonL1h5LxKMLB.2LB.qLxKML1KBL1-qt; SSOLoginState=1744601158"  # 必须配置

# --- 容器ID生成（增加备用方案）---
CONTAINER_ID="230413$USER_ID"  # 新格式容器ID
ALTERNATE_ID="107603$USER_ID"  # 备用旧格式

# --- 请求验证 ---
[ -z "$COOKIE" ] || [ -z "$USER_ID" ] && {
  echo "##[error] 必需参数缺失"
  exit 1
}

# --- 创建目录 ---
mkdir -p "$(dirname "$OUTPUT_FILE")"

# --- 抓取数据（反爬措施）---
sleep $((RANDOM % 25 + 10))  # 延长至10-25秒延迟

# --- 双重容器ID请求 ---
for CID in $CONTAINER_ID $ALTERNATE_ID; do
  HTTP_CODE=$(curl -v -s -o "$OUTPUT_FILE" -w "%{http_code}" -L \
    -H "Cookie: $COOKIE; $(grep 'set-cookie' "$OUTPUT_FILE" 2>/dev/null | awk -F';' '{print $1}' | sed 's/< //g' | tr '\n' ';')" \
    -H "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Weibo (iPhone15,3__weibo__16.2.0__iphone__os17.6)" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Referer: https://m.weibo.cn/u/$USER_ID" \
    -H "X-XSRF-TOKEN: $(grep 'XSRF-TOKEN' "$OUTPUT_FILE" 2>/dev/null | awk -F'=' '{print $2}' | cut -d';' -f1)" \
    -H "Host: m.weibo.cn" \
    "${API_URL}?containerid=$CID&page=1&luicode=10000011&lfid=230283$USER_ID")  # 新增lfid参数

  # 验证响应
  if [ "$HTTP_CODE" == "200" ]; then
    break
  fi
done

# --- 数据解析增强 ---
WEIBO_DATA=$(jq -r '
  .data.cards[] | 
  select(.card_type == 41 or .card_type == 9 or .card_type == 11) |
  {
    text: (.mblog.text | gsub("<.*?>"; "")),
    created_at: (.mblog.created_at | strptime("%a %b %d %H:%M:%S %z %Y") | strftime("%Y-%m-%d %H:%M")),
    id: .mblog.id,
    pics: [.mblog.pics[].url]
  } | select(.text != null)' "$OUTPUT_FILE" | jq -s '.[0]')

# --- 异常处理 ---
if [[ $(jq -e 'length > 0' <<< "$WEIBO_DATA") != "true" ]]; then
  echo "##[error] 无有效微博数据，调试信息："
  jq '.' "$OUTPUT_FILE"
  exit 1
fi

# --- 消息构造 ---
MSG_JSON=$(jq -n \
  --argjson data "$WEIBO_DATA" \
  --arg defaultPic "https://placehold.co/600x400?text=暂无图片" \
  '{
    msgtype: "news",
    news: {
      articles: [{
        title: "微博更新 - \($data.created_at)",
        description: "\($data.text[0:200])",
        url: "https://m.weibo.cn/detail/\($data.id)",
        picurl: (if $data.pics[0] then $data.pics[0] else $defaultPic end)
      }]
    }
  }')

# --- 发送到企业微信 ---
curl -X POST -H "Content-Type: application/json" \
  -d "$MSG_JSON" "$WEBHOOK_URL"
  
