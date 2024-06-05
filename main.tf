terraform {
  backend "s3" {}
}

provider "google" {
  project = var.gcp_project_id
  access_token = chomp(file("/workspace/gcloud_access_token"))
}

provider "google-beta" {
  project = var.gcp_project_id
  access_token = chomp(file("/workspace/gcloud_access_token"))
}

data "google_project" "user_project" {
  project_id = var.gcp_project_id
}

resource "google_project_service" "workflows_service_enabled" {
  project = var.gcp_project_id
  service = "workflows.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service_identity" "workflows_service_identity" {
  depends_on = [google_project_service.workflows_service_enabled]
  provider = google-beta

  project = var.gcp_project_id
  service = "workflows.googleapis.com"
}

resource "google_project_service" "eventarc_service_enabled" {
  project = var.gcp_project_id
  service = "eventarc.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service_identity" "eventarc_service_identity" {
  depends_on = [google_project_service.eventarc_service_enabled]
  provider = google-beta

  project = var.gcp_project_id
  service = "eventarc.googleapis.com"
}

resource "google_project_service" "cloud_run_service_enabled" {
  project = var.gcp_project_id
  service = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service_identity" "cloud_run_service_identity" {
  depends_on = [google_project_service.cloud_run_service_enabled]
  provider = google-beta

  project = var.gcp_project_id
  service = "run.googleapis.com"
}

resource "google_project_iam_member" "lariat_service_account_iam" {
  project = var.gcp_project_id
  role = "roles/eventarc.eventReceiver"
  member = "serviceAccount:${google_service_account.lariat_service_account.email}"
}

resource "google_project_iam_member" "lariat_cloud_run_service_agent_iam" {
  depends_on = [google_project_service_identity.cloud_run_service_identity]
  project = var.gcp_project_id
  role = "roles/run.serviceAgent"
  member = "serviceAccount:service-${data.google_project.user_project.number}@serverless-robot-prod.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "lariat_worfklow_service_agent_iam" {
  depends_on = [google_project_service_identity.workflows_service_identity]
  project = var.gcp_project_id
  role = "roles/iam.serviceAccountTokenCreator"
  member = "serviceAccount:service-${data.google_project.user_project.number}@gcp-sa-workflows.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "lariat_eventarc_service_agent_iam" {
  depends_on = [google_project_service_identity.eventarc_service_identity]
  project = var.gcp_project_id
  role = "roles/iam.serviceAccountTokenCreator"
  member = "serviceAccount:service-${data.google_project.user_project.number}@gcp-sa-eventarc.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "lariat_cloud_storage_service_agent_iam" {
  project = var.gcp_project_id
  role = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.user_project.number}@gs-project-accounts.iam.gserviceaccount.com"
}

resource "google_service_account" "lariat_service_account" {
  account_id   = "lariat-service-account"
  display_name = "Lariat Data Service Account"
}

resource "google_cloud_run_v2_job" "lariat_cloud_run_job" {
  depends_on = [google_project_iam_member.lariat_cloud_run_service_agent_iam]
  name = "lariat-gcs-monitoring-job"
  location = var.gcp_region

  template {
    template {
      containers {
        image = "us-east5-docker.pkg.dev/gcs-object-storage-sandbox/lariat-agents/lariat-gcs-agent:latest"
      }
    }
  }
}

resource "google_workflows_workflow" "lariat_monitoring_workflow" {
  depends_on = [google_project_iam_member.lariat_worfklow_service_agent_iam, google_project_iam_member.lariat_cloud_storage_service_agent_iam]
  name = "lariat-monitoring-workflow"
  region = var.gcp_region
  service_account = google_service_account.lariat_service_account.id

  source_contents = <<-EOF
  main:
    params: [event]
    steps:
        - init:
            assign:
                - project_id: ${var.gcp_project_id}
                - event_bucket: $${event.data.bucket}
                - event_file: $${event.data.name}
                - job_location: ${var.gcp_region}
        - run_job:
            call: googleapis.run.v1.namespaces.jobs.run
            args:
                name: ${google_cloud_run_v2_job.lariat_cloud_run_job.id}
                location: $${job_location}
                body:
                    overrides:
                        containerOverrides:
                            env:
                                - name: INPUT_BUCKET
                                  value: $${event_bucket}
                                - name: INPUT_FILE
                                  value: $${event_file}
                                - name: CLOUD_AGENT_CONFIG_PATH
                                  value: ${google_storage_bucket_object.lariat_gcs_agent_config_object.self_link}
                                - name: LARIAT_API_KEY
                                  value: ${var.lariat_api_key}
                                - name: LARIAT_APPLICATION_KEY
                                  value: ${var.lariat_application_key}
                                - name: LARIAT_ENDPOINT
                                  value: "http://ingest.lariatdata.com/api"
                                - name: LARIAT_OUTPUT_BUCKET
                                  value: "lariat-batch-agent-sink"
                                - name: LARIAT_SINK_AWS_ACCESS_KEY_ID
                                  value: ${var.lariat_sink_aws_access_key_id}
                                - name: LARIAT_SINK_AWS_SECRET_ACCESS_KEY
                                  value: ${var.lariat_sink_aws_secret_access_key}
                                - name: LARIAT_PAYLOAD_SOURCE
                                  value: ${var.lariat_payload_source}
            result: job_execution
        - finish:
            return: $${job_execution}
  EOF
}


data "google_storage_bucket" "lariat_monitored_bucket" {
  for_each = toset(var.target_gcs_buckets)
  name = each.key
}


resource "google_eventarc_trigger" "trigger_monitoring_workflow" {
  depends_on = [google_project_iam_member.lariat_eventarc_service_agent_iam]
  name = "trigger-lariat-monitoring-workflow"
  service_account = google_service_account.lariat_service_account.id
  for_each = toset(var.target_gcs_buckets)

  # The trigger needs to be in the same region as the target bucket. Buckets may be multi-region e.g. "us" or "asia", or single region like "us-east1"
  # But the string needs to match, so if GCP_REGION us-east1 is set for this installation, we can't use that region string if the bucket is multi-region "us"

  # Lower-case the string so that it matches US => us
  location = lower(data.google_storage_bucket.lariat_monitored_bucket[each.key].location)

  matching_criteria {
      attribute = "type"
      value = "google.cloud.storage.object.v1.finalized"
  }

  matching_criteria {
    attribute = "bucket"
    value = data.google_storage_bucket.lariat_monitored_bucket[each.key].name
  }

  destination {
    workflow = google_workflows_workflow.lariat_monitoring_workflow.id
  }
}

resource "google_storage_bucket" "lariat_gcs_agent_config_bucket" {
  name = "lariat-gcs-agent-config"
  location = var.gcp_region
  force_destroy = true
}

resource "google_storage_bucket_object" "lariat_gcs_agent_config_object" {
  name = "gcs_agent.yaml"
  bucket = google_storage_bucket.lariat_gcs_agent_config_bucket.name
  source = "/workspace/gcs_agent.yaml"
}
