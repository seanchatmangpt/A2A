apiVersion: v1
kind: Config
current-context: ${cluster_name}
contexts:
- context:
    cluster: ${cluster_name}
    user: ${cluster_name}-user
  name: ${cluster_name}
clusters:
- cluster:
    certificate-authority-data: ${cluster_ca_certificate}
    server: https://${cluster_endpoint}
  name: ${cluster_name}
users:
- name: ${cluster_name}-user
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: gke-gcloud-auth-plugin
      installHint: Install gke-gcloud-auth-plugin for kubectl by following https://cloud.google.com/blog/products/containers-kubernetes/kubectl-auth-changes-in-gke
      provideClusterInfo: true
