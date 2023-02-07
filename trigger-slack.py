import json
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
import boto3
#Create a SSM Client to access parameter store
ssm = boto3.client('ssm')
#define the function
def lambda_handler(event,context):
    #retrieve message from event when lamda is triggered from SNS
    print(json.dumps(event))
    
    message = event['Records'][int(0)]['Sns']['Message']
    print(message)
    
    '''
    Retrieve Json vriables from message
    AlarmName is the name of the cloudwatch alarm tht was set
    NewStateValue is the state of the alarm when lambda is triggered which means it has 
                gone from OK to Alarm
    NewStateReason is the reason for the change in state
    '''
    
    #Create format for slack message
    slack_message = {'text' : message}
    #retrieve webhook url from parameter store
    webhook_url = "https://hooks.slack.com/services/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"
    
    
    #make  request to the API
    
    req = Request(webhook_url,
                    json.dumps(slack_message).encode('utf-8'))
    
    try:
        response = urlopen(req)
        response.read()
        print("Messge posted to Slack")
    except HTTPError as e:
        print(f'Request failed: {e.code} {e.reason}')
    except URLError as e:
        print(f'Server Connection failed:  {e.reason}')