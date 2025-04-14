#!/bin/bash
set -euo pipefail

# --- 配置区 ---
API_URL="https://m.weibo.cn/api/container/getIndex"  # 更新为有效API地址
OUTPUT_FILE="$GITHUB_WORKSPACE/weibo.json"
USER_ID="$USER_ID"  # 要监控的微博用户UID
WEBHOOK_URL="$WEBHOOK_URL"
COOKIE="SUB=_2A25K-PAUDeRhGedL7FsW8y3Nwz6IHXVmdA3crDV6PUJbktAbLVPtkW1NVIHML4psSgJa6KrNJkyvcDMHsc2a_0k7; SUBP=0033WrSXqPxfM725Ws9jqgMF55529P9D9W58SbVGVkK3ivfE9Smzfy6Z5JpX5KzhUgL.Fo2fS0.Ne0ep1hz2dJLoI0YLxKqLBonL1h-LxKnL12BLBoMLxK-L1h-L1heLxK-LBo.LBoBLxKBLBonL1h5LxKMLB.2LB.qLxKML1KBL1-qt; SSOLoginState=1744601158"  # 必须配置

# --- 容器ID生成（2025最新格式）---
declare -a CONTAINER_IDS=(
  "107603$USER_ID"    # 网页端容器格式
  "230413$USER_ID"    # 移动端容器格式
  "100505$USER_ID"    # 历史兼容格式
)

# --- 动态令牌管理 ---
XSRF_TOKEN=""
update_xsrf_token() {
  XSRF_TOKEN=$(grep 'XSRF-TOKEN' "$OUTPUT_FILE" 2>/dev/null | 
    awk -F'[=;]' '{print $2}' | tr -d '\n')
}

# --- 创建目录 ---
mkdir -p "$(dirname "$OUTPUT_FILE")"

# --- 请求执行 ---
for CID in "${CONTAINER_IDS[@]}"; do
  sleep $((RANDOM % 25 + 15))
  
  HTTP_CODE=$(curl -v -s -o "$OUTPUT_FILE" -w "%{http_code}" -L \
    -H "Cookie: $COOKIE; $(grep 'set-cookie' "$OUTPUT_FILE" 2>/dev/null | 
      awk -F';' '{print $1}' | sed 's/< //g' | tr '\n' ';')" \
    -H "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 17_6_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Weibo (iPhone15,3__weibo__17.2.0__iphone__os17.6.1)" \
    -H "X-XSRF-TOKEN: ${XSRF_TOKEN:-d41d8cd98f00b204e9800998ecf8427e}" \
    -H "Referer: https://m.weibo.cn/u/$USER_ID" \
    "${API_URL}?containerid=$CID&page=1&luicode=10000011&lfid=230283$USER_ID&from=10_9094")

  update_xsrf_token
  [ "$HTTP_CODE" == "200" ] && break
done

# --- 数据解析增强 ---
WEIBO_DATA=$(jq -r '
  (.data.cards // []) | map(select(
    .card_type? | IN(41, 9, 11, 201, 302) and 
    (.mblog? != null) and 
    (.mblog.isDeleted? != true)
  ))[0] // {} | 
  .mblog | {
    text: (.text | gsub("<.*?>"; "")),
    created_at: (.created_at | strptime("%a %b %d %H:%M:%S %z %Y")? // now | strftime("%Y-%m-%d %H:%M")),
    id: (.id // "unknown"),
    pics: ([.pics[]?.url] // [])
  }' "$OUTPUT_FILE")
  
# --- 异常处理 ---
if [[ $(jq -e 'length > 0' <<< "$WEIBO_DATA") != "true" ]]; then
  echo "##[error] 无有效微博数据，调试信息："
  jq '.' "$OUTPUT_FILE"
  exit 1
fi

# 增强消息模板（支持多图展示）
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
        picurl: ($data.pics | if length >0 then .[0] else $defaultPic end)
      }] + [
        $data.pics[1:3][] | {picurl: .}
      ]
    }
  }')

# --- 发送到企业微信 ---
curl -X POST -H "Content-Type: application/json" \
  -d "$MSG_JSON" "$WEBHOOK_URL"
  
