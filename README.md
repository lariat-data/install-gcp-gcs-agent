[<img src="https://img.shields.io/docker/v/lariatdata/install-gcp-gcs-agent/latest">](https://hub.docker.com/repository/docker/lariatdata/install-gcp-gcs-agent)


## Intro

[Lariat Data](www.lariatdata.com) is a Continuous Data Quality Monitoring Platform to ensure data products don't break even as business logic, input data and infrastructure change.

This repository contains the Docker image and dependencies for installing the Lariat GCS Agent on Google Cloud Platform.

## How it works
This installer uses Terraform, with remote `.tfstate` files, to create and manage infrastructure in the target cloud account and data source.

This installer creates the following in the target GCP project:
- A Lariat Service Account
- A Workflow and Cloud Run Job to perform the monitoring workload
- Eventarc triggers on the target GCS buckets to be monitored, triggering the abovementioned Workflow

## Structure
- The Entrypoint for Lariat installations is [init-and-apply.sh](init-and-apply.sh). This script contacts Lariat for the latest Terraform state (which may be empty), and proceeds to work against this state.
- Infrastructure-as-code definitions live under [main.tf](main.tf)


## Pre-requisites
- This installer requires a valid access token for the target Google Cloud account and project. This can be mounted via a Docker volume like so:
```
$ gcloud auth application-default print-access-token > gcloud_access_token
$ docker run --mount type=bind,source=$PWD/gcloud_access_token,target=/workspace/gcloud_access_token,readonly  ... lariatdata/install-gcp-gcs-agent:latest install
```
