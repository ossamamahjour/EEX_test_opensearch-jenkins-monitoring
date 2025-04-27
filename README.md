# OpenSearch Monitor Automation Solution

## Overview

This project provides a complete solution for managing OpenSearch monitors through a simple web interface and automated Jenkins jobs. It allows business users to easily create, update, and delete monitors with minimal effort by updating a single JSON file through a user-friendly interface.

## Architecture

The solution consists of four main components running in Docker containers:

1. **OpenSearch** - The core search and analytics engine with three indexes (index_a, index_b, index_c)
2. **OpenSearch Dashboards** - Web UI for OpenSearch, providing visualization and monitoring capabilities
3. **Jenkins** - Automation server for scheduling and running the monitor update job
4. **Monitor UI** - Custom web interface for business users to manage monitor configurations

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│                      OPENSEARCH MONITOR AUTOMATION                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│                         DOCKER CONTAINER ENVIRONMENT                    │
│                                                                         │
├─────────────────┬─────────────────┬─────────────────┬─────────────────┤
│                 │                 │                 │                 │
│   ┌─────────┐   │   ┌─────────┐   │   ┌─────────┐   │   ┌─────────┐   │
│   │         │   │   │         │   │   │         │   │   │         │   │
│   │ MONITOR │   │   │ JENKINS │   │   │OPENSEARCH│   │   │OPENSEARCH│   │
│   │   UI    │◄──┼───┤         │   │   │         │   │   │DASHBOARDS│   │
│   │PORT:5000│   │   │PORT:8080│   │   │PORT:9200│   │   │PORT:5601 │   │
│   │         │   │   │         │   │   │         │   │   │         │   │
│   └────┬────┘   │   └────┬────┘   │   └────┬────┘   │   └────┬────┘   │
│        │        │        │        │        │        │        │        │
└────────┼────────┴────────┼────────┴────────┼────────┴────────┼────────┘
         │                 │                 │                 │
         │                 │                 │                 │
         ▼                 │                 │                 ▼
┌────────────────┐         │                 │         ┌────────────────┐
│                │         │                 │         │                │
│  Business User │         │                 │         │ IT/Operations  │
│   Interface    │         │                 │         │    Interface   │
│                │         │                 │         │                │
└────────┬───────┘         │                 │         └────────────────┘
         │                 │                 │
         │                 │                 │
         │     ┌───────────▼─────────┐       │
         │     │                     │       │
         └────►│       Monitors      │◄──────┘
               │    Configuration    │
               │    (JSON File)      │
               │                     │
               └─────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│                           DATA & WORKFLOW                               │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. Business users manage monitors through the web UI (port 5000)       │
│                                                                         │
│  2. Changes are saved to the monitors.json configuration file           │
│                                                                         │
│  3. "Trigger Job Now" button or scheduled Jenkins job applies changes   │
│                                                                         │
│  4. Jenkins executes the update_monitors.sh script                      │
│                                                                         │
│  5. Script creates/updates monitors in OpenSearch via API               │
│                                                                         │
│  6. OpenSearch processes monitors, checking indexes for matching data   │
│                                                                         │
│  7. Alerts are triggered based on monitor conditions                    │
│                                                                         │
│  8. Results can be viewed in OpenSearch Dashboards                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

All components communicate via a shared Docker network, and persistent data is stored in Docker volumes.

## Prerequisites

- Ubuntu running on Windows via WSL
- Docker and Docker Compose
- Web browser

## Step-by-Step Setup Instructions

### 1. Set Up Docker in Ubuntu WSL

```bash
# Update package lists
sudo apt update

# Install prerequisites
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

# Add Docker repository
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Install Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Add your user to docker group (to run Docker without sudo)
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.15.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Apply group changes to current shell session
newgrp docker

# Start Docker service
sudo service docker start
```

### 2. Create Project Structure

```bash
# Create project directory
mkdir -p ~/opensearch-test
cd ~/opensearch-test

# Create directories for our components
mkdir -p monitor-ui/templates config
```

