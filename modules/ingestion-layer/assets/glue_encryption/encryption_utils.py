from pyspark.sql.functions import (
    col,
    udf,
    monotonically_increasing_id,
    row_number,
    concat,
    concat_ws,
    when,
    count,
    lit,
    size,
    posexplode,
    collect_list,
    first,
    array,
    isnull,
    regexp_extract_all,
    expr,
    transform,
    struct
)

from pyspark.sql import functions as F

from pyspark import TaskContext
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.window import Window
from pyspark.sql.types import (
    ArrayType,
    StringType,
    StructType,
    StructField,
    IntegerType,
    LongType,
    MapType,
    BooleanType
)

from functools import reduce
import boto3
import logging
import os
from datetime import datetime
import time
import json
import requests
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from typing import List, Dict, Any
from urllib.parse import urlparse
import random

# The Vault Transform API method uses AWS_IAM authorization, so every request
# must be SigV4-signed with credentials whose IAM policy allows
# execute-api:Invoke on POST /transform/encrypt. Reaching the API through the
# VPC interface endpoint is necessary but not sufficient.
EXECUTE_API_SERVICE = "execute-api"

# Vault-compatible request headers, kept so the payload and header shape match
# what a HashiCorp Vault Transform engine expects. They are routing and
# namespace metadata, not credentials: authentication is SigV4 and the
# encryption_api Lambda neither reads nor validates these headers.
#
# X-Vault-Token is a placeholder retained for shape only. A real Vault
# deployment would resolve this from Secrets Manager at call time rather than
# holding it in source.
VAULT_NAMESPACE = "root"
VAULT_TOKEN = "not-a-credential-sigv4-is-used-instead"  # noqa: S105 - placeholder, not a secret

# One boto3 Session per executor process. Sessions cache the credential
# resolution chain, so this avoids re-resolving the Glue job role's credentials
# on every chunk. Signing itself is local and cheap.
_SESSION = None


logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


def _get_session():
    """Return a process-local boto3 Session.

    Created lazily because this runs on Spark executors: a Session built on the
    driver cannot be pickled and shipped, so each executor builds its own.
    """
    global _SESSION
    if _SESSION is None:
        _SESSION = boto3.Session()
    return _SESSION


def _resolve_region(url: str) -> str:
    """Resolve the region to sign with.

    Order: boto3 session (Glue sets AWS_REGION on executors), then the standard
    environment variables, then the region embedded in the execute-api hostname.
    The signing region must match the API's region or the signature is rejected.
    """
    session_region = _get_session().region_name
    if session_region:
        return session_region

    env_region = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION")
    if env_region:
        return env_region

    # e.g. abc123.execute-api.us-east-1.amazonaws.com
    host_parts = urlparse(url).netloc.split(".")
    if EXECUTE_API_SERVICE in host_parts:
        return host_parts[host_parts.index(EXECUTE_API_SERVICE) + 1]

    raise RuntimeError(
        f"Cannot resolve an AWS region for SigV4 signing from url {url}. "
        "Set AWS_REGION on the Glue job."
    )


def encryption_api(url: str, headers: dict, payload: dict, logger2):
    """Send a SigV4-signed POST to the Vault Transform encrypt endpoint.

    The API method is configured with AWS_IAM authorization, so the request is
    signed with the Glue job role's credentials. Signing happens per call, which
    also means every retry gets a fresh signature rather than replaying an
    expired one.

    Note url should have the path specified, e.g. /transform/encrypt.

    Arguments:
        url: Full invoke URL including the resource path.
        headers: Caller headers, e.g. the Vault-compatible set from
            build_headers(). These are included in the signed header set, so the
            exact values sent must match those signed. Authorization,
            X-Amz-Date and X-Amz-Security-Token are added by the signer.
        payload: Request body, serialized to JSON before signing.
        logger2: Logger that writes to the Spark executor log.

    Returns:
        requests.Response
    """
    try:
        region = _resolve_region(url)
        credentials = _get_session().get_credentials()
        if credentials is None:
            raise RuntimeError(
                "No AWS credentials available on this executor to sign the "
                "Vault Transform API request."
            )

        # SigV4 signs a hash of the exact bytes sent, so the body is serialized
        # once and reused for both signing and sending. Passing json=payload to
        # requests would re-serialize it and could produce a different byte
        # string, which fails signature verification.
        body = json.dumps(payload)

        request_headers = dict(headers or {})
        request_headers["Content-Type"] = "application/json"
        request_headers["Host"] = urlparse(url).netloc

        aws_request = AWSRequest(
            method="POST",
            url=url,
            data=body,
            headers=request_headers,
        )
        SigV4Auth(credentials, EXECUTE_API_SERVICE, region).add_auth(aws_request)

        response = requests.post(
            url,
            headers=dict(aws_request.headers),
            data=body,
            timeout=60,
            verify=True,
        )

        #ERROR, WARNING and Print will be logged in glue error log for Executor logs (which run inside mappartition() functions.
        #INFO logs will not be logged for Executor logs (which run inside mappartition() functions.
        logger2.warning(f"Status Code: {response.status_code}")
        logger2.warning(f"Response JSON: {response.text}")

        return response
    except requests.exceptions.RequestException as e:
        logger2.exception(f"API request error: {str(e)}")
        raise

