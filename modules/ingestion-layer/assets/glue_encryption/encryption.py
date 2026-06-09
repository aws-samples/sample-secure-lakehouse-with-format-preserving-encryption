"""
Glue Encryption Job — PySpark script for sensitive data detection and FPE encryption.

This script detects sensitive PCI data (credit card numbers) using Luhn algorithm,
BIN lookup, and regex patterns, then encrypts sensitive fields using Format-Preserving
Encryption (FPE) via the vault-transform-service private API.

Encrypted output is written back to the quarantine bucket under an /encrypted suffix path.
"""


import boto3
import os
import logging
import json
import requests
import uuid
import time
from datetime import datetime
import re
import json
import requests
from urllib.parse import urlparse
from datetime import datetime
from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import (
    col,
    udf,
    monotonically_increasing_id,
    row_number,
    concat,
    lit,
    concat_ws,
    when,
    size,
    posexplode,
    collect_list,
    first,
    array,
    pandas_udf,
    isnull,
)

from pyspark.sql.types import (
    StringType,
    ArrayType,
    StructType,
    StructField,
    IntegerType,
    MapType,
)

from pyspark.sql.window import Window
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
# import orjson as ujson
# from spark_util.utils import di_dq_check
import pandas as pd


from encryption_utils import processing_sensitive_columns
from contract_utils import Contract as Treatment_Contract

from pyspark.context import SparkContext
from pyspark.sql import DataFrame
from awsglue.context import GlueContext
from awsglue.job import Job
# from requests.auth import HTTPBasicAuth


def initialize_spark():
    """
    Initialize GlueContext and SparkSession.
    """
    glueContext = GlueContext(SparkContext.getOrCreate())
    spark = glueContext.spark_session
    job = Job(glueContext)

    # Initialize logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s %(filename)s %(lineno)d %(levelname)s %(message)s',
    )

    # Fallback logger
    logger = glueContext.get_logger() if glueContext else logging.getLogger("")
    logger = glueContext.get_logger()

    # glueContext.get_logger() does not seem to log INFO statements no matter what we do
    # not sure if it is at least logging the low level glue logs
    # defining a second logger to log OUR info statements
    logger2 = logging.getLogger()
    logger2.setLevel(logging.INFO)

    return glueContext, spark, job, logger, logger2


def process_file(args, spark: SparkSession, logger2):
    """
    Process a single file
    """

    print(args)
    source_key = args["source_key"]
    dataset = args["dataset"]
    metadata_bucket = args["metadata_bucket"]
    source_bucket = args["source_bucket"]
    vault_api_url = args["vault_api_url"]
    bin_file_path = args["bin_file_path"]



    source_file= f"s3://{source_bucket}/{source_key}"
    print(f"Source Data is {source_file} ")

    treatment_contract = Treatment_Contract(
        dataset, metadata_bucket
    )

    contract_key = treatment_contract.contract_file_path
    logger2.info(f"Contract file key: {contract_key}")
    sensitive_columns_details = treatment_contract.get_sensitive_columns_details()
    print(sensitive_columns_details)
    sensitive_columns = treatment_contract.get_sensitive_column_names()
    print(sensitive_columns)

    # # Read csv input file
    file_options = {
        "header": True,
        "quote": "\"",
        "quoteAll": True,
        "escape": "\"",
        "multiLine": True,
        "ignoreLeadingWhiteSpace": False,
        "ignoreTrailingWhiteSpace": False,
    }
    df = spark.read.options(**file_options).csv(source_file)
    df.show(20,truncate=False)

    processing_sensitive_columns(args, spark, logger2, df, sensitive_columns)


def main(args, spark=None, logger=None, logger2=None):
    """
    Main entry point for processing multiple files based on run_stats.json.
    """
    # Initialize Spark and Logger if not provided (for production)
    if spark is None or logger is None or logger2 is None:
        glueContext, spark, job, logger, logger2 = initialize_spark()
    else:
        # Use the provided SparkSession and logger (for testing)
        pass

    print(f"Job Arguments is {args}")

    process_file(args, spark, logger2)


if __name__ == "__main__":
    import sys

    args = getResolvedOptions(
        sys.argv,
        [
            "source_key",
            "dataset",
            "domain_id",
            "transformation",
            "datasource",
            "metadata_bucket",
            "source_bucket",
            "JOB_NAME",
            "bin_file_path",
            "vault_api_url"
        ],
    )

    args.setdefault(
        "traceability_enabled", "true"
    )  # We disable traceability by default to avoid additional processing for each count operation. This can be enabled by passing --traceability_enabled true
    # as job parameters.
    main(args)

