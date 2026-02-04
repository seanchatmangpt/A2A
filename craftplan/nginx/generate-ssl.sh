#!/bin/bash

# =============================================================================
# SSL Certificate Generator for Craftplan
# Generates self-signed certificates for development/testing
# =============================================================================

set -e

SSL_DIR="./nginx/ssl"
CERT_FILE="$SSL_DIR/cert.pem"
KEY_FILE="$SSL_DIR/key.pem"

# Create SSL directory if it doesn't exist
mkdir -p "$SSL_DIR"

# Generate private key and certificate
openssl req -x509 -newkey rsa:4096 -keyout "$KEY_FILE" -out "$CERT_FILE" -sha256 -days 365 -nodes \
  -subj "/C=US/ST=State/L=City/O=Craftplan/CN=localhost"

echo "✅ SSL certificate generated successfully!"
echo ""
echo "Certificate: $CERT_FILE"
echo "Private Key: $KEY_FILE"
echo ""
echo "📋 Next steps:"
echo "1. Update your hosts file if needed"
echo "2. Restart the nginx service: ./deploy.sh update"
echo "3. Access services via HTTPS:"
echo "   - Craftplan: https://localhost"
echo "   - Grafana: https://grafana.localhost"
echo "   - MinIO: https://minio.localhost"
echo ""
echo "⚠️  Note: These are self-signed certificates for development only."
echo "   For production, use certificates from Let's Encrypt or your CA."