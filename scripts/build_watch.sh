#!/usr/bin/env bash
# Builds the Garmin Connect IQ watch app in Garmin/.
#
#   scripts/build_watch.sh            sideloadable .prg for the default device (fr265)
#   scripts/build_watch.sh fenix7     .prg for another device id (see Garmin/manifest.xml)
#   scripts/build_watch.sh store      .iq package with every device, for the Connect IQ Store
#
# Needs `monkeyc` on PATH, the device files for the target (Garmin SDK Manager), and a developer key:
#   openssl genrsa -out developer_key.pem 4096
#   openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
# Point CIQ_DEVELOPER_KEY at the .der file (default ~/.connectiq/developer_key.der). Never commit it: the store
# only accepts updates signed with the same key.
set -euo pipefail

cd "$(dirname "$0")/../Garmin"
target="${1:-fr265}"
key="${CIQ_DEVELOPER_KEY:-$HOME/.connectiq/developer_key.der}"
mkdir -p build

if [[ "$target" == "store" ]]; then
    monkeyc -f monkey.jungle -e -r -w -y "$key" -o build/StridePlan.iq
    echo "Built Garmin/build/StridePlan.iq"
else
    monkeyc -f monkey.jungle -d "$target" -w -y "$key" -o "build/StridePlan-$target.prg"
    echo "Built Garmin/build/StridePlan-$target.prg"
fi
