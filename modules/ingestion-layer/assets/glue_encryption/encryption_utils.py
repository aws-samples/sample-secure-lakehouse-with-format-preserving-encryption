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
    pandas_udf,
    isnull,
    regexp_extract_all,
    regexp_instr,
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
    MapType,
    BooleanType
)

from functools import reduce
import boto3
import logging
from datetime import datetime
import time
import json
import re
import requests
from requests.auth import HTTPBasicAuth
from typing import List, Dict, Any
import pandas as pd
from urllib.parse import urlparse
import random

# Vault-compatible HTTP headers for API Gateway request format.
# These are informational only — the encryption_api Lambda logs them
# but does not validate them. Security is enforced by VPC endpoint restriction.
VAULT_NAMESPACE = "root"
VAULT_TOKEN = "demo-placeholder-not-a-real-token"  # noqa: S105 - intentional placeholder


logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)



def encryption_api(url: str, headers: dict, payload: dict, logger2):
    """This function takes in the headers and payload from a tenant and forwards the request to encryption api endpoint. Note url should have path specified e.g. /encrypt"""
    try:
        # logger2.error(f"Received following inputs; url: {url}, headers: {headers}, payload: {payload}")
        response = requests.post(url, headers=headers, json=payload, timeout=60, verify=True)

        #ERROR, WARNING and Print will be logged in glue error log for Executor logs (which run inside mappartition() functions.
        #INFO logs will not be logged for Executor logs (which run inside mappartition() functions.
        # traceid = headers.get("X-B3-TraceId", "N/A")
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

    |enc_detected_values                         |enc_row_index|enc_detected_values_position|
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

    for sensitive_column in sensitive_columns:
        logger2.info(f"Processing sensitive column: {sensitive_column}")

        #Fake header
        headers = build_headers()

        start = datetime.now()
        df_detected = detect_sensitive_data(
            args, spark, df_reconstructed, sensitive_column, logger2
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
            # Add chunk_id for distributed processing
            chunked_df = add_chunk_id(exploded_df, chunk_size=15000)
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
    logger2.info(f"File is copied to S3 using Spark Native Writer")
    end = datetime.now()
    logger2.info(f"**Spark Transformation and File is written to S3 process took: {end - start}")


def add_row_indexes(
    df: DataFrame,
    order_column_name: str = "enc_order_id",
    row_index_column_name: str = "enc_row_index",

) -> DataFrame:
    """
    Adds unique row IDs.

    Example input:
    | id | comments1 | notes  |
    |----|-----------|--------|
    | 1  | text1     | Note A |
    | 2  | text2     | Note B |

    Example output:
    | id | comments1 | notes  | enc_row_index |
    |----|-----------|--------|----------------|
    | 1  | text1     | Note A | 0             |
    | 2  | text2     | Note B | 1             |

    Returns:
        DataFrame: DataFrame with enc_row_index.
    """
    df_with_order = df.withColumn(order_column_name, monotonically_increasing_id())
    window = Window.orderBy(order_column_name)
    return (
        df_with_order.withColumn("_row_number_int", row_number().over(window) - 1)
        .withColumn(row_index_column_name, col("_row_number_int"))
        .drop("_row_number_int")
        .drop(order_column_name)
    )


def detect_sensitive_data(args, spark: SparkSession, df: DataFrame, column_to_check, logger2):
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

    # Narrow the DataFrame and stash the original text so we can locate
    # match positions later against the unmodified column value.
    initial_df = df.select(column_to_check, "enc_row_index")
    final_df = initial_df.withColumn("orig_text", col(column_to_check))
    #final_df.show(20,truncate=False)
    logger2.info("preprocess completed")
    logger2.info(
        f"Number of partitions after preprocess completed: {final_df.rdd.getNumPartitions()}"
    )

    # 1) Extract candidate card-number-shaped substrings with native Spark SQL.
    #    Pattern allows optional leading zeros and \s . - _ as separators between digits.
    final_df = final_df.withColumn(
        "card_candidates",
        expr(
            r"""
            transform(
                regexp_extract_all(orig_text, r'(?<!\d)0*([1-9](?:[\s.\-_]?\d){10,18})(?=\D|$)', 1),
                x -> x
            )
            """
        ),
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

    #final_df.show(20,truncate=False)

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


# More optimized version using mapPartitions for distributed processing
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
    
    Glue worker log will be available in Error Logs(Stderr) not Output Logs(stdout), including Exceptions, Stack traces and Failed Spark stages in distributed tasks.
    Suggest to use print() inside mapPartitions as it is more efficient than making log-back appender that sends logs over the network back to driver, which is error-prone.
    The function named process_partition can be run on all executors when you process a data frame, so the print will stay on executor and sent to Error Logs.
    The driver isn't the one running the code so it can't be logged to.
    
    Args:
        spark: SparkSession
        df: DataFrame with values to encrypt
        transformation: Type of transformation to apply
        headers: HTTP headers for API call
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
        StructField(row_index_col_name, IntegerType(), True),
        StructField("value", StringType(), True),
        StructField(array_item_col_name, IntegerType(), True),
        StructField(index_pos_col_name, StringType(), True),
        StructField(sensitive_column, StringType(), True),
        StructField(encrypted_values_col_name, StringType(), True)
    ])
    
    # Store the current headers in an outer scope
    current_headers = headers
    
    # Define function to process each partition. mapPartitions gives you an iterator over the rows in a partition
    def process_partition(iterator):
         # Define function to process each partition. mapPartitions gives you an iterator over the rows in a partition.
        # import traceback
        # from pyspark import TaskContext
        # import random
        
        task_context = TaskContext.get()
        task_id = task_context.taskAttemptId()
        partition_id = task_context.partitionId()
        # For inner function to access variable from outer function
        nonlocal current_headers
        
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
                
                # Create API payload
                # now = datetime.utcnow()
                # request_time = now.strftime("%d/%b/%Y:%H:%M:%S +0000")
                # request_time_epoch = int(time.mktime(now.timetuple())) * 1000
                
                payload = {
                    "transformationType": transformation,
                    "domainId": domain_id,
                    "dataSetName": dataset,
                    "dataSourceName": datasource,
                    "values": api_input_payload
                }
                
                # Make API call
                base_url = args["vault_api_url"].rstrip("/")
                url = f"{base_url}/transform/encrypt"
                logger2.warning(f"**{sensitive_column}: Making API call to {url} for chunk_id {chunk_id} to process {len(api_input_payload)} credit cards\n")
                
                # current_headers can be either the original headers or new_headers after a token refresh for error 401 within the same partition
                response = encryption_api(url, current_headers, payload, logger2)
                
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
                elif response.status_code == 504:
                    # 60 seconds between chunks in the same partition
                    base_delay = 6
                    max_retries = 5
                    # old_traceid = traceid
                    
                    for i in range(max_retries):
                        # Calculate exponential backoff delay: 6, 12, 24, 48, 96
                        chunk_delay = base_delay * (2 ** i)
                        # Add small random component to avoid synchronized calls
                        jitter = random.uniform(1, 5)
                        total_delay = chunk_delay + jitter
                        logger2.warning(
                            f"**{sensitive_column}: We have reached API Mesh timeout errors for chunk_id {chunk_id}, retry attempt {i+1}/{max_retries}."
                        )
                        
                        # Apply the delay  
                        time.sleep(total_delay)
                        response = encryption_api(url, current_headers, payload, logger2)
                    
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
                    else:
                        # If this was the last retry attempt
                        if i == max_retries - 1:
                            logger2.error(f"**{sensitive_column}: API call failed with status {response.status_code} for chunk_id {chunk_id} "
                                          f"after {{max_retries}}")
                            raise Exception(f"API returned status {response.status_code} for chunk_id {chunk_id} after {max_retries} retries\n")
                                        
                        else:
                            logger2.warning(f"**{sensitive_column}: Retry {i+1}/{max_retries} failed with status {response.status_code} "
                                            f"for chunk_id {chunk_id}, continuing...")
                elif response.status_code in (429, 502):
                    # 60 seconds between chunks in the same partition
                    base_delay = 6
                    max_retries = 5
                    # old_traceid = traceid
                    
                    for i in range(max_retries):
                        # Calculate exponential backoff delay: 6, 12, 24, 48, 96
                        chunk_delay = base_delay * (2 ** i)
                        # Add small random component to avoid synchronized calls
                        jitter = random.uniform(1, 5)
                        total_delay = chunk_delay + jitter
                        logger2.warning(
                            f"**{sensitive_column}: We have received Vault Transform Engine Rate Limit for chunk_id {{chunk_id}}, retry attempt {{i+1}}/{{max_retries}}."
                            f"**Will retry again in {chunk_delay + jitter} seconds\n"
                        )
                        
                        # Apply the delay
                        time.sleep(total_delay)
                        response = encryption_api(url, current_headers, payload, logger2)

                        if response.status_code == 200:
                           logger2.warning(f"***[sensitive_column]: Retry {i+1}/{max_retries} successful for chunk_id {chunk_id}\n")

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
                        else:
                            # If this was the last retry attempt
                            if i == max_retries - 1:
                                logger2.error(f"***[sensitive_column]: API call failed with status {response.status_code} for chunk {chunk_id} "
                                              f"after {max_retries} retry attempts")
                                raise Exception(f"API returned {response.status_code} from partition for chunk_id {chunk_id} after {max_retries} retries\n")
                            else:
                                logger2.warning(f"***[sensitive_column]: Retry {i+1}/{max_retries} failed with status {response.status_code} "
                                f"for chunk_id {chunk_id}, continuing...")
                else:
                    logger2.error(f"***[sensitive_column]: API call failed with status {response.status_code}\n")
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


