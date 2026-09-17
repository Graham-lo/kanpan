# The market fallback host (the standby gateway) serves open interest and
# nothing else: no accounts, no database, no secrets. `install.py` is for the
# host that holds people's data; this one only needs the binary and a cache.
import pathlib,subprocess
unit='''[Unit]
Description=Kanpan open interest for the market fallback host
After=network-online.target
[Service]
DynamicUser=yes
WorkingDirectory=/opt/kanpan-api
Environment=KANPAN_BIND=127.0.0.1:8794
Environment=KANPAN_OI_CACHE=/var/cache/kanpan-api/oi
Environment=RUST_LOG=warn
ExecStart=/opt/kanpan-api/target/release/kanpan-api metrics
Restart=on-failure
RestartSec=3
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
CacheDirectory=kanpan-api
MemoryMax=512M
CPUQuota=150%
TasksMax=128
[Install]
WantedBy=multi-user.target
'''
pathlib.Path('/etc/systemd/system/kanpan-metrics.service').write_text(unit)
subprocess.run(['systemctl','daemon-reload'],check=True)
subprocess.run(['systemctl','enable','--now','kanpan-metrics'],check=True)
