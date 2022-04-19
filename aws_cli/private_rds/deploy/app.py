import sys
import logging
import json
import rds_config
import rds_host
import pymysql
#rds settings
rds_host_uri = rds_host.uri_string
name = rds_config.db_username
password = rds_config.db_password
db_name = rds_config.db_name

logger = logging.getLogger()
logger.setLevel(logging.INFO)

try:
    conn = pymysql.connect(host=rds_host_uri, user=name, passwd=password, db=db_name, connect_timeout=5)
except pymysql.MySQLError as e:
    logger.error("ERROR: Unexpected error: Could not connect to MySQL instance.")
    logger.error(e)
    sys.exit()

logger.info("SUCCESS: Connection to RDS MySQL instance succeeded")
def handler(event, context):
    print("event:")
    print(event)
    print("context:")
    print(context.__dict__)
    """
    This function fetches content from MySQL RDS instance
    """
    
    users = []
    user = {}
    body = ""
    if(event['httpMethod'] == 'POST'):
        jsonBody = json.loads(event["body"])
        email = jsonBody['email']
        password = jsonBody['password']
        if len(email.strip()) > 0 and len(password.strip()) > 0:
            print(email)
            print(password)
            with conn.cursor() as cur:
                user_insert_query = """INSERT INTO User ( email, password )
                                VALUES ( %s, %s );"""
                record = (email, password)
                cur.execute(user_insert_query, record)
            conn.commit()
    
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM User;")
        
        for row in cur:
            logger.info(row)
            #print(row[0])
            #print(row[1])
            #print(row[2])
            user['email'] = row[1]
            user['password'] = row[2]
            users.append(user.copy())
    
    return {
        'statusCode': 200,
        'headers': {
            #'Access-Control-Allow-Origin': '*',
            #'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            #'Access-Control-Allow-Credentials': 'true',
            'Content-Type': 'application/json'
        },
        'body': json.dumps(users)
    }
