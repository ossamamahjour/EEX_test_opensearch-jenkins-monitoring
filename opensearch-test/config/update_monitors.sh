#!/bin/bash

# Script to update OpenSearch monitors from JSON config
# Designed to run as a Jenkins job

CONFIG_FILE="/config/monitors.json"
OPENSEARCH_URL="http://opensearch:9200"
ALERTING_API="/_plugins/_alerting/monitors"

# Index mapping
declare -A INDEX_MAPPING
INDEX_MAPPING["Index_A"]="index_a"
INDEX_MAPPING["Index_B"]="index_b"
INDEX_MAPPING["Index_C"]="index_c"

# Log function
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting monitor update process"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  log "Error: Config file not found at $CONFIG_FILE"
  exit 1
fi

# Check if jq is installed, install if not
if ! command -v jq &> /dev/null; then
  log "Installing jq..."
  apt-get update && apt-get install -y jq
fi

# Wait for OpenSearch to be ready
max_retries=10
retry_count=0

while [ $retry_count -lt $max_retries ]; do
  if curl -s "$OPENSEARCH_URL" > /dev/null; then
    log "OpenSearch is ready"
    break
  fi
  
  log "Waiting for OpenSearch to be ready (attempt $((retry_count+1))/$max_retries)..."
  sleep 5
  retry_count=$((retry_count+1))
done

if [ $retry_count -eq $max_retries ]; then
  log "Error: OpenSearch is not available after multiple attempts"
  exit 1
fi

# Check if notification channels exist, create if not
NOTIFICATION_CHANNELS=$(curl -s "$OPENSEARCH_URL/_plugins/_notifications/configs")
if [[ $NOTIFICATION_CHANNELS != *"notification_channel_1"* ]]; then
  log "Creating notification channel 1"
  curl -s -X POST "$OPENSEARCH_URL/_plugins/_notifications/configs" \
    -H 'Content-Type: application/json' \
    -d '{
      "name": "notification_channel_1",
      "config": {
        "name": "Webhook channel 1",
        "type": "slack",
        "is_enabled": true
      }
    }' > /dev/null
fi

if [[ $NOTIFICATION_CHANNELS != *"notification_channel_2"* ]]; then
  log "Creating notification channel 2"
  curl -s -X POST "$OPENSEARCH_URL/_plugins/_notifications/configs" \
    -H 'Content-Type: application/json' \
    -d '{
      "name": "notification_channel_2",
      "config": {
        "name": "Webhook channel 2",
        "type": "slack",
        "is_enabled": true
      }
    }' > /dev/null
fi

# Get existing monitors from OpenSearch
log "Fetching existing monitors from OpenSearch"
EXISTING_MONITORS=$(curl -s "$OPENSEARCH_URL$ALERTING_API")

# Parse the JSON config file
MONITORS=$(cat "$CONFIG_FILE" | jq -c '.Monitors[]')

# Process each monitor
echo "$MONITORS" | while read -r MONITOR; do
  # Extract monitor details
  MONITOR_NAME=$(echo $MONITOR | jq -r '.Monitor_Name')
  DISPLAY_INDEX=$(echo $MONITOR | jq -r '.Index')
  
  # Map display index to actual index (lowercase)
  case $DISPLAY_INDEX in
    "Index_A") ACTUAL_INDEX="index_a" ;;
    "Index_B") ACTUAL_INDEX="index_b" ;;
    "Index_C") ACTUAL_INDEX="index_c" ;;
    *) ACTUAL_INDEX=$(echo $DISPLAY_INDEX | tr '[:upper:]' '[:lower:]') ;;
  esac
  
  TEXT=$(echo $MONITOR | jq -r '.Text2Scan_in_Message')
  TIME=$(echo $MONITOR | jq -r '.Time2Scan')
  CHANNEL=$(echo $MONITOR | jq -r '.notificantion_channel')
  
  log "Processing monitor: $MONITOR_NAME (index: $DISPLAY_INDEX -> $ACTUAL_INDEX)"
  
  # Check if monitor already exists
  MONITOR_ID=$(echo "$EXISTING_MONITORS" | jq -r --arg name "$MONITOR_NAME" '.monitors[] | select(.name == $name) | ._id' 2>/dev/null)
  
  # Build the monitor configuration JSON
  MONITOR_CONFIG=$(cat <<EOF
{
  "name": "$MONITOR_NAME",
  "type": "monitor",
  "enabled": true,
  "schedule": {
    "period": {
      "interval": 1,
      "unit": "MINUTES"
    }
  },
  "inputs": [
    {
      "search": {
        "indices": ["$ACTUAL_INDEX"],
        "query": {
          "size": 0,
          "query": {
            "bool": {
              "must": [
                {
                  "range": {
                    "@timestamp": {
                      "gte": "now-$TIME",
                      "lte": "now"
                    }
                  }
                },
                {
                  "match": {
                    "message": "$TEXT"
                  }
                }
              ]
            }
          }
        }
      }
    }
  ],
  "triggers": [
    {
      "name": "Found $TEXT in $DISPLAY_INDEX",
      "severity": "1",
      "condition": {
        "script": {
          "source": "ctx.results[0].hits.total.value > 0",
          "lang": "painless"
        }
      },
      "actions": [
        {
          "name": "Notify",
          "destination_id": "$CHANNEL",
          "message_template": {
            "source": "Monitor {{ctx.monitor.name}} detected {{ctx.results[0].hits.total.value}} instances of '$TEXT' in $DISPLAY_INDEX index in the last $TIME.",
            "lang": "mustache"
          },
          "throttle_enabled": true,
          "throttle": {
            "value": 10,
            "unit": "MINUTES"
          }
        }
      ]
    }
  ]
}
EOF
)
  
  # Create or update the monitor
  if [ -z "$MONITOR_ID" ]; then
    # Create new monitor
    log "Creating new monitor: $MONITOR_NAME"
    RESPONSE=$(curl -s -X POST "$OPENSEARCH_URL$ALERTING_API" \
      -H 'Content-Type: application/json' \
      -d "$MONITOR_CONFIG")
    
    if [[ $RESPONSE == *"error"* ]]; then
      log "Error creating monitor: $RESPONSE"
    else
      log "Successfully created monitor: $MONITOR_NAME"
    fi
  else
    # Update existing monitor
    log "Updating existing monitor: $MONITOR_NAME (ID: $MONITOR_ID)"
    RESPONSE=$(curl -s -X PUT "$OPENSEARCH_URL$ALERTING_API/$MONITOR_ID" \
      -H 'Content-Type: application/json' \
      -d "$MONITOR_CONFIG")
    
    if [[ $RESPONSE == *"error"* ]]; then
      log "Error updating monitor: $RESPONSE"
    else
      log "Successfully updated monitor: $MONITOR_NAME"
    fi
  fi
done

log "Monitor update process completed"