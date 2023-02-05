import json
import boto3

client = boto3.client('dynamodb')

def lambda_handler(event, context):
    # read the item
    data = client.get_item(
        TableName='cloud-resume-dynamodb-table',
        Key = {
            'DomainName': {
                'S': 'enzezhou'
            },
            'ID': {'S': 'id001'}
        }
    )
    #extract likes and do the incremntation
    count = data.get('Item').get('Visitors').get('N')
    count = int(count)+1
    
    #update likes
    update = client.update_item(
        TableName='cloud-resume-dynamodb-table',
        Key = {
            'DomainName': {'S': 'enzezhou'},
            'ID': {'S': 'id001'}
        },
        UpdateExpression='SET Visitors = :count',
        ExpressionAttributeValues={
            ':count': {'N':str(count)}
        }
    )

    #send a message
    response = {
      'statusCode': 200,
      'body': str(count),
      'headers': {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': 'enzezhou.com'
      },
    }
    return response;
