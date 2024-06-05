FROM --platform=linux/amd64 lariatdata/install-gcp-base:latest
RUN pip3 install ruamel.yaml boto3 awscli --break-system-packages
WORKDIR /workspace

COPY . /workspace

RUN chmod +x /workspace/init-and-apply.sh

ENTRYPOINT ["/workspace/init-and-apply.sh"]
