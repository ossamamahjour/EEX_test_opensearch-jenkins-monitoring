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
    app.run(host='0.0.0.0', port=5000)