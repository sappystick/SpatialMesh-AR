const AWS = require('aws-sdk');
const dynamoDB = new AWS.DynamoDB.DocumentClient();

const EARNINGS_TABLE = process.env.EARNINGS_TABLE_NAME;
const TRANSACTIONS_TABLE = process.env.TRANSACTIONS_TABLE_NAME;
const MIN_TRANSACTION_AMOUNT = 0.01;
const MAX_TRANSACTION_AMOUNT = 1000.00;

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
  if (!data.userId || !data.amount || !data.type || !data.contributionId) {
    throw new Error('Missing required fields: userId, amount, type, contributionId');
  }

  const amount = parseFloat(data.amount);
  if (isNaN(amount) || amount < MIN_TRANSACTION_AMOUNT || amount > MAX_TRANSACTION_AMOUNT) {
    throw new Error(`Amount must be between ${MIN_TRANSACTION_AMOUNT} and ${MAX_TRANSACTION_AMOUNT}`);
  }

  return {
    ...data,
    amount,
  };
};

const updateEarningsAtomic = async (userId, amount, type) => {
  const params = {
    TableName: EARNINGS_TABLE,
    Key: { userId },
    UpdateExpression: `
      SET totalEarnings = if_not_exists(totalEarnings, :zero) + :amount,
          pendingEarnings = if_not_exists(pendingEarnings, :zero) + :amount,
          contributionCount = if_not_exists(contributionCount, :zero) + :one,
          lastUpdated = :now,
          earningsByType.#type = if_not_exists(earningsByType.#type, :zero) + :amount,
          contributionsByType.#type = if_not_exists(contributionsByType.#type, :zero) + :one
    `,
    ExpressionAttributeNames: {
      '#type': type,
    },
    ExpressionAttributeValues: {
      ':amount': amount,
      ':zero': 0,
      ':one': 1,
      ':now': new Date().toISOString(),
    },
    ReturnValues: 'ALL_NEW',
  };

  return await dynamoDB.update(params).promise();
};

const createTransaction = async (data) => {
  const transaction = {
    transactionId: `tx_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
    userId: data.userId,
    amount: data.amount,
    type: data.type,
    contributionId: data.contributionId,
    timestamp: new Date().toISOString(),
    status: 'completed',
    metadata: data.metadata || {},
  };

  const params = {
    TableName: TRANSACTIONS_TABLE,
    Item: transaction,
    ConditionExpression: 'attribute_not_exists(transactionId)',
  };

  await dynamoDB.put(params).promise();
  return transaction;
};

exports.handler = async (event) => {
  console.log('putEarnings invoked with event:', JSON.stringify(event));

  const transaction = { id: null, amount: 0 };

  try {
    // Validate request
    const data = validateInput(JSON.parse(event.body));
    
    // Start transaction
    const dynamoTransact = new AWS.DynamoDB.DocumentClient({ params: { ReturnConsumedCapacity: 'TOTAL' } });
    
    // Update earnings atomically
    const updatedEarnings = await updateEarningsAtomic(data.userId, data.amount, data.type);

    // Create transaction record
    const newTransaction = await createTransaction(data);
    transaction.id = newTransaction.transactionId;
    transaction.amount = newTransaction.amount;

    // Publish event to SNS if configured
    if (process.env.SNS_TOPIC_ARN) {
      const sns = new AWS.SNS();
      await sns.publish({
        TopicArn: process.env.SNS_TOPIC_ARN,
        Message: JSON.stringify({
          type: 'EARNINGS_UPDATED',
          data: {
            userId: data.userId,
            transaction: newTransaction,
            newBalance: updatedEarnings.Attributes.totalEarnings,
          },
        }),
      }).promise();
    }

    // Log metrics
    const cloudwatch = new AWS.CloudWatch();
    await cloudwatch.putMetricData({
      Namespace: 'SpatialMesh/Earnings',
      MetricData: [
        {
          MetricName: 'EarningsRecorded',
          Value: data.amount,
          Unit: 'None',
          Dimensions: [
            {
              Name: 'UserId',
              Value: data.userId,
            },
            {
              Name: 'Type',
              Value: data.type,
            },
          ],
        },
      ],
    }).promise();

    return createResponse(200, {
      status: 'success',
      message: 'Earnings updated successfully',
      data: {
        transactionId: newTransaction.transactionId,
        userId: data.userId,
        amount: data.amount,
        newTotalEarnings: updatedEarnings.Attributes.totalEarnings,
        newPendingEarnings: updatedEarnings.Attributes.pendingEarnings,
      },
    });

  } catch (error) {
    console.error('Error updating earnings:', error);

    // Log failed transaction for reconciliation if partial update occurred
    if (transaction.id) {
      const reconciliationParams = {
        TableName: process.env.RECONCILIATION_TABLE_NAME,
        Item: {
          transactionId: transaction.id,
          amount: transaction.amount,
          error: error.message,
          timestamp: new Date().toISOString(),
        },
      };
      
      try {
        await dynamoDB.put(reconciliationParams).promise();
      } catch (reconciliationError) {
        console.error('Failed to log failed transaction:', reconciliationError);
      }
    }

    if (error.name === 'ValidationError') {
      return createResponse(400, {
        status: 'error',
        message: error.message,
        code: 'VALIDATION_ERROR',
      });
    }

    // Log error to CloudWatch
    const cloudwatch = new AWS.CloudWatch();
    await cloudwatch.putMetricData({
      Namespace: 'SpatialMesh/Errors',
      MetricData: [
        {
          MetricName: 'PutEarningsError',
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
