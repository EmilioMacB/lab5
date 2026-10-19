import json

def handler(event, context):
    records = event.get('Records', [])
    print(f"Recibidos {len(records)} eventos desde SQS.")
    
    for record in records:
        try:
            body = json.loads(record['body'])
            print(f"Evento procesado: {body}")
        except Exception as e:
            print(f"Error parseando mensaje: {e}")
            continue

    return {
        'statusCode': 200,
        'body': json.dumps({'status': 'processed', 'records_count': len(records)})
    }