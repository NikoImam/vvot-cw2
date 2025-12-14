import boto3
import ydb
import os
import requests
import uuid
import json

YDB_ENDPOINT = os.getenv('YDB_ENDPOINT')
YDB_DATABASE = os.getenv('YDB_DATABASE')
AWS_ACCESS_KEY_ID = os.getenv('AWS_ACCESS_KEY_ID')
AWS_SECRET_ACCESS_KEY = os.getenv('AWS_SECRET_ACCESS_KEY')
BUCKET_NAME = os.getenv('BUCKET_NAME')
ZONE = os.getenv('ZONE')

def upload_to_bucket(name: str, url: str) -> uuid.UUID:
    s3_client = boto3.client(
        service_name='s3',
        endpoint_url='https://storage.yandexcloud.net',
        region_name=ZONE,
        aws_access_key_id=AWS_ACCESS_KEY_ID,
        aws_secret_access_key=AWS_SECRET_ACCESS_KEY
    )

    id = uuid.uuid4()

    obj_key = f'docs/{id}'

    with requests.get(url=url, stream=True, timeout=20) as response:
        response.raise_for_status()

        s3_client.upload_fileobj(
            response.raw,
            BUCKET_NAME,
            obj_key,
            ExtraArgs={
                'ContentType': response.headers.get('Content-Type'),
                'ContentDisposition': f'attachment; filename="{name}"'
            }
        )
        
    return id
    
def add_to_db(id, name, url):
    driver = ydb.Driver(
        endpoint=YDB_ENDPOINT,
        database=YDB_DATABASE,
        credentials=ydb.iam.MetadataUrlCredentials()
    )

    try:
        driver.wait(fail_fast=True, timeout=5)

        session = driver.table_client.session().create()

        query = """
            DECLARE $id AS Uuid;
            DECLARE $name as Utf8;
            DECLARE $url as Utf8;

            UPSERT INTO docs (id, name, url)
            VALUES ($id, $name, $url);
        """

        params = {
            '$id': id,
            '$name': name,
            '$url': url
        }

        prepared_query = session.prepare(query)
        session.transaction().execute(
            prepared_query,
            params,
            commit_tx=True
        )

    except Exception as e:
        print(f'Ошибка при выполнении запроса к базе данных: {e}')

    finally:
        driver.stop()

def handler(event, context):
    for msg in event['messages']:
        body = json.loads(msg['details']['message']['body'])
        name = body.get('name')
        url = body.get('url')

        if name == None or url == None:
            return {"statusCode": 200}

        try:
            id = upload_to_bucket(name, url)
            add_to_db(id, name, url)

        except:
            return {"statusCode": 200}