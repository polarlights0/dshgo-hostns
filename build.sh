#!/bin/bash
# 打包成 Magisk 可安装的 zip：bash build.sh [输出路径]
set -e
cd "$(dirname "$0")"
VER=$(sed -n 's/^version=//p' module.prop)
OUT=${1:-dist/dshgo_rootd-$VER.zip}
mkdir -p "$(dirname "$OUT")"
chmod 755 service.sh action.sh uninstall.sh bin/* 2>/dev/null
chmod 644 module.prop config.sh README.md 2>/dev/null
rm -f "$OUT"
python3 - "$OUT" <<'PY'
import sys, zipfile, os
out = sys.argv[1]
base = os.getcwd()
include = ['module.prop', 'config.sh', 'service.sh', 'action.sh', 'uninstall.sh', 'bin']
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for item in include:
        paths = [item] if os.path.isfile(item) else sorted(
            os.path.join(d, f) for d, _, fs in os.walk(item) for f in fs)
        for p in paths:
            zi = zipfile.ZipInfo(p)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = (os.stat(p).st_mode & 0xFFFF) << 16
            zi.create_system = 3
            z.writestr(zi, open(p, 'rb').read())
print(out, os.path.getsize(out), 'bytes')
PY
