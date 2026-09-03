# Infrastructure -- AWS SAM

Minimal, cheap-to-run infrastructure for the ChangaSmart scaffold:

```
API Gateway (HTTP API)  ->  Lambda (FastAPI via Mangum)  ->  Strands Agent  ->  Amazon Bedrock
```

Deliberately excluded for this scaffold: DynamoDB, VPC, custom domains,
authentication. Storage is in-memory inside the Lambda function, so state
does **not** persist across cold starts or across concurrent invocations --
this infrastructure exists to prove the request path end-to-end, not to be
production-ready.

## Prerequisites

* [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html)
* AWS credentials configured (`aws configure` or environment variables)
* Bedrock model access enabled for `amazon.nova-micro-v1:0` (or your chosen
  model) in the target region/account, via the Bedrock console's "Model
  access" page

## Deploy

```bash
cd infrastructure/aws
sam build
sam deploy
```

`sam build` picks up `backend/requirements.txt` automatically (see
`CodeUri: ../../backend` in `template.yaml`) and installs dependencies for
the Lambda runtime.

The first `sam deploy` will prompt for confirmation of the change set
(disable with `--no-confirm-changeset` once you trust the pipeline).
Defaults (stack name, region, parameters) live in `samconfig.toml`.

## What gets created

* One Lambda function (`changasmart-<stage>`) running the FastAPI app
* One API Gateway HTTP API, proxying all routes to the Lambda
* One IAM policy scoped to `bedrock:InvokeModel` /
  `bedrock:InvokeModelWithResponseStream` on exactly the configured model
  ARN -- not a wildcard Bedrock grant
* One CloudWatch Log Group with 14-day retention

## Configuration

| Parameter | Default | Notes |
|---|---|---|
| `BedrockModelId` | `amazon.nova-micro-v1:0` | Also controls the IAM policy's resource ARN |
| `Stage` | `dev` | API Gateway stage name |

`AWS_REGION` is set automatically by the Lambda runtime and is not
configurable via the template (it's a reserved Lambda environment
variable).

## After deploying

```bash
curl https://<ApiUrl output>/health
```

## Tear down

```bash
sam delete
```
