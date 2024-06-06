from collections import defaultdict
from ruamel.yaml import YAML

import json
import os
import sys
import subprocess
import re

def validate_agent_config():
    yaml = YAML()
    with open("gcs_agent.yaml") as agent_config_file:
        agent_config = yaml.load(agent_config_file)

    assert "buckets" in agent_config

    for bucket in agent_config["buckets"].keys():
        assert isinstance(agent_config["buckets"][bucket], list)

    print(f"Agent Config Validated: \n {json.dumps(agent_config, indent=4)}")

def get_target_gcs_buckets():
    yaml = YAML()

    with open("gcs_agent.yaml") as agent_config_file:
        agent_config = yaml.load(agent_config_file)

    buckets = list(agent_config["buckets"].keys())
    return buckets

if __name__ == '__main__':
    #validate_agent_config()
    target_buckets = get_target_gcs_buckets()

    # get existing event notification state for target gcs buckets
    print(f"Installing lariat to GCS buckets {target_buckets}")

    lariat_api_key = os.environ.get("LARIAT_API_KEY")
    lariat_application_key = os.environ.get("LARIAT_APPLICATION_KEY")

    lariat_payload_source= os.environ.get("LARIAT_PAYLOAD_SOURCE", "gcs")

    lariat_sink_aws_access_key_id = os.getenv("LARIAT_TMP_AWS_ACCESS_KEY_ID")
    lariat_sink_aws_secret_access_key = os.getenv("LARIAT_TMP_AWS_SECRET_ACCESS_KEY")

    gcp_region = os.getenv("GCP_REGION")
    gcp_project_id = os.getenv("GCP_PROJECT_ID")
    gcp_organization_id = os.getenv("GCP_ORGANIZATION_ID")

    tf_env = {
        "lariat_api_key": lariat_api_key,
        "lariat_application_key": lariat_application_key,
        "lariat_sink_aws_access_key_id": lariat_sink_aws_access_key_id,
        "lariat_sink_aws_secret_access_key": lariat_sink_aws_secret_access_key,
        "lariat_payload_source": lariat_payload_source,
        "target_gcs_buckets": target_buckets,
        "gcp_region": gcp_region,
        "gcp_project_id": gcp_project_id,
        "gcp_organization_id": gcp_organization_id,
    }

    print("Passing configuration through to terraform")
    with open("lariat.auto.tfvars.json", "w") as f:
        json.dump(tf_env, f)