### 3. Create Docker Compose Configuration

```bash
cat > docker-compose.yml << 'EOF'
version: '3'
services:
  opensearch:
    image: opensearchproject/opensearch:2.5.0
    container_name: opensearch
    environment:
      - discovery.type=single-node
      - bootstrap.memory_lock=true
      - "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m"
      - "DISABLE_SECURITY_PLUGIN=true"
      - "DISABLE_INSTALL_DEMO_CONFIG=true"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - opensearch-data:/usr/share/opensearch/data
    ports:
      - 9200:9200
      - 9600:9600
    networks:
      - opensearch-net

  opensearch-dashboards:
    image: opensearchproject/opensearch-dashboards:2.5.0
    container_name: opensearch-dashboards
    ports:
      - 5601:5601
    environment:
      - 'OPENSEARCH_HOSTS=["http://opensearch:9200"]'
      - "DISABLE_SECURITY_DASHBOARDS_PLUGIN=true"
    networks:
      - opensearch-net
    depends_on:
      - opensearch

  jenkins:
    image: jenkins/jenkins:lts
    container_name: jenkins
    user: root
    ports:
      - 8080:8080
      - 50000:50000
    volumes:
      - jenkins-data:/var/jenkins_home
      - ./config:/config
    networks:
      - opensearch-net

  monitor-ui:
    build:
      context: ./monitor-ui
    container_name: monitor-ui
    volumes:
      - ./monitor-ui:/app
      - ./config:/config
    ports:
      - 5000:5000
    networks:
      - opensearch-net
    depends_on:
      - opensearch
      - jenkins

networks:
  opensearch-net:
    driver: bridge

volumes:
  opensearch-data:
  jenkins-data:
EOF
```

### 4. Create Monitor UI Files

Create the Dockerfile for the Monitor UI:

```bash
cat > monitor-ui/Dockerfile << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# Install curl and jq for debugging
RUN apt-get update && apt-get install -y curl jq

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000

CMD ["python", "app.py"]
EOF
```

Create the requirements.txt file:

```bash
cat > monitor-ui/requirements.txt << 'EOF'
flask==2.0.1
werkzeug==2.0.3
requests==2.26.0
EOF
```

Create the app.py file:

```bash
cat > monitor-ui/app.py << 'EOF'
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify
import json
import os
import requests
import time
import logging

app = Flask(__name__)
app.secret_key = "opensearch-monitor-automation"

# Add enumerate to Jinja2 globals
app.jinja_env.globals.update(enumerate=enumerate)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
CONFIG_PATH = "/config/monitors.json"
OPENSEARCH_URL = "http://opensearch:9200"
JENKINS_URL = "http://jenkins:8080"

# Define index mapping between display names and actual index names
INDEX_MAPPING = {
    "Index_A": "index_a",
    "Index_B": "index_b",
    "Index_C": "index_c"
}

def load_config():
    # Create default config if it doesn't exist
    if not os.path.exists(CONFIG_PATH):
        default_config = {
            "Monitors": [
                {
                    "Monitor_Name": "Index A check for error",
                    "Index": "Index_A",
                    "Text2Scan_in_Message": "error",
                    "Time2Scan": "5m",
                    "notificantion_channel": "notification_channel_1"
                },
                {
                    "Monitor_Name": "Index B check for error",
                    "Index": "Index_B",
                    "Text2Scan_in_Message": "error",
                    "Time2Scan": "5m",
                    "notificantion_channel": "notification_channel_2"
                }
            ]
        }
        with open(CONFIG_PATH, 'w') as f:
            json.dump(default_config, f, indent=2)
    
    with open(CONFIG_PATH, 'r') as f:
        return json.load(f)

def save_config(config):
    with open(CONFIG_PATH, 'w') as f:
        json.dump(config, f, indent=2)

@app.route('/')
def index():
    config = load_config()
    
    # Check if OpenSearch is up
    opensearch_status = "Unknown"
    try:
        response = requests.get(f"{OPENSEARCH_URL}", timeout=2)
        if response.status_code == 200:
            opensearch_status = "Running"
    except Exception as e:
        opensearch_status = f"Error: {str(e)}"
    
    # Check if indexes exist
    index_status = {}
    
    if opensearch_status == "Running":
        for display_name, actual_name in INDEX_MAPPING.items():
            try:
                response = requests.head(f"{OPENSEARCH_URL}/{actual_name}", timeout=2)
                index_status[display_name] = "Exists" if response.status_code == 200 else "Not found"
            except Exception as e:
                index_status[display_name] = f"Error: {str(e)}"
    
    return render_template('index.html', 
                          monitors=config['Monitors'], 
                          opensearch_status=opensearch_status,
                          index_status=index_status)

@app.route('/add', methods=['GET', 'POST'])
def add_monitor():
    if request.method == 'POST':
        # Get form data
        monitor = {
            "Monitor_Name": request.form.get('name'),
            "Index": request.form.get('index'),
            "Text2Scan_in_Message": request.form.get('text'),
            "Time2Scan": request.form.get('time'),
            "notificantion_channel": request.form.get('channel')
        }
        
        # Load and update config
        config = load_config()
        config['Monitors'].append(monitor)
        save_config(config)
        
        flash('Monitor added successfully')
        return redirect(url_for('index'))
    
    return render_template('add.html')

@app.route('/edit/<int:index>', methods=['GET', 'POST'])
def edit_monitor(index):
    config = load_config()
    
    if request.method == 'POST':
        config['Monitors'][index] = {
            "Monitor_Name": request.form.get('name'),
            "Index": request.form.get('index'),
            "Text2Scan_in_Message": request.form.get('text'),
            "Time2Scan": request.form.get('time'),
            "notificantion_channel": request.form.get('channel')
        }
        
        save_config(config)
        flash('Monitor updated successfully')
        return redirect(url_for('index'))
    
    return render_template('edit.html', monitor=config['Monitors'][index], index=index)

@app.route('/delete/<int:index>')
def delete_monitor(index):
    config = load_config()
    del config['Monitors'][index]
    save_config(config)
    
    flash('Monitor deleted successfully')
    return redirect(url_for('index'))

@app.route('/setup-indexes')
def setup_indexes():
    """Create the three required indexes if they don't exist"""
    results = []
    
    # Wait for OpenSearch to be ready
    max_retries = 5
    retry_count = 0
    
    while retry_count < max_retries:
        try:
            response = requests.get(OPENSEARCH_URL)
            if response.status_code == 200:
                break
        except:
            pass
        
        logger.info(f"Waiting for OpenSearch to be ready (attempt {retry_count+1}/{max_retries})...")
        time.sleep(5)
        retry_count += 1
    
    if retry_count == max_retries:
        return jsonify({"results": ["Error: OpenSearch is not available after multiple attempts"]})
    
    # Create indexes (using lowercase names)
    for display_name, actual_name in INDEX_MAPPING.items():
        try:
            response = requests.put(f"{OPENSEARCH_URL}/{actual_name}", json={
                "settings": {
                    "number_of_shards": 1,
                    "number_of_replicas": 0
                }
            })
            
            if response.status_code in [200, 201]:
                results.append(f"Created or confirmed index {display_name} (using {actual_name})")
            else:
                results.append(f"Failed to create index {display_name}: {response.text}")
        except Exception as e:
            results.append(f"Error creating index {display_name}: {str(e)}")
    
    return jsonify({"results": results})

@app.route('/trigger-job')
def trigger_job():
    """Trigger the update_monitors.sh script directly"""
    try:
        os.system("bash /config/update_monitors.sh")
        return jsonify({"status": "Job triggered successfully"})
    except Exception as e:
        return jsonify({"status": f"Error: {str(e)}"})

if __name__ == '__main__':
    # Create templates
    if not os.path.exists('templates/index.html'):
        with open('templates/index.html', 'w') as f:
            f.write('''
<!DOCTYPE html>
<html>
<head>
    <title>OpenSearch Monitor Configuration</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .button { padding: 8px 16px; margin-right: 5px; text-decoration: none; background-color: #4CAF50; color: white; border-radius: 4px; }
        .delete { background-color: #f44336; }
        .blue { background-color: #2196F3; }
        .message { padding: 10px; margin-bottom: 20px; background-color: #dff0d8; border-color: #d6e9c6; color: #3c763d; }
        .status { margin-bottom: 20px; }
        .status-item { margin-bottom: 5px; }
        .status-good { color: green; }
        .status-bad { color: red; }
    </style>
    <script>
        function setupIndexes() {
            fetch('/setup-indexes')
                .then(response => response.json())
                .then(data => {
                    alert(data.results.join('\\n'));
                    window.location.reload();
                });
        }
        
        function triggerJob() {
            fetch('/trigger-job')
                .then(response => response.json())
                .then(data => {
                    alert(data.status);
                });
        }
    </script>
</head>
<body>
    <h1>OpenSearch Monitor Configuration</h1>
    
    {% with messages = get_flashed_messages() %}
        {% if messages %}
            {% for message in messages %}
                <div class="message">{{ message }}</div>
            {% endfor %}
        {% endif %}
    {% endwith %}
    
    <div class="status">
        <h2>System Status</h2>
        <div class="status-item">
            OpenSearch: <span class="{{ 'status-good' if opensearch_status == 'Running' else 'status-bad' }}">{{ opensearch_status }}</span>
        </div>
        
        <h3>Index Status</h3>
        {% for idx, status in index_status.items() %}
        <div class="status-item">
            {{ idx }}: <span class="{{ 'status-good' if status == 'Exists' else 'status-bad' }}">{{ status }}</span>
        </div>
        {% endfor %}
    </div>
    
    <div style="margin-bottom: 20px;">
        <a href="{{ url_for('add_monitor') }}" class="button">Add New Monitor</a>
        <button onclick="setupIndexes()" class="button blue">Setup Indexes</button>
        <button onclick="triggerJob()" class="button blue">Trigger Job Now</button>
    </div>
    
    <p>The automated job will run each night to apply these configurations.</p>
    
    <h2>Current Monitors</h2>
    <table>
        <thead>
            <tr>
                <th>Name</th>
                <th>Index</th>
                <th>Text to Scan</th>
                <th>Time Window</th>
                <th>Notification Channel</th>
                <th>Actions</th>
            </tr>
        </thead>
        <tbody>
            {% for i, monitor in enumerate(monitors) %}
            <tr>
                <td>{{ monitor.Monitor_Name }}</td>
                <td>{{ monitor.Index }}</td>
                <td>{{ monitor.Text2Scan_in_Message }}</td>
                <td>{{ monitor.Time2Scan }}</td>
                <td>{{ monitor.notificantion_channel }}</td>
                <td>
                    <a href="{{ url_for('edit_monitor', index=i) }}" class="button">Edit</a>
                    <a href="{{ url_for('delete_monitor', index=i) }}" class="button delete" onclick="return confirm('Are you sure?')">Delete</a>
                </td>
            </tr>
            {% endfor %}
        </tbody>
    </table>
</body>
</html>
            ''')
    
    if not os.path.exists('templates/add.html'):
        with open('templates/add.html', 'w') as f:
            f.write('''
<!DOCTYPE html>
<html>
<head>
    <title>Add Monitor</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .form-group { margin-bottom: 15px; }
        label { display: block; margin-bottom: 5px; }
        input[type="text"] { width: 300px; padding: 8px; }
        .button { padding: 8px 16px; text-decoration: none; background-color: #4CAF50; color: white; border-radius: 4px; border: none; cursor: pointer; }
        .cancel { background-color: #f44336; }
    </style>
</head>
<body>
    <h1>Add New Monitor</h1>
    
    <form method="post">
        <div class="form-group">
            <label for="name">Monitor Name:</label>
            <input type="text" id="name" name="name" required>
        </div>
        
        <div class="form-group">
            <label for="index">Index:</label>
            <input type="text" id="index" name="index" required>
        </div>
        
        <div class="form-group">
            <label for="text">Text to Scan:</label>
            <input type="text" id="text" name="text" required>
        </div>
        
        <div class="form-group">
            <label for="time">Time Window (e.g., 5m, 1h):</label>
            <input type="text" id="time" name="time" required>
        </div>
        
        <div class="form-group">
            <label for="channel">Notification Channel:</label>
            <input type="text" id="channel" name="channel" required>
        </div>
        
        <button type="submit" class="button">Add Monitor</button>
        <a href="{{ url_for('index') }}" class="button cancel">Cancel</a>
    </form>
</body>
</html>
            ''')
    
    if not os.path.exists('templates/edit.html'):
        with open('templates/edit.html', 'w') as f:
            f.write('''
<!DOCTYPE html>
<html>
<head>
    <title>Edit Monitor</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .form-group { margin-bottom: 15px; }
        label { display: block; margin-bottom: 5px; }
        input[type="text"] { width: 300px; padding: 8px; }
        .button { padding: 8px 16px; text-decoration: none; background-color: #4CAF50; color: white; border-radius: 4px; border: none; cursor: pointer; }
        .cancel { background-color: #f44336; }
    </style>
</head>
<body>
    <h1>Edit Monitor</h1>
    
    <form method="post">
        <div class="form-group">
            <label for="name">Monitor Name:</label>
            <input type="text" id="name" name="name" value="{{ monitor.Monitor_Name }}" required>
        </div>
        
        <div class="form-group">
            <label for="index">Index:</label>
            <input type="text" id="index" name="index" value="{{ monitor.Index }}" required>
        </div>
        
        <div class="form-group">
            <label for="text">Text to Scan:</label>
            <input type="text" id="text" name="text" value="{{ monitor.Text2Scan_in_Message }}" required>
        </div>
        
        <div class="form-group">
            <label for="time">Time Window (e.g., 5m, 1h):</label>
            <input type="text" id="time" name="time" value="{{ monitor.Time2Scan }}" required>
        </div>
        
        <div class="form-group">
            <label for="channel">Notification Channel:</label>
            <input type="text" id="channel" name="channel" value="{{ monitor.notificantion_channel }}" required>
        </div>
        
        <button type="submit" class="button">Update Monitor</button>
        <a href="{{ url_for('index') }}" class="button cancel">Cancel</a>
    </form>
</body>
</html>
            ''')
    
    app.run(host='0.0.0.0', port=5000)
EOF
```

