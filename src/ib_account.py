import json
import os
from abc import abstractmethod


class IBAccount(object):

    @abstractmethod
    def __init__(self):
        self.__client = None

    @staticmethod
    def isEnabledGCPSecret() -> bool:
        try:
            gcp_json_path = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS', None)
            if gcp_json_path is not None:
                if os.path.exists(gcp_json_path):
                    return True
                else:
                    raise FileNotFoundError(f'No GCP creds found at path: {gcp_json_path}')
            return False
        except ValueError:
            return False

    @staticmethod
    def isEnabledFileSecret() -> bool:
        try:
            file_cred_path = os.environ.get('IB_CREDENTIALS_FILEPATH', None)
            if file_cred_path is not None:
                if os.path.exists(file_cred_path):
                    return True
                else:
                    raise FileNotFoundError(f'No File creds found at path: {file_cred_path}')
            return False
        except ValueError:
            return False

    @abstractmethod
    def account(self) -> str:
        return os.environ['IB_ACCOUNT']

    @abstractmethod
    def password(self):
        return os.environ['IB_PASSWORD']

    @abstractmethod
    def trade_mode(self):
        return os.environ['TRADE_MODE']


class FileCredsIBAccount(IBAccount):

    def __init__(self):
        super().__init__()
        self.__file_path = os.environ.get('IB_CREDENTIALS_FILEPATH', None)
        if self.__file_path is None:
            raise ValueError("IB_CREDENTIALS_FILEPATH Env var not set!")
        try:
            self.__creds = json.load(open(self.__file_path))
        except FileNotFoundError as e:
            raise FileNotFoundError(f'No file at {self.__file_path}')
        except Exception as e:
            raise e

    def password(self) -> str:
        try:
            return self.__creds['password']
        except ValueError:
            raise ValueError(f'key "password" not found in JSON file: {self.__file_path}')

    def account(self) -> str:
        try:
            return self.__creds['account']
        except ValueError:
            raise ValueError(f'key "account" not found in JSON file: {self.__file_path}')

    def trade_mode(self) -> str:
        if 'trade_mode' in self.__creds:
            return self.__creds['trade_mode']
        else:
            trade_mode = os.environ.get('TRADE_MODE', None)
            if trade_mode is not None:
                return trade_mode
        raise ValueError(f'trade_mode not set in {self.__file_path} and TRADE_MODE not set as env var!')


class GCPIBAccount(IBAccount):
    def __init__(self):
        super().__init__()
        from google.cloud import secretmanager
        gcp_creds_path = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS', None)
        if gcp_creds_path:
            self.__gcp_project_id = os.environ['GCP_PROJECT_ID']
            self.__client = secretmanager.SecretManagerServiceClient.from_service_account_json(gcp_creds_path)
        else:
            raise ValueError('Need to set env var for GOOGLE_APPLICATION_CREDENTIALS to use GCP credentials!')

    def retrieve_gcp_secret(self, secret_id):
        name = self.__client.secret_version_path(self.__gcp_project_id, secret_id, 'latest')
        response = self.__client.access_secret_version(name=name)
        payload = response.payload.data.decode('UTF-8')
        return payload

    def account(self) -> str:
        return self.retrieve_gcp_secret(os.environ['GCP_SECRET_IB_ACCOUNT'])

    def password(self):
        return self.retrieve_gcp_secret(os.environ['GCP_SECRET_IB_PASSWORD'])

    def trade_mode(self):
        return self.retrieve_gcp_secret(os.environ['GCP_SECRET_IB_TRADE_MODE'])
