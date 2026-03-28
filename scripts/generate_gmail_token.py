"""
Generates gmail_token.json using OAuth2 Desktop app credentials.

Usage:
  pip install google-auth-oauthlib
  python scripts/generate_gmail_token.py path/to/oauth_client.json
"""

import json
import sys
from google_auth_oauthlib.flow import InstalledAppFlow

client_secrets_file = sys.argv[1] if len(sys.argv) > 1 else "oauth_client.json"

SCOPES = ["https://www.googleapis.com/auth/gmail.readonly"]

flow = InstalledAppFlow.from_client_secrets_file(client_secrets_file, SCOPES)
creds = flow.run_local_server(port=0)

token_data = {
    "token": creds.token,
    "refresh_token": creds.refresh_token,
    "token_uri": creds.token_uri,
    "client_id": creds.client_id,
    "client_secret": creds.client_secret,
    "scopes": list(creds.scopes),
}

with open("gmail_token.json", "w") as f:
    json.dump(token_data, f, indent=2)

print("gmail_token.json created. Set these env vars on your server:\n")
print(f"  GMAIL_CLIENT_ID={creds.client_id}")
print(f"  GMAIL_CLIENT_SECRET={creds.client_secret}")
print(f"  GMAIL_REFRESH_TOKEN={creds.refresh_token}")
