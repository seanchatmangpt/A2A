#!/usr/bin/env bash
# =============================================================================
# Dockerfile Validation Script
# =============================================================================
# Validates the Docker setup and provides helpful diagnostics

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}A2A Erlang Docker Validation${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if Docker is installed
echo -e "${BLUE}Checking Docker installation...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker version: $(docker --version)${NC}"
echo ""

# Check if Dockerfile exists
echo -e "${BLUE}Checking Dockerfile...${NC}"
if [ ! -f "Dockerfile" ]; then
    echo -e "${RED}✗ Dockerfile not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Dockerfile found${NC}"
echo ""

# Validate Dockerfile syntax
echo -e "${BLUE}Validating Dockerfile syntax...${NC}"
if docker build --help | grep -q "--check"; then
    # Docker 23.0+ has --check option
    if docker build --check -f Dockerfile . 2>&1; then
        echo -e "${GREEN}✓ Dockerfile syntax is valid${NC}"
    else
        echo -e "${RED}✗ Dockerfile syntax errors found${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ Docker version doesn't support --check, skipping syntax validation${NC}"
fi
echo ""

# Check required files
echo -e "${BLUE}Checking required files...${NC}"
REQUIRED_FILES=(
    "rebar.config"
    "src/a2a_erl.app.src"
    "config/sys.config"
    "config/vm.args"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓ $file${NC}"
    else
        echo -e "${RED}✗ $file (missing)${NC}"
        exit 1
    fi
done
echo ""

# Check .dockerignore
echo -e "${BLUE}Checking .dockerignore...${NC}"
if [ -f ".dockerignore" ]; then
    echo -e "${GREEN}✓ .dockerignore found${NC}"
    EXCLUDE_COUNT=$(grep -v '^#' .dockerignore | grep -v '^$' | wc -l | tr -d ' ')
    echo -e "${GREEN}  Excluding $EXCLUDE_COUNT patterns${NC}"
else
    echo -e "${YELLOW}⚠ .dockerignore not found (build may be slower)${NC}"
fi
echo ""

# Check Docker Compose
echo -e "${BLUE}Checking docker-compose.yml...${NC}"
if [ -f "docker-compose.yml" ]; then
    echo -e "${GREEN}✓ docker-compose.yml found${NC}"
    if command -v docker-compose &> /dev/null; then
        if docker-compose config &> /dev/null; then
            echo -e "${GREEN}✓ docker-compose.yml is valid${NC}"
        else
            echo -e "${RED}✗ docker-compose.yml has errors${NC}"
            exit 1
        fi
    elif docker compose version &> /dev/null; then
        if docker compose config &> /dev/null; then
            echo -e "${GREEN}✓ docker-compose.yml is valid${NC}"
        else
            echo -e "${RED}✗ docker-compose.yml has errors${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠ docker-compose not installed, skipping validation${NC}"
    fi
else
    echo -e "${YELLOW}⚠ docker-compose.yml not found${NC}"
fi
echo ""

# Check Makefile
echo -e "${BLUE}Checking Makefile...${NC}"
if [ -f "Makefile" ]; then
    echo -e "${GREEN}✓ Makefile found${NC}"
    if command -v make &> /dev/null; then
        if make help &> /dev/null; then
            echo -e "${GREEN}✓ Makefile is valid${NC}"
        else
            echo -e "${YELLOW}⚠ Makefile may have issues${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ make not installed${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Makefile not found${NC}"
fi
echo ""

# Validate Dockerfile stages
echo -e "${BLUE}Analyzing Dockerfile stages...${NC}"
STAGES=$(grep -E '^FROM ' Dockerfile | wc -l | tr -d ' ')
echo -e "${GREEN}✓ Found $STAGES build stages${NC}"

grep -E '^FROM .*AS' Dockerfile | while read -r line; do
    stage_name=$(echo "$line" | sed -E 's/FROM .*AS //' | tr -d ' ')
    echo -e "${GREEN}  - $stage_name${NC}"
done
echo ""

# Check for OTP 28 requirement
echo -e "${BLUE}Checking OTP version requirement...${NC}"
if grep -q 'otp-28' Dockerfile; then
    echo -e "${GREEN}✓ Dockerfile uses OTP 28${NC}"
else
    echo -e "${YELLOW}⚠ OTP 28 not explicitly specified${NC}"
fi

if grep -q '{minimum_otp_vsn, "28"}' rebar.config; then
    echo -e "${GREEN}✓ rebar.config requires OTP 28${NC}"
else
    echo -e "${YELLOW}⚠ rebar.config doesn't specify minimum OTP version${NC}"
fi
echo ""

# Check for security best practices
echo -e "${BLUE}Checking security best practices...${NC}"

if grep -q 'USER a2a' Dockerfile; then
    echo -e "${GREEN}✓ Uses non-root user${NC}"
else
    echo -e "${RED}✗ Doesn't use non-root user${NC}"
fi

if grep -q 'HEALTHCHECK' Dockerfile; then
    echo -e "${GREEN}✓ Includes health check${NC}"
else
    echo -e "${YELLOW}⚠ No health check defined${NC}"
fi

if grep -q 'expose 8080' Dockerfile || grep -q 'EXPOSE 8080' Dockerfile; then
    echo -e "${GREEN}✓ Exposes port 8080${NC}"
else
    echo -e "${YELLOW}⚠ Port 8080 not explicitly exposed${NC}"
fi
echo ""

# Check multi-stage build optimization
echo -e "${BLUE}Checking build optimization...${NC}"

if grep -q 'COPY --from=builder' Dockerfile; then
    echo -e "${GREEN}✓ Uses multi-stage build${NC}"
else
    echo -e "${RED}✗ Doesn't use multi-stage build (image will be large)${NC}"
fi

if grep -q 'rebar.config rebar.lock' Dockerfile; then
    echo -e "${GREEN}✓ Copies dependency files first (for layer caching)${NC}"
else
    echo -e "${YELLOW}⚠ Doesn't optimize layer caching${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Validation Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "  1. Build the image:"
echo -e "     ${YELLOW}docker build -t a2a-erl:0.1.0 .${NC}"
echo ""
echo -e "  2. Or use Makefile:"
echo -e "     ${YELLOW}make build${NC}"
echo ""
echo -e "  3. Run the container:"
echo -e "     ${YELLOW}docker run -p 8080:8080 a2a-erl:0.1.0${NC}"
echo ""
echo -e "  4. Or use docker-compose:"
echo -e "     ${YELLOW}docker-compose up -d${NC}"
echo ""
echo -e "See ${BLUE}DOCKER.md${NC} for detailed documentation."
echo ""
