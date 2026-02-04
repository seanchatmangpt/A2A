#!/bin/bash

# =============================================================================
# Craftplan Secret Generation Script
# =============================================================================
# This script generates secure random values for Craftplan deployment
# =============================================================================

set -e

echo "🔐 Generating Craftplan secrets..."

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    cp .env.secrets .env
    echo "✅ Created .env from template"
fi

# Generate SECRET_KEY_BASE (64 bytes base64 encoded)
if grep -q "your_secret_key_base_here" .env; then
    SECRET_KEY_BASE=$(openssl rand -base64 48)
    sed -i.bak "s/your_secret_key_base_here_min_64_bytes/$SECRET_KEY_BASE/" .env
    rm .env.bak
    echo "✅ Generated SECRET_KEY_BASE"
fi

# Generate TOKEN_SIGNING_SECRET (64 bytes base64 encoded)
if grep -q "your_token_signing_secret_here" .env; then
    TOKEN_SIGNING_SECRET=$(openssl rand -base64 48)
    sed -i.bak "s/your_token_signing_secret_here_min_64_bytes/$TOKEN_SIGNING_SECRET/" .env
    rm .env.bak
    echo "✅ Generated TOKEN_SIGNING_SECRET"
fi

# Generate CLOAK_KEY (32 bytes base64 encoded)
if grep -q "your_cloak_key_here_32_bytes" .env; then
    CLOAK_KEY=$(openssl rand -base64 32)
    sed -i.bak "s/your_cloak_key_here_32_bytes_base64/$CLOAK_KEY/" .env
    rm .env.bak
    echo "✅ Generated CLOAK_KEY"
fi

# Generate POSTGRES_PASSWORD
if grep -q "your_postgres_password_here" .env; then
    POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '+/=' | cut -c1-24)
    sed -i.bak "s/your_postgres_password_here/$POSTGRES_PASSWORD/" .env
    rm .env.bak
    echo "✅ Generated POSTGRES_PASSWORD"
fi

# Generate GRAFANA_PASSWORD
if grep -q "your_grafana_admin_password" .env; then
    GRAFANA_PASSWORD=$(openssl rand -base64 16 | tr -d '+/=' | cut -c1-16)
    sed -i.bak "s/your_grafana_admin_password/$GRAFANA_PASSWORD/" .env
    rm .env.bak
    echo "✅ Generated GRAFANA_PASSWORD"
fi

# Generate MINIO credentials if using defaults
if [ "$MINIO_ROOT_USER" = "minioadmin" ] || [ -z "$MINIO_ROOT_USER" ]; then
    MINIO_ROOT_USER=minioadmin
    MINIO_ROOT_PASSWORD=$(openssl rand -base64 16 | tr -d '+/=' | cut -c1-16)
    sed -i.bak "s/MINIO_ROOT_PASSWORD=minioadmin/MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD/" .env
    rm .env.bak
    echo "✅ Generated MINIO_ROOT_PASSWORD"
fi

echo ""
echo "🎉 All secrets generated successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Review .env file to ensure all values are correct"
echo "2. Deploy the stack: docker stack deploy -c docker-compose.stack.yml craftplan"
echo "3. Access Craftplan at: http://localhost:4000"
echo "   Demo credentials: test@test.com / Aa123123123123"
echo "4. Access Grafana at: http://localhost:3000"
echo "   Admin user: admin / password: $(grep GRAFANA_PASSWORD .env | cut -d= -f2)"
echo "5. Access Prometheus at: http://localhost:9090"
echo "6. Access MinIO console at: http://localhost:9001"
echo ""
echo "📁 Important files:"
echo "- docker-compose.stack.yml: Docker Swarm configuration"
echo "- .env: Environment variables and secrets"
echo "- monitoring/: Prometheus and Grafana configurations"
echo ""
echo "⚠️  Security reminder:"
echo "- Never commit .env to version control"
echo "- Rotate secrets regularly in production"
echo "- Use HTTPS in production (update nginx.conf for SSL)"