def explode_identified_sensitive_data(
    spark: SparkSession,
    identified_df: DataFrame,
    sensitive_column: str,
    detected_values_col_name: str = "enc_detected_values",
    row_index_col_name: str = "enc_row_index",
    index_pos_col_name: str = "enc_detected_values_position",
    array_item_col_name: str = "enc_array_item_index",
) -> DataFrame:
    """This function takes in an identified data frame with following structure.

    |enc_detected_values                           |enc_row_index |enc_detected_values_position|
    |----------------------------------------------|--------------|---------------------------|
    |[1111-2222-3333-4444, 5555-6666-7777-8888]    |1             |[(0, 20), (21, 40)]        |
    |[0876-5432-1098-9000]                         |2             |[(0, 25)]                  |
    |[9999-8888-7777-6666, 2222-3333-4444-5555,... |3             |[(0, 20), (21, 45), (46, 70)]|
    |NULL                                          |4             |NULL                       |

    It processes each row and splits it into its own unique row for easier chunking and sending to encryption API.
    It makes use of the posexplode function of spark, which takes splits the value_list rows into their own unique rows
    and captures the order of their occurence.

    Then we take the index_position_list column and place the correct positional info with the corresponding value. The end:

    |index|pos |value               |index_position|
    |-----|----|--------------------|--------------|
    |  1  | 0  |1111-2222-3333-4444 | (0, 20)      |
    |  1  | 1  |5555-6666-7777-8888 | (21, 40)     |
    |  2  | 0  |0876-5432-1098-9000 | (0, 25)      |
    |  3  | 0  |9999-8888-7777-6666 | (0, 20)      |
    |  3  | 1  |2222-3333-4444-5555 | (21, 45)     |
    |  3  | 2  |1111-2222-3333-4444 | (46, 70)     |

    NB: NULL or [] are automatically filtered by posexplode since they cannot be split into any unique rows themself.

    Arguments:
        identified_df (DataFrame): The input DataFrame that we want to split into unique rows

    Returns:
        DataFrame: A dataframe with each row containing an individual sensitive value and its index position
    """

    exploded_df = identified_df.select(
        sensitive_column,
        row_index_col_name,
        index_pos_col_name,
        posexplode(detected_values_col_name).alias(array_item_col_name, "value"),
    )

    exploded_df = exploded_df.withColumn(
        index_pos_col_name, col(index_pos_col_name)[col(array_item_col_name)]
    )

    return exploded_df

def add_chunk_id(
    df: DataFrame,
    chunk_size: int,
    row_index_col_name: str = "enc_row_index",
    array_item_col_name: str = "enc_array_item_index"
) -> DataFrame:
    """
    This function adds a chunk_id column to the dataframe for parallel processing.

    Arguments:
        df (DataFrame): The input DataFrame that we want to apply chunking onto.
        chunk_size (integer): The number of rows per chunk.
        row_index_col_name (str): Name of the row index column
        array_item_col_name (str): Name of the array item index column

    Returns:
        DataFrame: Original dataframe with an additional chunk_id column for parallel processing.
    """
    # Filter non-null values
    filtered_df = df.filter(col("value").isNotNull())

    # Add row number for chunking without having to count or collect
    window_spec = Window.orderBy(row_index_col_name, array_item_col_name)
    df_with_row_num = filtered_df.withColumn("row_num", row_number().over(window_spec))

    # Add chunk_id column using integer division
    chunked_df = df_with_row_num.withColumn(
        "chunk_id",
        ((col("row_num") - 1) / chunk_size).cast(IntegerType())
    ).drop("row_num")

    return chunked_df

def build_headers() -> dict:
    """Vault-compatible request headers.

    These carry no authentication. encryption_api adds Authorization,
    X-Amz-Date and X-Amz-Security-Token from the Glue job role's credentials via
    SigV4 at call time, and includes these headers in the signed set.
    """
    return {
        "X-Vault-Request": "true",
        "X-Vault-Namespace": VAULT_NAMESPACE,
        "X-Vault-Token": VAULT_TOKEN,
        "Content-Type": "application/json",
    }


