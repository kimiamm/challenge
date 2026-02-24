#!/bin/bash

# =========================
# CONFIGURATION
# =========================

ES_HOST="http://188.121.107.139:9200"
ES_USER="elastic"
ES_PASS="Kimi%40123"

INDEXES=("cdn-logs-2026.02.24")
OUTPUT_FILE="elastic_data.json"
S3_BUCKET="kimi-ch"

# =========================
# MAIN
# =========================

if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Creating new output file."
    echo "[]" > "$OUTPUT_FILE"
fi

ALL_DATA="[]"

for index in "${INDEXES[@]}"; do
    echo "Fetching data from $index..."

    DUMP_FILE=$(mktemp)
    rm -f "$DUMP_FILE"

    elasticdump \
        --input="http://${ES_USER}:${ES_PASS}@188.121.107.139:9200/${index}" \
        --output="$DUMP_FILE" \
        --type=data \
        --quiet

    if [ -f "$DUMP_FILE" ]; then
        INDEX_DATA=$(jq -c '._source' "$DUMP_FILE" | jq -s 'sort_by(."@timestamp")')
        ALL_DATA=$(echo "$ALL_DATA $INDEX_DATA" | jq -s 'add | unique_by(."@timestamp")')
        rm -f "$DUMP_FILE"
    else
        echo "No data returned for $index"
    fi
done

if [ "$ALL_DATA" != "$(cat "$OUTPUT_FILE")" ]; then
    echo "New data found. Updating file."
    echo "$ALL_DATA" > "$OUTPUT_FILE"

    echo "Uploading to S3..."
    rclone copy "$OUTPUT_FILE" s3:${S3_BUCKET}/ --progress
    echo "Upload complete."
else
    echo "No new data. All received data are duplicates."
fi