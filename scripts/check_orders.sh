#!/bin/bash

API_URL="https://api.warframe.market/v2/orders/recent"
PRICE_THRESHOLD=50

echo "Fetching recent orders..."
response=$(curl -s "$API_URL")

if [ -z "$response" ]; then
  echo "API fetch failed"
  exit 1
fi

alerts=$(echo "$response" | jq -r '
  .data[] |
  select(.order_type=="buy" and .platinum > '"$PRICE_THRESHOLD"') |
  {
    item: .item.en,
    buyer: .user.ingame_name,
    price: .platinum,
    quantity: .quantity
  }
')

if [ -z "$alerts" ]; then
  echo "No qualifying buy orders found."
  exit 0
fi

echo "Preparing Discord payload..."

content=$(echo "$alerts" | jq -s '
  map(
    "**Item:** \(.item)\n" +
    "**Buyer:** \(.buyer)\n" +
    "**Price:** \(.price) 💰\n" +
    "**Quantity:** \(.quantity)\n"
  ) | join("\n---\n")
')

payload=$(jq -n \
  --arg title "🚨 Warframe Buy Order Alert (>50p)" \
  --arg desc "$content" \
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