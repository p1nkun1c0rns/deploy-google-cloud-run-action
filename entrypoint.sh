#!/bin/sh

set -e
set -o pipefail

echo "$INPUT_SERVICE_ACCOUNT_KEY" | base64 -d >key.json
trap "{ rm -f key.json; }" EXIT

gcloud auth activate-service-account --key-file=key.json --project="$INPUT_PROJECT_ID"

FQ_IMAGE="${INPUT_IMAGE_NAME}:${INPUT_IMAGE_TAG}"
REVISION_SUFFIX=v$(echo "$INPUT_IMAGE_TAG" | sed "s;\.;-;g")-t$(date +%s)

LAST_REVISION=$(gcloud run revisions list --platform=managed --project="$INPUT_PROJECT_ID" --region="$INPUT_GCP_REGION" --service="$INPUT_SERVICE_NAME" | grep yes | awk '{print $2}')

echo "Deploying $FQ_IMAGE as service $INPUT_SERVICE_NAME to $INPUT_GCP_REGION in revision $REVISION_SUFFIX replacing $LAST_REVISION"

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

ALLOW_UNAUTHENTICATED=""
if [ "$INPUT_ALLOW_UNAUTHENTICATED" = "true" ]; then
  ALLOW_UNAUTHENTICATED="--allow-unauthenticated"
fi

SERVICE_ACCOUNT=""
if [ "$INPUT_SERVICE_ACCOUNT" != "default" ]; then
  SERVICE_ACCOUNT="--service-account $INPUT_SERVICE_ACCOUNT"
fi

gcloud run deploy "$INPUT_SERVICE_NAME" \
  --platform "managed" "$ALLOW_UNAUTHENTICATED" "$SERVICE_ACCOUNT" \
  --region "$INPUT_GCP_REGION" \
  --image "${FQ_IMAGE}" \
  --concurrency "$INPUT_CONCURRENCY_PER_INSTANCE" \
  --cpu "$INPUT_CPU" \
  --max-instances "$INPUT_MAX_INSTANCES" \
  --memory "$INPUT_MEMORY" \
  --timeout "$INPUT_REQUEST_TIMEOUT" \
  --revision-suffix "${REVISION_SUFFIX}" \
  --set-env-vars "${ENV_VARS}" 2>&1 | tee gcloud.log

ENDPOINT=$(cat gcloud.log | grep -o 'traffic at .*')

echo ::set-output name=gcloud_log::"<pre>$(sed ':a;N;$!ba;s/\n/<br>/g' gcloud.log)</pre>"
echo ::set-output name=cloud_run_revision::"${INPUT_SERVICE_NAME}-${REVISION_SUFFIX}"
echo ::set-output name=cloud_run_endpoint::"${ENDPOINT/traffic at /}"
