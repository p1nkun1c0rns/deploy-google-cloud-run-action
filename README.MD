# Deploy Google Cloud Run Service Action

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
| `concurrency_per_instance` | Max number of concurrent requests per instance, max: 80 | `80` | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--concurrency) |
| `cpu` | VCPU limit per instance | `1` | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--cpu) |
| `memory` | Memory limit per instance | `256Mi` | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--memory) |
| `max_instances` | Max nummber of instances to be scaled | `10` | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--max-instances) |
| `request_timeout` | Timeout for a single request to be processed | `10s` | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--timeout) |
| `allow_unauthenticated` | Wether the service should not be protected by GCP authorization | `true` | false | [gcloud run deploy](https://cloud.google.com/sdk/gcloud/reference/run/deploy) |

### Environment

For passing configuration and secrets to the Cloud Run service [`--set-env-vars`](https://cloud.google.com/sdk/gcloud/reference/run/deploy#--set-env-vars) is used.
All env variables starting with `SET_ENV_` are passed:
```yaml
env:
  SET_ENV_DISABLE_SIGNAL_HANDLERS: yeah
  SET_ENV_APPLICATION_SECRET: ${{ secrets.APPLICATION_SECRET }}
```
becomes:
```shell script
--set-env-vars 'DISABLE_SIGNAL_HANDLERS=yeah,APPLICATION_SECRET=***'
```

## Output

| Parameter | Description | Example |
|---|---|---|
| cloud_run_revision | Revision of the deployed service | yourservice-v1-5-1-t1587453463 |
| cloud_run_endpoint | Endpoint the service is serving at | https://yourservice-djgts23jkbq-ez.a.run.app |
| gcloud_log | Log output of the gcloud run deploy command |  |

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

## Remarks

* The service revision suffix is built from the `image_tag` replacing the dots with dashes concatinating the current epoch seconds for beeing able to redeploy the same version with different configuration.
* Container image name is built by concatinating `image_name`:`image_tag`

## TODO

* Add service account to be used

## Contribution

***Welcomed***
