import ydb
import os
import json

YDB_ENDPOINT = os.getenv('YDB_ENDPOINT')
YDB_DATABASE = os.getenv('YDB_DATABASE') 

def get_all_docs():
    driver = ydb.Driver(
        endpoint=YDB_ENDPOINT,
        database=YDB_DATABASE,
        credentials=ydb.iam.MetadataUrlCredentials()
    )

    docs = []

    try:
        driver.wait(fail_fast=True, timeout=5)

        session = driver.table_client.session().create()

        query = """
            SELECT 
                id,
                name,
                url
            FROM docs;
        """

        result = session.transaction().execute(query, commit_tx=True)

        for row in result[0].rows:
            docs.append({
                "id": str(row.id),
                "name": row.name,
                "url": row.url
                })

    except Exception as e:
        print(f'Ошибка при выполнении запроса к базе данных: {e}')

    finally:
        driver.stop()
        
        return docs

def handler(event, context):
    docs = get_all_docs()

    return {
        "statusCode": 200,
        "body": docs,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
        }
    }