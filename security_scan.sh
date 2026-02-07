#!/bin/bash

################################################################################
# Security Scanning Script for A2A Project
# Uses Trivy and Grype for comprehensive security analysis
# Scans: Dockerfiles, Terraform files, Kubernetes manifests, and filesystem
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Timestamp for report
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SCAN_DIR="/home/user/A2A"
REPORT_DIR="${SCAN_DIR}/security_reports_${TIMESTAMP}"

# Create report directory
mkdir -p "${REPORT_DIR}"

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   A2A Security Scanning Suite - $(date)${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

################################################################################
# Function: Check and Install Tools
################################################################################
check_and_install_tools() {
    echo -e "${YELLOW}[1/7] Checking security scanning tools...${NC}"

    # Create local bin directory
    LOCAL_BIN="${HOME}/.local/bin"
    mkdir -p "${LOCAL_BIN}"
    export PATH="${LOCAL_BIN}:${PATH}"

    # Check Trivy
    if ! command -v trivy &> /dev/null; then
        echo -e "${YELLOW}Installing Trivy to ${LOCAL_BIN}...${NC}"
        cd /tmp
        wget -q https://github.com/aquasecurity/trivy/releases/download/v0.48.3/trivy_0.48.3_Linux-64bit.tar.gz
        tar zxf trivy_0.48.3_Linux-64bit.tar.gz
        mv trivy "${LOCAL_BIN}/"
        rm -f trivy_0.48.3_Linux-64bit.tar.gz
        cd - > /dev/null
        echo -e "${GREEN}✓ Trivy installed successfully${NC}"
    else
        echo -e "${GREEN}✓ Trivy is installed ($(trivy --version | head -n1))${NC}"
    fi

    # Check Grype
    if ! command -v grype &> /dev/null; then
        echo -e "${YELLOW}Installing Grype to ${LOCAL_BIN}...${NC}"
        curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b "${LOCAL_BIN}"
        echo -e "${GREEN}✓ Grype installed successfully${NC}"
    else
        echo -e "${GREEN}✓ Grype is installed ($(grype version | head -n1))${NC}"
    fi

    echo ""
}

################################################################################
# Function: Scan Dockerfiles
################################################################################
scan_dockerfiles() {
    echo -e "${YELLOW}[2/7] Scanning Dockerfiles...${NC}"

    DOCKERFILE_REPORT="${REPORT_DIR}/dockerfiles_scan.txt"
    echo "Dockerfile Security Scan Report - ${TIMESTAMP}" > "${DOCKERFILE_REPORT}"
    echo "========================================" >> "${DOCKERFILE_REPORT}"
    echo "" >> "${DOCKERFILE_REPORT}"

    # Find all Dockerfiles
    find "${SCAN_DIR}" -type f \( -name "Dockerfile*" -o -name "*.Dockerfile" \) ! -path "*/node_modules/*" ! -path "*/.git/*" | while read -r dockerfile; do
        echo -e "${BLUE}  Scanning: ${dockerfile}${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "${DOCKERFILE_REPORT}"
        echo "File: ${dockerfile}" >> "${DOCKERFILE_REPORT}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "${DOCKERFILE_REPORT}"

        # Trivy scan for Dockerfile misconfigurations
        trivy config --severity HIGH,CRITICAL --format table "${dockerfile}" >> "${DOCKERFILE_REPORT}" 2>&1 || true
        echo "" >> "${DOCKERFILE_REPORT}"
    done

    echo -e "${GREEN}✓ Dockerfile scan complete. Report: ${DOCKERFILE_REPORT}${NC}"
    echo ""
}

################################################################################
# Function: Scan Terraform Files (IaC)
################################################################################
scan_terraform() {
    echo -e "${YELLOW}[3/7] Scanning Terraform files (IaC)...${NC}"

    TERRAFORM_REPORT="${REPORT_DIR}/terraform_scan.txt"
    echo "Terraform/IaC Security Scan Report - ${TIMESTAMP}" > "${TERRAFORM_REPORT}"
    echo "========================================" >> "${TERRAFORM_REPORT}"
    echo "" >> "${TERRAFORM_REPORT}"

    # Find Terraform directories
    TF_DIRS=$(find "${SCAN_DIR}" -type f -name "*.tf" ! -path "*/.terraform/*" ! -path "*/node_modules/*" -exec dirname {} \; | sort -u)

    if [ -n "${TF_DIRS}" ]; then
        echo "${TF_DIRS}" | while read -r tf_dir; do
            echo -e "${BLUE}  Scanning Terraform directory: ${tf_dir}${NC}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "${TERRAFORM_REPORT}"
            echo "Directory: ${tf_dir}" >> "${TERRAFORM_REPORT}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "${TERRAFORM_REPORT}"

            # Trivy IaC scan
            trivy config --severity HIGH,CRITICAL --format table "${tf_dir}" >> "${TERRAFORM_REPORT}" 2>&1 || true
            echo "" >> "${TERRAFORM_REPORT}"
        done
    else
        echo "No Terraform files found." >> "${TERRAFORM_REPORT}"
    fi

    echo -e "${GREEN}✓ Terraform scan complete. Report: ${TERRAFORM_REPORT}${NC}"
    echo ""
}

################################################################################
# Function: Scan Kubernetes Manifests
################################################################################
scan_kubernetes() {
    echo -e "${YELLOW}[4/7] Scanning Kubernetes manifests...${NC}"

    K8S_REPORT="${REPORT_DIR}/kubernetes_scan.txt"
    echo "Kubernetes Manifests Security Scan Report - ${TIMESTAMP}" > "${K8S_REPORT}"
    echo "========================================" >> "${K8S_REPORT}"
    echo "" >> "${K8S_REPORT}"

    # Find Kubernetes YAML files
    K8S_DIRS=$(find "${SCAN_DIR}" -type f \( -name "*.yaml" -o -name "*.yml" \) -path "*/kubernetes/*" -o -path "*/k8s/*" -o -path "*/helm/*" ! -path "*/node_modules/*" ! -path "*/.github/*" -exec dirname {} \; | sort -u | head -20)

    if [ -n "${K8S_DIRS}" ]; then
        echo "${K8S_DIRS}" | while read -r k8s_dir; do
            echo -e "${BLUE}  Scanning K8s directory: ${k8s_dir}${NC}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "${K8S_REPORT}"
            echo "Directory: ${k8s_dir}" >> "${K8S_REPORT}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "${K8S_REPORT}"

            # Trivy K8s scan
            trivy config --severity HIGH,CRITICAL --format table "${k8s_dir}" >> "${K8S_REPORT}" 2>&1 || true
            echo "" >> "${K8S_REPORT}"
        done
    else
        echo "No Kubernetes manifest directories found." >> "${K8S_REPORT}"
    fi

    echo -e "${GREEN}✓ Kubernetes scan complete. Report: ${K8S_REPORT}${NC}"
    echo ""
}

################################################################################
# Function: Scan Filesystem for Vulnerabilities
################################################################################
scan_filesystem() {
    echo -e "${YELLOW}[5/7] Scanning filesystem for vulnerabilities...${NC}"

    FS_REPORT="${REPORT_DIR}/filesystem_scan.txt"
    echo "Filesystem Vulnerability Scan Report - ${TIMESTAMP}" > "${FS_REPORT}"
    echo "========================================" >> "${FS_REPORT}"
    echo "" >> "${FS_REPORT}"

    echo -e "${BLUE}  Running Trivy filesystem scan...${NC}"
    trivy fs --severity HIGH,CRITICAL --format table "${SCAN_DIR}" > "${FS_REPORT}" 2>&1 || true

    echo -e "${GREEN}✓ Filesystem scan complete. Report: ${FS_REPORT}${NC}"
    echo ""
}

################################################################################
# Function: Scan with Grype
################################################################################
scan_with_grype() {
    echo -e "${YELLOW}[6/7] Running Grype vulnerability scan...${NC}"

    GRYPE_REPORT="${REPORT_DIR}/grype_scan.txt"
    echo "Grype Vulnerability Scan Report - ${TIMESTAMP}" > "${GRYPE_REPORT}"
    echo "========================================" >> "${GRYPE_REPORT}"
    echo "" >> "${GRYPE_REPORT}"

    echo -e "${BLUE}  Scanning directory with Grype...${NC}"
    grype dir:"${SCAN_DIR}" --fail-on high --scope all-layers -o table >> "${GRYPE_REPORT}" 2>&1 || true

    echo -e "${GREEN}✓ Grype scan complete. Report: ${GRYPE_REPORT}${NC}"
    echo ""
}

################################################################################
# Function: Generate Summary Report
################################################################################
generate_summary() {
    echo -e "${YELLOW}[7/7] Generating summary report...${NC}"

    SUMMARY_REPORT="${REPORT_DIR}/SUMMARY.txt"

    cat > "${SUMMARY_REPORT}" << EOF
════════════════════════════════════════════════════════════════
A2A Security Scan Summary Report
════════════════════════════════════════════════════════════════
Scan Date: $(date)
Scan Directory: ${SCAN_DIR}
Report Directory: ${REPORT_DIR}

════════════════════════════════════════════════════════════════
SCANS PERFORMED
════════════════════════════════════════════════════════════════
1. Dockerfile Security Analysis
2. Terraform/IaC Configuration Scan
3. Kubernetes Manifest Security Scan
4. Filesystem Vulnerability Scan (Trivy)
5. Vulnerability Database Scan (Grype)

════════════════════════════════════════════════════════════════
CRITICAL FINDINGS SUMMARY
════════════════════════════════════════════════════════════════

EOF

    # Count critical findings
    echo "Dockerfile Issues (HIGH/CRITICAL):" >> "${SUMMARY_REPORT}"
    if [ -f "${REPORT_DIR}/dockerfiles_scan.txt" ]; then
        grep -i "critical\|high" "${REPORT_DIR}/dockerfiles_scan.txt" | wc -l >> "${SUMMARY_REPORT}" 2>/dev/null || echo "0" >> "${SUMMARY_REPORT}"
    fi
    echo "" >> "${SUMMARY_REPORT}"

    echo "Terraform Issues (HIGH/CRITICAL):" >> "${SUMMARY_REPORT}"
    if [ -f "${REPORT_DIR}/terraform_scan.txt" ]; then
        grep -i "critical\|high" "${REPORT_DIR}/terraform_scan.txt" | wc -l >> "${SUMMARY_REPORT}" 2>/dev/null || echo "0" >> "${SUMMARY_REPORT}"
    fi
    echo "" >> "${SUMMARY_REPORT}"

    echo "Kubernetes Issues (HIGH/CRITICAL):" >> "${SUMMARY_REPORT}"
    if [ -f "${REPORT_DIR}/kubernetes_scan.txt" ]; then
        grep -i "critical\|high" "${REPORT_DIR}/kubernetes_scan.txt" | wc -l >> "${SUMMARY_REPORT}" 2>/dev/null || echo "0" >> "${SUMMARY_REPORT}"
    fi
    echo "" >> "${SUMMARY_REPORT}"

    cat >> "${SUMMARY_REPORT}" << EOF

════════════════════════════════════════════════════════════════
DETAILED REPORTS
════════════════════════════════════════════════════════════════
- Dockerfiles: ${REPORT_DIR}/dockerfiles_scan.txt
- Terraform/IaC: ${REPORT_DIR}/terraform_scan.txt
- Kubernetes: ${REPORT_DIR}/kubernetes_scan.txt
- Filesystem: ${REPORT_DIR}/filesystem_scan.txt
- Grype Scan: ${REPORT_DIR}/grype_scan.txt

════════════════════════════════════════════════════════════════
RECOMMENDATIONS
════════════════════════════════════════════════════════════════
1. Review all HIGH and CRITICAL findings immediately
2. Update vulnerable dependencies
3. Fix IaC misconfigurations
4. Apply security best practices to Dockerfiles
5. Ensure Kubernetes manifests follow security policies
6. Re-run scan after remediation

════════════════════════════════════════════════════════════════
EOF

    echo -e "${GREEN}✓ Summary report generated: ${SUMMARY_REPORT}${NC}"
    echo ""

    # Display summary
    cat "${SUMMARY_REPORT}"
}

################################################################################
# Main Execution
################################################################################
main() {
    check_and_install_tools
    scan_dockerfiles
    scan_terraform
    scan_kubernetes
    scan_filesystem
    scan_with_grype
    generate_summary

    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Security scan complete!${NC}"
    echo -e "${BLUE}All reports saved to: ${REPORT_DIR}${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
}

# Run main function
main
