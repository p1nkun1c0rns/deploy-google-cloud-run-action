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
REVISION_PREFIX="v$(echo "$IMAGE_TAG" | sed "s;\.;-;g")"
REVISION_DATE="-t$(date +%s)"

# Full service name must not exceed a length of 63 characters
SERVICE_NAME_LENGTH=${#INPUT_SERVICE_NAME}
REVISION_PREFIX_LENGTH=${#REVISION_PREFIX}
REVISION_DATE_LENGTH=${#REVISION_DATE}
COMPOSED_NAME_LENGTH=$(expr $SERVICE_NAME_LENGTH + $REVISION_PREFIX_LENGTH + $REVISION_DATE_LENGTH)

if [ $COMPOSED_NAME_LENGTH -gt 63 ]; then
  # revision_prefix will be shortened to have composed length in allowed range
  OVERFLOW_LENGTH=$(expr $COMPOSED_NAME_LENGTH - 63)
  STRIP_LENGTH=$(expr $REVISION_PREFIX_LENGTH - $OVERFLOW_LENGTH)
  if [[ $STRIP_LENGTH -lt 0 ]]; then
    echo "Service name to long, please shorten it, so that service + image tage are shorter than $(expr 63 - $REVISION_DATE_LENGTH) characters."
    exit 1
  else
    echo "Stripping $STRIP_LENGTH chars off from revision '$REVISION_PREFIX' as full service name must not exceed 63 characters."
  fi
  REVISION_PREFIX=${REVISION_PREFIX:0:$STRIP_LENGTH}
fi

REVISION_SUFFIX=${REVISION_PREFIX}${REVISION_DATE}

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

CLOUDSQL_INSTANCES="--clear-cloudsql-instances"
if [ -n "$INPUT_CLOUDSQL_INSTANCES" ]; then
  CLOUDSQL_INSTANCES="--set-cloudsql-instances=$INPUT_CLOUDSQL_INSTANCES"
fi

VPC_CONNECTOR="--clear-vpc-connector"
if [ -n "$INPUT_VPC_CONNECTOR" ]; then
  VPC_CONNECTOR="--vpc-connector=$INPUT_VPC_CONNECTOR"
fi

# check if service already exists, as "--no-traffic" is not allowed for new installations
NO_TRAFFIC=""
set +e
enableDebug
gcloud beta run services describe --region="$INPUT_GCP_REGION" "$INPUT_SERVICE_NAME" 2>&1 > /dev/null
if [ $? -eq 0 ]; then
  # 'describe' command results in an error, if service dows not exist
  NO_TRAFFIC="--no-traffic"
fi
disableDebug
set -e

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
  $NO_TRAFFIC \
  $ALLOW_UNAUTHENTICATED \
  $SERVICE_ACCOUNT \
  $CLOUDSQL_INSTANCES \
  $VPC_CONNECTOR \
  $ENV_VARS \
  $SECRETS \
  2>&1 | tee gcloud.log
disableDebug

if [ "$INPUT_NO_TRAFFIC" != "true" ]; then
  enableDebug
  gcloud beta run services update-traffic "$INPUT_SERVICE_NAME" \
    --to-latest \
    --platform=managed \
    --region="$INPUT_GCP_REGION" \
    2>&1 | tee traffic.log
  disableDebug

  ENDPOINT=$(cat traffic.log | grep -o 'URL: .*')
  ENDPOINT="${ENDPOINT/URL: /}"
else
  echo "" > traffic.log
  ENDPOINT=""
fi

echo ::set-output name=gcloud_log::"<pre>$(sed ':a;N;$!ba;s/\n/<br>/g' gcloud.log)</pre><hr><pre>$(sed ':a;N;$!ba;s/\n/<br>/g' traffic.log)</pre>"
echo ::set-output name=cloud_run_revision::"${INPUT_SERVICE_NAME}-${REVISION_SUFFIX}"
echo ::set-output name=cloud_run_endpoint::"${ENDPOINT}"
echo ::set-output name=deployed_image_tag::"${IMAGE_TAG}"
