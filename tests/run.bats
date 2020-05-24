#!/usr/bin/env bats

# global variables ############################################################
CONTAINER_NAME="deploy-google-cloud-run-action"

# build container to test the behavior ########################################
@test "build container" {
  docker build -t $CONTAINER_NAME . >&2
}

# functions ###################################################################

function setup() {
  unset INPUT_DEBUG
  unset INPUT_SERVICE_ACCOUNT_KEY
  unset INPUT_PROJECT_ID
  unset INPUT_IMAGE_NAME
  unset INPUT_IMAGE_TAG
  unset INPUT_GCP_REGION
  unset INPUT_SERVICE_NAME
  unset INPUT_ALLOW_UNAUTHENTICATED
  unset INPUT_CONCURRENCY_PER_INSTANCE
  unset INPUT_CPU
  unset INPUT_MEMORY
  unset INPUT_MAX_INSTANCES
  unset INPUT_REQUEST_TIMEOUT
}

function debug() {
  status="$1"
  output="$2"
  if [[ ! "${status}" -eq "0" ]]; then
  echo "status: ${status}"
  echo "output: ${output}"
  fi
}

###############################################################################
## test cases #################################################################
###############################################################################

## general cases ##############################################################
###############################################################################

@test "just start" {
  INPUT_PATH="/mnt/good_case_1"
  INPUT_FILES=".yaml"
  INPUT_EXCLUDE="skip"

  run docker run --rm \
  -v "$(pwd)/tests/data:/mnt/" \
  -i $CONTAINER_NAME

  debug "${status}" "${output}" "${lines}"

  echo $output | grep -q "Could not read json file key.json"
  [[ "${status}" -eq 1 ]]
}
