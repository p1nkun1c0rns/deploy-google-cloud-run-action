# Deploy Google Cloud Run Service Action

![image-prebuild](https://github.com/p1nkun1c0rns/deploy-google-cloud-run-action/workflows/Pre-Build%20Image/badge.svg)
![lint](https://github.com/p1nkun1c0rns/deploy-google-cloud-run-action/workflows/Test/badge.svg)

A Github Action that deploys a service to Google Cloud Run (GCP managed Knative-Serving).

## Input

### Parameter

| Parameter | Description | Default | Required | Reference |
|---|---|---|---|---|
| `project_id` | GCP project ID |  | true | [gcloud](https://cloud.google.com/sdk/gcloud/reference#--project) |
| `service_account_key` | Base64 encoded JSON key for GCP service account |  | true | [gcloud auth](https://cloud.google.com/sdk/gcloud/reference/auth/activate-service-account#--key-file) |
| `image_name` | Name of container image to be deployed |  | true | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--image) |
| `service_name` | Name of the service to be deployed |  | true | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#SERVICE) |
| `gcp_region` | GCP region to deploy the service in |  | true | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--region) |
| `image_tag` | Tag of container image to be deployed | `latest` | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--image) |
| `image_tag_pattern` | Regex pattern to identify the image_tag automatically | `` | false | [see below](https://github.com/p1nkun1c0rns/deploy-google-cloud-run-action#image_tag_pattern) |
| `concurrency_per_instance` | Max number of concurrent requests per instance, max: 250 | `80` | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--concurrency) |
| `cpu` | VCPU limit per instance, max: `4` | `1` | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--cpu) |
| `memory` | Memory limit per instance, with `4` CPU, min is `2Gi` | `256Mi` | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--memory) |
| `max_instances` | Max nummber of instances to be scaled | `10` | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--max-instances) |
| `min_instances` | Min nummber of instances to be available in idle | `0` | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--min-instances) |
| `request_timeout` | Timeout for a single request to be processed | `10s` | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--timeout) |
| `allow_unauthenticated` | Whether the service should not be protected by GCP authorization | `true` | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--[no-]allow-unauthenticated) |
| `cpu_throttling` | Set to false so that CPU is always allocated and available even when there are no incoming requests | `true` | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--[no-]cpu-throttling) |
| `startup_boost` | Set to true to have additional CPU available at startup time | `false` | false | [cloud run docs](https://cloud.google.com/run/docs/configuring/cpu#startup-boost) |
| `service_account` | Service Account to be used by the revision to be deployed | GCP docs: "If not provided, the revision will use the project's default service account." | false | [gcloud_run_deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--service-account) |
| `no_traffic` | Set to true to just deploy a new revision without shifting traffic | `false` | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--no-traffic) |
| `cloudsql_instances` | Comma separated list of CloudSQL instances to connect to | | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--set-cloudsql-instances) |
| `vpc_connector` | Name of the Serverless VPC Access connector to use with this service | | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--vpc-connector) |
| `vpc_egress` | Outbound traffic configuration, if a vpc_connector is configured; options are: `private-ranges-only`, `all-traffic`  | `private-ranges-only` | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--vpc-egress) |
| `execution_environment` | Selects the execution environment where the application will run; options are: `gen1`, `gen2` | | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--execution-environment), [cloud run docs](https://cloud.google.com/run/docs/about-execution-environments) |
| `debug` | Whether the gcloud commands should be printed to output | `false` | false | | 

#### `image_tag_pattern`

If parameter `image_tag_pattern` is provided and no explicit `image_tag` is given, the highest image tag (bash `sort`) matching the pattern (`grep -E "^${image_tag_pattern}"`) will be deployed.
For doing this, the used GCP service account has to have the role _`roles/storage.objectViewer`_.

Example: `image_tag_pattern: 1\.3\.\d+`

#### `service_account_key`

The service account needs the following roles for the deployment to work properly:
* `roles/run.admin`
* `roles/iam.serviceAccountUser`
* (optional) `roles/storage.objectViewer` - see **`image_tag_pattern`**

### Environment

For passing configuration and secrets to the Cloud Run service [`--set-env-vars`](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--set-env-vars) is used.

All env variables starting with `SET_ENV_` are passed:

```yaml
env:
  SET_ENV_DISABLE_SIGNAL_HANDLERS: yeah
  SET_ENV_APPLICATION_CONFIG: ${{ env.APPLICATION_CONFIG }}
```

becomes:

```shell script
--set-env-vars 'DISABLE_SIGNAL_HANDLERS=yeah,APPLICATION_CONFIG=thisisgreat'
```

### Secrets

Cloud Run supports [mounting or setting secrets](https://cloud.google.com/run/docs/configuring/secrets) from [Secret Manager](https://cloud.google.com/secret-manager) via the [`--set-secrets](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--set-secrets) argument.

This action translates its environment variables as `--set-secrets` (similar to `--set-env-vars`) to simplify the use, as the argument could get quite long.

Values of env variables prefixed with `SET_SECRET_` will be used as entries in the `--set-secrets` list, please see the [official documentation](https://cloud.google.com/run/docs/configuring/secrets) for the exact format:

```yaml
env:
  SET_SECRET_SOME_ENV_SECRET: ENV_VAR_NAME=SECRET_NAME:VERSION
  SET_SECRET_SOME_MOUNT_SECRET: PATH=SECRET_NAME:VERSION
  SET_SECRET_SOME_ENV_SECRET_FROM_FOREIGN_PROJECT: ENV_VAR_NAME=project/PROJECT_NUMBER/secrets/SECRET_NAME:VERSION
```

becomes:

```shell script
--set-secrets=ENV_VAR_NAME=SECRET_NAME:VERSION,PATH=SECRET_NAME:VERSION,project/PROJECT_NUMBER/secrets/SECRET_NAME:VERSION
```

Remark: The service account used by the deployed Cloud Run service needs IAM rights to access all configured secrets, and the Cloud Run service account needs to be "Secret Manager Secret Accessor".

## Output

| Parameter | Description | Example |
|---|---|---|
| cloud_run_revision | Revision of the deployed service | yourservice-v1-5-1-t1587453463 |
| cloud_run_endpoint | Endpoint the service is serving at | https://yourservice-djgts23jkbq-ez.a.run.app |
| gcloud_log | Log output of the gcloud run deploy command |  |
| deployed_image_tag | Tag of the image that was deployed | 1.3.23 |

## Usage

```yaml
  - name: Deploy Cloud Run
    id: deploy
    uses: p1nkun1c0rns/deploy-google-cloud-run-action@master
    with:
      service_account_key: ${{ secrets.GOOGLE_SERVICEACCOUNT_KEY }}
      project_id: your-gcp-project-id
      gcp_region: europe-west4
      service_name: yourservice
      image_name: eu.gcr.io/your-gcp-project-id/yourservice
      image_tag: '1.5.1'
    env:
      SET_ENV_DISABLE_SIGNAL_HANDLERS: yeah
      SET_ENV_APPLICATION_SECRET: ${{ secrets.APPLICATION_SECRET }}

  - name: Create Release
    uses: actions/create-release@latest
    env:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    with:
      tag_name: ${{ steps.deploy.outputs.cloud_run_revision }}
      release_name: ${{ steps.deploy.outputs.cloud_run_revision }} serving at ${{ steps.deploy.outputs.cloud_run_endpoint }}
      body: |
        ${{ steps.deploy.outputs.gcloud_log }}
```

### Prebuild latest image

Instead of using the latest (`@master`) or a tagged version there's a prebuild image of the latest release in the `action` branch available:

```yaml
  - name: Deploy Cloud Run
    id: deploy
    uses: p1nkun1c0rns/deploy-google-cloud-run-action@action
```

## Remarks

* The service revision suffix is built from the `image_tag` replacing the dots with dashes concatinating the current epoch seconds for beeing able to redeploy the same version with different configuration.
* Container image name is built by concatinating `image_name`:`image_tag`

## Contribution

***Welcomed***
