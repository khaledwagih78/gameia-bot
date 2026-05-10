

import os
import requests
import schedule
import time
from datetime import date
from google.oauth2 import service_account
from googleapiclient.discovery import build
import json
 
BOT_TOKEN = os.environ.get("BOT_TOKEN", "8267904285:AAGVOoTasLqP8dGr82euRFSxyw34wuGnSCs")
CHAT_ID = os.environ.get("CHAT_ID", "90437191")
SHEET_ID = os.environ.get("SHEET_ID", "1P2SfWJqq8k_8Gk7mRV1fPLq1kXdonOpoxjvP1z7IUHg")
 
CREDENTIALS = {
  "type": "service_account",
  "project_id": "direct-outlet-472308-k9",
  "private_key_id": "0a14b2a82a833bd3534fc66ff984f8cee3f3c91a",
  "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQDpcL0Eib/3knYX\n9zkvBJsRzap7/rwYOorZGywmY+9SOQmH4YbuQ9/N8oPNMe3CktHVBAWtjuL/MgHA\n7wqmzE9o+5o1sOC1bMYdmC8VuNcsORS0lzPFeEAgOjInT32tcBLi8swlRASKV8f7\nSm0sBw4NqrqfIkCgJ+D6a003xk2rx1R1YXBLfo0s7UNB3kLj8LQKEqdZfULp7wf2\nW6NqMC4aCfzENxww/QG6mvmRNIUjt8ygYRVLfhMzOhLGmFC6P6czStZCl4E5LHh0\n0O4+tj19xwzaVd9qoL+FGSKvD6A21aC9y4SPahvPrROmk9lbD0LJ/dhR08pY8OC1\nWXSIQ1ftAgMBAAECggEAD9X9NJga+jKo0+JfsjVX8a1n3HvWNbc5oRXAo9ARYEdh\n7U0FfWyu+4ZxSNO+GH4jlursGa8rmKVDTNvKd1s9Iyw3n18i4fEsQBNeqlS84BFK\nkB+rvEB2lS5teuY1FTVuSpAEUkjax/8WyrtsoYPPARVXuKDht8ZMyErMKmBHokNF\nEQ8Rt+uBNp4Q6WGMYcyrcdesO1zrKtku21LFBYsvvQTNXAZTuEzCJDKTVVHXGQ5S\ndKvYNQe6Q4a08dNDCYuKc6aRKfFTDteYTIGy8ZCrC3aT36DUIfmFPcS4SdUnQPlg\nM3ODGstKDcnJDlCv9ciC1JedZ/2i+FBVQ9vqus5lTwKBgQD5dX09nePg7D31J66r\nkv9ar1F3LztpXdC1oMTVPky0dWBBf3OCRj/Jh65RyUqvAE7iBTZqbQk4qaIoeCeS\n6Bf+X0AnCk8hnw18SI7qvDiBbUckmtvOMCCfBaXz4ks883Sgu0eL6/sKIeSLfmaR\nZ2mL/BSVVz3AUXxxvK0bTq+hvwKBgQDvj7kycFfhMTokql0r2R8JMKfKSnTCmFqH\n7udLc6v4FNv1qq7eAozwvgBT1Rb3YPNN9GRS2jzPN7QzBWK/VEQ9Uj3ATU0CPg7L\n3/skiXipPLcvjSmZwdaS6nVvUUa6rz3iVhVhvJpyWE/lncihjREPQQLbX4Zemcqo\nckQv6onZUwKBgQCQV4Q1QAPYZLng/aobCv6IWYNY5FKLQEaAodrizJ6TmIsuuvF6\nQu2rzb93AXMeWZ5LN9rpr9ezGqyCoCu93F/txu2W6WcqPB8Qd+eCOZC0iyesLZLb\n9osZmKoSuTDxvqkQS+01MEFc9omIkYYFwoGXBzBdzVIk0sGgCh1b/KaxfwKBgQCU\nn5MjMsWipVrQMo25TWvO1MvUWdsUe1b3LIV8rxfKwo4wXKM+g1CTbx1e5T3pXdG0\n1GGFcXX2jTWTzcyUrR/k92fuLUcQlBWz8JKr+UnNnSh9LNPZW4PXA/S1ijQaT+xR\nxlxflZYwSI/RAdHeQFmMICY4mYwQltM/LB0XqSe6lwKBgQC17VG7ibrJQgKQG/lk\nvwqmzqkbKe3h5dfNo150xR6ppb9zOuqMW2SqkBkIbIUi6yjSL4knf3wEM1k6hGUt\ndFaSvnb6iLo7c7G4ftBQHjbRp016nBsu8kuK8e/D5gklIno3XVpw3AlhA0dul/Rr\nrnYjEPd0aY20zHCamVPaZYE54w==\n-----END PRIVATE KEY-----\n",
  "client_email": "gameia-bot@direct-outlet-472308-k9.iam.gserviceaccount.com",
  "client_id": "100070048815612406823",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/gameia-bot%40direct-outlet-472308-k9.iam.gserviceaccount.com",
  "universe_domain": "googleapis.com"
}
 