# def write_df_to_s3_csv_bz2_pandas(args, df: DataFrame, logger2) -> None:
#     """
#     Write a DataFrame to S3 as a bz2-compressed CSV, preserving folder structure
#     and placing the output in an "encrypted" subfolder next to the ingest file.

#     Args:
#         df (DataFrame): PySpark DataFrame to write
#         args (dict): Dictionary containing keys:
#             - "ingest_file" (str): full S3 URI to input file
#             - "SourceBucketName" (str): bucket name
#     """
#     # Convert to pandas and write to local bz2 file
#     try:
#         local_file = "/tmp/encrypted_output.csv.bz2"
#         pdf = df.toPandas()
#         pdf.to_csv(local_file, index=False, compression="bz2")

#         # Parse S3 ingest file path
#         ingest_path = args["ingest_file"]
#         bucket_name = args["source_bucket"]
#         parsed = urlparse(ingest_path)

#         # Extract key path
#         full_key_path = parsed.path.lstrip("/")  # remove leading slash
#         path_parts = full_key_path.split("/")
#         file_name = path_parts[-1]
#         parent_path = "/".join(path_parts[:-1])
#         encrypted_key = f"{parent_path}/encrypted/{file_name}"

#         # Upload to S3
#         s3 = boto3.client("s3")
#         s3.upload_file(local_file, bucket_name, encrypted_key)

#         logger2.info(f"📦 File uploaded to s3://{bucket_name}/{encrypted_key}")

#     except Exception as e:
#         logger2.exception("An exception occurred using pandas to write")
#         raise


def write_df_to_s3_csv_bz2(args, df: DataFrame, logger2) -> None:
    """
    Write a DataFrame to S3 as a bz2-compressed CSV, preserving folder structure
    and placing the output in an "encrypted" subfolder next to the ingest file.
    Update from write_df_to_s3_csv_bz2_pandas to write_df_to_s3_csv_bz2
    as the Pandas Spark action has the performance issue for large file size(3.5 GB+) based on the Load T

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
        # df1 = df.coalesce(1)
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