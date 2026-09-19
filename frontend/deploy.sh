#!/bin/bash
set -e

# Move to the terraform directory to fetch outputs
cd "$(dirname "$0")/../terraform/app"
APP_ID=$(terraform output -raw amplify_app_id)
BRANCH_NAME=$(terraform output -raw amplify_branch_name)
AWS_REGION=$(terraform output -raw cognito_region) # インフラと同期させるためTerraformから取得
USER_POOL_ID=$(terraform output -raw cognito_user_pool_id)
CLIENT_ID=$(terraform output -raw cognito_client_id)
API_ENDPOINT=$(terraform output -raw api_endpoint)
cd ../../frontend

echo "Updating .env.local from Terraform outputs..."
cat <<EOF > .env.local
VITE_COGNITO_REGION=$AWS_REGION
VITE_COGNITO_USER_POOL_ID=$USER_POOL_ID
VITE_COGNITO_CLIENT_ID=$CLIENT_ID
VITE_API_BASE_URL=$API_ENDPOINT
EOF

echo "Deploying to Amplify App: $APP_ID (Branch: $BRANCH_NAME)"

# Get deployment info
COMMIT_HASH=$(git rev-parse HEAD)
DEPLOY_USER=$(git config user.name || echo "unknown")
echo "Commit: $COMMIT_HASH by $DEPLOY_USER"

# Build (Vite will inject VITE_COMMIT_HASH)
export VITE_COMMIT_HASH=$COMMIT_HASH
echo "Building the application..."
npm run build

# Zip artifacts
echo "Zipping build artifacts..."
rm -f build.zip
cd dist
zip -r ../build.zip . > /dev/null
cd ..

# Create deployment
echo "Creating deployment in AWS Amplify..."
CREATE_DEPLOYMENT_RES=$(aws amplify create-deployment --app-id "$APP_ID" --branch-name "$BRANCH_NAME" --output json)

# Extract jobId and zipUploadUrl using python
JOB_ID=$(echo "$CREATE_DEPLOYMENT_RES" | python3 -c "import sys, json; print(json.load(sys.stdin)['jobId'])")
UPLOAD_URL=$(echo "$CREATE_DEPLOYMENT_RES" | python3 -c "import sys, json; print(json.load(sys.stdin)['zipUploadUrl'])")

if [ -z "$JOB_ID" ] || [ -z "$UPLOAD_URL" ]; then
    echo "Error: Failed to extract jobId or zipUploadUrl"
    exit 1
fi

echo "Uploading build.zip to S3..."
curl -s -T build.zip "$UPLOAD_URL"

echo "Starting deployment (Job ID: $JOB_ID)..."
aws amplify start-deployment --app-id "$APP_ID" --branch-name "$BRANCH_NAME" --job-id "$JOB_ID" --output text

echo "Tagging Amplify branch with commit info..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
BRANCH_ARN="arn:aws:amplify:${AWS_REGION}:${AWS_ACCOUNT_ID}:apps/${APP_ID}/branches/${BRANCH_NAME}"

aws amplify tag-resource \
  --resource-arn "$BRANCH_ARN" \
  --tags "LastDeployCommit=$COMMIT_HASH,LastDeployUser=$DEPLOY_USER"

echo "Deployment submitted successfully!"
rm -f build.zip
