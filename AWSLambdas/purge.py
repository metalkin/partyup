"""
Scan through the Samples table for oldish items and either favorite them or purge them
"""
import logging
import json
import boto3
import time
import uuid
from decimal import Decimal
from boto3.dynamodb.types import Binary
from boto3.dynamodb.conditions import Key, Attr

logger = logging.getLogger()
logger.setLevel(logging.DEBUG)

basic_bucket = 'com.sandcastleapps.partyup'
standard_lifetime = 172800
standard_prefix = 'media'
favorite_lifetime = 2505600
favorite_prefix = 'favorite'
favorite_count_max = 4

def purge_sample(sample, vote_table, samples_batch, votes_batch):
    samples_batch.delete_item(Key={'event' : sample['event'], 'id': sample['id']})
    sample_identity =  Binary(sample['id'].value + bytearray(sample['event'], "utf_8"))
    sample_key = Key('sample').eq(sample_identity)

    response = vote_table.query(KeyConditionExpression=sample_key)

    for item in response['Items']:
        votes_batch.delete_item(Key={'sample' : item['sample'], 'user': item['user']})

        while 'LastEvaluatedKey' in response:
            response = query(KeyConditionExpression=sample_key, ExclusiveStartKey=response['LastEvaluatedKey'])

            for item in response['Items']:
                votes_batch.delete_item(Key={'sample' : item['sample'], 'user': item['user']})

def favorite_sample(sample, sample_table, s3):
    if 'prefix' not in sample:
        id_bytes = sample['id'].value
        id_unique = str(uuid.UUID(bytes=id_bytes[0:16])).upper()
        id_count = ord(id_bytes[16])
        
        try:
            video = s3.Object(basic_bucket, favorite_prefix + '/' + id_unique + str(id_count) + '.mp4')
            video.copy_from(CopySource={'Bucket': basic_bucket, 'Key': standard_prefix + '/' + id_unique + str(id_count) + '.mp4'}, StorageClass='REDUCED_REDUNDANCY')
            sample_table.update_item(Key={'event' : sample['event'], 'id': sample['id']}, UpdateExpression="set prefix=:f", ExpressionAttributeValues={':f': favorite_prefix})
        except:
            logger.exception("Favorite failure")

def process_sample(sample, vote_table, samples_batch, votes_batch, s3, candidates):
    purge = sample
    
    if sample['time'] >= time.time()-favorite_lifetime:
        rating = sample['ups'] - sample['downs']
        if rating >= 0:
            candidate_list = candidates.get(sample['event'], [])
            sample['rating'] = rating
            if len(candidate_list) >= favorite_count_max:
                index,value = min(enumerate(candidate_list), key=lambda x: x[1]['rating'])
                if value['rating'] < rating or (value['rating'] == rating and value['time'] < sample['time']):
                    purge = value
                    candidate_list[index] = sample
            else:
                purge = None
                candidates[sample['event']] = candidate_list + [sample]

    if purge:
        purge_sample(purge, vote_table, samples_batch, votes_batch)


def purge_handler(event, context):
    dynamodb = boto3.resource('dynamodb')
    s3 = boto3.resource('s3')

    sample_table = dynamodb.Table('Samples')
    vote_table = dynamodb.Table('Votes')

    candidates = dict()

    filter = (Attr('time').lte(Decimal(time.time()-standard_lifetime)) & Attr('prefix').not_exists()) | Attr('prefix').eq(favorite_prefix)

    with sample_table.batch_writer() as samples_batch, vote_table.batch_writer() as votes_batch:
        response = sample_table.scan(FilterExpression=filter)

        for item in response['Items']:
            process_sample(item, vote_table, samples_batch, votes_batch, s3, candidates)

        while 'LastEvaluatedKey' in response:
            response = scan(FilterExpression=filter, ExclusiveStartKey=response['LastEvaluatedKey'])

            for item in response['Items']:
                process_sample(item, vote_table, samples_batch, votes_batch, s3, candidates)

    for venue_candidates in candidates.itervalues():
        for candidate in venue_candidates:
            favorite_sample(candidate, sample_table, s3)