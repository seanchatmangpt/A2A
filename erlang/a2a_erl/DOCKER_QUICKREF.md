# Docker Quick Reference - A2A Erlang

## Essential Commands

### Build
```bash
make build              # Build production image
docker build -t a2a-erl:0.1.0 .
```

### Run
```bash
make prod               # Run production container
docker run -p 8080:8080 a2a-erl:0.1.0
docker-compose up -d    # Using docker-compose
```

### Test
```bash
make test               # Run tests in container
curl http://localhost:8080/.well-known/agent-card.json
```

### Manage
```bash
make stop               # Stop container
make logs               # View logs
make health             # Check health
make shell              # Open shell
```

## Common Patterns

### Development
```bash
make dev                # Start with volume mounts
```

### Production
```bash
docker run -d \
  --restart unless-stopped \
  -p 8080:8080 \
  --name a2a-erl \
  a2a-erl:0.1.0
```

### Custom Configuration
```bash
docker run -p 9000:8080 \
  -e PORT=9000 \
  -e HOST=a2a.example.com \
  a2a-erl:0.1.0
```

## Ports
- **8080**: HTTP server
- **4369**: EPMD

## Health Check
```bash
curl http://localhost:8080/.well-known/agent-card.json
```

## Help
```bash
make help               # All Makefile targets
./scripts/validate-docker.sh  # Validate setup
```

## Full Documentation
See `DOCKER.md` for complete guide.
