const AWS = require('aws-sdk');
const dynamoDB = new AWS.DynamoDB.DocumentClient();

const EARNINGS_TABLE = process.env.EARNINGS_TABLE_NAME;
const TRANSACTIONS_TABLE = process.env.TRANSACTIONS_TABLE_NAME;
const MAX_TRANSACTIONS = 50;

const createResponse = (statusCode, body) => ({
  statusCode,
  headers: {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Credentials': true,
  },
  body: JSON.stringify(body),
});

const getEarningsData = async (userId) => {
  const params = {
    TableName: EARNINGS_TABLE,
    Key: { userId },
  };

  const result = await dynamoDB.get(params).promise();
  return result.Item || {
    userId,
    totalEarnings: 0,
    totalPaid: 0,
    pendingEarnings: 0,
    earningsByType: {},
    lastUpdated: new Date().toISOString(),
    contributionCount: 0,
    averageQualityScore: 0,
    contributionsByType: {},
  };
};

const getRecentTransactions = async (userId, lastEvaluatedKey = null) => {
  const params = {
    TableName: TRANSACTIONS_TABLE,
    KeyConditionExpression: 'userId = :userId',
    ExpressionAttributeValues: {
      ':userId': userId,
      ':cutoffDate': new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString(), // Last 30 days
    },
    FilterExpression: 'transactionDate > :cutoffDate',
    Limit: MAX_TRANSACTIONS,
    ScanIndexForward: false, // Sort descending by date
  };

  if (lastEvaluatedKey) {
    params.ExclusiveStartKey = JSON.parse(Buffer.from(lastEvaluatedKey, 'base64').toString());
  }

  return await dynamoDB.query(params).promise();
};

const calculateEarningStats = (transactions) => {
  const now = new Date();
  const stats = {
    dailyEarnings: 0,
    weeklyEarnings: 0,
    monthlyEarnings: 0,
    earningTrend: [],
  };

  transactions.forEach(tx => {
    const txDate = new Date(tx.timestamp);
    const daysDiff = (now - txDate) / (1000 * 60 * 60 * 24);

    if (daysDiff < 1) stats.dailyEarnings += tx.amount;
    if (daysDiff < 7) stats.weeklyEarnings += tx.amount;
    if (daysDiff < 30) stats.monthlyEarnings += tx.amount;
  });

  // Calculate daily earning trend for the last 7 days
  const last7Days = Array.from({ length: 7 }, (_, i) => {
    const date = new Date(now);
    date.setDate(date.getDate() - i);
    return date.toISOString().split('T')[0];
  });

  stats.earningTrend = last7Days.map(date => ({
    date,
    earnings: transactions
      .filter(tx => tx.timestamp.startsWith(date))
      .reduce((sum, tx) => sum + tx.amount, 0),
  }));

  return stats;
};

exports.handler = async (event) => {
  console.log('getEarnings invoked with event:', JSON.stringify(event));

  try {
    const userId = event.pathParameters?.userId;
    if (!userId) {
      return createResponse(400, {
        status: 'error',
        message: 'userId is required',
        code: 'MISSING_USER_ID',
      });
    }

    // Get basic earnings data
    const earningsData = await getEarningsData(userId);

    // Get recent transactions with pagination
    const queryParams = event.queryStringParameters || {};
    const transactionsResult = await getRecentTransactions(userId, queryParams.nextToken);

    // Calculate additional statistics
    const stats = calculateEarningStats(transactionsResult.Items);

    // Create next token for pagination
    let nextToken = null;
    if (transactionsResult.LastEvaluatedKey) {
      nextToken = Buffer.from(JSON.stringify(transactionsResult.LastEvaluatedKey)).toString('base64');
    }

    // Log metrics
    const cloudwatch = new AWS.CloudWatch();
    await cloudwatch.putMetricData({
      Namespace: 'SpatialMesh/Earnings',
      MetricData: [
        {
          MetricName: 'UserEarningsQueried',
          Value: 1,
          Unit: 'Count',
          Dimensions: [
            {
              Name: 'UserId',
              Value: userId,
            },
          ],
        },
        {
          MetricName: 'TotalUserEarnings',
          Value: earningsData.totalEarnings,
          Unit: 'None',
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
        ...earningsData,
        recentTransactions: transactionsResult.Items,
        transactionCount: transactionsResult.Count,
        nextToken,
        stats,
      },
    });

  } catch (error) {
    console.error('Error fetching earnings:', error);

    // Log error to CloudWatch
    const cloudwatch = new AWS.CloudWatch();
    await cloudwatch.putMetricData({
      Namespace: 'SpatialMesh/Errors',
      MetricData: [
        {
          MetricName: 'GetEarningsError',
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
