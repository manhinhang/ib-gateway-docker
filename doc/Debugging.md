# Debugging

For debugging, Use x11 forwarding to visit IB gateway GUI for the investigation.

## Debugging in Mac OSX

- install xquartz

    ```
    brew install --cask xquartz.
    ```

- In *XQuartz* -> Prefences ->Security

    Turn on `Allow connections from network clients`

- Run Docker with mounting `.Xauthority` and point DISPLAY environment variable with ip address

    Example: 

    ```
    docker run --platform linux/amd64 -d \
    --env IB_ACCOUNT= \
    --env IB_PASSWORD= \
    --env TRADE_MODE= \
    -v ~/.Xauthority:/root/.Xauthority \
    -e DISPLAY=$ip:0 \
    -p 4002:4002 \
    ib-gateway-docker tail -f /dev/null
    ```
