#!/bin/bash

API_URL="https://api.warframe.market/v2/orders/recent"
ITEM_API_BASE="https://api.warframe.market/v2/itemId"
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/1494659720466792501/vb4V_t-ya_F7V5TQbHqDnrjQR_bXf_o_OgPQ6nk0OwZPm10lpbcNW9NBImqLkW7uVwrg"
RUN_TIMESTAMP=$(TZ=Asia/Kolkata date +"%d/%m-%I:%M %p")

PRICE_THRESHOLD=30
ORDERS_PER_EMBED=3
MAX_EMBEDS_PER_MESSAGE=10   # Discord hard limit

if [ -z "$DISCORD_WEBHOOK_URL" ]; then
  echo "❌ DISCORD_WEBHOOK_URL not set"
  exit 1
fi

send_embeds() {
  local embeds_json="$1"

  payload=$(jq -n --argjson embeds "$embeds_json" '{ embeds: $embeds }')

  curl -s -X POST "$DISCORD_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$payload"
}

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
embed_count=0

# ---- separator embed (ONLY ON FIRST MESSAGE)
embeds=$(echo "$embeds" | jq '
  . + [{
    "title": " 🔔 Warframe Buy Orders '"$RUN_TIMESTAMP"'",
    "color": 9807270
  }]
')
embed_count=1

current_embed=""
order_count=0

flush_if_needed() {
  if [ "$embed_count" -ge "$MAX_EMBEDS_PER_MESSAGE" ]; then
    send_embeds "$embeds"
    embeds="[]"
    embed_count=0
  fi
}

while read -r order; do
  slug=$(get_slug "$(echo "$order" | jq -r '.itemId')")

  block="**Item:** [\`$slug\`](https://warframe.market/items/$slug)
**Buyer:** $(echo "$order" | jq -r '.user.ingameName')
**Price:** $(echo "$order" | jq -r '.platinum') 💰
**Rank:** $(echo "$order" | jq -r '.rank')
**Quantity:** $(echo "$order" | jq -r '.quantity')
"

  current_embed+="$block---"$'\n'
  ((order_count++))

  if [ "$order_count" -eq "$ORDERS_PER_EMBED" ]; then
    flush_if_needed

    embeds=$(echo "$embeds" | jq \
      --arg desc "$current_embed" \
      '. + [{ "description": $desc, "color": 15158332 }]'
    )

    current_embed=""
    order_count=0
    ((embed_count++))
  fi
done <<< "$(echo "$filtered" | jq -c '.[]')"

# Remaining orders
if [ -n "$current_embed" ]; then
  flush_if_needed

  embeds=$(echo "$embeds" | jq \
    --arg desc "$current_embed" \
    '. + [{ "description": $desc, "color": 15158332 }]'
  )
  ((embed_count++))
fi

# Final send
if [ "$(echo "$embeds" | jq 'length')" -gt 0 ]; then
  send_embeds "$embeds"
fi

echo "✅ Discord notifications sent (batched safely)"
