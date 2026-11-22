import subprocess,sys
from pathlib import Path
base=Path('01_Project/build/TransferHistoryRun08')
objects=[str(p) for p in (base/'Build/Intermediates.noindex/QuickStatsPanel.build/Debug/QuickStatsPanel.build/Objects-normal/arm64').glob('*.o') if p.name!='QuickStatsPanelApp.o']
cmd=['xcrun','swiftc','-parse-as-library','-module-cache-path','/tmp/qsp-e1-run08/ModuleCache','-target','arm64-apple-macos15.0','-I',str(base/'Build/Products/Debug'),'/tmp/qsp-e1-run08/graph.swift',*objects,'-framework','AppKit','-framework','SwiftUI','-framework','IOKit','-lIOReport','-o','/tmp/qsp-e1-run08/QSPGraphProbeRun08']
r=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
print(r.stdout[-5000:])
raise SystemExit(r.returncode)