def processing_sensitive_columns(args, spark: SparkSession, logger2, input_df: DataFrame, sensitive_columns: list):
    logger2.info("===============")

    df_row_ids = add_row_indexes(input_df)
    logger2.info("=================")

    logger2.info("Added row indexes.")

    df_reconstructed = df_row_ids

    for sensitive in sensitive_columns:
        sensitive_column = sensitive.get("fieldName")
        validation = sensitive.get("validation") or {}
        column_regex = validation.get("regex", "").strip()

        logger2.info(f"Processing sensitive column: {sensitive_column} using Regex rules: {column_regex}")
        
        if not sensitive_columns:
            continue

        # Vault-compatible headers, no authentication. SigV4 headers are added
        # per request inside encryption_api, since a signature is short-lived
        # and cannot be reused across the retry backoff.
        headers = build_headers()

        start = datetime.now()
        df_detected = detect_sensitive_data(
            args, spark, df_reconstructed, sensitive_column, column_regex, logger2
        )
        df_detected.cache()
        df_detected.count()  # force materialization into cache
        end = datetime.now()
        # logger2.info(f"**Sensitive detection process took: {(end - start) / 60:.3f} minutes")
        logger2.info(f"**Sensitive detection process took: {end - start}")

        if has_enc_detected_values(df_detected):
            logger2.info("=================")

            logger2.info(f"Detected credit cards in {sensitive_column}")
            start = datetime.now()
            exploded_df = explode_identified_sensitive_data(
                spark, df_detected, sensitive_column
            )

            end = datetime.now()
            logger2.info(f"**Explode the detected dataframe took: {end - start}")

            #DEBUG
            row_count = exploded_df.count()
            logger2.info(f"Total number of Credit Card for encryption in {sensitive_column}: {row_count}")

            start = datetime.now()
            # chunk_size is supplied as the --chunk_size Glue job argument so it can be
            # tuned per environment without a code change. Size it against measured p99
            # Lambda duration: a chunk must encrypt well inside the API Gateway
            # integration timeout, or the request returns 504 on every retry.
            chunk_size = int(args.get("chunk_size", 15000))
            logger2.info(f"Using encryption chunk_size={chunk_size} for {sensitive_column}")
            chunked_df = add_chunk_id(exploded_df, chunk_size=chunk_size)
            end = datetime.now()
            # logger2.info(f"**Chunking process took: {(end - start) / 60:.3f} minutes")
            logger2.info(f"**Chunking process took: {end - start}")

            #DEBUG
            chunked_count = chunked_df.select("chunk_id").distinct().count()
            logger2.info(f"Total number of chunks: {chunked_count} for {sensitive_column}")

            transformation_type = args["transformation"]
            encryption_api_url = args["vault_api_url"]
            domain_id = args["domain_id"]
            dataset = args["dataset"]
            datasource = args["datasource"]

            start = datetime.now()
            df_encrypted_advanced = encrypt_dataframe_mappartitions(
                args,
                logger2,
                spark,
                chunked_df,
                transformation_type,
                headers,
                encryption_api_url,
                domain_id,
                dataset,
                datasource,
                sensitive_column
            )
            end = datetime.now()
            logger2.info(f"**Encryption process took: {end - start}")
            logger2.info("FINAL ENCRYPTED DF:")

            start = datetime.now()
            df_merged = merge_encrypted_with_original(
                df_encrypted_advanced, df_detected, sensitive_column
            )
            logger2.info("================merge_encrypted_with_original\n")

            end = datetime.now()
            logger2.info(f"**Merge encrypted with original process took: {end - start}")

            start = datetime.now()
            df_replaced = replace_encrypted_values_in_dataframe(
                df_merged, sensitive_column
            )
            end = datetime.now()
            logger2.info("================replace_encrypted_values_in_dataframe\n")

            logger2.info(f"**Replace encrypted value process took: {end - start}")

            logger2.info("Replaced sensitive values in {sensitive_column}")

            start = datetime.now()
            df_reconstructed = reconstruct_encrypted_data(
                df_reconstructed, df_replaced, sensitive_column
            )
            end = datetime.now()
            logger2.info("================reconstruct_encrypted_data\n")

            logger2.info(f"**Reconstructed value process took: {end - start}")

            logger2.info("Reconstructed data for {sensitive_column}")
        else:
            df_reconstructed = df_reconstructed.withColumn(
                f"enc_vals_{sensitive_column}", lit("")
            )
    start = datetime.now()
    df_cleansed = remove_row_indexes(df_reconstructed)
    end = datetime.now()
    logger2.info("================remove_row_indexes\n")
    logger2.info(f"**Removed row index columns process took: {end - start}")

    start = datetime.now()
    write_df_to_s3_csv_bz2(args, df_cleansed, logger2)
    logger2.info("File is copied to S3 using Spark Native Writer")
    end = datetime.now()
    logger2.info(f"**Spark Transformation and File is written to S3 process took: {end - start}")


def add_row_indexes(
    df: DataFrame,
    row_index_column_name: str = "enc_row_index",
) -> DataFrame:
    """
    Adds unique row IDs.

    Example input:
    | id | comments1 | notes  |
    |----|-----------|--------|
    | 1  | text1     | Note A |
    | 2  | text2     | Note B |

    Example output (ids are unique and increasing, but not necessarily consecutive —
    values jump between Spark partitions):
    | id | comments1 | notes  | enc_row_index |
    |----|-----------|--------|----------------|
    | 1  | text1     | Note A | 0             |
    | 2  | text2     | Note B | 8589934592    |

    Returns:
        DataFrame: DataFrame with enc_row_index.
    """
    # monotonically_increasing_id() is assigned per partition with no shuffle, so it
    # avoids the single-partition global sort that row_number() over an unpartitioned
    # window requires. The id is unique and increases with row order, which is all the
    # downstream joins and the final orderBy need — the values are sparse, not 0..N-1.
    # NOTE: the id is only stable while the DataFrame is cached; callers must keep the
    # cache in place because the joins rely on the same value appearing on both sides.
    return df.withColumn(row_index_column_name, monotonically_increasing_id())


