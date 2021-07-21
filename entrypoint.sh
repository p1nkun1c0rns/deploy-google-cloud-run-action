#!/bin/bash

if [ "$INPUT_DEBUG" = "true" ]; then
  echo "=== gcloud version ==="
  gcloud version
  echo "======================"
fi

function enableDebug() {
  if [ "$INPUT_DEBUG" = "true" ]; then
    set -x
  fi
}

function disableDebug() {
  set +x
}

set -e
set -o pipefail

echo "$INPUT_SERVICE_ACCOUNT_KEY" | base64 -d >key.json
trap "{ rm -f key.json; }" EXIT

enableDebug
gcloud auth activate-service-account --key-file=key.json --project="$INPUT_PROJECT_ID"
disableDebug

IMAGE_TAG="latest"
if [ -n "$INPUT_IMAGE_TAG" ]; then
  IMAGE_TAG="$INPUT_IMAGE_TAG"
elif [ -n "$INPUT_IMAGE_TAG_PATTERN" ]; then
  # read image tags from registry, grep by pattern and sort for the latest
  enableDebug
  IMAGE_TAG=$(gcloud container images list-tags "$INPUT_IMAGE_NAME" --format json | jq -r '.[].tags | .[]' | grep -E "^${INPUT_IMAGE_TAG_PATTERN}" | sort -V | tail -n 1)
  disableDebug
fi

FQ_IMAGE="${INPUT_IMAGE_NAME}:${IMAGE_TAG}"
REVISION_SUFFIX=v$(echo "$IMAGE_TAG" | sed "s;\.;-;g")-t$(date +%s)

echo "Deploying $FQ_IMAGE as service $INPUT_SERVICE_NAME to $INPUT_GCP_REGION in revision $REVISION_SUFFIX."

# turn off globbing
set -f
# split on new line
IFS='
'
ENV_VARS=""
# write all env starting with SET_ENV_ to ENV_VARS in form KEY1=VAL1,KEY2=VAL2
for e in $(env | grep SET_ENV_); do
  if [ -n "$ENV_VARS" ]; then
    ENV_VARS="${ENV_VARS},"
  fi
  ENV_VARS="${ENV_VARS}${e/SET_ENV_/}"
done

if [ -n "$ENV_VARS" ]; then
  ENV_VARS="--set-env-vars=${ENV_VARS}"
else
  ENV_VARS="--clear-env-vars"
fi

SECRETS=""
# write all env values starting with SET_SECRET_ to form ENV_VALUE1,ENV_VALUE2
for s in $(env | grep SET_SECRET_); do
  if [ -n "$SECRETS" ]; then
    SECRETS="${SECRETS},"
  fi
  SECRETS="${SECRETS}${s#*=}"
done

if [ -n "$SECRETS" ]; then
  SECRETS="--set-secrets=${SECRETS}"
else
 SECRETS="--clear-secrets"
fi

ALLOW_UNAUTHENTICATED=""
if [ "$INPUT_ALLOW_UNAUTHENTICATED" = "true" ]; then
  ALLOW_UNAUTHENTICATED="--allow-unauthenticated"
fi

SERVICE_ACCOUNT=""
if [ "$INPUT_SERVICE_ACCOUNT" != "default" ]; then
  SERVICE_ACCOUNT="--service-account=$INPUT_SERVICE_ACCOUNT"
fi

NO_TRAFFIC=""
if [ "$INPUT_NO_TRAFFIC" = "true" ]; then
  NO_TRAFFIC="--no-traffic"
fi

CLOUDSQL_INSTANCES="--clear-cloudsql-instances"
if [ -n "$INPUT_CLOUDSQL_INSTANCES" ]; then
  CLOUDSQL_INSTANCES="--set-cloudsql-instances=$INPUT_CLOUDSQL_INSTANCES"
fi

VPC_CONNECTOR="--clear-vpc-connector"
if [ -n "$INPUT_VPC_CONNECTOR" ]; then
  VPC_CONNECTOR="--vpc-connector=$INPUT_VPC_CONNECTOR"
fi

enableDebug
gcloud beta run deploy "$INPUT_SERVICE_NAME" \
  --platform="managed" \
  --region="$INPUT_GCP_REGION" \
  --image="$FQ_IMAGE" \
  --concurrency="$INPUT_CONCURRENCY_PER_INSTANCE" \
  --cpu="$INPUT_CPU" \
  --max-instances="$INPUT_MAX_INSTANCES" \
  --min-instances="$INPUT_MIN_INSTANCES" \
  --memory="$INPUT_MEMORY" \
  --timeout="$INPUT_REQUEST_TIMEOUT" \
  --revision-suffix="$REVISION_SUFFIX" \
  $ALLOW_UNAUTHENTICATED \
  $SERVICE_ACCOUNT \
  $NO_TRAFFIC \
  $CLOUDSQL_INSTANCES \
  $VPC_CONNECTOR \
  $ENV_VARS \
  $SECRETS \
  2>&1 | tee gcloud.log
disableDebug

ENDPOINT=$(cat gcloud.log | grep -o 'Service URL: .*')

echo ::set-output name=gcloud_log::"<pre>$(sed ':a;N;$!ba;s/\n/<br>/g' gcloud.log)</pre>"
echo ::set-output name=cloud_run_revision::"${INPUT_SERVICE_NAME}-${REVISION_SUFFIX}"
echo ::set-output name=cloud_run_endpoint::"${ENDPOINT/Service URL: /}"
echo ::set-output name=deployed_image_tag::"${IMAGE_TAG}"
