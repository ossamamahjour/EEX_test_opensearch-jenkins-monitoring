#!/bin/bash

# Updated script that handles OpenSearch API correctly
CONFIG_FILE="/config/monitors.json"
OPENSEARCH_URL="http://opensearch:9200"
ALERTING_API="/_plugins/_alerting/monitors"
SEARCH_API="/_plugins/_alerting/monitors/_search"
LOG_FILE="/tmp/monitor_update.log"

# Clear log file
echo "=== Monitor Update $(date) ===" > $LOG_FILE

# Log to both stdout and log file
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

log "Starting monitor update process"

# First get all monitors (using POST with empty body)
log "Getting existing monitors..."
ALL_MONITORS=$(curl -s -X POST "$OPENSEARCH_URL$SEARCH_API" \
  -H 'Content-Type: application/json' \
  -d '{}')

echo "Monitor Search Result: $ALL_MONITORS" >> $LOG_FILE

# Check if there are hits in the response
if echo "$ALL_MONITORS" | jq -e '.hits.hits' > /dev/null; then
  # Extract IDs of existing monitors
  MONITOR_IDS=$(echo "$ALL_MONITORS" | jq -r '.hits.hits[]._id' 2>/dev/null)
  log "Found monitors: $MONITOR_IDS"
  
  # Delete all existing monitors
  if [ ! -z "$MONITOR_IDS" ]; then
    log "Deleting existing monitors..."
    for ID in $MONITOR_IDS; do
      log "Deleting monitor $ID"
      DELETE_RESULT=$(curl -s -X DELETE "$OPENSEARCH_URL$ALERTING_API/$ID")
      log "Delete result: $DELETE_RESULT"
      sleep 1
    done
  else
    log "No existing monitors found to delete"
  fi
else
  log "No monitors found or unexpected response format"
  echo "$ALL_MONITORS" >> $LOG_FILE
fi

# Handle notification channels
log "Setting up notification channels..."
# Extract unique notification channels from the monitors.json file
UNIQUE_CHANNELS=$(jq -r '.Monitors[].notificantion_channel' $CONFIG_FILE | sort | uniq)

for CHANNEL in $UNIQUE_CHANNELS; do
  log "Creating notification channel: $CHANNEL"
  
  CHANNEL_CONFIG="{
    \"name\": \"$CHANNEL\",
    \"config\": {
      \"name\": \"$CHANNEL\",
      \"type\": \"slack\",
      \"is_enabled\": true,
      \"slack\": {
        \"url\": \"https://hooks.slack.com/services/test/webhook/url\"
      }
    }
  }"
  
  # Create the channel (ignore errors if it already exists)
  curl -s -X POST "$OPENSEARCH_URL/_plugins/_notifications/configs" \
    -H 'Content-Type: application/json' \
    -d "$CHANNEL_CONFIG" >> $LOG_FILE
  
  sleep 1
done

# Extract monitors from config file
log "Creating monitors from config..."
MONITORS=$(jq -c '.Monitors[]' $CONFIG_FILE)

# Process each monitor
echo "$MONITORS" | while read -r MONITOR_JSON; do
  NAME=$(echo "$MONITOR_JSON" | jq -r '.Monitor_Name')
  INDEX=$(echo "$MONITOR_JSON" | jq -r '.Index')
  
  # Get lowercase index name
  case "$INDEX" in
    "Index_A") ACTUAL_INDEX="index_a" ;;
    "Index_B") ACTUAL_INDEX="index_b" ;;
    "Index_C") ACTUAL_INDEX="index_c" ;;
    *) ACTUAL_INDEX=$(echo "$INDEX" | tr '[:upper:]' '[:lower:]') ;;
  esac
  
  TEXT=$(echo "$MONITOR_JSON" | jq -r '.Text2Scan_in_Message')
  TIME=$(echo "$MONITOR_JSON" | jq -r '.Time2Scan')
  CHANNEL=$(echo "$MONITOR_JSON" | jq -r '.notificantion_channel')
  
  log "Creating monitor: $NAME for index $ACTUAL_INDEX"
  
  # Build monitor JSON
  MONITOR_CONFIG="{
    \"name\": \"$NAME\",
    \"type\": \"monitor\",
    \"enabled\": true,
    \"schedule\": {\"period\": {\"interval\": 1, \"unit\": \"MINUTES\"}},
    \"inputs\": [{
      \"search\": {
        \"indices\": [\"$ACTUAL_INDEX\"],
        \"query\": {
          \"size\": 0,
          \"query\": {
            \"bool\": {
              \"must\": [
                {\"range\": {\"@timestamp\": {\"gte\": \"now-$TIME\", \"lte\": \"now\"}}},
                {\"match\": {\"message\": \"$TEXT\"}}
              ]
            }
          }
        }
      }
    }],
    \"triggers\": [{
      \"name\": \"Found $TEXT in $INDEX\",
      \"severity\": \"1\",
      \"condition\": {\"script\": {\"source\": \"ctx.results[0].hits.total.value > 0\", \"lang\": \"painless\"}},
      \"actions\": [{
        \"name\": \"Notify\",
        \"destination_id\": \"$CHANNEL\",
        \"message_template\": {
          \"source\": \"Monitor {{ctx.monitor.name}} detected {{ctx.results[0].hits.total.value}} instances of '$TEXT' in $INDEX index in the last $TIME.\",
          \"lang\": \"mustache\"
        },
        \"throttle_enabled\": true,
        \"throttle\": {\"value\": 10, \"unit\": \"MINUTES\"}
      }]
    }]
  }"
  
  # Create the monitor
  CREATE_RESULT=$(curl -s -X POST "$OPENSEARCH_URL$ALERTING_API" \
    -H 'Content-Type: application/json' \
    -d "$MONITOR_CONFIG")
  
  echo "Create monitor result: $CREATE_RESULT" >> $LOG_FILE
  
  if echo "$CREATE_RESULT" | grep -q "error"; then
    log "Error creating monitor: $NAME"
  else
    log "Successfully created monitor: $NAME"
  fi
  
  sleep 2
done

log "Monitor update completed"