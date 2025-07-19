# Lambda Package Placeholder
# This directory contains the packaged Lambda functions
# Each .zip file contains the code for a specific Lambda function

# To build the packages, run:
# cd src/lambda/auth && zip -r ../../../terraform/modules/lambda/lambda-packages/auth.zip .
# cd src/lambda/notifications && zip -r ../../../terraform/modules/lambda/lambda-packages/notifications.zip .
# cd src/lambda/analytics && zip -r ../../../terraform/modules/lambda/lambda-packages/analytics.zip .
# cd src/lambda/certificates && zip -r ../../../terraform/modules/lambda/lambda-packages/certificates.zip .
# cd src/lambda/crud-api && zip -r ../../../terraform/modules/lambda/lambda-packages/crud-api.zip .
# cd src/lambda/webhooks && zip -r ../../../terraform/modules/lambda/lambda-packages/webhooks.zip .

# For now, create empty zip files as placeholders:
touch auth.zip notifications.zip analytics.zip certificates.zip crud-api.zip webhooks.zip
