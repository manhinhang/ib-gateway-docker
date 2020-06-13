import os
from distutils.util import strtobool
from google.cloud import secretmanager

class IBAccount(object):
    # Create the Secret Manager client.
    __client = None
   
    @classmethod
    def retrieve_secret(cls, secret_id):
        if not cls.__client:
            cls.__client = secretmanager.SecretManagerServiceClient()
        gcp_project_id = os.environ['GCP_PROJECT_ID']
        name = cls.__client.secret_version_path(gcp_project_id, secret_id, 'latest')
        response = cls.__client.access_secret_version(name)
        payload = response.payload.data.decode('UTF-8')
        return payload

    @staticmethod
    def isEnabledGCPSecret():
        try:
            return bool(strtobool(os.environ['GCP_SECRET']))
        except ValueError:
            return False
    
    @classmethod
    def account(cls):
        if not cls.isEnabledGCPSecret():
            return os.environ['IB_ACCOUNT']
        return cls.retrieve_secret(os.environ['GCP_SECRET_IB_ACCOUNT'])
    
    @classmethod
    def password(cls):
        if not cls.isEnabledGCPSecret():
            return os.environ['IB_PASSWORD']
        return cls.retrieve_secret(os.environ['GCP_SECRET_IB_PASSWORD'])

    @classmethod
    def trade_mode(cls):
        if not cls.isEnabledGCPSecret():
            return os.environ['TRADE_MODE']
        return cls.retrieve_secret(os.environ['GCP_SECRET_IB_TRADE_MODE'])

    