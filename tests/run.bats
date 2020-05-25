#!/usr/bin/env bats

# global variables ############################################################
IMAGE="deploy-google-cloud-run-action"
CST_VERSION="latest" # version of GoogleContainerTools/container-structure-test
HADOLINT_VERSION="v1.17.6-9-g550ee0d-alpine"

# build container to test the behavior ########################################
@test "build container" {
  docker build -t $IMAGE . >&2
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
  run docker run --rm \
  -v "$(pwd)/tests/data:/mnt/" \
  -i $IMAGE

  debug "${status}" "${output}" "${lines}"

  echo $output | grep -q "Could not read json file key.json"
  [[ "${status}" -eq 1 ]]
}

@test "start hadolint" {
  docker run --rm -i hadolint/hadolint:$HADOLINT_VERSION < Dockerfile
  debug "${status}" "${output}" "${lines}"
  [[ "${status}" -eq 0 ]]
}

@test "start container-structure-test" {

  # init
  mkdir -p $HOME/bin
  export PATH=$PATH:$HOME/bin

  # check the os
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
          cst_os="linux"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
          cst_os="darwin"
  else
          skip "This test is not supported on your OS platform 😒"
  fi

  # donwload the container-structure-test binary
  cst_bin_name="container-structure-test-$cst_os-amd64"
  cst_download_url="https://storage.googleapis.com/container-structure-test/$CST_VERSION/$cst_bin_name"

  if [ ! -f "$HOME/bin/container-structure-test" ]; then
    curl -LO $cst_download_url
    chmod +x $cst_bin_name
    mv $cst_bin_name $HOME/bin/container-structure-test
  fi

  container-structure-test test --image ${IMAGE} -q --config tests/structure_test.yaml

  debug "${status}" "${output}" "${lines}"

  [[ "${status}" -eq 0 ]]
}
