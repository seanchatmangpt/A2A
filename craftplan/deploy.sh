#!/bin/bash

# =============================================================================
# Craftplan Docker Swarm Deployment Script
# =============================================================================
# Usage: ./deploy.sh [up|down|status|logs|scale|update]
# =============================================================================

set -e

STACK_NAME="craftplan"
COMPOSE_FILE="docker-compose.stack.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Display help
show_help() {
    echo "Craftplan Docker Swarm Deployment Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  up          Deploy or update the Craftplan stack"
    echo "  down        Remove the stack and all associated volumes"
    echo "  status      Show stack status and service information"
    echo "  logs        Follow logs for all services"
    echo "  logs [svc]  Follow logs for specific service"
    echo "  scale       Show current service replicas"
    echo "  scale [svc] Scale specific service (e.g., scale craftplan=3)"
    echo "  update      Pull latest images and redeploy"
    echo "  health      Check health of all services"
    echo "  clean       Remove unused images, networks, and containers"
    echo "  help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 up                    # Deploy stack"
    echo "  $0 scale craftplan=3     # Scale craftplan to 3 replicas"
    echo "  $0 logs craftplan        # View craftplan logs"
    echo ""
}

# Check if Docker Swarm is initialized
check_swarm() {
    if ! docker info | grep -q "Swarm: active"; then
        echo -e "${YELLOW}🔧 Initializing Docker Swarm...${NC}"
        docker swarm init
    fi
}

# Deploy the stack
deploy_stack() {
    echo -e "${BLUE}🚀 Deploying Craftplan stack...${NC}"

    # Check if .env exists
    if [ ! -f .env ]; then
        echo -e "${RED}❌ .env file not found!${NC}"
        echo "Run './generate-secrets.sh' first to generate required secrets."
        exit 1
    fi

    # Deploy stack
    docker stack deploy -c $COMPOSE_FILE $STACK_NAME

    echo -e "${GREEN}✅ Stack deployed successfully!${NC}"
    echo ""
    echo "Services will be available at:"
    echo "- Craftplan: http://localhost:4000"
    echo "- Grafana: http://localhost:3000"
    echo "- Prometheus: http://localhost:9090"
    echo "- MinIO: http://localhost:9001"
    echo ""
}

# Remove the stack
remove_stack() {
    echo -e "${YELLOW}🗑️  Removing Craftplan stack...${NC}"
    docker stack rm $STACK_NAME

    # Wait for stack to be removed
    while docker stack ls | grep -q $STACK_NAME; do
        echo "Waiting for stack removal..."
        sleep 2
    done

    echo -e "${GREEN}✅ Stack removed successfully!${NC}"
}

# Show stack status
show_status() {
    echo -e "${BLUE}📊 Craftplan Stack Status${NC}"
    echo "========================="

    # Check stack status
    if docker stack ls | grep -q $STACK_NAME; then
        echo -e "${GREEN}✅ Stack is active${NC}"
        echo ""

        # Show services
        echo "Services:"
        docker stack services $STACK_NAME --format "table {{.Name}}\t{{.Mode}}\t{{.Replicas}}\t{{.Image}}"

        # Show tasks
        echo ""
        echo "Tasks:"
        docker stack ps $STACK_NAME --format "table {{.ID}}\t{{.Name}}\t{{.Node}}\t{{.CurrentState}}\t{{.DesiredState}}"
    else
        echo -e "${RED}❌ Stack is not deployed${NC}"
    fi
}

# Show logs
show_logs() {
    SERVICE=$1

    if [ -z "$SERVICE" ]; then
        echo -e "${BLUE}📋 Following logs for all services...${NC}"
        docker service logs $STACK_NAME --follow --since 1m
    else
        echo -e "${BLUE}📋 Following logs for $SERVICE...${NC}"
        docker service logs $STACK_NAME_$SERVICE --follow --since 1m
    fi
}

# Scale services
scale_services() {
    SERVICE=$1

    if [ -z "$SERVICE" ]; then
        echo -e "${BLUE}📊 Current service replicas:${NC}"
        docker service ls --filter name=$STACK_NAME_ --format "table {{.Name}}\t{{.Replicas}}"
    else
        # Validate service name
        if ! docker service ls --filter name=$STACK_NAME_$SERVICE --quiet | grep -q .; then
            echo -e "${RED}❌ Service '$SERVICE' not found in stack${NC}"
            exit 1
        fi

        # Parse scale command (e.g., "craftplan=3")
        if [[ $SERVICE =~ ^= ]]; then
            SCALE_CMD=$SERVICE
        else
            echo -e "${RED}❌ Invalid scale format. Use: service=replicas${NC}"
            echo "Example: scale craftplan=3"
            exit 1
        fi

        echo -e "${BLUE}⚖️  Scaling service...${NC}"
        docker service scale $STACK_NAME_$SCALE_CMD
    fi
}

# Update stack
update_stack() {
    echo -e "${BLUE}🔄 Updating stack...${NC}"

    # Pull latest images
    echo "Pulling latest images..."
    docker compose -f $COMPOSE_FILE pull

    # Redeploy stack
    docker stack deploy -c $COMPOSE_FILE $STACK_NAME

    echo -e "${GREEN}✅ Stack updated successfully!${NC}"
}

# Check health
check_health() {
    echo -e "${BLUE}🏥 Service Health Check${NC}"
    echo "======================"

    # Check all services
    for service in $(docker service ls --filter name=$STACKNAME_ --format "{{.Name}}"); do
        replicas=$(docker service ls --filter name=$service --format "{{.Replicas}}")
        running=$(docker service ps $service --filter "desired-state=running" --format "{{.CurrentState}}" | head -1)

        if echo "$running" | grep -q "Running"; then
            echo -e "✅ $service: $replicas replicas (running)"
        else
            echo -e "❌ $service: $replicas replicas (not running)"
        fi
    done
}

# Cleanup unused resources
cleanup() {
    echo -e "${YELLOW}🧹 Cleaning up unused resources...${NC}"

    # Remove unused images
    docker image prune -f

    # Remove unused networks
    docker network prune -f

    # Remove stopped containers
    docker container prune -f

    echo -e "${GREEN}✅ Cleanup completed!${NC}"
}

# Main script logic
case "${1:-help}" in
    "up")
        check_swarm
        deploy_stack
        ;;
    "down")
        remove_stack
        ;;
    "status")
        show_status
        ;;
    "logs")
        show_logs $2
        ;;
    "scale")
        scale_services $2
        ;;
    "update")
        update_stack
        ;;
    "health")
        check_health
        ;;
    "clean")
        cleanup
        ;;
    "help"|*)
        show_help
        ;;
esac