FROM gcr.io/cloud-marketplace-tools/k8s/deployer_envsubst:latest

ENV CLOUD_SDK_VERSION=465.0.0 \
    KUBECTL_VERSION=1.29.1 \
    HELM_VERSION=3.14.0 \
    PATH=/google-cloud-sdk/bin:$PATH

RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    jq \
    python3 \
    python3-pip \
    gettext \
    gnupg \
    lsb-release \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${CLOUD_SDK_VERSION}-linux-x86_64.tar.gz && \
    tar xzf google-cloud-cli-${CLOUD_SDK_VERSION}-linux-x86_64.tar.gz && \
    rm google-cloud-cli-${CLOUD_SDK_VERSION}-linux-x86_64.tar.gz && \
    ./google-cloud-sdk/install.sh --usage-reporting=false --path-update=true --quiet && \
    gcloud components install kubectl --quiet && \
    gcloud components update --quiet

RUN curl -fsSL https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz -o helm.tar.gz && \
    tar -zxvf helm.tar.gz && \
    mv linux-amd64/helm /usr/local/bin/helm && \
    rm -rf linux-amd64 helm.tar.gz && \
    helm version

RUN curl -LO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/kubectl && \
    kubectl version --client

COPY deploy.sh /bin/deploy.sh
COPY create_manifests.sh /bin/create_manifests.sh
COPY validate.sh /bin/validate.sh

RUN chmod +x /bin/deploy.sh /bin/create_manifests.sh /bin/validate.sh

WORKDIR /data

ENTRYPOINT ["/bin/deploy.sh"]
