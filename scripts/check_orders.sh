#!/bin/bash

API_URL="https://api.warframe.market/v2/orders/recent"
ITEM_API_BASE="https://api.warframe.market/v1/items"
PRICE_THRESHOLD=50

echo "Fetching recent orders..."
response=$(curl -s "$API_URL")

if [ -z "$response" ]; then
  echo "API fetch failed"
  exit 1
fi

# Filter qualifying buy orders
orders=$(echo "$response" | jq '
  .data[]
  | select(.type=="buy" and .platinum > '"$PRICE_THRESHOLD"')
')

if [ -z "$orders" ]; then
  echo "No qualifying buy orders found."
  exit 0
fi

# Collect unique itemIds
item_ids=$(echo "$orders" | jq -r '.itemId' | sort -u)

declare -A ITEM_SLUG_MAP

echo "Resolving item slugs..."

for item_id in $item_ids; do
  item_response=$(curl -s "$ITEM_API_BASE/$item_id")
  slug=$(echo "$item_response" | jq -r '.data.item.slug // "unknown-item"')
  ITEM_SLUG_MAP["$item_id"]="$slug"
done

echo "Formatting Discord message..."

description=""

while read -r order; do
  item_id=$(echo "$order" | jq -r '.itemId')
  slug="${ITEM_SLUG_MAP[$item_id]}"

  description+="**Item:** \`$slug\`\n"
  description+="**Buyer:** $(echo "$order" | jq -r '.user.ingameName')\n"
  description+="**Price:** $(echo "$order" | jq -r '.platinum') 💰\n"
  description+="**Quantity:** $(echo "$order" | jq -r '.quantity')\n"
  description+="**Order ID:** $(echo "$order" | jq -r '.id')\n"
  description+="**Created:** $(echo "$order" | jq -r '.createdAt')\n"
  description+="\n---\n\n"
done <<< "$(echo "$orders" | jq -c '.')"

payload=$(jq -n \
  --arg title "🚨 Warframe BUY Orders > 50 Platinum" \
  --arg desc "$description" \
  '{
    embeds: [{
      title: $title,
      description: $desc,
      color: 15158332
    }]
  }')

curl -s -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$payload"
