
import logging, os, json
from azure.cosmos import CosmosClient
from azure.storage.blob import BlobServiceClient
from datetime import datetime, timedelta

def main(mytimer):
    cosmos = CosmosClient(os.environ["COSMOS_URI"], os.environ["COSMOS_KEY"])
    db = cosmos.get_database_client(os.environ["COSMOS_DB_NAME"])
    container = db.get_container_client(os.environ["COSMOS_CONTAINER"])
    
    blob_service = BlobServiceClient(account_url=f"https://{os.environ['BLOB_ACCOUNT_NAME']}.blob.core.windows.net", credential=None)
    blob_container = blob_service.get_container_client(os.environ["BLOB_CONTAINER"])

    cutoff = datetime.utcnow() - timedelta(days=int(os.environ["ARCHIVE_DAYS"]))
    query = f"SELECT * FROM c WHERE c.timestamp < '{cutoff.isoformat()}'"
    
    for item in container.query_items(query=query, enable_cross_partition_query=True):
        blob_name = f"{item['id']}.json"
        blob_container.upload_blob(name=blob_name, data=json.dumps(item), overwrite=True)
        archived = {
            "id": item["id"],
            "archived": True,
            "blob_uri": f"https://{os.environ['BLOB_ACCOUNT_NAME']}.blob.core.windows.net/{os.environ['BLOB_CONTAINER']}/{blob_name}",
            "summary": item.get("summary", ""),
            "timestamp": item["timestamp"]
        }
        container.upsert_item(archived)
