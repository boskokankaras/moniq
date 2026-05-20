#!/bin/bash
TOKEN="nfp_Gfhst22NazQ4N5s4pCEojuGSM7XtuPtre7e8"
SITE_ID="59bd04fe-587b-4ca6-b6bc-ccd707a28fd0"
FILE="/Users/boskokankaras/moniq/moniq.html"

HASH=$(shasum "$FILE" | awk '{print $1}')
DEPLOY=$(curl -s -X POST "https://api.netlify.com/api/v1/sites/$SITE_ID/deploys" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"files\":{\"/index.html\":\"$HASH\"}}")

DEPLOY_ID=$(echo "$DEPLOY" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

curl -s -X PUT "https://api.netlify.com/api/v1/deploys/$DEPLOY_ID/files/index.html" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"$FILE" > /dev/null

echo "✅ Deploy gotov: https://chimerical-daffodil-e938ed.netlify.app"