### 5. Create the Monitoring Script

```bash
cat > config/update_monitors.sh << 'EOF'
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
EOF

# Make the script executable
chmod +x config/update_monitors.sh
```

### 6. Create Initial Monitors JSON File

```bash
cat > config/monitors.json << 'EOF'
{
  "Monitors": [
    {
      "Monitor_Name": "Index A check for error",
      "Index": "Index_A",
      "Text2Scan_in_Message": "error",
      "Time2Scan": "5m",
      "notificantion_channel": "notification_channel_1"
    },
    {
      "Monitor_Name": "Index B check for error",
      "Index": "Index_B",
      "Text2Scan_in_Message": "error",
      "Time2Scan": "5m",
      "notificantion_channel": "notification_channel_2"
    }
  ]
}
EOF
```

### 7. Build and Start the Environment

```bash
# Build and start the containers
docker-compose up -d

# Wait for services to start (it might take a minute or two)
echo "Waiting for services to start..."
sleep 30
```

### 8. Set Up Jenkins

1. Get the initial admin password:

```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

2. Open Jenkins in your browser: http://localhost:8080
3. Complete the setup wizard:
   - Enter the admin password from the previous step
   - Select "Install suggested plugins"
   - Create an admin user when prompted
   - Use the default Jenkins URL

4. Create a Jenkins job:
   - Click "New Item" in the Jenkins dashboard
   - Enter "OpenSearch-Monitor-Update" for the name and select "Freestyle project"
   - Click "OK"
   - In the "Build Triggers" section, check "Build periodically" and enter `0 0 * * *` (runs at midnight)
   - In the "Build" section, click "Add build step" and select "Execute shell"
   - Enter the following shell command:
   ```
   bash /config/update_monitors.sh
   ```
   - Click "Save"

## Usage

### Testing the Solution

1. Access the Monitor UI at http://localhost:5000
2. Click the "Setup Indexes" button to create the three required OpenSearch indexes
3. View the current monitors from the initial JSON file
4. Try adding a new monitor using the "Add New Monitor" button
5. Trigger the Jenkins job manually by clicking the "Trigger Job Now" button
6. Verify that the monitors have been created in OpenSearch by accessing OpenSearch Dashboards at http://localhost:5601 and navigating to the Alerting section

### For Business Users

1. Access the web interface at http://localhost:5000
2. Add, edit, or delete monitors as needed through the UI
3. Changes are automatically saved to the configuration file
4. The Jenkins job will run nightly at midnight to apply changes to OpenSearch

## Troubleshooting

### Docker Not Running

If you encounter an error like "Cannot connect to the Docker daemon", ensure Docker is running:

```bash
sudo service docker status
sudo service docker start
```

### Flask Application Errors

If the Monitor UI shows an internal server error, check the logs:

```bash
docker logs monitor-ui
```

Common issues and fixes:

1. **'enumerate' is undefined**: Add `app.jinja_env.globals.update(enumerate=enumerate)` to your Flask app
2. **Incompatible Flask/Werkzeug versions**: Use compatible versions in requirements.txt (flask==2.0.1, werkzeug==2.0.3)

### OpenSearch Index Creation Errors

If index creation fails with errors like "invalid_index_name_exception", use lowercase index names:

```bash
# OpenSearch requires lowercase index names
# Use a mapping between display names and actual index names
INDEX_MAPPING = {
    "Index_A": "index_a",
    "Index_B": "index_b",
    "Index_C": "index_c"
}
```

### Monitors Not Appearing in OpenSearch Dashboards

If monitors aren't showing up in OpenSearch Dashboards:

1. Ensure notification channels exist:
   ```bash
   curl http://localhost:9200/_plugins/_notifications/configs
   ```

2. Manually run the update script with verbose output:
   ```bash
   docker exec -it monitor-ui bash -c "bash /config/update_monitors.sh"
   ```

3. Check if the alerting plugin is enabled:
   ```bash
   curl http://localhost:9200/_cat/plugins
   ```

## Assumptions

1. **OpenSearch Setup**: 
   - A single-node OpenSearch cluster is sufficient for this test
   - Security plugins are disabled for simplicity (would be enabled in production)
   - Three indexes (Index_A, Index_B, Index_C) are required as specified

2. **Monitor Configuration**:
   - Monitor configuration is stored in a JSON file with the structure provided in the test
   - Business users require a simple way to edit this configuration
   - The JSON structure remains consistent with the example provided

3. **Notification Channels**:
   - Notification channels are automatically created if they don't exist
   - In a production environment, these would be connected to real notification systems

4. **Automation Requirements**:
   - Jenkins is used for scheduling and running the automation
   - The automation script runs nightly at midnight
   - The automation script handles both creation of new monitors and updates to existing ones

5. **User Interface**:
   - Business users prefer a simple web interface over manually editing JSON files
   - The web interface should provide basic validation and error handling
   - The interface should show the current status of the system

6. **Docker Environment**:
   - Docker is used to simplify deployment and ensure consistency
   - All components can run in containers
   - Volumes are used for persistent storage of data and configurations

7. **Security Considerations**:
   - This is a test environment, so security is minimal
   - In production, we would implement proper authentication, HTTPS, and secure secrets management