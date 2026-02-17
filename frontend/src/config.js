import { CognitoUserPool } from 'amazon-cognito-identity-js';

const poolData = {
  UserPoolId: import.meta.env.VITE_COGNITO_POOL_ID || '',
  ClientId: import.meta.env.VITE_COGNITO_CLIENT_ID || '',
};

export const userPool = new CognitoUserPool(poolData);
export const API_URL = import.meta.env.VITE_API_URL || '';
export const AWS_REGION = import.meta.env.VITE_AWS_REGION || 'us-east-1';
