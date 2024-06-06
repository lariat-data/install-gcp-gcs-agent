variable "lariat_api_key" {
  type = string
}

variable "lariat_application_key" {
  type = string
}

variable "lariat_sink_aws_access_key_id" {
  type = string
}

variable "lariat_sink_aws_secret_access_key" {
  type = string
}

variable "gcp_region" {
  type = string
}

variable "gcp_project_id" {
  type = string
}

variable "gcp_organization_id" {
  type = string
}

variable "target_gcs_buckets" {
  type = list(string)
}

variable "lariat_payload_source" {
  type = string
}
