#!/usr/bin/env python3
"""Refresh the deployable PWA from audited native content. No third-party dependencies."""
import hashlib, json, shutil
from pathlib import Path
root=Path(__file__).resolve().parents[1]
out=root/'PWA'
for name in ['guide.json','data.json']:
    shutil.copy2(root/'CFWGuide/Resources'/name,out/name)
shutil.copytree(root/'CFWGuide/Resources/SiteAssets/assets',out/'assets',dirs_exist_ok=True)
files=sorted(str(p.relative_to(out)) for p in out.rglob('*') if p.is_file() and p.name not in ['sw.js','precache.json','_headers','_redirects'])
version=hashlib.sha256(b''.join((out/p).read_bytes() for p in files)).hexdigest()[:16]
(out/'precache.json').write_text(json.dumps(files))
template=(root/'scripts/pwa-service-worker.js').read_text()
(out/'sw.js').write_text(template.replace('__VERSION__',version))
print(f'PWA ready: {len(files)} offline resources, version {version}')
