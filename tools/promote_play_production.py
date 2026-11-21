#!/usr/bin/env python3
"""Promote the latest Google Play internal-track release to production.

Uses the Play Developer API with PLAY_SERVICE_ACCOUNT_JSON (base64 in CI).
Run:  PLAY_SA_B64=$(echo $SECRET | base64 -d) python3 promote_play_production.py \
        --package com.trsonn.macrotrack [--status completed]
Steps: insert edit -> list internal-track releases -> copy the newest
release (the same release note/version codes) to the production track ->
commit edit. Prints the production track state afterwards.
"""
import argparse, base64, json, os, sys, time
import urllib.request, urllib.error

API = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications'


def token(sa_json: dict) -> str:
    """Self-signed JWT access token (no external deps; HS-free ES256 via stdlib
    is not possible, so use google-auth if available, else fail loudly)."""
    try:
        from google.oauth2 import service_account
        creds = service_account.Credentials.from_service_account_info(
            sa_json, scopes=['https://www.googleapis.com/auth/androidpublisher'])
        creds.refresh(__import__('google.auth.transport.requests', fromlist=['Request']).Request())
        return creds.token
    except Exception as e:  # pragma: no cover
        sys.exit(f'google-auth not available: {e}. pip install google-auth')


def call(method, path, token_, body=None):
    req = urllib.request.Request(API + path, method=method)
    req.add_header('Authorization', 'Bearer ' + token_)
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, data=data) as r:
            return json.loads(r.read().decode() or '{}')
    except urllib.error.HTTPError as e:
        sys.exit(f'{method} {path} -> {e.code}: {e.read().decode()[:400]}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--package', required=True)
    ap.add_argument('--status', default='completed',
                    help='rollout status for production (completed | inProgress)')
    args = ap.parse_args()

    raw = os.environ.get('PLAY_SA_JSON') or base64.b64decode(
        os.environ['PLAY_SA_B64']).decode()
    sa = json.loads(raw)
    tk = token(sa)

    edit = call('POST', f'/{args.package}/edits', tk, {})
    eid = edit['id']
    print('edit:', eid)

    tracks = call('GET', f'/{args.package}/edits/{eid}/tracks', tk)['tracks']
    internal = next((t for t in tracks if t['track'] == 'internal'), None)
    if not internal or not internal.get('releases'):
        sys.exit('no releases on the internal track')
    rel = sorted(internal['releases'],
                 key=lambda r: r.get('name', ''), reverse=True)[0]
    print('promoting release:', rel.get('name'),
          'versionCodes:', rel.get('versionCodes'))

    prod_body = {'track': 'production', 'releases': [{
        'name': rel.get('name'),
        'versionCodes': rel['versionCodes'],
        'status': args.status,
        **({'releaseNotes': rel['releaseNotes']} if rel.get('releaseNotes') else {}),
    }]}
    call('PUT', f'/{args.package}/edits/{eid}/tracks/production', tk, prod_body)
    call('POST', f'/{args.package}/edits/{eid}:commit', tk, {})
    print('committed. production rollout status:', args.status)


if __name__ == '__main__':
    main()
