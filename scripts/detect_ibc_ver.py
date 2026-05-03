"""Fetch the latest IBC release info from GitHub and write IBC_VER /
IBC_ASSET_URL to .env.

This script is meant to be invoked once per detection run. The .env file is
consumed by .github/workflows/detect-new-ver.yml.
"""
import sys

import requests

GITHUB_RELEASES_URL = "https://api.github.com/repos/IbcAlpha/IBC/releases"
HTTP_TIMEOUT_SECONDS = 10


def main() -> int:
    response = requests.get(GITHUB_RELEASES_URL, timeout=HTTP_TIMEOUT_SECONDS)
    response.raise_for_status()
    releases = response.json()
    if not releases:
        print("No releases returned from GitHub", file=sys.stderr)
        return 1

    latest = releases[0]
    ver = latest["name"]
    asset_url = next(
        (
            asset["browser_download_url"]
            for asset in latest["assets"]
            if asset["name"].startswith("IBCLinux")
        ),
        None,
    )
    if asset_url is None:
        print(f"No IBCLinux asset found in release {ver}", file=sys.stderr)
        return 1

    # Truncate so re-runs don't accumulate duplicate entries.
    with open(".env", "w") as fp:
        fp.write(f"IBC_VER={ver}\n")
        fp.write(f"IBC_ASSET_URL={asset_url}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