def detect_sensitive_data(args, spark: SparkSession, df: DataFrame, column_to_check, contract_column_regex, logger2):
    """Detect potential credit card numbers in `column_to_check` using a Spark-SQL
    regex extraction (fast, JVM-side) followed by Python UDFs that apply BIN +
    Luhn validation and locate match positions in the original text.

    Returns a DataFrame with the same columns as the input plus:
      - enc_detected_values            : array<string>  (validated card values)
      - enc_detected_values_position   : array<string>  (e.g. "13-32")
    """
    # Parse S3 ingest file path
    bin_path = args["bin_file_path"]

    logger2.info(f"BIN Path: {bin_path}")

    # Load and broadcast the BIN list once on the driver.
    bin_lookup = load_bins_from_s3(bin_path, logger2)
    bc_bin_set = spark.sparkContext.broadcast(bin_lookup)

    initial_df = df.select(column_to_check, "enc_row_index")
    final_df = initial_df.withColumn("orig_text", col(column_to_check))
    
    logger2.info("preprocess completed")
    logger2.info(
        f"Number of partitions after preprocess completed: {final_df.rdd.getNumPartitions()}"
    )

    default_column_regex = r"(?<!\d)0*([1-9](?:[\s.\-_]?\d){10,18})(?=\D|$)"
    final_regex = contract_column_regex or default_column_regex 


    # 1) Extract candidate card-number-shaped substrings with native Spark DataFrame API
    #    Pattern allows optional leading zeros and \s . - _ as separators between digits.
    final_df = final_df.withColumn(
        "card_candidates",
        transform(
            regexp_extract_all(col("orig_text"), lit(final_regex), lit(1)),
            lambda x: x
        )
    )

    # 2) Strip separators so BIN/Luhn checks see digits only.
    final_df = final_df.withColumn(
        "cleaned_card_candidates",
        expr(r"transform(card_candidates, x -> regexp_replace(x, r'[\s\-\._]', ''))"),
    )

    # 3) Per-candidate validation: keeps the existing `bin_validation` (which
    #    internally calls `luhn_algorithm`). UDF returns parallel boolean array.
    def check_all_bins(card_list):
        if not card_list:
            return []
        result = []
        for card in card_list:
            try:
                result.append(bin_validation(card, logger2, bc_bin_set.value))
            except (ValueError, TypeError):
                result.append(False)
        return result

    check_all_bins_udf = udf(check_all_bins, ArrayType(BooleanType()))

    final_df = final_df.withColumn(
        "valid_card", check_all_bins_udf(col("cleaned_card_candidates"))
    )

    # 4) Keep only candidates that passed validation, in the same order.
    final_df = final_df.withColumn(
        "filtered_matches",
        expr(
            """
            filter(
                zip_with(
                    card_candidates,
                    valid_card,
                    (match, is_valid) -> IF(is_valid, match, NULL)
                ),
                x -> x IS NOT NULL
            )
            """
        ),
    )

    # 5) Locate each surviving match within the original text using sequential
    #    str.find — replaces the previous extract_clean_digits/finditer logic.
    def find_positions(text, matches):  # PRAGMA: no cover
        """Return ["<start>-<end>", ...] for each match in `matches` against `text`.

        Walks left-to-right with a moving cursor so duplicates yield distinct
        positions. Skipping a match (idx == -1) is tolerated.
        """
        if not matches:
            return []
        positions = []
        start = 0  # 0-based index
        for m in matches:
            idx = text.find(m, start)  # Python str.find is 0-based
            if idx == -1:
                continue
            positions.append(f"{idx}-{idx + len(m)}")
            start = idx + len(m)  # advance past this match
        return positions

    find_positions_udf = udf(find_positions, ArrayType(StringType()))

    final_df = final_df.withColumn(
        "filtered_positions", find_positions_udf("orig_text", "filtered_matches")
    )

    # 6) Bundle into the same struct the downstream code expects.
    final_df = final_df.withColumn(
        "detection_result",
        struct(
            col("filtered_matches").alias("enc_detected_values"),
            col("filtered_positions").alias("enc_detected_values_position"),
        ),
    )

    logger2.info(
        f"Number of partitions after regex: {final_df.rdd.getNumPartitions()}"
    )

    # Extract the individual fields from the struct
    final_df = final_df.withColumn(
        "enc_detected_values",
        col("detection_result.enc_detected_values"),
    )
    final_df = final_df.withColumn(
        "enc_detected_values_position",
        col("detection_result.enc_detected_values_position"),
    )

    # Drop working columns; preserve original column under its incoming name.
    final_df = final_df.drop(
        "orig_text",
        "card_candidates",
        "cleaned_card_candidates",
        "valid_card",
        "filtered_matches",
        "filtered_positions",
        "detection_result",
    )

    logger2.info("Sensitive data detection completed")

    return final_df


