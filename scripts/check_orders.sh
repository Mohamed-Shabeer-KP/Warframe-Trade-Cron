#!/bin/bash

API_URL="https://api.warframe.market/v2/orders/recent"
ITEM_API_BASE="https://api.warframe.market/v2/itemId"
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/1494659720466792501/vb4V_t-ya_F7V5TQbHqDnrjQR_bXf_o_OgPQ6nk0OwZPm10lpbcNW9NBImqLkW7uVwrg"
RUN_TIMESTAMP=$(TZ=Asia/Kolkata date +"%d/%m-%I:%M %p")

PRICE_THRESHOLD=30
ORDERS_PER_EMBED=5
MAX_EMBEDS=10


send_embeds() {
  local embeds_json="$1"

  payload=$(jq -n --argjson embeds "$embeds_json" '{ embeds: $embeds }')

  curl -s -X POST "$DISCORD_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$payload"
}

if [ -z "$DISCORD_WEBHOOK_URL" ]; then
  echo "❌ DISCORD_WEBHOOK_URL not set"
  exit 1
fi

echo "🔍 Fetching recent orders..."
response=$(curl -s "$API_URL")

if [ -z "$response" ]; then
  echo "❌ API fetch failed"
  exit 1
fi

total_orders=$(echo "$response" | jq '.data | length')
echo "✅ Fetched $total_orders recent orders"

filtered=$(echo "$response" | jq '
  .data
  | map(select(.type=="buy" and .platinum > '"$PRICE_THRESHOLD"'))
  | sort_by(.platinum)
  | reverse
')

filtered_count=$(echo "$filtered" | jq 'length')
echo "✅ Found $filtered_count buy orders with price condition met"

if [ "$filtered_count" -eq 0 ]; then
  exit 0
fi

echo "🔎 Resolving item slugs..."

declare -A SLUG_CACHE

get_slug() {
  local id="$1"
  if [ -z "${SLUG_CACHE[$id]}" ]; then
    SLUG_CACHE[$id]=$(curl -s "$ITEM_API_BASE/$id" | jq -r '.data.slug // "unknown-item"')
  fi
  echo "${SLUG_CACHE[$id]}"
}

echo "📝 Building embeds..."

embeds="[]"
current_embed=""
count=0
embed_count=0

embeds=$(echo "$embeds" | jq '
  . + [{
    "title": "🔔 WARFRAME ORDERS ('"$RUN_TIMESTAMP"')",
    "color": 9807270
  }]
')

while read -r order; do
  slug=$(get_slug "$(echo "$order" | jq -r '.itemId')")

  block="**Item:** [\`$slug\`](https://warframe.market/items/$slug)
**Buyer:** $(echo "$order" | jq -r '.user.ingameName')
**Price:** $(echo "$order" | jq -r '.platinum') 💰
**Rank:** $(echo "$order" | jq -r '.rank') 
**Quantity:** $(echo "$order" | jq -r '.quantity') 
"

if [ "$embed_count" -eq 10 ]; then
  send_embeds "$embeds"
  embeds="[]"
  embed_count=0
fi

  current_embed+="$block-"$'\n'
  ((count++))

  if [ "$count" -eq "$ORDERS_PER_EMBED" ]; then
    embeds=$(echo "$embeds" | jq \
      --arg desc "$current_embed" \
      '. + [{"description": $desc, "color": 15158332 }]'
    )
    current_embed=""
    
    count=0
    ((embed_count++))
    [ "$embed_count" -ge "$MAX_EMBEDS" ] && break
  fi
done <<< "$(echo "$filtered" | jq -c '.[]')"

# Add remaining orders

if [ -n "$current_embed" ] && [ "$embed_count" -lt "$MAX_EMBEDS" ]; then
  embeds=$(echo "$embeds" | jq \
    --arg desc "$current_embed" \
     '. + [{"description": $desc, "color": 15158332 }]'
  )
fi


if [ "$(echo "$embeds" | jq 'length')" -gt 0 ]; then
  send_embeds "$embeds"
fi


payload=$(jq -n --argjson embeds "$embeds" '{ embeds: $embeds }')

curl -s -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$payload"

echo "✅ Discord notification sent with multiple embeds"