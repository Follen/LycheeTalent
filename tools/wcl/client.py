"""Small WCL v2 client. Secrets stay in process memory, never in output/cache."""
import argparse
import concurrent.futures
import json
import os
import time
import threading
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

class WCLPermissionError(RuntimeError):
    def __init__(self,message,payload):
        super().__init__(message);self.payload=payload

class WCL:
    def __init__(self, credential_file=None):
        self._combatants = {}
        self._combatant_summaries = {}
        self._combatants_lock = threading.Lock()
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

    def combatants(self, code, fight):
        """Share one complete fight's original actor/talent events across ranking jobs."""
        key = (code, fight)
        with self._combatants_lock:
            pending = self._combatants.get(key)
            owner = pending is None
            if owner:
                pending = concurrent.futures.Future()
                self._combatants[key] = pending
        if not owner:
            return pending.result()
        try:
            prefix = '{reportData{report(code:' + json.dumps(code) + '){'
            args = 'fightIDs:[' + str(fight) + '],dataType:CombatantInfo,limit:10000'
            report = self.query(prefix + 'playerDetails(fightIDs:[' + str(fight) + '])events(' + args + '){data nextPageTimestamp}}}}')['reportData']['report']
            pages = [report['events']]
            while pages[-1]['nextPageTimestamp'] is not None:
                cursor = pages[-1]['nextPageTimestamp']
                page = self.query(prefix + 'events(' + args + ',startTime:' + str(cursor) + '){data nextPageTimestamp}}}}')['reportData']['report']['events']
                pages.append(page)
            result = {'playerDetails':report['playerDetails'], 'pages':pages}
            pending.set_result(result)
            return result
        except Exception as exc:
            pending.set_exception(exc)
            raise

    def combatant_summary(self, code, fight):
        """Share the Summary fallback's original per-actor data for this fight."""
        key = (code, fight)
        with self._combatants_lock:
            pending = self._combatant_summaries.get(key)
            owner = pending is None
            if owner:
                pending = concurrent.futures.Future()
                self._combatant_summaries[key] = pending
        if not owner:
            return pending.result()
        try:
            query = '{reportData{report(code:' + json.dumps(code) + '){table(fightIDs:[' + str(fight) + '],dataType:Summary)}}}'
            result = self.query(query)['reportData']['report']['table']['data']
            pending.set_result(result)
            return result
        except Exception as exc:
            pending.set_exception(exc)
            raise

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
                    message="; ".join(e.get("message", "GraphQL error") for e in result["errors"])
                    if message=="You do not have permission to view this report.":raise WCLPermissionError(message,result)
                    raise RuntimeError(message)
                return result["data"]
            except urllib.error.HTTPError as exc:
                if exc.code==403:raise WCLPermissionError("WCL HTTP 403",{"status":403}) from None
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
    output.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")
    print(json.dumps({"saved":str(output),"fields":list(data)}))