def load_bins_from_s3(bin_path, logger2):
    s3 = boto3.client("s3")
    # Split the S3 URL (e.g. "s3://my-bucket/path/to/bins.csv") into bucket and key.
    parsed = urlparse(bin_path)
    bucket_name = parsed.netloc
    key = parsed.path.lstrip("/")
    try:
        response = s3.get_object(Bucket=bucket_name, Key=key)
        lines = response["Body"].read().decode("utf-8").splitlines()
        bin_set = set(line.strip() for line in lines[1:] if line.strip().isdigit())
        logger2.info(f"Loaded BINS from S3: {bin_set}")
        return bin_set
    except Exception as e:
        logger2.exception(f"Error loading BIN list from S3://{bucket_name}/{key}: {e}")
        return set()



def bin_validation(card_number: str, logger2, bin_set: set) -> bool:
    """
    Analyze text using Regex.
    Args:
        card_number (str): The credit card to validate.
        bin_set (set): The BIN set from spark broadcasted values
    Returns:
        bool: True if the card number is valid, False otherwise.
    """
    try:
        # Basic checks
        if not (12 <= len(card_number) <= 19):
            logger2.error("Invalid length")
            return False
            
        if not card_number.isdigit():
            logger2.error("Non-digit characters in this card")
            return False
            
        bin_prefix = card_number[:6]
        if bin_prefix not in bin_set:
            # logger2.error(f"BIN not found: {bin_prefix}")
            return False
            
        # Call your Luhn function
        return luhn_algorithm(card_number, logger2)
    except Exception as e:
        logger2.error("BIN validation error")
        return False


def luhn_algorithm(card_number: str, logger2) -> bool:
    """
    Validate a credit card number using the Luhn algorithm.
    
    Args:
        card_number (str): The credit card number to validate.
    Returns:
        bool: True if the card number is valid, False otherwise.
    """
    try:
        digits = [int(d) for d in card_number]
        checksum = 0
        odd_digits = digits[-1::-2]
        even_digits = digits[-2::-2]
        checksum += sum(odd_digits)
        for d in even_digits:
            checksum += sum(divmod(d * 2, 10))
        return checksum % 10 == 0
    except ValueError as e:
        logger2.error("Invalid card number format for Luhn algorithm")
        return False
    except Exception as e:
        logger2.error("Unexpected error in Luhn algorithm")
        return False


def has_enc_detected_values(df):
    return (
        df.filter(
            (~isnull(col("enc_detected_values"))) &
            (size(col("enc_detected_values")) > 0)
        )
        .limit(1)
        .count() > 0
    )


