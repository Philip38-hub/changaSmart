# Infrastructure -- AWS SAM

Minimal, cheap-to-run infrastructure for the ChangaSmart scaffold:

```
API Gateway (HTTP API)  ->  Lambda (FastAPI via Mangum)  ->  Strands Agent  ->  Amazon Bedrock
```

Deliberately excluded for this scaffold: DynamoDB, VPC, custom domains,
authentication. Storage is in-memory inside the Lambda function. **Verified
via `sam local start-api`: state does not persist between separate
requests at all** (each gets its own container there), and real deployed
Lambda offers no stronger guarantee -- this infrastructure exists to prove
the request path end-to-end, not to be production-ready.

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

> **Local Python version mismatch:** `sam build` needs a `python3.12`
> binary on `PATH` matching the Lambda runtime. If your local Python is a
> different version (e.g. 3.13), that plain `sam build` will fail with a
> `PythonPipBuilder:Validation` error -- use `sam build --use-container`
> instead (or `make sam-build-container` from the repo root), which builds
> inside Docker's official `public.ecr.aws/sam/build-python3.12` image
> regardless of your local Python version. The first run pulls that image
> (a few hundred MB); subsequent builds reuse the cached image and are
> fast.

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
| `AgentMode` | `bedrock` | `bedrock` uses the real agent; `mock` simulates decisions deterministically with zero Bedrock calls (e.g. `sam deploy --parameter-overrides AgentMode=mock` to deploy without needing Bedrock quota/access) |

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
