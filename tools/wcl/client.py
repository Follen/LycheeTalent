"""Small WCL v2 client. Secrets stay in process memory, never in output/cache."""
import argparse
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

class WCL:
    def __init__(self, credential_file=None):
        values = dict(os.environ)
        if credential_file:
            for line in Path(credential_file).read_text(encoding="utf-8-sig").splitlines():
                if "=" in line and not line.lstrip().startswith("#"):
                    key, value = line.split("=", 1)
                    values[key.strip()] = value.strip().strip("\"'")
        cid = values.get("WCL_CLIENT_ID", values.get("CLIENT_ID"))
        secret = values.get("WCL_CLIENT_SECRET", values.get("CLIENT_SECRET"))
        if not cid or not secret:
            raise RuntimeError("Missing WCL credentials")
        body = urllib.parse.urlencode({"grant_type":"client_credentials", "client_id":cid, "client_secret":secret}).encode()
        request = urllib.request.Request("https://www.warcraftlogs.com/oauth/token", data=body)
        with urllib.request.urlopen(request, timeout=30) as response:
            self.token = json.load(response)["access_token"]

    def query(self, query, variables=None):
        body = json.dumps({"query":query,"variables":variables or {}}).encode()
        request = urllib.request.Request("https://www.warcraftlogs.com/api/v2/client", data=body,
            headers={"Authorization":"Bearer "+self.token,"Content-Type":"application/json"})
        for attempt in range(3):
            try:
                with urllib.request.urlopen(request, timeout=40) as response:
                    result = json.load(response)
                if result.get("errors"):
                    # GraphQL errors contain schema errors, never authentication headers.
                    raise RuntimeError("; ".join(e.get("message", "GraphQL error") for e in result["errors"]))
                return result["data"]
            except urllib.error.HTTPError as exc:
                if exc.code not in (429, 500, 502, 503, 504) or attempt == 2:
                    raise RuntimeError(f"WCL HTTP {exc.code}") from None
                time.sleep(min(4, 2 ** attempt))
        raise RuntimeError("WCL request exhausted")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--credentials")
    parser.add_argument("--query-file", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    data = WCL(args.credentials).query(Path(args.query_file).read_text(encoding="utf-8-sig"))
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"saved":str(output),"fields":list(data)}))
