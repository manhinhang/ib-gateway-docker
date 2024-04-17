import requests
import os

if __name__ == "__main__":
    url = "https://api.github.com/repos/IbcAlpha/IBC/releases"
    response = requests.get(url)
    data = response.json()
    latest = data[0]
    ver = latest["name"]
    for asset in latest["assets"]:
        if asset["name"].startswith("IBCLinux"):
            asset_url = asset["browser_download_url"]

    with open('.env', 'a') as fp:
        fp.write(f'IBC_VER={ver}\n')
        fp.write(f'IBC_ASSET_URL={asset_url}\n')
