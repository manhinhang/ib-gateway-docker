import requests
import json
import re

if __name__ == "__main__":
    url = "https://download2.interactivebrokers.com/installers/ibgateway/stable-standalone/version.json"
    regex = r"([^(]+)\)"
    response = requests.get(url)
    response_text = response.text
    matches = re.finditer(regex, response_text)
    # print(matches)
    json_str = next(matches).group(1)
    data = json.loads(json_str)
    print(data["buildVersion"])
