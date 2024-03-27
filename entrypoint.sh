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

# Full service name must not exceed a certain length of characters
SERVICE_NAME_LENGTH_LIMIT=62

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

# validate and shorten service name length
SERVICE_NAME_LENGTH=${#INPUT_SERVICE_NAME}
REVISION_PREFIX_LENGTH=${#REVISION_PREFIX}
REVISION_DATE_LENGTH=${#REVISION_DATE}
COMPOSED_NAME_LENGTH=$(expr $SERVICE_NAME_LENGTH + $REVISION_PREFIX_LENGTH + $REVISION_DATE_LENGTH)

if [ $COMPOSED_NAME_LENGTH -gt $SERVICE_NAME_LENGTH_LIMIT ]; then
  # revision_prefix will be shortened to have composed length in allowed range
  OVERFLOW_LENGTH=$(expr $COMPOSED_NAME_LENGTH - $SERVICE_NAME_LENGTH_LIMIT)
  STRIP_LENGTH=$(expr $REVISION_PREFIX_LENGTH - $OVERFLOW_LENGTH)
  if [[ $STRIP_LENGTH -lt 0 ]]; then
    echo "Service name to long, please shorten it, so that service + image tage are shorter than $(expr $SERVICE_NAME_LENGTH_LIMIT - $REVISION_DATE_LENGTH) characters."
    exit 1
  else
    echo "Stripping $STRIP_LENGTH chars off from revision '$REVISION_PREFIX' as full service name must not exceed $SERVICE_NAME_LENGTH_LIMIT characters."
  fi
  REVISION_PREFIX=${REVISION_PREFIX:0:$STRIP_LENGTH}
fi

REVISION_SUFFIX=${REVISION_PREFIX}${REVISION_DATE}

# lowercase service name and suffix to be DNS compliant
SERVICE_NAME="${INPUT_SERVICE_NAME,,}"
REVISION_SUFFIX="${REVISION_SUFFIX,,}"

echo "Deploying $FQ_IMAGE as service $SERVICE_NAME to $INPUT_GCP_REGION in revision $REVISION_SUFFIX."

# turn off globbing
set -f
# split on new line
IFS='
'
setenv_pattern="^SET_ENV_\w+=.+$"
ENV_VARS=""
# write all env starting with SET_ENV_ to ENV_VARS in form KEY1=VAL1---__---KEY2=VAL2 where '---__---' is the delimiter, see: https://cloud.google.com/sdk/gcloud/reference/topic/escaping
for e in $(env | grep SET_ENV_); do
  # ignore SET_ENV_ entries with invalid name or missing value
  if [[ "$e" =~ $setenv_pattern ]]; then
    if [ -n "$ENV_VARS" ]; then
      ENV_VARS="${ENV_VARS}---__---"
    fi
    ENV_VARS="${ENV_VARS}${e/SET_ENV_/}"
  else
    echo "Ignoring env '$e'"
  fi
done

if [ -n "$ENV_VARS" ]; then
  ENV_VARS="--set-env-vars=^---__---^${ENV_VARS}"
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

if [ "$INPUT_ALLOW_UNAUTHENTICATED" = "true" ]; then
  ALLOW_UNAUTHENTICATED="--allow-unauthenticated"
else
  ALLOW_UNAUTHENTICATED="--no-allow-unauthenticated"
fi

if [ "$INPUT_CPU_THROTTLING" = "true" ]; then
  CPU_THROTTLING="--cpu-throttling"
else
  CPU_THROTTLING="--no-cpu-throttling"
fi

if [ "$INPUT_STARTUP_BOOST" = "true" ]; then
  STARTUP_BOOST="--cpu-boost"
else
  STARTUP_BOOST="--no-cpu-boost"
fi

SERVICE_ACCOUNT=""
if [ "$INPUT_SERVICE_ACCOUNT" != "default" ]; then
  SERVICE_ACCOUNT="--service-account=$INPUT_SERVICE_ACCOUNT"
fi

CLOUDSQL_INSTANCES="--clear-cloudsql-instances"
if [ -n "$INPUT_CLOUDSQL_INSTANCES" ]; then
  CLOUDSQL_INSTANCES="--set-cloudsql-instances=$INPUT_CLOUDSQL_INSTANCES"
fi

VPC_EGRESS=""
VPC_CONNECTOR="--clear-vpc-connector"
if [ -n "$INPUT_VPC_CONNECTOR" ]; then
  VPC_CONNECTOR="--vpc-connector=$INPUT_VPC_CONNECTOR"

  if [ -n "${INPUT_VPC_EGRESS}" ]; then
    VPC_EGRESS="--vpc-egress=$INPUT_VPC_EGRESS"
  fi
fi

# Network and Network Tags can/must be cleared. There is no --clear-subnet flag
# At most one of --clear-network | --network --subnet --clear-network-tags | --network-tags can be specified
VPC_NETWORK="--clear-network"
VPC_SUBNET=""
VPC_NETWORK_TAGS=""

if [ -n "$INPUT_VPC_NETWORK" ]; then
  VPC_NETWORK="--network=$INPUT_VPC_NETWORK"
  VPC_NETWORK_TAGS="--clear-network-tags"     # if VPC_NETWORK is set and NETWORK_TAGS is not

  if [ -n "$INPUT_VPC_SUBNET" ]; then
  VPC_SUBNET="--subnet=$INPUT_VPC_SUBNET"
  fi

  if [ -n "$INPUT_VPC_NETWORK_TAGS" ]; then
  VPC_NETWORK_TAGS="--network-tags=$INPUT_VPC_NETWORK_TAGS"
  fi

  if [ -n "${INPUT_VPC_EGRESS}" ]; then
    VPC_EGRESS="--vpc-egress=$INPUT_VPC_EGRESS"
  fi

fi

INGRESS=""
if [ -n "$INPUT_INGRESS" ]; then
  INGRESS="--ingress=$INPUT_INGRESS"
fi

EXECUTION_ENVIRONMENT=""
if [ -n "$INPUT_EXECUTION_ENVIRONMENT" ]; then
  EXECUTION_ENVIRONMENT="--execution-environment=$INPUT_EXECUTION_ENVIRONMENT"
fi

# check if service already exists, as "--no-traffic" is not allowed for new installations
NO_TRAFFIC=""
set +e
enableDebug
gcloud beta run services describe --region="$INPUT_GCP_REGION" "$SERVICE_NAME" 2>&1 > /dev/null
if [ $? -eq 0 ]; then
  # 'describe' command results in an error, if service dows not exist
  NO_TRAFFIC="--no-traffic"
fi
disableDebug
set -e

LABELS="version=${IMAGE_TAG//./-}"

enableDebug
gcloud beta run deploy "$SERVICE_NAME" \
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
  --clear-labels --labels="$LABELS" \
  $NO_TRAFFIC \
  $ALLOW_UNAUTHENTICATED \
  $CPU_THROTTLING \
  $STARTUP_BOOST \
  $SERVICE_ACCOUNT \
  $CLOUDSQL_INSTANCES \
  $VPC_CONNECTOR $VPC_EGRESS \
  $VPC_NETWORK $VPC_SUBNET $VPC_NETWORK_TAGS \
  $INGRESS \
  $EXECUTION_ENVIRONMENT \
  $ENV_VARS \
  $SECRETS \
  2>&1 | tee gcloud.log
disableDebug

if [ "$INPUT_NO_TRAFFIC" != "true" ]; then
  enableDebug
  gcloud beta run services update-traffic "$SERVICE_NAME" \
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

echo gcloud_log="<pre>$(sed ':a;N;$!ba;s/\n/<br>/g' gcloud.log)</pre><hr><pre>$(sed ':a;N;$!ba;s/\n/<br>/g' traffic.log)</pre>" >> $GITHUB_OUTPUT
echo cloud_run_revision="${SERVICE_NAME}-${REVISION_SUFFIX}" >> $GITHUB_OUTPUT
echo cloud_run_endpoint="${ENDPOINT}" >> $GITHUB_OUTPUT
echo deployed_image_tag="${IMAGE_TAG}" >> $GITHUB_OUTPUT