# Using mapPartitions for distributed processing
def encrypt_dataframe_mappartitions(
    args,
    logger2,
    spark: SparkSession,
    df: DataFrame,
    transformation: str,
    headers,
    encryption_api_url: str,
    domain_id: str,
    dataset: str,
    datasource: str,
    sensitive_column: str,
    chunk_size: int = 1000,
    detected_values_col_name: str = "enc_detected_values",
    row_index_col_name: str = "enc_row_index",
    index_pos_col_name: str = "enc_detected_values_position",
    array_item_col_name: str = "enc_array_item_index",
    encrypted_values_col_name: str = "enc_encrypted_values"
) -> DataFrame:
    """
    This function uses mapPartitions for distributed processing.
    Each partition will be processed independently in parallel.
    
    
    Args:
        spark: SparkSession
        df: DataFrame with values to encrypt
        transformation: Type of transformation to apply
        headers: Vault-compatible request headers, no authentication. SigV4 auth
            headers are added per request inside encryption_api.
        encryption_api_url: URL for encryption API
        domain_id: Domain ID
        dataset: Dataset name
        datasource: Data source name
        sensitive_column: Column containing sensitive text
        chunk_size: Number of records to process in each chunk
        detected_values_col_name: Column name for detected values
        row_index_col_name: Column name for row index
        index_pos_col_name: Column name for position information
        array_item_col_name: Column name for array item index
        encrypted_values_col_name: Column name for encrypted values
        
    Returns:
        DataFrame: Result dataframe with encrypted values in new column
    """
    
    # Add chunk_id for processing
    # Repartition by chunk_id to ensure each partition contains complete chunks
    # This ensures that each partition processes complete chunks
    
    logger2.info("Repartitioning dataframe")
    
    # Method 2: Use repartition to ensure all rows with same chunk_id are in same partition
    num_chunks = df.select("chunk_id").distinct().count()
    
    if num_chunks < 100:
        # If fewer than 80 chunks, use the actual number of chunks
        partitioned_df = df.repartition(num_chunks, "chunk_id")
    else:
        # If 100 or more chunks, cap the partitions at 100 to minimize the API calls
        partitioned_df = df.repartition(100, "chunk_id")
    
    # Cached in the distributed memory across executors
    partitioned_df.cache()
    partitioned_df.count()
    
    num_partitions1 = partitioned_df.rdd.getNumPartitions()
    logger2.warning(f"{sensitive_column}: Number of partitions after cached: {num_partitions1}")
    
    # Define schema for the encrypted rows
    schema = StructType([
        # LongType: monotonically_increasing_id() encodes the partition index in the
        # high bits, so values exceed Int32 for any partition beyond the first.
        StructField(row_index_col_name, LongType(), True),
        StructField("value", StringType(), True),
        StructField(array_item_col_name, IntegerType(), True),
        StructField(index_pos_col_name, StringType(), True),
        StructField(sensitive_column, StringType(), True),
        StructField(encrypted_values_col_name, StringType(), True)
    ])
    
    # Define function to process each partition. mapPartitions gives you an iterator over the rows in a partition
    def process_partition(iterator):
       # Define function to process each partition. mapPartitions gives you an iterator over the rows in a partition.
        
        task_context = TaskContext.get()
        task_id = task_context.taskAttemptId()
        partition_id = task_context.partitionId()

        # Group rows by chunk_id
        chunk_groups = {}
        for row in iterator:
            chunk_id = row['chunk_id']
            if chunk_id not in chunk_groups:
                chunk_groups[chunk_id] = []
            chunk_groups[chunk_id].append(row)
        # Logging each partition should process one or more chunks
        logger2.warning(f"**{sensitive_column}: this partition{partition_id} assigned to spark task:{task_id} processes chunk_id: {list(chunk_groups.keys())} \n")
        
        # Process each chunk
        all_results = []
        for chunk_id, rows in chunk_groups.items():
            try:
                batch_input_metadata = []
                api_input_payload = []
                
                for row in rows:
                    batch_input_metadata.append({
                        row_index_col_name: row[row_index_col_name],
                        array_item_col_name: row[array_item_col_name],
                        "value": row["value"],
                        index_pos_col_name: row[index_pos_col_name],
                        sensitive_column: row[sensitive_column]
                    })
                    
                    api_input_payload.append(
                        row["value"]
                    )
                          
                payload = {
                    "transformationType": transformation,
                    "domainId": domain_id,
                    "dataSetName": dataset,
                    "dataSourceName": datasource,
                    "values": api_input_payload
                }
                
                # Make API call
                base_url = encryption_api_url.rstrip("/")
                url = f"{base_url}/transform/encrypt"
                logger2.warning(f"**{sensitive_column}: Making API call to {url} for chunk_id {chunk_id} to process {len(api_input_payload)} credit cards\n")
                
                # encryption_api signs this request with the Glue job role's
                # credentials on this executor before sending it.
                response = encryption_api(url, headers, payload, logger2)
                
                # The retry delays will be:
                # j=0: 6 (2^0) = 6 seconds + jitter
                # j=1: 6 (2^1) = 12 seconds + jitter
                # j=2: 6 (2^2) = 24 seconds + jitter
                # j=3: 6 (2^3) = 48 seconds + jitter
                # j=4: 6 (2^4) = 96 seconds + jitter
                if response.status_code == 200:
                    
                    try:
                        response_json = response.json()

                     # Process and pair results
                        for meta, result in zip(
                            batch_input_metadata,
                            response_json["encryptedData"]["data"]["batch_results"]
                        ):
                            meta[encrypted_values_col_name] = result
                            all_results.append(meta)
                    except (json.JSONDecodeError, ValueError) as e:
                        logger2.exception("JSON decode error")
                        raise
                # Retryable server errors — exponential backoff with jitter, capped.
                elif response.status_code in (500, 502, 503, 504):
                    base_delay = 6
                    max_delay = 96
                    max_retries = 5

                    for i in range(max_retries):
                        # Exponential backoff: 6, 12, 24, 48, 96 (capped at max_delay).
                        chunk_delay = min(base_delay * (2 ** i), max_delay)
                        # Add small random component to avoid synchronized calls.
                        jitter = random.uniform(1, 5)
                        total_delay = chunk_delay + jitter
                        logger2.warning(
                            f"**{sensitive_column}: Vault server error {response.status_code} for chunk_id {chunk_id}, "
                            f"retry attempt {i+1}/{max_retries} in {total_delay:.1f}s"
                        )

                        time.sleep(total_delay)
                        # Re-signed on each attempt: a SigV4 signature is only
                        # valid for a few minutes and the backoff can exceed that.
                        response = encryption_api(url, headers, payload, logger2)

                        if response.status_code == 200:
                            logger2.warning(f"**{sensitive_column}: Retry {i+1}/{max_retries} successful for chunk_id {chunk_id}\n")
                            try:
                                response_json = response.json()
                                for meta, result in zip(
                                    batch_input_metadata,
                                    response_json["encryptedData"]["data"]["batch_results"]
                                ):
                                    meta[encrypted_values_col_name] = result
                                    all_results.append(meta)
                                break
                            except (json.JSONDecodeError, ValueError) as e:
                                logger2.exception("JSON decode error")
                                raise
                        elif i == max_retries - 1:
                            logger2.error(f"**{sensitive_column}: API call failed with status {response.status_code} for chunk_id {chunk_id} "
                                          f"after {max_retries} retries")
                            raise Exception(f"API returned status {response.status_code} for chunk_id {chunk_id} after {max_retries} retries\n")
                        else:
                            logger2.warning(f"**{sensitive_column}: Retry {i+1}/{max_retries} failed with status {response.status_code} "
                                            f"for chunk_id {chunk_id}, continuing...")
                # Retryable client errors (timeout / rate limit) — backoff with jitter, capped.
                elif response.status_code in (408, 429):
                    base_delay = 6
                    max_delay = 96
                    max_retries = 5

                    for i in range(max_retries):
                        # Exponential backoff: 6, 12, 24, 48, 96 (capped at max_delay).
                        chunk_delay = min(base_delay * (2 ** i), max_delay)
                        # Add small random component to avoid synchronized calls.
                        jitter = random.uniform(1, 5)
                        total_delay = chunk_delay + jitter
                        logger2.warning(
                            f"**{sensitive_column}: Vault rate limit ({response.status_code}) for chunk_id {chunk_id}, "
                            f"retry attempt {i+1}/{max_retries} in {total_delay:.1f}s\n"
                        )

                        time.sleep(total_delay)
                        # Re-signed on each attempt: a SigV4 signature is only
                        # valid for a few minutes and the backoff can exceed that.
                        response = encryption_api(url, headers, payload, logger2)

                        if response.status_code == 200:
                            logger2.warning(f"**{sensitive_column}: Retry {i+1}/{max_retries} successful for chunk_id {chunk_id}\n")
                            try:
                                response_json = response.json()
                                for meta, result in zip(
                                    batch_input_metadata,
                                    response_json["encryptedData"]["data"]["batch_results"]
                                ):
                                    meta[encrypted_values_col_name] = result
                                    all_results.append(meta)
                                break
                            except (json.JSONDecodeError, ValueError) as e:
                                logger2.exception("JSON decode error")
                                raise
                        elif i == max_retries - 1:
                            logger2.error(f"**{sensitive_column}: API call failed with status {response.status_code} for chunk_id {chunk_id} "
                                          f"after {max_retries} retries")
                            raise Exception(f"API returned {response.status_code} for chunk_id {chunk_id} after {max_retries} retries\n")
                        else:
                            logger2.warning(f"**{sensitive_column}: Retry {i+1}/{max_retries} failed with status {response.status_code} "
                                            f"for chunk_id {chunk_id}, continuing...")
                # Non-retryable errors — fail fast. Under AWS_IAM authorization a
                # 403 means the request was unsigned, signed for the wrong
                # region, arrived from an unexpected VPC endpoint, or the Glue
                # role lacks execute-api:Invoke. Retrying will not fix any of
                # those, so surface the failure.
                else:
                    logger2.error(f"**{sensitive_column}: API call failed with non-retryable status {response.status_code}\n")
                    raise Exception(f"API returned {response.status_code} for other error codes for chunk_id {chunk_id}\n")
                
            except Exception as e:
                logger2.error(f"Error processing chunk_id {chunk_id}")
                raise
    
        return all_results
    
    # Apply the function to each partition (partition of rows) for distributed processing
    encrypted_rdd = partitioned_df.rdd.mapPartitions(process_partition).collect()

    partitioned_df.unpersist()

    # Construct dataframe
    encrypted_df = spark.createDataFrame(encrypted_rdd, schema)

    # Transform and aggregate the results
    encrypted_result_df = (
        encrypted_df.orderBy(row_index_col_name, array_item_col_name)
        .groupBy(row_index_col_name)
        .agg(
            collect_list("value").alias(detected_values_col_name),
            collect_list(encrypted_values_col_name).alias(encrypted_values_col_name),
            collect_list(index_pos_col_name).alias(index_pos_col_name),
            first(col(sensitive_column)).alias(sensitive_column)
        )
    )

    return encrypted_result_df


