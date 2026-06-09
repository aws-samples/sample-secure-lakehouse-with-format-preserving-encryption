import boto3
import logging
import yaml
from typing import List, Dict, Any
import pprint

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

class ContractNotFoundException(Exception):
    """Custom exception made for stating when a contract is not found on Amazon AWS S3.

    Raised in 'Contract._read_s3_file()' when a Contract file is not found."""
    pass

class Contract:
    """Blog Data contract container class.

    Takes a YAML data contract stored on Amazon AWS S3, based on input parameters.
    Data contracts are used to ensure the integrity and validity of incoming data from external sources into the encryption system.

    Arguments:
        dataset (str): Dataset name used to build the contract S3 key.
        metadata_bucket (str): An Amazon S3 bucket where the data contracts are stored.
    """

    def __init__(self, dataset: str, metadata_bucket: str):
        self.dataset = dataset
        self.metadata_bucket = metadata_bucket
        self.__cntrct = self.get_contract()
        self.__sensitive_columns = self._extract_sensitive_columns()

    @property
    def contract_file_path(self):
        """
        Based on the `dataset` attribute, builds the s3 path to the data contract file.

        Returns:
            s3_key (str): S3 Key String, pointing to a YAML data contract.
        """
        s3_key = f"treatment-contract/{self.dataset}-treatment-contract.yaml"
        logger.info(f"Contract file key: {s3_key}")
        return s3_key

    @property
    def contract(self):
        return self.__cntrct

    @property
    def sensitive_columns(self):
        return self.__sensitive_columns

    def _read_s3_file(self, s3_bucket: str, key: str) -> str:
        """Read contents of a S3 file based using Bucket and Prefix.

        Args:
            s3_bucket (str): S3 Bucket name
            key (str): Prefix

        Returns:
            contact_str (str): S3 file content.
        """
        s3_client = boto3.client("s3")
        try:
            contract_str = (
                s3_client.get_object(Bucket=s3_bucket, Key=key)["Body"]
                .read()
                .decode("UTF-8")
            )
        except s3_client.exceptions.NoSuchKey:
            logger.error(f"Contract not found, key: {key}")
            raise ContractNotFoundException
        logger.info(f"Read contract from s3://{s3_bucket}/{key}")
        return contract_str

    def get_contract(self) -> dict:
        """Read Contract from S3 and return the yaml as a safe-loaded Python dictionary. Used on __init__.

        Returns:
            cntrct (dict): Data contract, represented as dict.
        """
        logger.info("Reading contract from S3")
        contract_s3_key = self.contract_file_path
        cntrct = yaml.safe_load(
            self._read_s3_file(self.metadata_bucket, contract_s3_key)
        )
        return cntrct

    def _extract_sensitive_columns(self) -> List[Dict[str, Any]]:
        """
        Extracts sensitive columns and their configurations from the data contract.

        Returns:
            List[Dict[str, Any]]: A list of sensitive columns with their full configurations.
        """
        sensitive_columns = []
        records = (
            self.contract.get("schema", {})
            .get("specification", {})
            .get("fileMetadata", {})
            .get("records", [])
        )

        for record in records:
            for field in record.get("fields", []):
                treatment = field.get("treatment", {})
                sensitive_columns.append(
                    {
                        "fieldName": field.get("fieldName"),
                        "description": field.get("businessName", ""),
                        "encryptionType": treatment.get("encryptionType", ""),
                        "parameters": treatment.get("parameters", {}),
                        "validation": treatment.get("validation", {}),
                        "isNullable": field.get("isNullable", True),
                        "treatment": treatment,  # full raw treatment block added here
                    }
                )
        return sensitive_columns

    def get_sensitive_columns_details(self) -> List[Dict[str, Any]]:
        """
        Returns the list of sensitive columns with their configurations.

        Returns:
            List[Dict[str, Any]]: Sensitive columns and their configurations.
        """
        return self.sensitive_columns

    def get_sensitive_column_names(self) -> List[str]:
        """
        Returns only the field names of the sensitive columns.

        Returns:
            List[str]: Field names of the sensitive columns.
        """
        return [column["fieldName"] for column in self.sensitive_columns]
