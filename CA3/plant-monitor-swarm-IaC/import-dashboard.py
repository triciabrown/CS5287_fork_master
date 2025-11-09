#!/usr/bin/env python3
"""
Grafana Dashboard Import Script
Fixes datasource references and imports the CA3 Plant Monitoring Dashboard
"""

import json
import requests
import sys
from pathlib import Path

# Configuration
MANAGER_IP = "18.219.157.100"
GRAFANA_URL = f"http://{MANAGER_IP}:3000"
GRAFANA_USER = "admin"
GRAFANA_PASS = "admin"
DASHBOARD_FILE = "configs/grafana-plant-monitoring-dashboard.json"

def check_grafana():
    """Check if Grafana is accessible"""
    print("🔍 Checking Grafana accessibility...")
    try:
        response = requests.get(f"{GRAFANA_URL}/api/health", timeout=5)
        if response.status_code == 200:
            print(f"✅ Grafana is accessible at {GRAFANA_URL}")
            return True
        else:
            print(f"❌ Grafana returned status code: {response.status_code}")
            return False
    except requests.exceptions.RequestException as e:
        print(f"❌ Cannot connect to Grafana: {e}")
        return False

def get_prometheus_datasource():
    """Get or create Prometheus datasource"""
    print("\n🔍 Looking for Prometheus datasource...")
    try:
        response = requests.get(
            f"{GRAFANA_URL}/api/datasources",
            auth=(GRAFANA_USER, GRAFANA_PASS),
            timeout=5
        )
        
        if response.status_code == 200:
            datasources = response.json()
            for ds in datasources:
                if ds.get('type') == 'prometheus':
                    print(f"✅ Found Prometheus datasource: {ds['name']} (UID: {ds['uid']})")
                    return ds['uid']
            
            # Create if not found
            print("⚠️  Prometheus datasource not found. Creating...")
            create_response = requests.post(
                f"{GRAFANA_URL}/api/datasources",
                auth=(GRAFANA_USER, GRAFANA_PASS),
                json={
                    "name": "Prometheus",
                    "type": "prometheus",
                    "url": "http://prometheus:9090",
                    "access": "proxy",
                    "isDefault": True,
                    "jsonData": {
                        "timeInterval": "5s"
                    }
                },
                timeout=5
            )
            
            if create_response.status_code in [200, 201]:
                ds_data = create_response.json()
                uid = ds_data.get('datasource', {}).get('uid') or ds_data.get('uid')
                print(f"✅ Created Prometheus datasource (UID: {uid})")
                return uid
            else:
                print(f"❌ Failed to create datasource: {create_response.text}")
                return None
        else:
            print(f"❌ Failed to get datasources: {response.text}")
            return None
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Error accessing Grafana API: {e}")
        return None

def fix_dashboard_datasources(dashboard, prometheus_uid):
    """Add datasource references to all panel targets"""
    print("\n🔧 Fixing dashboard datasource references...")
    
    if 'dashboard' not in dashboard:
        print("❌ Invalid dashboard format: missing 'dashboard' key")
        return None
    
    dash = dashboard['dashboard']
    
    # Add datasource to each panel's targets
    if 'panels' in dash:
        for panel in dash['panels']:
            if 'targets' in panel:
                for target in panel['targets']:
                    target['datasource'] = {
                        "type": "prometheus",
                        "uid": prometheus_uid
                    }
        print(f"✅ Updated datasource references in {len(dash['panels'])} panels")
    
    return dashboard

def import_dashboard(dashboard_data):
    """Import dashboard to Grafana"""
    print("\n📤 Importing dashboard to Grafana...")
    try:
        response = requests.post(
            f"{GRAFANA_URL}/api/dashboards/db",
            auth=(GRAFANA_USER, GRAFANA_PASS),
            json=dashboard_data,
            timeout=10
        )
        
        if response.status_code in [200, 201]:
            result = response.json()
            dashboard_uid = result.get('uid')
            dashboard_url = f"{GRAFANA_URL}/d/{dashboard_uid}"
            print(f"✅ Dashboard imported successfully!")
            print(f"\n{'='*60}")
            print(f"🎉 SUCCESS! Dashboard is ready")
            print(f"{'='*60}")
            print(f"\n🌐 Access URL: {dashboard_url}")
            print(f"🔑 Login: {GRAFANA_USER} / {GRAFANA_PASS}")
            print(f"\n📊 The dashboard has 11 panels showing:")
            print(f"   • Sensor data rate (readings/sec)")
            print(f"   • Kafka consumer lag")
            print(f"   • Database insert rate")
            print(f"   • Processing throughput")
            print(f"   • Latency percentiles (P50, P95, P99)")
            print(f"   • Health scores")
            print(f"   • System resource usage")
            print(f"   • And more...")
            print(f"\n⏳ Wait 30 seconds for data to populate if panels are empty")
            print()
            return True
        else:
            print(f"❌ Failed to import dashboard: {response.text}")
            return False
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Error importing dashboard: {e}")
        return False

def main():
    print("="*60)
    print("  CA3 Grafana Dashboard Import Tool")
    print("="*60)
    print()
    
    # Check if dashboard file exists
    dashboard_path = Path(DASHBOARD_FILE)
    if not dashboard_path.exists():
        print(f"❌ Dashboard file not found: {DASHBOARD_FILE}")
        print(f"   Current directory: {Path.cwd()}")
        sys.exit(1)
    
    # Load dashboard JSON
    print(f"📄 Loading dashboard from: {DASHBOARD_FILE}")
    try:
        with open(dashboard_path, 'r') as f:
            dashboard_data = json.load(f)
        print(f"✅ Dashboard loaded successfully")
    except json.JSONDecodeError as e:
        print(f"❌ Invalid JSON in dashboard file: {e}")
        sys.exit(1)
    
    # Check Grafana
    if not check_grafana():
        print("\n❌ Cannot proceed: Grafana is not accessible")
        print("   Please verify the service is running:")
        print(f"   ssh -i ~/.ssh/docker-swarm-key ubuntu@{MANAGER_IP} 'docker service ls | grep grafana'")
        sys.exit(1)
    
    # Get Prometheus datasource
    prometheus_uid = get_prometheus_datasource()
    if not prometheus_uid:
        print("\n❌ Cannot proceed without Prometheus datasource")
        sys.exit(1)
    
    # Fix datasource references
    fixed_dashboard = fix_dashboard_datasources(dashboard_data, prometheus_uid)
    if not fixed_dashboard:
        sys.exit(1)
    
    # Import dashboard
    if import_dashboard(fixed_dashboard):
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
