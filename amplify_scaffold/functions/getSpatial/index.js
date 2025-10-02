const AWS = require('aws-sdk');
const dynamoDB = new AWS.DynamoDB.DocumentClient();

const TABLE_NAME = process.env.SPATIAL_TABLE_NAME;
const MAX_ITEMS = 50; // Maximum items per page

const createResponse = (statusCode, body) => ({
  statusCode,
  headers: {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Credentials': true,
  },
  body: JSON.stringify(body),
});

const validateQueryParams = (queryParams) => {
  const errors = [];

  if (queryParams.radius && isNaN(queryParams.radius)) {
    errors.push('radius must be a number');
  }

  if (queryParams.minQuality && (isNaN(queryParams.minQuality) || queryParams.minQuality < 0 || queryParams.minQuality > 1)) {
    errors.push('minQuality must be a number between 0 and 1');
  }

  if (errors.length > 0) {
    throw new Error(`Invalid query parameters: ${errors.join(', ')}`);
  }
};

const queryAnchorsInRadius = async (userId, center, radius) => {
  // Use DynamoDB's geohash-based querying for spatial queries
  const params = {
    TableName: TABLE_NAME,
    IndexName: 'GeohashIndex',
    KeyConditionExpression: 'userId = :userId',
    FilterExpression: 'distance_from_point(:lat, :lon) <= :radius',
    ExpressionAttributeValues: {
      ':userId': userId,
      ':lat': center.latitude,
      ':lon': center.longitude,
      ':radius': radius,
    },
  };

  const result = await dynamoDB.query(params).promise();
  return result.Items;
};

exports.handler = async (event) => {
  console.log('getSpatial invoked with event:', JSON.stringify(event));

  try {
    const userId = event.pathParameters?.userId;
    if (!userId) {
      return createResponse(400, {
        status: 'error',
        message: 'userId is required',
        code: 'MISSING_USER_ID',
      });
    }

    const queryParams = event.queryStringParameters || {};
    validateQueryParams(queryParams);

    let params = {
      TableName: TABLE_NAME,
      IndexName: 'UserIdIndex',
      KeyConditionExpression: 'userId = :userId',
      FilterExpression: 'status = :status',
      ExpressionAttributeValues: {
        ':userId': userId,
        ':status': 'active',
      },
      Limit: MAX_ITEMS,
    };

    // Add quality score filter if specified
    if (queryParams.minQuality) {
      params.FilterExpression += ' AND qualityScore >= :minQuality';
      params.ExpressionAttributeValues[':minQuality'] = parseFloat(queryParams.minQuality);
    }

    // Add pagination support
    if (queryParams.nextToken) {
      params.ExclusiveStartKey = JSON.parse(Buffer.from(queryParams.nextToken, 'base64').toString());
    }

    // Handle spatial queries if center and radius are provided
    if (queryParams.lat && queryParams.lon && queryParams.radius) {
      const anchors = await queryAnchorsInRadius(userId, {
        latitude: parseFloat(queryParams.lat),
        longitude: parseFloat(queryParams.lon),
      }, parseFloat(queryParams.radius));

      return createResponse(200, {
        status: 'success',
        data: {
          anchors,
          count: anchors.length,
        },
      });
    }

    // Regular query
    const result = await dynamoDB.query(params).promise();

    // Create next token for pagination
    let nextToken = null;
    if (result.LastEvaluatedKey) {
      nextToken = Buffer.from(JSON.stringify(result.LastEvaluatedKey)).toString('base64');
    }

    // Log metrics
    const cloudwatch = new AWS.CloudWatch();
    await cloudwatch.putMetricData({
      Namespace: 'SpatialMesh/Queries',
      MetricData: [
        {
          MetricName: 'AnchorsQueried',
          Value: result.Items.length,
          Unit: 'Count',
          Dimensions: [
            {
              Name: 'UserId',
              Value: userId,
            },
          ],
        },
      ],
    }).promise();

    return createResponse(200, {
      status: 'success',
      data: {
        anchors: result.Items,
        count: result.Items.length,
        nextToken,
      },
    });

  } catch (error) {
    console.error('Error querying spatial anchors:', error);

    if (error.message.includes('Invalid query parameters')) {
      return createResponse(400, {
        status: 'error',
        message: error.message,
        code: 'INVALID_PARAMETERS',
      });
    }

    // Log error to CloudWatch
    const cloudwatch = new AWS.CloudWatch();
    await cloudwatch.putMetricData({
      Namespace: 'SpatialMesh/Errors',
      MetricData: [
        {
          MetricName: 'GetSpatialAnchorsError',
          Value: 1,
          Unit: 'Count',
        },
      ],
    }).promise();

    return createResponse(500, {
      status: 'error',
      message: 'Internal server error',
      code: 'INTERNAL_ERROR',
      requestId: event.requestContext?.requestId,
    });
  }
};
