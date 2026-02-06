"""
Architecture Diagram Generator
Generates Mermaid and PlantUML diagrams for A2A system architecture
"""

import os
from pathlib import Path


class ArchitectureDiagrams:
    """Generate architecture diagrams for A2A system"""

    def __init__(self, output_dir="docs/diagrams"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def generate_all(self):
        """Generate all architecture diagrams"""
        self.generate_network_diagram()
        self.generate_security_diagram()
        self.generate_data_flow_diagram()
        self.generate_multi_region_diagram()
        print(f"All diagrams generated in {self.output_dir}")

    def generate_network_diagram(self):
        """Generate network architecture diagram"""
        mermaid = """
graph TB
    subgraph "Internet"
        Client[Client Applications]
        CDN[CloudFront CDN]
    end

    subgraph "AWS Region - us-east-1"
        subgraph "VPC"
            subgraph "Public Subnet"
                ALB[Application Load Balancer]
                NAT[NAT Gateway]
            end

            subgraph "Private Subnet - App Tier"
                ECS1[ECS Container 1]
                ECS2[ECS Container 2]
                ECS3[ECS Container 3]
            end

            subgraph "Private Subnet - Data Tier"
                RDS[(RDS PostgreSQL)]
                ElastiCache[(ElastiCache Redis)]
                S3[(S3 Buckets)]
            end
        end

        subgraph "Monitoring"
            CloudWatch[CloudWatch]
            XRay[X-Ray]
        end
    end

    Client --> CDN
    CDN --> ALB
    ALB --> ECS1
    ALB --> ECS2
    ALB --> ECS3
    ECS1 --> RDS
    ECS2 --> RDS
    ECS3 --> RDS
    ECS1 --> ElastiCache
    ECS2 --> ElastiCache
    ECS3 --> ElastiCache
    ECS1 --> S3
    ECS2 --> S3
    ECS3 --> S3
    ECS1 --> NAT
    ECS2 --> NAT
    ECS3 --> NAT
    ECS1 -.-> CloudWatch
    ECS2 -.-> CloudWatch
    ECS3 -.-> CloudWatch
    ECS1 -.-> XRay
    ECS2 -.-> XRay
    ECS3 -.-> XRay

    style Client fill:#e1f5ff
    style ALB fill:#ff9999
    style ECS1 fill:#99ff99
    style ECS2 fill:#99ff99
    style ECS3 fill:#99ff99
    style RDS fill:#ffcc99
    style ElastiCache fill:#ffcc99
"""

        plantuml = """
@startuml Network Architecture
!define AWSPuml https://raw.githubusercontent.com/awslabs/aws-icons-for-plantuml/v14.0/dist
!include AWSPuml/AWSCommon.puml
!include AWSPuml/Compute/EC2.puml
!include AWSPuml/Compute/ECS.puml
!include AWSPuml/Database/RDS.puml
!include AWSPuml/Database/ElastiCache.puml
!include AWSPuml/Storage/S3.puml
!include AWSPuml/NetworkingContentDelivery/CloudFront.puml
!include AWSPuml/NetworkingContentDelivery/VPC.puml
!include AWSPuml/NetworkingContentDelivery/ElasticLoadBalancing.puml

package "Client Layer" {
    actor Client
    CloudFront(cdn, "CDN", "CloudFront")
}

package "AWS VPC - us-east-1" {
    package "Public Subnet" {
        ElasticLoadBalancing(alb, "Application LB", "ALB")
    }

    package "Private Subnet - App" {
        ECS(ecs1, "Container 1", "Fargate")
        ECS(ecs2, "Container 2", "Fargate")
        ECS(ecs3, "Container 3", "Fargate")
    }

    package "Private Subnet - Data" {
        RDS(rds, "Database", "PostgreSQL")
        ElastiCache(cache, "Cache", "Redis")
        S3(s3, "Object Storage", "S3")
    }
}

Client --> cdn
cdn --> alb
alb --> ecs1
alb --> ecs2
alb --> ecs3
ecs1 --> rds
ecs2 --> rds
ecs3 --> rds
ecs1 --> cache
ecs2 --> cache
ecs3 --> cache
ecs1 --> s3
ecs2 --> s3
ecs3 --> s3

@enduml
"""

        self._write_diagram("network_architecture_mermaid.md", mermaid, "mermaid")
        self._write_diagram("network_architecture_plantuml.puml", plantuml, "plantuml")

    def generate_security_diagram(self):
        """Generate security architecture diagram"""
        mermaid = """
graph TB
    subgraph "Edge Security"
        WAF[AWS WAF]
        Shield[AWS Shield]
        CloudFront[CloudFront]
    end

    subgraph "Authentication & Authorization"
        Cognito[AWS Cognito]
        IAM[IAM Roles/Policies]
        Secrets[Secrets Manager]
    end

    subgraph "Network Security"
        subgraph "VPC Security"
            NACL[Network ACLs]
            SG[Security Groups]
            VPCFlow[VPC Flow Logs]
        end

        subgraph "Application Security"
            TLS[TLS 1.3 Encryption]
            APIGateway[API Gateway]
            JWT[JWT Validation]
        end
    end

    subgraph "Data Security"
        Encryption[Encryption at Rest]
        KMS[AWS KMS]
        EncryptionTransit[Encryption in Transit]
    end

    subgraph "Monitoring & Compliance"
        GuardDuty[GuardDuty]
        SecurityHub[Security Hub]
        CloudTrail[CloudTrail]
        Config[AWS Config]
    end

    CloudFront --> WAF
    WAF --> Shield
    Shield --> APIGateway
    APIGateway --> JWT
    JWT --> Cognito
    Cognito --> IAM

    APIGateway --> SG
    SG --> NACL
    NACL --> VPCFlow

    IAM --> Secrets
    Secrets --> KMS
    KMS --> Encryption

    VPCFlow -.-> GuardDuty
    CloudTrail -.-> SecurityHub
    Config -.-> SecurityHub
    GuardDuty -.-> SecurityHub

    style WAF fill:#ff9999
    style Shield fill:#ff9999
    style KMS fill:#ffcc99
    style Encryption fill:#ffcc99
    style GuardDuty fill:#99ccff
    style SecurityHub fill:#99ccff
"""

        plantuml = """
@startuml Security Architecture
!define AWSPuml https://raw.githubusercontent.com/awslabs/aws-icons-for-plantuml/v14.0/dist
!include AWSPuml/AWSCommon.puml
!include AWSPuml/SecurityIdentityCompliance/WAF.puml
!include AWSPuml/SecurityIdentityCompliance/Shield.puml
!include AWSPuml/SecurityIdentityCompliance/Cognito.puml
!include AWSPuml/SecurityIdentityCompliance/IAM.puml
!include AWSPuml/SecurityIdentityCompliance/SecretsManager.puml
!include AWSPuml/SecurityIdentityCompliance/KeyManagementService.puml
!include AWSPuml/SecurityIdentityCompliance/GuardDuty.puml
!include AWSPuml/SecurityIdentityCompliance/SecurityHub.puml

package "Edge Protection" {
    WAF(waf, "Web Application", "Firewall")
    Shield(shield, "DDoS Protection", "Shield")
}

package "Identity & Access" {
    Cognito(cognito, "User Auth", "Cognito")
    IAM(iam, "Access Control", "IAM")
    SecretsManager(secrets, "Secret Storage", "Secrets Manager")
}

package "Encryption" {
    KeyManagementService(kms, "Key Management", "KMS")
    component "Data Encryption" as encryption {
        [At Rest]
        [In Transit]
    }
}

package "Threat Detection" {
    GuardDuty(guardduty, "Threat Detection", "GuardDuty")
    SecurityHub(hub, "Security Posture", "Security Hub")
}

package "Network Security" {
    component "VPC Security" as vpc {
        [Security Groups]
        [Network ACLs]
        [VPC Flow Logs]
    }
}

waf --> shield
shield --> cognito
cognito --> iam
iam --> secrets
secrets --> kms
kms --> encryption

vpc --> guardduty
guardduty --> hub

note right of encryption
  * TLS 1.3 for transit
  * AES-256 for rest
  * KMS managed keys
end note

note left of hub
  * Centralized security
  * Compliance monitoring
  * Automated remediation
end note

@enduml
"""

        self._write_diagram("security_architecture_mermaid.md", mermaid, "mermaid")
        self._write_diagram("security_architecture_plantuml.puml", plantuml, "plantuml")

    def generate_data_flow_diagram(self):
        """Generate data flow diagram"""
        mermaid = """
sequenceDiagram
    participant Client
    participant CDN
    participant ALB
    participant API
    participant Auth
    participant Cache
    participant Queue
    participant Worker
    participant DB
    participant S3

    Client->>CDN: HTTPS Request
    CDN->>ALB: Forward to ALB
    ALB->>API: Route to API Service
    API->>Auth: Validate JWT Token
    Auth-->>API: Token Valid

    API->>Cache: Check Cache
    alt Cache Hit
        Cache-->>API: Return Cached Data
        API-->>Client: 200 OK (Cached)
    else Cache Miss
        API->>DB: Query Database
        DB-->>API: Return Data
        API->>Cache: Store in Cache
        API-->>Client: 200 OK
    end

    rect rgb(200, 220, 250)
        note right of Client: Async Processing Flow
        Client->>API: POST Request (Large Job)
        API->>Queue: Enqueue Task
        Queue-->>API: Task ID
        API-->>Client: 202 Accepted (Task ID)

        Queue->>Worker: Dequeue Task
        Worker->>DB: Read/Write Data
        Worker->>S3: Store Results
        Worker->>Cache: Update Cache
        Worker->>Queue: Mark Complete
    end

    rect rgb(250, 220, 220)
        note right of Client: Real-time Updates
        Client->>API: WebSocket Connect
        API-->>Client: Connected
        Worker->>API: Push Update
        API->>Client: Send Event
    end
"""

        plantuml = """
@startuml Data Flow Architecture
!define AWSPuml https://raw.githubusercontent.com/awslabs/aws-icons-for-plantuml/v14.0/dist
!include AWSPuml/AWSCommon.puml

actor Client
participant "CloudFront" as CDN
participant "ALB" as ALB
participant "API Service" as API
participant "Auth Service" as Auth
participant "Redis Cache" as Cache
participant "SQS Queue" as Queue
participant "Worker Service" as Worker
database "PostgreSQL" as DB
database "S3 Storage" as S3

== Synchronous Request Flow ==
Client -> CDN: HTTPS Request
activate CDN
CDN -> ALB: Forward
activate ALB
ALB -> API: Route
activate API

API -> Auth: Validate Token
activate Auth
Auth --> API: Validated
deactivate Auth

API -> Cache: GET cached_key
activate Cache
alt Cache Hit
    Cache --> API: Cached Data
    deactivate Cache
    API --> Client: 200 OK (fast)
else Cache Miss
    Cache --> API: Not Found
    deactivate Cache
    API -> DB: SELECT query
    activate DB
    DB --> API: Result Set
    deactivate DB
    API -> Cache: SET cached_key
    API --> Client: 200 OK
end
deactivate API
deactivate ALB
deactivate CDN

== Asynchronous Processing Flow ==
Client -> API: POST /process (large job)
activate API
API -> Queue: Enqueue Task
activate Queue
Queue --> API: Task ID
deactivate Queue
API --> Client: 202 Accepted
deactivate API

Queue -> Worker: Dequeue
activate Worker
Worker -> DB: Read/Write
activate DB
DB --> Worker: Data
deactivate DB
Worker -> S3: Store Results
activate S3
S3 --> Worker: Stored
deactivate S3
Worker -> Cache: Invalidate/Update
Worker --> Queue: Complete
deactivate Worker

== Real-time Updates ==
Client -> API: WebSocket Connect
activate API
API --> Client: Connected
Worker -> API: Event Notification
API -> Client: Push Update
deactivate API

@enduml
"""

        self._write_diagram("data_flow_mermaid.md", mermaid, "mermaid")
        self._write_diagram("data_flow_plantuml.puml", plantuml, "plantuml")

    def generate_multi_region_diagram(self):
        """Generate multi-region architecture diagram"""
        mermaid = """
graph TB
    subgraph "Global Layer"
        Route53[Route 53 - Global DNS]
        GlobalCDN[CloudFront - Global CDN]
    end

    subgraph "US-EAST-1 Primary Region"
        subgraph "VPC-USE1"
            ALB1[Application LB]
            ECS1[ECS Cluster]
            RDS1[(RDS Primary)]
            S31[(S3 Bucket)]
            Cache1[(ElastiCache)]
        end

        DynamoDB1[(DynamoDB Global Table)]
    end

    subgraph "US-WEST-2 Secondary Region"
        subgraph "VPC-USW2"
            ALB2[Application LB]
            ECS2[ECS Cluster]
            RDS2[(RDS Read Replica)]
            S32[(S3 Bucket)]
            Cache2[(ElastiCache)]
        end

        DynamoDB2[(DynamoDB Global Table)]
    end

    subgraph "EU-WEST-1 Europe Region"
        subgraph "VPC-EUW1"
            ALB3[Application LB]
            ECS3[ECS Cluster]
            RDS3[(RDS Read Replica)]
            S33[(S3 Bucket)]
            Cache3[(ElastiCache)]
        end

        DynamoDB3[(DynamoDB Global Table)]
    end

    Route53 --> GlobalCDN
    GlobalCDN --> ALB1
    GlobalCDN --> ALB2
    GlobalCDN --> ALB3

    ALB1 --> ECS1
    ECS1 --> RDS1
    ECS1 --> Cache1
    ECS1 --> S31
    ECS1 --> DynamoDB1

    ALB2 --> ECS2
    ECS2 --> RDS2
    ECS2 --> Cache2
    ECS2 --> S32
    ECS2 --> DynamoDB2

    ALB3 --> ECS3
    ECS3 --> RDS3
    ECS3 --> Cache3
    ECS3 --> S33
    ECS3 --> DynamoDB3

    RDS1 -.->|Replication| RDS2
    RDS1 -.->|Replication| RDS3

    S31 <-.->|Cross-Region Replication| S32
    S31 <-.->|Cross-Region Replication| S33

    DynamoDB1 <-.->|Global Replication| DynamoDB2
    DynamoDB2 <-.->|Global Replication| DynamoDB3
    DynamoDB1 <-.->|Global Replication| DynamoDB3

    style Route53 fill:#ff9999
    style GlobalCDN fill:#ff9999
    style RDS1 fill:#ffcc99
    style RDS2 fill:#ccffcc
    style RDS3 fill:#ccffcc
    style DynamoDB1 fill:#99ccff
    style DynamoDB2 fill:#99ccff
    style DynamoDB3 fill:#99ccff
"""

        plantuml = """
@startuml Multi-Region Architecture
!define AWSPuml https://raw.githubusercontent.com/awslabs/aws-icons-for-plantuml/v14.0/dist
!include AWSPuml/AWSCommon.puml
!include AWSPuml/NetworkingContentDelivery/Route53.puml
!include AWSPuml/NetworkingContentDelivery/CloudFront.puml
!include AWSPuml/Compute/ECS.puml
!include AWSPuml/Database/RDS.puml
!include AWSPuml/Database/DynamoDB.puml
!include AWSPuml/Storage/S3.puml

package "Global Services" {
    Route53(dns, "Global DNS", "Route 53")
    CloudFront(cdn, "CDN", "CloudFront")
}

package "US-EAST-1 (Primary)" <<AWS Cloud>> {
    package "VPC-USE1" {
        ECS(ecs1, "App Cluster", "ECS")
        RDS(rds1, "Primary DB", "PostgreSQL")
        S3(s31, "Data Bucket", "S3")
        DynamoDB(ddb1, "Global Table", "DynamoDB")
    }
}

package "US-WEST-2 (Secondary)" <<AWS Cloud>> {
    package "VPC-USW2" {
        ECS(ecs2, "App Cluster", "ECS")
        RDS(rds2, "Read Replica", "PostgreSQL")
        S3(s32, "Data Bucket", "S3")
        DynamoDB(ddb2, "Global Table", "DynamoDB")
    }
}

package "EU-WEST-1 (Europe)" <<AWS Cloud>> {
    package "VPC-EUW1" {
        ECS(ecs3, "App Cluster", "ECS")
        RDS(rds3, "Read Replica", "PostgreSQL")
        S3(s33, "Data Bucket", "S3")
        DynamoDB(ddb3, "Global Table", "DynamoDB")
    }
}

package "AP-SOUTHEAST-1 (Asia)" <<AWS Cloud>> {
    package "VPC-APS1" {
        ECS(ecs4, "App Cluster", "ECS")
        RDS(rds4, "Read Replica", "PostgreSQL")
        S3(s34, "Data Bucket", "S3")
        DynamoDB(ddb4, "Global Table", "DynamoDB")
    }
}

dns --> cdn
cdn --> ecs1
cdn --> ecs2
cdn --> ecs3
cdn --> ecs4

ecs1 --> rds1
ecs2 --> rds2
ecs3 --> rds3
ecs4 --> rds4

ecs1 --> s31
ecs2 --> s32
ecs3 --> s33
ecs4 --> s34

ecs1 --> ddb1
ecs2 --> ddb2
ecs3 --> ddb3
ecs4 --> ddb4

rds1 .down.> rds2 : Async Replication
rds1 .down.> rds3 : Async Replication
rds1 .down.> rds4 : Async Replication

s31 <.> s32 : CRR
s31 <.> s33 : CRR
s31 <.> s34 : CRR

ddb1 <.> ddb2 : Global Tables
ddb2 <.> ddb3 : Global Tables
ddb3 <.> ddb4 : Global Tables
ddb1 <.> ddb4 : Global Tables

note right of dns
  Latency-based routing
  Health check failover
  Geolocation routing
end note

note bottom of rds1
  Primary region handles writes
  Cross-region replicas for reads
  Automated failover available
end note

note bottom of ddb1
  Multi-master replication
  Sub-second latency
  Active-active configuration
end note

@enduml
"""

        self._write_diagram("multi_region_mermaid.md", mermaid, "mermaid")
        self._write_diagram("multi_region_plantuml.puml", plantuml, "plantuml")

    def _write_diagram(self, filename, content, diagram_type):
        """Write diagram content to file"""
        filepath = self.output_dir / filename

        if diagram_type == "mermaid":
            with open(filepath, 'w') as f:
                f.write("```mermaid\n")
                f.write(content.strip())
                f.write("\n```\n")
        else:
            with open(filepath, 'w') as f:
                f.write(content.strip())
                f.write("\n")

        print(f"Generated: {filepath}")


def generate_readme():
    """Generate README for diagrams"""
    readme_content = """# Architecture Diagrams

This directory contains architecture diagrams for the A2A system.

## Diagram Types

### Network Architecture
- **network_architecture_mermaid.md**: Network topology showing VPC, subnets, load balancers, and services
- **network_architecture_plantuml.puml**: PlantUML version of network architecture

### Security Architecture
- **security_architecture_mermaid.md**: Security layers including WAF, authentication, encryption, and monitoring
- **security_architecture_plantuml.puml**: PlantUML version of security architecture

### Data Flow
- **data_flow_mermaid.md**: Sequence diagram showing synchronous and asynchronous data flows
- **data_flow_plantuml.puml**: PlantUML version of data flow

### Multi-Region Architecture
- **multi_region_mermaid.md**: Global multi-region deployment with replication
- **multi_region_plantuml.puml**: PlantUML version of multi-region architecture

## Viewing Diagrams

### Mermaid Diagrams
Mermaid diagrams can be viewed in:
- GitHub/GitLab (native support)
- VS Code with Mermaid extension
- Online: https://mermaid.live/

### PlantUML Diagrams
PlantUML diagrams can be rendered using:
- VS Code with PlantUML extension
- IntelliJ IDEA with PlantUML plugin
- Online: https://www.plantuml.com/plantuml/
- Command line: `plantuml diagram.puml`

## Generating Diagrams

To regenerate all diagrams:

```bash
python docs/architecture.py
```

## Architecture Overview

### Key Components

1. **Global Layer**: Route 53 DNS, CloudFront CDN
2. **Compute Layer**: ECS/Fargate containers, auto-scaling groups
3. **Data Layer**: RDS PostgreSQL, ElastiCache Redis, DynamoDB, S3
4. **Security Layer**: WAF, Shield, Cognito, IAM, KMS
5. **Monitoring**: CloudWatch, X-Ray, GuardDuty, Security Hub

### Design Principles

- **High Availability**: Multi-AZ deployments, auto-scaling
- **Security**: Defense in depth, encryption at rest and in transit
- **Performance**: Caching layers, CDN, read replicas
- **Scalability**: Horizontal scaling, queue-based processing
- **Resilience**: Multi-region failover, health checks
- **Observability**: Comprehensive logging and monitoring

### Data Flow Patterns

1. **Synchronous**: Client → CDN → ALB → API → Cache/DB → Response
2. **Asynchronous**: Client → API → Queue → Worker → Storage
3. **Real-time**: Client ↔ WebSocket ↔ API ↔ Event Stream

### Multi-Region Strategy

- **Primary Region**: US-EAST-1 (all writes)
- **Secondary Regions**: US-WEST-2, EU-WEST-1, AP-SOUTHEAST-1 (reads, failover)
- **Replication**: RDS cross-region, S3 CRR, DynamoDB global tables
- **Routing**: Latency-based, geolocation, health check failover

## Notes

- Diagrams are auto-generated and should not be manually edited
- Update the generator script to modify diagrams
- All diagrams follow AWS well-architected framework principles
"""

    readme_path = Path("docs/diagrams/README.md")
    with open(readme_path, 'w') as f:
        f.write(readme_content)
    print(f"Generated: {readme_path}")


if __name__ == "__main__":
    print("Generating A2A Architecture Diagrams...")
    print("=" * 60)

    generator = ArchitectureDiagrams()
    generator.generate_all()

    print("\n" + "=" * 60)
    generate_readme()

    print("\n" + "=" * 60)
    print("All diagrams generated successfully!")
    print("\nOutput directory: docs/diagrams/")
    print("\nDiagram files:")
    print("  - network_architecture_mermaid.md")
    print("  - network_architecture_plantuml.puml")
    print("  - security_architecture_mermaid.md")
    print("  - security_architecture_plantuml.puml")
    print("  - data_flow_mermaid.md")
    print("  - data_flow_plantuml.puml")
    print("  - multi_region_mermaid.md")
    print("  - multi_region_plantuml.puml")
    print("  - README.md")
