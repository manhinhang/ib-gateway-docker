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
    os.putenv("IBC_VER", ver)
    os.putenv("IBC_ASSET_URL", asset_url)
    print(ver)
    print(asset_url)
