# 🏺 Craftplan + Docker Swarm Setup

Self-hosted ERP for artisanal D2C micro-businesses, deployed with Docker Swarm for production scalability.

## 🚀 Quick Start

### 1. Generate Secrets
```bash
./generate-secrets.sh
```

### 2. Deploy Stack
```bash
./deploy.sh up
```

### 3. Access Services
- **Craftplan**: http://localhost:4000
  - Demo: test@test.com / Aa123123123123
- **Grafana**: http://localhost:3000
  - Admin: admin / (generated password)
- **Prometheus**: http://localhost:9090
- **MinIO**: http://localhost:9001

## 📋 Prerequisites

- Docker and Docker Swarm initialized
- At least 2GB RAM available
- Port 4000, 3000, 9000, 9001, 9090 available

## 🛠️ Deployment

### Available Commands

| Command | Description |
|---------|-------------|
| `./deploy.sh up` | Deploy/Update stack |
| `./deploy.sh down` | Remove stack |
| `./deploy.sh status` | Show stack status |
| `./deploy.sh logs` | View all logs |
| `./deploy.sh logs craftplan` | View service logs |
| `./deploy.sh scale craftplan=3` | Scale service |
| `./deploy.sh update` | Pull latest images |
| `./deploy.sh health` | Health check |
| `./deploy.sh clean` | Cleanup resources |

### Scaling Services

```bash
# Scale Craftplan to 3 instances
./deploy.sh scale craftplan=3

# Check current replicas
./deploy.sh scale
```

## 🔧 Configuration

### Environment Variables

Edit `.env` file to configure:
- **Secrets**: SECRET_KEY_BASE, TOKEN_SIGNING_SECRET, CLOAK_KEY
- **Database**: POSTGRES_PASSWORD
- **Storage**: MINIO credentials
- **Scaling**: CPU/memory limits for each service

### Resource Limits

```yaml
# Example scaling settings
CRAFTPLAN_REPLICAS=3
CRAFTPLAN_CPU_LIMIT=2.0
CRAFTPLAN_MEMORY_LIMIT=2G
```

## 📊 Monitoring

### Prometheus Metrics

Craftplan exposes metrics at `/metrics` endpoint:
- HTTP request rates
- Response times
- Error rates
- Resource usage

### Grafana Dashboards

Pre-configured dashboard includes:
- HTTP request rates
- Memory usage
- CPU usage
- Service status

### Monitoring Commands

```bash
# View metrics in Prometheus
curl http://localhost:4000/metrics

# Access Grafana dashboard
open http://localhost:3000
```

## 🔒 Security

### Default Credentials

- **Craftplan**: test@test.com / Aa123123123123
- **Grafana**: admin / (generated password)
- **MinIO**: minioadmin / (generated password)

### Production Security

1. **Generate Strong Secrets**
   ```bash
   ./generate-secrets.sh
   ```

2. **Configure HTTPS** (see Nginx section)

3. **Restrict Access**
   ```bash
   # Add basic auth to services
   htpasswd -c auth/nginx.htpasswd your_username
   ```

## 🌐 Load Balancing

The stack includes Traefik labels for automatic load balancing with:
- Health checks
- Automatic SSL (with Let's Encrypt)
- Path routing
- Service discovery

## 📁 Architecture

```
craftplan/
├── docker-compose.stack.yml    # Docker Swarm configuration
├── .env.secrets              # Secret template
├── generate-secrets.sh        # Secret generator
├── deploy.sh                  # Deployment script
├── monitoring/               # Monitoring configs
│   ├── prometheus.yml       # Prometheus config
│   └── grafana/             # Grafana configs
├── nginx/                   # Reverse proxy (optional)
│   └── nginx.conf            # Nginx config
└── README.md                 # This file
```

## 🚨 Troubleshooting

### Common Issues

**Services not starting:**
```bash
# Check stack status
./deploy.sh status

# View logs
./deploy.sh logs

# Check Docker Swarm
docker node ls
```

**Port conflicts:**
```bash
# Check port usage
docker ps
netstat -an | grep 4000
```

**Memory issues:**
```bash
# Adjust memory limits in .env
CRAFTPLAN_MEMORY_LIMIT=512M
```

### Health Checks

Each service includes health checks:
```bash
# Check service health
./deploy.sh health

# Manual health check
curl http://localhost:4000/health
```

## 🔄 Updates

### Update Procedure

1. **Backup** your data
2. **Update images**:
   ```bash
   ./deploy.sh update
   ```
3. **Monitor** deployment:
   ```bash
   ./deploy.sh logs
   ```

### Rollback

If issues occur:
```bash
# Rollback to previous version
docker service update --rollback craftplan_craftplan
```

## 📈 Performance Tuning

### JVM Tuning (Craftplan)

```yaml
# Add to craftplan service environment
JAVA_OPTS: "-Xmx512m -Xms256m"
```

### PostgreSQL Tuning

```yaml
# Adjust in .env
POSTGRES_SHARED_BUFFERS=128MB
POSTGRES_EFFECTIVE_CACHE_SIZE=256MB
```

### Cache Configuration

```yaml
# Enable Redis cache
REDIS_REPLICAS=1
```

## 🔌 Integrations

### External Databases

Use existing PostgreSQL:
```yaml
# Update postgres service
image: your-registry/postgres:16
environment:
  POSTGRES_HOST: db.external.com
  POSTGRES_PORT: 5432
```

### External Storage

Configure S3 instead of MinIO:
```yaml
# In .env
AWS_S3_SCHEME=https://
AWS_S3_HOST=your-s3-bucket.s3.amazonaws.com
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret
```

## 📚 Resources

- [Craftplan Documentation](https://github.com/puemos/craftplan)
- [Docker Swarm Docs](https://docs.docker.com/engine/swarm/)
- [Prometheus Docs](https://prometheus.io/docs/)
- [Grafana Docs](https://grafana.com/docs/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test thoroughly
4. Submit a pull request

## 📄 License

Craftplan is licensed under AGPLv3. See LICENSE file for details.