def merge_encrypted_with_original(
    df_encrypted: DataFrame,
    df_original: DataFrame,
    sensitive_column: str,
    id_column: str = "enc_row_index",
) -> DataFrame:
    """
    Merges encrypted data with the original DataFrame, ensuring all rows are preserved.
    
    Args:
        df_encrypted (DataFrame): Rows with detected/encrypted sensitive values.
        df_original (DataFrame): Full original dataset.
        sensitive_column (str): Name of the column that holds sensitive data (e.g., "CNum").
        id_column (str): Name of the join column (default: "enc_row_index").
    
    Returns:
        DataFrame: Merged DataFrame with full data + empty values where encryption didn't apply.
    """
    
    encrypted_col = "enc_encrypted_values"
    
    # Left anti join to find missing rows (no sensitive match)
    df_missing = df_original.join(
        df_encrypted.select(id_column), on=id_column, how="left_anti"
    )
    
    # Add placeholder with empty array<string> for encrypted values
    empty_array = array().cast(ArrayType(StringType()))
    df_missing_filled = df_missing.withColumn(encrypted_col, empty_array)
    
    # Ensure column alignment for union
    columns_to_keep = df_original.columns + [encrypted_col]
    df_encrypted_aligned = df_encrypted.select(
        *[col for col in columns_to_keep if col in df_encrypted.columns]
    )
    
    # Union the two
    df_merged = df_encrypted_aligned.unionByName(
        df_missing_filled.select(*df_encrypted_aligned.columns)
    )
    
    return df_merged

