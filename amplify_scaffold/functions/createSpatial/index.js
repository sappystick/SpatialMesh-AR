const AWS = require('aws-sdk');
const dynamoDB = new AWS.DynamoDB.DocumentClient();
const { v4: uuidv4 } = require('uuid');

const TABLE_NAME = process.env.SPATIAL_TABLE_NAME;
const REGION = process.env.AWS_REGION;

AWS.config.update({ region: REGION });

const createResponse = (statusCode, body) => ({
  statusCode,
  headers: {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Credentials': true,
  },
  body: JSON.stringify(body),
});

const validateInput = (data) => {
  if (!data.userId || !data.position || !data.metadata) {
    throw new Error('Missing required fields: userId, position, metadata');
  }

  if (!data.position.x || !data.position.y || !data.position.z) {
    throw new Error('Position must include x, y, z coordinates');
  }

  if (typeof data.qualityScore !== 'number' || data.qualityScore < 0 || data.qualityScore > 1) {
    throw new Error('Quality score must be a number between 0 and 1');
  }
};

exports.handler = async (event) => {
  console.log('createSpatial invoked with event:', JSON.stringify(event));

  try {
    const requestBody = JSON.parse(event.body);
    validateInput(requestBody);

    const timestamp = new Date().toISOString();
    const anchorId = uuidv4();

    const item = {
      anchorId,
      userId: requestBody.userId,
      position: requestBody.position,
      rotation: requestBody.rotation || { x: 0, y: 0, z: 0 },
      metadata: requestBody.metadata,
      qualityScore: requestBody.qualityScore,
      createdAt: timestamp,
      updatedAt: timestamp,
      isPersistent: requestBody.isPersistent || true,
      sharedWith: requestBody.sharedWith || [],
      earnings: 0,
      status: 'active',
      version: 1,
    };

    const params = {
      TableName: TABLE_NAME,
      Item: item,
      ConditionExpression: 'attribute_not_exists(anchorId)',
    };

    await dynamoDB.put(params).promise();

    // Create GSI entry for user-based queries
    const userIndexParams = {
      TableName: TABLE_NAME,
      Item: {
        userId: requestBody.userId,
        anchorId,
        createdAt: timestamp,
        status: 'active',
      },
    };

    await dynamoDB.put(userIndexParams).promise();

    // Publish to SNS for real-time updates (if configured)
    if (process.env.SNS_TOPIC_ARN) {
      const sns = new AWS.SNS();
      await sns.publish({
        TopicArn: process.env.SNS_TOPIC_ARN,
        Message: JSON.stringify({
          type: 'SPATIAL_ANCHOR_CREATED',
          data: item,
        }),
      }).promise();
    }

    // Log metrics
    const cloudwatch = new AWS.CloudWatch();
    await cloudwatch.putMetricData({
      Namespace: 'SpatialMesh/Anchors',
      MetricData: [
        {
          MetricName: 'AnchorCreated',
          Value: 1,
          Unit: 'Count',
          Dimensions: [
            {
              Name: 'UserId',
              Value: requestBody.userId,
            },
            {
              Name: 'QualityScore',
              Value: requestBody.qualityScore.toString(),
            },
          ],
        },
      ],
    }).promise();

    return createResponse(201, {
      status: 'success',
      message: 'Spatial anchor created successfully',
      data: {
        anchorId,
        userId: requestBody.userId,
        createdAt: timestamp,
      },
    });

  } catch (error) {
    console.error('Error creating spatial anchor:', error);

    if (error.name === 'ValidationError') {
      return createResponse(400, {
        status: 'error',
        message: error.message,
        code: 'VALIDATION_ERROR',
      });
    }

    if (error.code === 'ConditionalCheckFailedException') {
      return createResponse(409, {
        status: 'error',
        message: 'Anchor ID already exists',
        code: 'DUPLICATE_ERROR',
      });
    }

    // Log error to CloudWatch
    const cloudwatch = new AWS.CloudWatch();
    await cloudwatch.putMetricData({
      Namespace: 'SpatialMesh/Errors',
      MetricData: [
        {
          MetricName: 'CreateSpatialAnchorError',
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