month_map = {
    "شهر 10": "2025-10","شهر 11": "2025-11","شهر 12": "2025-12",
    "شهر 1-26": "2026-01","شهر 2-26": "2026-02","شهر 3-26": "2026-03",
    "شهر 4-26": "2026-04","شهر 5-26": "2026-05","شهر 6-26": "2026-06",
    "شهر 7-26": "2026-07","شهر 8-26": "2026-08","شهر 9-26": "2026-09",
    "شهر 10-26": "2026-10","شهر 11-26": "2026-11","شهر 12-26": "2026-12",
    "شهر 27-1": "2027-01","شهر 27-2": "2027-02","شهر 27-3": "2027-03",
    "شهر 27-4": "2027-04","شهر 27-5": "2027-05","شهر 27-6": "2027-06",
    "شهر 27-7": "2027-07","شهر 27-8": "2027-08","شهر 27-9": "2027-09",
    "شهر 27-10": "2027-10",
}
 
def read_sheet():
    creds = service_account.Credentials.from_service_account_info(
        CREDENTIALS,
        scopes=["https://www.googleapis.com/auth/spreadsheets.readonly"]
    )
    service = build("sheets", "v4", credentials=creds)
    rows = service.spreadsheets().values().get(
        spreadsheetId=SHEET_ID,
        range="الورقة1!A1:L50"
    ).execute().get("values", [])
    return rows
 
def parse_schedule(rows):
    gameia1 = {}
    gameia2 = {}
    n = 0
    for row in rows:
        name = row[0].strip() if len(row) > 0 and row[0] else ""
        month = row[1].strip() if len(row) > 1 and row[1] else ""
        if month in month_map and name:
            n += 1
            gameia1[month_map[month]] = (n, name)
        if len(row) >= 8:
            c = row[2].strip() if row[2] else ""
            h = row[7].strip() if row[7] else ""
            g = row[6].strip() if row[6] else ""
            if c and h and g:
                try:
                    sn = int(c)
                    mn = int(g)
                    mk = f"2025-{mn:02d}" if mn >= 10 else f"2026-{mn:02d}"
                    gameia2[mk] = (sn, h)
                except:
                    pass
    return gameia1, gameia2
 
def send_reminder():
    today = date.today()
    day = today.day
    if day > 10:
        return
    mk = today.strftime("%Y-%m")
    try:
        rows = read_sheet()
        g1, g2 = parse_schedule(rows)
        g1_data = g1.get(mk)
        g2_data = g2.get(mk)
        msg = f"تنبيه الجمعية - يوم {day}\n\n"
        if g1_data:
            msg += f"الجمعية الاولى\nالسهم {g1_data[0]} - {g1_data[1]}\nالمبلغ: 400 جنيه\n\n"
        if g2_data:
            msg += f"الجمعية الثانية\nالسهم {g2_data[0]} - {g2_data[1]}\nالمبلغ: 625 جنيه\n"
        if not g1_data and not g2_data:
            msg += "مفيش جمعية الشهر ده"
        requests.post(
            f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage",
            json={"chat_id": CHAT_ID, "text": msg}
        )
        print(f"تم الارسال - يوم {day}")
    except Exception as e:
        print(f"خطأ: {e}")
 
print("البوت شغال...")
send_reminder()
schedule.every().day.at("10:00").do(send_reminder)
while True:
    schedule.run_pending()
    time.sleep(60)
