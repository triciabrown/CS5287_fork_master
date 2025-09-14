# Screenshots Guide for CA0 Assignment

## 📸 Required Screenshots Checklist

### AWS Infrastructure Screenshots
- [ ] `aws-vpc-dashboard.png` - AWS Console → VPC → Your VPCs (showing complete network)
- [ ] `ec2-instances-running.png` - AWS Console → EC2 → Instances (all 4 VMs running)
- [ ] `security-groups-config.png` - AWS Console → EC2 → Security Groups (showing rules)

### Application Service Screenshots
- [ ] `docker-services-status.png` - Terminal showing `docker ps` on all VMs
- [ ] `kafka-topics-messages.png` - Kafka console consumer showing live messages
- [ ] `mongodb-sensor-data.png` - MongoDB query results with sensor data

### Home Assistant Screenshots  
- [ ] `homeassistant-dashboard.png` - Home Assistant web interface with plant sensors
- [ ] `mqtt-auto-discovery.png` - MQTT integration page showing discovered sensors
- [ ] `plant-health-alerts.png` - Plant status cards showing health and alerts

### Pipeline Verification Screenshots
- [ ] `pipeline-data-flow.png` - Multiple terminals showing data flow
- [ ] `system-performance.png` - System monitoring (htop, docker stats)

## 🖥️ How to Capture Screenshots

### Windows Screenshot Methods

1. **Snipping Tool (Recommended)**:
   ```
   Windows Key + Shift + S
   → Select area
   → Paste into Paint/image editor
   → Save as PNG to CA0/screenshots/ folder
   ```

2. **Full Screen**:
   ```
   PrtScn key → Paste into Paint → Save as PNG
   ```

3. **Active Window**:
   ```
   Alt + PrtScn → Paste into Paint → Save as PNG
   ```

### Screenshot Quality Guidelines

- **Format**: Save as PNG (better quality than JPG for screenshots)
- **Resolution**: Minimum 1280x720, prefer 1920x1080
- **Content**: Show full context (entire browser window, not just small sections)
- **Timing**: Capture during active operation (live data, not empty screens)
- **Clarity**: Ensure text is readable when viewing in GitHub

### Specific Capture Instructions

#### AWS Console Screenshots
1. **VPC Dashboard**: AWS Console → VPC → Your VPCs → Select your VPC → Show all resources
2. **EC2 Instances**: AWS Console → EC2 → Instances → Show all 4 VMs with status
3. **Security Groups**: AWS Console → EC2 → Security Groups → Select each group, show inbound rules

#### Application Screenshots
1. **Docker Status**: SSH to each VM, run `docker ps`, capture terminal
2. **Kafka Messages**: On VM-1, run Kafka consumer, show live plant-sensor messages
3. **MongoDB Data**: On VM-2, connect to MongoDB, query sensor_readings collection

#### Home Assistant Screenshots
1. **Dashboard**: Browse to VM-4 public IP:8123, show overview with plant sensors
2. **MQTT Integration**: Settings → Devices & Services → MQTT → Show discovered sensors
3. **Plant Cards**: Main dashboard showing plant health cards with live data

### Adding Screenshots to Git

```bash
# Add all screenshots to git
cd CA0/screenshots
git add *.png
git commit -m "Add CA0 assignment screenshots"
git push origin master
```

## 🔍 Verification

After adding screenshots, verify they display correctly:

1. **Check local README**: Open CA0/README.md in VS Code preview
2. **Check GitHub**: Push to repository and view on GitHub
3. **Test all links**: Ensure all screenshot references work
4. **Mobile friendly**: Check display on different screen sizes

## 📝 Image Optimization (Optional)

If images are too large (>1MB each):

1. **Use online compressor**: TinyPNG.com or similar
2. **Reduce resolution**: 1280x720 is sufficient for most screenshots
3. **Crop unnecessary areas**: Focus on relevant content only

## 🚀 Pro Tips

- **Take screenshots during peak operation** (when sensors are sending data)
- **Include timestamps** in terminal screenshots to show real-time activity
- **Show multiple services together** in split-screen terminal windows
- **Capture both success states and error handling** if relevant
- **Use descriptive commit messages** when adding images to git