def replace_encrypted_values_in_dataframe(
    df: DataFrame, sensitive_column: str
) -> DataFrame:
    """
    Replaces sensitive values with encrypted values and adds enc_enc_vals_<sensitive_column>.
    
    Example output:
    
    | enc_row_index | comments1_updated                    | enc_enc_vals_comments1        |
    |----------------|--------------------------------------|--------------------------------|
    | 0              | XXX 4444-3333-2222-1111 AND...       | [4444-3333-2222-1111, ...]     |
    
    Returns:
        DataFrame: updated sensitive_column + encrypted summary column.
    """
    
    encrypted_vals_col = f"enc_vals_{sensitive_column}"
    return (
        df.withColumn(
            sensitive_column,
            replace_sensitive_data_udf(
                col(sensitive_column),
                col("enc_detected_values_position"),
                col("enc_encrypted_values"),
            ),
        )
        .withColumn(encrypted_vals_col, col("enc_encrypted_values"))
        .select("enc_row_index", sensitive_column, encrypted_vals_col)
    )



def replace_sensitive_data(original_text, positions, encrypted_values):
    """
    Replaces substrings at positions with encrypted values.

    Example:
        original_text = "XXX 1234-1234-1234-1234 XXX"
        positions = ["4-23"]
        encrypted_values = ["4321-4321-4321-4321"]

        output: "XXX 4321-4321-4321-4321 XXX"

    Returns:
        str: updated string.
    """
    if not original_text or not positions or not encrypted_values:
        return original_text
    replacements = sorted(
        zip([tuple(map(int, p.split('-'))) for p in positions], encrypted_values),
        key=lambda x: x[0][0], reverse=True
    )
    for (start, end), enc_value in replacements:
        original_text = original_text[:start] + enc_value + original_text[end:]
    return original_text


replace_sensitive_data_udf = udf(replace_sensitive_data, StringType())


def reconstruct_encrypted_data(
    df_original: DataFrame, df_encrypted: DataFrame, column_name: str
) -> DataFrame:
    """
    Merges encrypted values back into original DataFrame.

    Example output:

    | enc_row_index | comments1              | enc_enc_vals_comments1          |
    |----------------|------------------------|----------------------------------|
    | 0              | XXX 4444-3333-2222-1111 AND... | 4444-3333-2222-1111|5555...  |

    Returns:
        DataFrame: merged DataFrame.
    """
    encrypted_col_temp = f"{column_name}_encrypted_temp"
    encrypted_vals_col = f"enc_vals_{column_name}"
    encrypted_vals_temp = f"{encrypted_vals_col}_temp"

    df_encrypted_renamed = df_encrypted.withColumnRenamed(
        column_name, encrypted_col_temp
    ).withColumnRenamed(encrypted_vals_col, encrypted_vals_temp)

    df_joined = df_original.join(
        df_encrypted_renamed.select(
            "enc_row_index", encrypted_col_temp, encrypted_vals_temp
        ),
        on="enc_row_index",
        how="left",
    )

    return (
        df_joined.withColumn(column_name, col(encrypted_col_temp))
        .withColumn(
            encrypted_vals_col,
            when(size(col(encrypted_vals_temp)) == 0, lit("")).otherwise(
                concat_ws("|", col(encrypted_vals_temp))
            ),
        )
        .drop(encrypted_col_temp, encrypted_vals_temp)
    )


def remove_row_indexes(df: DataFrame) -> DataFrame:
    """
    Removes the 'enc_row_index' column from the DataFrame.

    Example input:

    | id | comments1 | notes  | enc_row_index |
    |----|-----------|--------|----------------|
    | 1  | text1     | Note A | 0              |
    | 2  | text2     | Note B | 1              |

    Example output:

    | id | comments1 | notes  |
    |----|-----------|--------|
    | 1  | text1     | Note A |
    | 2  | text2     | Note B |

    Args:
        df (DataFrame): Input DataFrame containing 'enc_row_index' column.

    Returns:
        DataFrame: DataFrame without 'enc_row_index' column.
    """
    df = df.orderBy(col("enc_row_index")).drop("enc_row_index")
    return df


def write_df_to_s3_csv_bz2(args, df: DataFrame, logger2) -> None:
    """
    Write a DataFrame to S3 as a bz2-compressed CSV, preserving folder structure
    and placing the output in an "encrypted" subfolder next to the ingest file.

    Args:
        df (DataFrame): PySpark DataFrame to write
        args (dict): Dictionary containing keys:
            - "ingest_file" (str): full S3 URI to input file
            - "SourceBucketName" (str): bucket name
    """
    # Parse S3 ingest file path
    ##ingest_path = args["ingest_file"]
    ingest_path = args["source_key"]
    bucket_name = args["source_bucket"]
    parsed = urlparse(ingest_path)

    # Extract key path
    full_key_path = parsed.path.lstrip("/")  # remove leading slash
    path_parts = full_key_path.split("/")
    file_name = path_parts[-1]
    parent_path = "/".join(path_parts[:-1])
    encrypted_key = f"s3://{bucket_name}/{parent_path}/encrypted/{file_name}"
    logger2.info(f"Encryption key: {encrypted_key}")

    try:
        df.coalesce(1) \
            .write.format("csv") \
            .option("header", "true") \
            .option("compression", "bzip2") \
            .mode("overwrite") \
            .save(encrypted_key)

        logger2.info(f"Successfully wrote Dataframe to {encrypted_key}")

    except Exception as e:
        logger2.exception("An exception occurred")

    logger2.info(f"📦 File uploaded to s3://{bucket_name}/{encrypted_key}")