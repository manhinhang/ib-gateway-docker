# Example for Google cloud secret manager

If you're considering choose Google cloud as your IB gateway host, Google recommended store your sensitive key in secret manager.

Reference: <https://cloud.google.com/functions/docs/env-var#managing_secrets>

> Environment variables can be used for function configuration, but are not recommended as a way to store secrets such as database credentials or API keys. These more sensitive values should be stored outside both your source code and outside environment variables. Some execution environments or the use of some frameworks can result in the contents of environment variables being sent to logs, and storing sensitive credentials in YAML files, deployment scripts or under source control is not recommended.
>
> For storing secrets, we recommend that you review the best practices for secret management. Note that there is no Cloud Functions-specific integration with Cloud KMS.

---

This example just shown you how run docker & retrieve secret locally.

> *The deploy guide for google cloud may provide later.*

1. Set up your credentials path

    ```bash
    # your credentials json path
    export GOOGLE_APPLICATION_CREDENTIALS=
    ```

2. Run docker run command

    ```bash
    docker run --rm -it \
    --env GCP_SECRET_IB_ACCOUNT= \ # secret key name of your interactive brokers account name
    --env GCP_SECRET_IB_PASSWORD= \ # secret key name of your interactive brokers password
    --env GCP_SECRET_IB_TRADE_MODE= \ # secret key name of trade mode
    --env GCP_PROJECT_ID= \ # your project id
    -e GOOGLE_APPLICATION_CREDENTIALS=/tmp/keys/FILE_NAME.json \
    -v $GOOGLE_APPLICATION_CREDENTIALS:/tmp/keys/FILE_NAME.json:ro \
    manhinhang/ib-gateway-docker
    ```
