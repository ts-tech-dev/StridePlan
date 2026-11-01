#!/usr/bin/env python3
"""Create fresh App Store provisioning profiles via the App Store Connect API (used by CI).

For each bundle ID: registers it if missing, enables the given capabilities, deletes any
previous profile named "<bundle id> AppStore", creates a new IOS_APP_STORE profile containing
all valid distribution certificates, and installs it where Xcode looks for profiles.

Usage: asc_profiles.py KEY_ID ISSUER_ID KEY_PATH BUNDLE_ID[:CAP,CAP] ...
Requires: PyJWT with cryptography (pip install 'pyjwt[crypto]').
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
PROFILE_DIRS = [
    os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles"),
    os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles"),
]


class ASC:
    def __init__(self, key_id, issuer, key_path):
        self.key_id, self.issuer = key_id, issuer
        with open(key_path) as f:
            self.key = f.read()

    def _token(self):
        now = int(time.time())
        return jwt.encode({"iss": self.issuer, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                          self.key, algorithm="ES256", headers={"kid": self.key_id, "typ": "JWT"})

    def call(self, method, path, params=None, body=None):
        url = API + path + ("?" + urllib.parse.urlencode(params) if params else "")
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": "Bearer " + self._token(), "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req) as r:
                raw = r.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            sys.exit(f"::error::App Store Connect API {method} {path} failed ({e.code}): {e.read().decode()}")


def ensure_bundle_id(asc, identifier, caps):
    found = asc.call("GET", "/bundleIds", {"filter[identifier]": identifier, "limit": 200})["data"]
    match = [b for b in found if b["attributes"]["identifier"] == identifier]
    if match:
        bid = match[0]["id"]
    else:
        print(f"Registering bundle ID {identifier}")
        name = identifier.replace(".", " ")
        bid = asc.call("POST", "/bundleIds", body={"data": {"type": "bundleIds", "attributes": {
            "identifier": identifier, "name": name, "platform": "IOS"}}})["data"]["id"]
    have = {c["attributes"]["capabilityType"]
            for c in asc.call("GET", f"/bundleIds/{bid}/bundleIdCapabilities")["data"]}
    for cap in caps:
        if cap not in have:
            print(f"Enabling {cap} on {identifier}")
            asc.call("POST", "/bundleIdCapabilities", body={"data": {
                "type": "bundleIdCapabilities", "attributes": {"capabilityType": cap},
                "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}})
    return bid


def distribution_certs(asc):
    certs = asc.call("GET", "/certificates", {"limit": 200})["data"]
    now = time.strftime("%Y-%m-%dT%H:%M:%S")
    ids = [c["id"] for c in certs
           if c["attributes"]["certificateType"] in ("DISTRIBUTION", "IOS_DISTRIBUTION")
           and c["attributes"].get("expirationDate", "9999")[:19] > now]
    if not ids:
        sys.exit("::error::No valid Apple Distribution certificate on the account")
    return ids


def make_profile(asc, identifier, bid, cert_ids):
    name = f"{identifier} AppStore"
    for p in asc.call("GET", "/profiles", {"filter[name]": name, "limit": 200})["data"]:
        if p["attributes"]["name"] == name:
            asc.call("DELETE", f"/profiles/{p['id']}")
    attrs = asc.call("POST", "/profiles", body={"data": {
        "type": "profiles", "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bid}},
            "certificates": {"data": [{"type": "certificates", "id": c} for c in cert_ids]}}}})["data"]["attributes"]
    content = base64.b64decode(attrs["profileContent"])
    for d in PROFILE_DIRS:
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, attrs["uuid"] + ".mobileprovision"), "wb") as f:
            f.write(content)
    print(f"Installed profile '{name}' ({attrs['uuid']})")


def main():
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    key_id, issuer, key_path, *targets = sys.argv[1:]
    asc = ASC(key_id, issuer, key_path)
    cert_ids = distribution_certs(asc)
    for t in targets:
        identifier, _, caps = t.partition(":")
        bid = ensure_bundle_id(asc, identifier, [c for c in caps.split(",") if c])
        make_profile(asc, identifier, bid, cert_ids)


if __name__ == "__main__":
    main()
