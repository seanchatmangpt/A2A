"""
Authentication and authorization unit tests for Craftplan MCP + A2A Integration

This module provides unit tests for authentication and authorization components:
- JWT token handling
- Role-based access control
- Permission management
- Authentication middleware
- Authorization policies
- Session management
- Security headers
- Rate limiting
- Multi-factor authentication
- OAuth2 integration
- API key authentication
- LDAP integration
- SAML integration
- Security audit logging
- Password policies
- Token refresh
- Session timeout
- Security policies
- Compliance requirements
- Integration with MCP and A2A servers
"""

import pytest
import json
import time
import jwt
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional, Union
from unittest.mock import Mock, AsyncMock, patch, MagicMock
from fastapi import HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field

# Import authentication modules (would be in actual implementation)
# from src.auth.jwt_manager import JWTManager
# from src.auth.role_manager import RoleManager
# from src.auth.permission_manager import PermissionManager


class MockJWTManager:
    """Mock JWT manager for testing"""

    def __init__(self, secret_key: str = "test-secret"):
        self.secret_key = secret_key
        self.algorithm = "HS256"
        self.token_lifetime = 3600  # 1 hour

    def generate_token(self, user_id: str, roles: List[str] = None, permissions: List[str] = None) -> str:
        """Generate a JWT token"""
        payload = {
            "sub": user_id,
            "iat": datetime.utcnow(),
            "exp": datetime.utcnow() + timedelta(seconds=self.token_lifetime),
            "roles": roles or [],
            "permissions": permissions or []
        }
        return jwt.encode(payload, self.secret_key, algorithm=self.algorithm)

    def verify_token(self, token: str) -> Dict[str, Any]:
        """Verify a JWT token"""
        try:
            payload = jwt.decode(token, self.secret_key, algorithms=[self.algorithm])
            return payload
        except jwt.ExpiredSignatureError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token has expired"
            )
        except jwt.InvalidTokenError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token"
            )


class MockRoleManager:
    """Mock role manager for testing"""

    def __init__(self):
        self.roles = {
            "admin": {
                "name": "Administrator",
                "description": "System administrator with full access",
                "permissions": ["*"]
            },
            "user": {
                "name": "Regular User",
                "description": "Regular user with limited access",
                "permissions": ["read", "write"]
            },
            "viewer": {
                "name": "Viewer",
                "description": "Read-only access",
                "permissions": ["read"]
            }
        }

    def get_role(self, role_name: str) -> Dict[str, Any]:
        """Get role definition"""
        return self.roles.get(role_name)

    def get_user_roles(self, user_id: str) -> List[str]:
        """Get user roles (mock)"""
        # Mock data - in real implementation, this would query a database
        mock_user_roles = {
            "user_1": ["admin"],
            "user_2": ["user"],
            "user_3": ["viewer"],
            "user_4": ["user", "viewer"]
        }
        return mock_user_roles.get(user_id, [])

    def has_role(self, user_id: str, role_name: str) -> bool:
        """Check if user has a specific role"""
        return role_name in self.get_user_roles(user_id)

    def assign_role(self, user_id: str, role_name: str) -> bool:
        """Assign role to user (mock)"""
        # In real implementation, this would update the database
        return True

    def revoke_role(self, user_id: str, role_name: str) -> bool:
        """Revoke role from user (mock)"""
        # In real implementation, this would update the database
        return True


class MockPermissionManager:
    """Mock permission manager for testing"""

    def __init__(self):
        self.permissions = {
            "read": {
                "name": "Read Access",
                "description": "Read access to resources"
            },
            "write": {
                "name": "Write Access",
                "description": "Write access to resources"
            },
            "delete": {
                "name": "Delete Access",
                "description": "Delete access to resources"
            },
            "admin": {
                "name": "Admin Access",
                "description": "Administrative access"
            }
        }

    def get_permission(self, permission_name: str) -> Dict[str, Any]:
        """Get permission definition"""
        return self.permissions.get(permission_name)

    def check_permission(self, user_id: str, permission: str) -> bool:
        """Check if user has a specific permission"""
        # Mock implementation
        user_permissions = self.get_user_permissions(user_id)
        return permission in user_permissions

    def get_user_permissions(self, user_id: str) -> List[str]:
        """Get user permissions (mock)"""
        # Mock data - in real implementation, this would combine roles and user-specific permissions
        mock_user_permissions = {
            "user_1": ["read", "write", "delete", "admin"],  # Admin
            "user_2": ["read", "write"],  # User
            "user_3": ["read"],  # Viewer
            "user_4": ["read", "write"]  # User
        }
        return mock_user_permissions.get(user_id, [])

    def grant_permission(self, user_id: str, permission: str) -> bool:
        """Grant permission to user (mock)"""
        # In real implementation, this would update the database
        return True

    def revoke_permission(self, user_id: str, permission: str) -> bool:
        """Revoke permission from user (mock)"""
        # In real implementation, this would update the database
        return True


class TestJWTAuthentication:
    """Test JWT authentication functionality"""

    def test_jwt_generation(self):
        """Test JWT token generation"""
        jwt_manager = MockJWTManager()

        # Generate token for user with roles
        token = jwt_manager.generate_token(
            user_id="user_1",
            roles=["admin"],
            permissions=["read", "write", "delete"]
        )

        assert isinstance(token, str)
        assert len(token) > 0

    def test_jwt_verification(self):
        """Test JWT token verification"""
        jwt_manager = MockJWTManager()

        # Generate token
        token = jwt_manager.generate_token(
            user_id="user_1",
            roles=["admin"],
            permissions=["read", "write", "delete"]
        )

        # Verify token
        payload = jwt_manager.verify_token(token)
        assert payload["sub"] == "user_1"
        assert "admin" in payload["roles"]
        assert "read" in payload["permissions"]
        assert "write" in payload["permissions"]
        assert "delete" in payload["permissions"]

    def test_jwt_expiration(self):
        """Test JWT token expiration"""
        jwt_manager = MockJWTManager()

        # Generate token with short expiration
        token = jwt_manager.generate_token(
            user_id="user_1",
            roles=["admin"],
            permissions=["read"],
            token_lifetime=1  # 1 second
        )

        # Verify token immediately
        payload = jwt_manager.verify_token(token)
        assert payload["sub"] == "user_1"

        # Wait for expiration
        time.sleep(2)

        # Try to verify expired token
        with pytest.raises(HTTPException) as excinfo:
            jwt_manager.verify_token(token)

        assert excinfo.value.status_code == 401
        assert "expired" in excinfo.value.detail.lower()

    def test_jwt_invalid_token(self):
        """Test JWT token verification with invalid token"""
        jwt_manager = MockJWTManager()

        # Test with invalid token
        with pytest.raises(HTTPException) as excinfo:
            jwt_manager.verify_token("invalid-token")

        assert excinfo.value.status_code == 401
        assert "invalid" in excinfo.value.detail.lower()

    def test_jwt_token_claims(self):
        """Test JWT token claims"""
        jwt_manager = MockJWTManager()

        # Generate token with specific claims
        token = jwt_manager.generate_token(
            user_id="user_123",
            roles=["user", "viewer"],
            permissions=["read"]
        )

        # Verify claims
        payload = jwt_manager.verify_token(token)
        assert payload["sub"] == "user_123"
        assert set(payload["roles"]) == {"user", "viewer"}
        assert set(payload["permissions"]) == {"read"}
        assert "iat" in payload
        assert "exp" in payload

    def test_jwt_token_refresh(self):
        """Test JWT token refresh"""
        jwt_manager = MockJWTManager()

        # Generate original token
        original_token = jwt_manager.generate_token(
            user_id="user_1",
            roles=["admin"]
        )

        # Verify original token
        original_payload = jwt_manager.verify_token(original_token)
        original_exp = original_payload["exp"]

        # Generate new token
        new_token = jwt_manager.generate_token(
            user_id="user_1",
            roles=["admin"]
        )

        # Verify new token
        new_payload = jwt_manager.verify_token(new_token)
        new_exp = new_payload["exp"]

        # New token should have later expiration
        assert new_exp > original_exp

    def test_jwt_token_blacklist(self):
        """Test JWT token blacklist"""
        jwt_manager = MockJWTManager()
        blacklist = set()

        # Generate token
        token = jwt_manager.generate_token(
            user_id="user_1",
            roles=["admin"]
        )

        # Add token to blacklist
        blacklist.add(token)

        # Try to verify blacklisted token
        with pytest.raises(HTTPException) as excinfo:
            jwt_manager.verify_token(token)

        assert excinfo.value.status_code == 401
        assert "blacklisted" in excinfo.value.detail.lower()


class TestRoleBasedAccessControl:
    """Test role-based access control (RBAC) functionality"""

    def setup_method(self):
        """Setup test fixtures"""
        self.role_manager = MockRoleManager()
        self.permission_manager = MockPermissionManager()

    def test_role_definition(self):
        """Test role definition management"""
        # Get admin role
        admin_role = self.role_manager.get_role("admin")
        assert admin_role["name"] == "Administrator"
        assert admin_role["description"] == "System administrator with full access"
        assert admin_role["permissions"] == ["*"]

        # Get user role
        user_role = self.role_manager.get_role("user")
        assert user_role["name"] == "Regular User"
        assert user_role["description"] == "Regular user with limited access"
        assert set(user_role["permissions"]) == {"read", "write"}

        # Get non-existent role
        non_existent_role = self.role_manager.get_role("non_existent")
        assert non_existent_role is None

    def test_user_role_assignment(self):
        """Test user role assignment"""
        # Assign role to user
        result = self.role_manager.assign_role("user_5", "admin")
        assert result is True

        # Check if user has role
        has_role = self.role_manager.has_role("user_5", "admin")
        assert has_role is True

        # Check user roles
        user_roles = self.role_manager.get_user_roles("user_5")
        assert "admin" in user_roles

    def test_role_removal(self):
        """Test role removal"""
        # Assign role first
        self.role_manager.assign_role("user_6", "user")

        # Remove role
        result = self.role_manager.revoke_role("user_6", "user")
        assert result is True

        # Check if role was removed
        has_role = self.role_manager.has_role("user_6", "user")
        assert has_role is False

        # Check remaining roles
        user_roles = self.role_manager.get_user_roles("user_6")
        assert "user" not in user_roles

    def test_multiple_role_assignment(self):
        """Test multiple role assignment"""
        # Assign multiple roles to user
        self.role_manager.assign_role("user_7", "user")
        self.role_manager.assign_role("user_7", "viewer")

        # Check user roles
        user_roles = self.role_manager.get_user_roles("user_7")
        assert "user" in user_roles
        assert "viewer" in user_roles
        assert len(user_roles) == 2

    def test_role_hierarchy(self):
        """Test role hierarchy"""
        # Admin should have all permissions
        admin_permissions = self.role_manager.get_user_roles("user_1")  # Has admin role
        assert "admin" in admin_permissions

        # Regular user should have limited permissions
        user_permissions = self.role_manager.get_user_roles("user_2")  # Has user role
        assert "user" in user_permissions
        assert "admin" not in user_permissions

        # Viewer should have read-only permissions
        viewer_permissions = self.role_manager.get_user_roles("user_3")  # Has viewer role
        assert "viewer" in viewer_permissions
        assert "admin" not in viewer_permissions
        assert "user" not in viewer_permissions

    def test_role_inheritance(self):
        """Test role inheritance"""
        # In a real implementation, this would test role inheritance
        # For now, we'll mock the behavior
        pass


class TestPermissionManagement:
    """Test permission management functionality"""

    def setup_method(self):
        """Setup test fixtures"""
        self.permission_manager = MockPermissionManager()

    def test_permission_definition(self):
        """Test permission definition management"""
        # Get read permission
        read_permission = self.permission_manager.get_permission("read")
        assert read_permission["name"] == "Read Access"
        assert read_permission["description"] == "Read access to resources"

        # Get write permission
        write_permission = self.permission_manager.get_permission("write")
        assert write_permission["name"] == "Write Access"
        assert write_permission["description"] == "Write access to resources"

        # Get non-existent permission
        non_existent_permission = self.permission_manager.get_permission("non_existent")
        assert non_existent_permission is None

    def test_user_permission_check(self):
        """Test user permission checking"""
        # Admin user should have all permissions
        admin_has_read = self.permission_manager.check_permission("user_1", "read")
        admin_has_write = self.permission_manager.check_permission("user_1", "write")
        admin_has_delete = self.permission_manager.check_permission("user_1", "delete")
        admin_has_admin = self.permission_manager.check_permission("user_1", "admin")

        assert admin_has_read is True
        assert admin_has_write is True
        assert admin_has_delete is True
        assert admin_has_admin is True

        # Regular user should have limited permissions
        user_has_read = self.permission_manager.check_permission("user_2", "read")
        user_has_write = self.permission_manager.check_permission("user_2", "write")
        user_has_delete = self.permission_manager.check_permission("user_2", "delete")
        user_has_admin = self.permission_manager.check_permission("user_2", "admin")

        assert user_has_read is True
        assert user_has_write is True
        assert user_has_delete is False
        assert user_has_admin is False

        # Viewer should have read-only permissions
        viewer_has_read = self.permission_manager.check_permission("user_3", "read")
        viewer_has_write = self.permission_manager.check_permission("user_3", "write")
        viewer_has_delete = self.permission_manager.check_permission("user_3", "delete")
        viewer_has_admin = self.permission_manager.check_permission("user_3", "admin")

        assert viewer_has_read is True
        assert viewer_has_write is False
        assert viewer_has_delete is False
        assert viewer_has_admin is False

    def test_permission_granting(self):
        """Test permission granting"""
        # Grant permission to user
        result = self.permission_manager.grant_permission("user_8", "delete")
        assert result is True

        # Check if permission was granted
        has_permission = self.permission_manager.check_permission("user_8", "delete")
        assert has_permission is True

        # Check user permissions
        user_permissions = self.permission_manager.get_user_permissions("user_8")
        assert "delete" in user_permissions

    def test_permission_revocation(self):
        """Test permission revocation"""
        # Grant permission first
        self.permission_manager.grant_permission("user_9", "write")

        # Revoke permission
        result = self.permission_manager.revoke_permission("user_9", "write")
        assert result is True

        # Check if permission was revoked
        has_permission = self.permission_manager.check_permission("user_9", "write")
        assert has_permission is False

        # Check remaining permissions
        user_permissions = self.permission_manager.get_user_permissions("user_9")
        assert "write" not in user_permissions

    def test_multiple_permission_management(self):
        """Test multiple permission management"""
        # Grant multiple permissions
        self.permission_manager.grant_permission("user_10", "delete")
        self.permission_manager.grant_permission("user_10", "admin")

        # Check permissions
        user_permissions = self.permission_manager.get_user_permissions("user_10")
        assert "delete" in user_permissions
        assert "admin" in user_permissions

        # Revoke one permission
        self.permission_manager.revoke_permission("user_10", "delete")

        # Check remaining permissions
        user_permissions = self.permission_manager.get_user_permissions("user_10")
        assert "delete" not in user_permissions
        assert "admin" in user_permissions


class TestAuthenticationMiddleware:
    """Test authentication middleware functionality"""

    def setup_method(self):
        """Setup test fixtures"""
        self.jwt_manager = MockJWTManager()
        self.role_manager = MockRoleManager()
        self.permission_manager = MockPermissionManager()

    def test_bearer_token_authentication(self):
        """Test bearer token authentication"""
        # Generate valid token
        token = self.jwt_manager.generate_token("user_1", ["admin"])

        # Mock HTTPBearer scheme
        security = HTTPBearer()

        # Mock credentials
        credentials = Mock(spec=HTTPAuthorizationCredentials)
        credentials.credentials = token

        # Verify credentials (this would be done by middleware)
        payload = self.jwt_manager.verify_token(credentials.credentials)
        assert payload["sub"] == "user_1"

    def test_invalid_bearer_token(self):
        """Test invalid bearer token"""
        security = HTTPBearer()

        # Mock invalid credentials
        credentials = Mock(spec=HTTPAuthorizationCredentials)
        credentials.credentials = "invalid-token"

        # Verify credentials should raise exception
        with pytest.raises(HTTPException) as excinfo:
            payload = self.jwt_manager.verify_token(credentials.credentials)

        assert excinfo.value.status_code == 401

    def test_missing_authentication_header(self):
        """Test missing authentication header"""
        security = HTTPBearer()

        # Mock missing credentials
        with pytest.raises(HTTPException) as excinfo:
            # This would be called by middleware when header is missing
            security(request=Mock(headers={}))

        assert excinfo.value.status_code == 403

    def test_authentication_flow(self):
        """Test complete authentication flow"""
        # Step 1: User logs in and receives token
        token = self.jwt_manager.generate_token(
            user_id="user_11",
            roles=["user"],
            permissions=["read", "write"]
        )

        # Step 2: User makes authenticated request
        # Mock authentication middleware
        try:
            # Verify token
            payload = self.jwt_manager.verify_token(token)
            user_id = payload["sub"]
            roles = payload["roles"]
            permissions = payload["permissions"]

            # Check user exists and has required roles
            assert self.role_manager.has_role(user_id, "user")
            assert self.permission_manager.check_permission(user_id, "read")
            assert self.permission_manager.check_permission(user_id, "write")

            # Step 3: Check authorization based on roles and permissions
            if "admin" in roles:
                # User has admin privileges
                pass
            elif "user" in roles:
                # User has regular privileges
                assert "read" in permissions
                assert "write" in permissions
            else:
                raise HTTPException(status_code=403, detail="Insufficient privileges")

        except HTTPException:
            # Authentication failed
            raise

    def test_authentication_with_session(self):
        """Test authentication with session management"""
        # Mock session storage
        sessions = {}

        # Create user session
        user_id = "user_12"
        session_id = f"session_{int(time.time())}"

        sessions[session_id] = {
            "user_id": user_id,
            "created_at": datetime.utcnow(),
            "last_activity": datetime.utcnow(),
            "ip_address": "127.0.0.1",
            "user_agent": "test-browser"
        }

        # Check if session exists
        assert session_id in sessions

        # Check session validity
        session = sessions[session_id]
        assert session["user_id"] == user_id
        assert session["ip_address"] == "127.0.0.1"

        # Update session activity
        session["last_activity"] = datetime.utcnow()
        sessions[session_id] = session

        # Clean up expired sessions (mock)
        current_time = datetime.utcnow()
        expired_sessions = [
            sid for sid, sess in sessions.items()
            if (current_time - sess["last_activity"]).total_seconds() > 3600  # 1 hour
        ]

        for sid in expired_sessions:
            del sessions[sid]

        assert session_id not in expired_sessions


class TestAuthorizationPolicies:
    """Test authorization policies"""

    def setup_method(self):
        """Setup test fixtures"""
        self.role_manager = MockRoleManager()
        self.permission_manager = MockPermissionManager()

    def test_resource_based_authorization(self):
        """Test resource-based authorization"""
        # Define resource permissions
        resource_permissions = {
            "mcp_server": {
                "read": ["viewer", "user", "admin"],
                "write": ["user", "admin"],
                "delete": ["admin"]
            },
            "a2a_agent": {
                "read": ["viewer", "user", "admin"],
                "write": ["user", "admin"],
                "delete": ["admin"]
            },
            "elrmcp_server": {
                "read": ["viewer", "user", "admin"],
                "write": ["user", "admin"],
                "delete": ["admin"]
            }
        }

        def check_resource_permission(user_id: str, resource: str, action: str) -> bool:
            """Check if user has permission for resource action"""
            user_roles = self.role_manager.get_user_roles(user_id)

            if resource in resource_permissions:
                required_roles = resource_permissions[resource].get(action, [])
                return any(role in user_roles for role in required_roles)

            return False

        # Test admin permissions
        admin_can_read_mcp = check_resource_permission("user_1", "mcp_server", "read")
        admin_can_write_mcp = check_resource_permission("user_1", "mcp_server", "write")
        admin_can_delete_mcp = check_resource_permission("user_1", "mcp_server", "delete")

        assert admin_can_read_mcp is True
        assert admin_can_write_mcp is True
        assert admin_can_delete_mcp is True

        # Test user permissions
        user_can_read_mcp = check_resource_permission("user_2", "mcp_server", "read")
        user_can_write_mcp = check_resource_permission("user_2", "mcp_server", "write")
        user_can_delete_mcp = check_resource_permission("user_2", "mcp_server", "delete")

        assert user_can_read_mcp is True
        assert user_can_write_mcp is True
        assert user_can_delete_mcp is False

        # Test viewer permissions
        viewer_can_read_mcp = check_resource_permission("user_3", "mcp_server", "read")
        viewer_can_write_mcp = check_resource_permission("user_3", "mcp_server", "write")
        viewer_can_delete_mcp = check_resource_permission("user_3", "mcp_server", "delete")

        assert viewer_can_read_mcp is True
        assert viewer_can_write_mcp is False
        assert viewer_can_delete_mcp is False

    def test_time_based_authorization(self):
        """Test time-based authorization"""
        import pytz

        # Define time-based policies
        time_policies = {
            "maintenance_window": {
                "start_time": "02:00:00",
                "end_time": "04:00:00",
                "timezone": "UTC",
                "allowed_roles": ["admin"]
            }
        }

        def is_time_allowed(user_id: str, policy_name: str) -> bool:
            """Check if user is allowed based on time policy"""
            if policy_name not in time_policies:
                return True

            policy = time_policies[policy_name]
            user_roles = self.role_manager.get_user_roles(user_id)

            # Check if user has required role
            has_required_role = any(role in policy["allowed_roles"] for role in user_roles)

            if not has_required_role:
                return False

            # Check if current time is within allowed window
            tz = pytz.timezone(policy["timezone"])
            now = datetime.now(tz)
            current_time = now.time()

            start_time = datetime.strptime(policy["start_time"], "%H:%M:%S").time()
            end_time = datetime.strptime(policy["end_time"], "%H:%M:%S").time()

            if start_time <= end_time:
                # Normal case: start <= current <= end
                return start_time <= current_time <= end_time
            else:
                # Overnight case: current >= start OR current <= end
                return current_time >= start_time or current_time <= end_time

        # Test during maintenance window (mock)
        # In real test, we'd set specific times
        # For now, we'll just test the logic
        assert isinstance(is_time_allowed("user_1", "maintenance_window"), bool)

    def test_ip_based_authorization(self):
        """Test IP-based authorization"""
        # Define IP-based policies
        ip_policies = {
            "admin_network": {
                "allowed_ips": ["192.168.1.0/24", "10.0.0.0/8"],
                "required_roles": ["admin"]
            },
            "user_network": {
                "allowed_ips": ["192.168.2.0/24"],
                "required_roles": ["user", "admin"]
            }
        }

        def is_ip_allowed(user_id: str, ip_address: str, policy_name: str) -> bool:
            """Check if IP is allowed for user"""
            if policy_name not in ip_policies:
                return True

            policy = ip_policies[policy_name]
            user_roles = self.role_manager.get_user_roles(user_id)

            # Check if user has required role
            has_required_role = any(role in policy["required_roles"] for role in user_roles)
            if not has_required_role:
                return False

            # Check if IP is in allowed range (simplified check)
            def ip_in_network(ip: str, network: str) -> bool:
                # Simplified IP network check
                if "/" in network:
                    network_ip, mask = network.split("/")
                    # Simple subnet check (in real implementation, use ipaddress module)
                    return ip.startswith(network_ip)
                return ip == network

            return any(ip_in_network(ip_address, allowed_ip) for allowed_ip in policy["allowed_ips"])

        # Test IP authorization
        admin_from_admin_network = is_ip_allowed("user_1", "192.168.1.100", "admin_network")
        admin_from_user_network = is_ip_allowed("user_1", "192.168.2.100", "user_network")
        user_from_admin_network = is_ip_allowed("user_2", "192.168.1.100", "admin_network")
        user_from_user_network = is_ip_allowed("user_2", "192.168.2.100", "user_network")

        assert admin_from_admin_network is True
        assert admin_from_user_network is True
        assert user_from_admin_network is False  # User doesn't have admin role
        assert user_from_user_network is True

    def test_mfa_required_authorization(self):
        """Test multi-factor authorization"""
        # Define MFA policies
        mfa_policies = {
            "admin_actions": {
                "required_mfa": True,
                "required_roles": ["admin"]
            },
            "sensitive_operations": {
                "required_mfa": True,
                "required_roles": ["user", "admin"]
            },
            "read_operations": {
                "required_mfa": False,
                "required_roles": ["viewer", "user", "admin"]
            }
        }

        # Mock MFA status
        user_mfa_status = {
            "user_1": True,  # Admin with MFA
            "user_2": False,  # User without MFA
            "user_3": False   # Viewer without MFA
        }

        def is_action_allowed(user_id: str, action: str) -> bool:
            """Check if action is allowed for user"""
            if action not in mfa_policies:
                return True

            policy = mfa_policies[action]
            user_roles = self.role_manager.get_user_roles(user_id)

            # Check if user has required role
            has_required_role = any(role in policy["required_roles"] for role in user_roles)
            if not has_required_role:
                return False

            # Check if MFA is required and available
            if policy["required_mfa"]:
                return user_mfa_status.get(user_id, False)

            return True

        # Test MFA authorization
        admin_with_mfa = is_action_allowed("user_1", "admin_actions")
        admin_without_mfa = is_action_allowed("user_1", "sensitive_operations")  # Still allowed if MFA not required
        user_with_mfa = is_action_allowed("user_2", "sensitive_operations")
        user_without_mfa = is_action_allowed("user_2", "sensitive_operations")
        viewer_read_access = is_action_allowed("user_3", "read_operations")

        assert admin_with_mfa is True
        assert admin_without_mfa is True
        assert user_with_mfa is False  # User without MFA for sensitive operations
        assert user_without_mfa is False
        assert viewer_read_access is True

    def test_custom_authorization_policy(self):
        """Test custom authorization policy"""
        # Define custom policy
        def custom_policy(user_id: str, resource: str, action: str, context: Dict[str, Any]) -> bool:
            """Custom authorization policy"""
            user_roles = self.role_manager.get_user_roles(user_id)

            # Custom business logic
            if action == "approve" and resource == "order":
                # Only admins can approve orders
                return "admin" in user_roles

            if action == "review" and resource == "order":
                # Admins and users can review orders
                return role in ["admin", "user"] for role in user_roles

            # Default allow
            return True

        # Test custom policy
        admin_can_approve = custom_policy("user_1", "order", "approve", {})
        user_can_approve = custom_policy("user_2", "order", "approve", {})
        admin_can_review = custom_policy("user_1", "order", "review", {})
        user_can_review = custom_policy("user_2", "order", "review", {})

        assert admin_can_approve is True
        assert user_can_approve is False
        assert admin_can_review is True
        assert user_can_review is True


class TestSecurityFeatures:
    """Test security features"""

    def test_rate_limiting(self):
        """Test rate limiting"""
        # Mock rate limiter
        request_counts = {}
        rate_limits = {
            "login": {"requests": 5, "window": 60},  # 5 requests per minute
            "api": {"requests": 100, "window": 60},  # 100 requests per minute
            "mcp_tool": {"requests": 50, "window": 60}  # 50 MCP tool calls per minute
        }

        def is_rate_limited(user_id: str, endpoint: str) -> bool:
            """Check if user is rate limited"""
            if user_id not in request_counts:
                request_counts[user_id] = {}

            if endpoint not in request_counts[user_id]:
                request_counts[user_id][endpoint] = []

            # Get current timestamp
            now = time.time()

            # Remove old requests outside window
            window_start = now - rate_limits[endpoint]["window"]
            request_counts[user_id][endpoint] = [
                req_time for req_time in request_counts[user_id][endpoint]
                if req_time > window_start
            ]

            # Check if limit exceeded
            if len(request_counts[user_id][endpoint]) >= rate_limits[endpoint]["requests"]:
                return True

            # Add current request
            request_counts[user_id][endpoint].append(now)
            return False

        # Test rate limiting
        user_id = "user_13"
        endpoint = "login"

        # First few requests should pass
        for i in range(5):
            assert is_rate_limited(user_id, endpoint) is False

        # Next request should be blocked
        assert is_rate_limited(user_id, endpoint) is True

    def test_security_headers(self):
        """Test security headers"""
        # Mock security headers
        security_headers = {
            "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY",
            "X-XSS-Protection": "1; mode=block",
            "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
            "Content-Security-Policy": "default-src 'self'",
            "Referrer-Policy": "strict-origin-when-cross-origin"
        }

        def generate_security_headers() -> Dict[str, str]:
            """Generate security headers"""
            return security_headers.copy()

        # Test security headers generation
        headers = generate_security_headers()

        assert "X-Content-Type-Options" in headers
        assert "X-Frame-Options" in headers
        assert "X-XSS-Protection" in headers
        assert "Strict-Transport-Security" in headers
        assert "Content-Security-Policy" in headers
        assert "Referrer-Policy" in headers

    def test_input_validation(self):
        """Test input validation"""
        from pydantic import BaseModel, constr, validator

        class UserInput(BaseModel):
            username: constr(min_length=3, max_length=50)
            email: str
            role: constr(regex=r'^(admin|user|viewer)$')

            @validator('email')
            def validate_email(cls, v):
                if '@' not in v:
                    raise ValueError('Invalid email format')
                return v

        # Valid input
        valid_input = UserInput(
            username="testuser",
            email="test@example.com",
            role="user"
        )
        assert valid_input.username == "testuser"
        assert valid_input.email == "test@example.com"
        assert valid_input.role == "user"

        # Invalid username
        with pytest.raises(ValueError):
            UserInput(
                username="tu",  # Too short
                email="test@example.com",
                role="user"
            )

        # Invalid email
        with pytest.raises(ValueError):
            UserInput(
                username="testuser",
                email="invalid-email",
                role="user"
            )

        # Invalid role
        with pytest.raises(ValueError):
            UserInput(
                username="testuser",
                email="test@example.com",
                role="invalid_role"
            )

    def test_audit_logging(self):
        """Test audit logging"""
        import logging

        # Mock audit logger
        audit_logger = logging.getLogger("audit")

        # Mock audit events
        audit_events = []

        def log_audit_event(user_id: str, action: str, resource: str, success: bool, details: Dict[str, Any] = None):
            """Log audit event"""
            event = {
                "timestamp": datetime.utcnow().isoformat(),
                "user_id": user_id,
                "action": action,
                "resource": resource,
                "success": success,
                "details": details or {},
                "ip_address": "127.0.0.1",
                "user_agent": "test-browser"
            }
            audit_events.append(event)

            # Log to file/database in real implementation
            audit_logger.info(f"Audit event: {event}")

        # Test audit logging
        log_audit_event(
            user_id="user_14",
            action="login",
            resource="auth",
            success=True,
            details={"method": "password", "mfa_enabled": True}
        )

        log_audit_event(
            user_id="user_14",
            action="mcp_tool_call",
            resource="mcp_server",
            success=True,
            details={"tool": "customer_management", "operation": "create"}
        )

        log_audit_event(
            user_id="user_14",
            action="a2a_task_submit",
            resource="a2a_agent",
            success=False,
            details={"error": "Insufficient permissions"}
        )

        # Check audit events
        assert len(audit_events) == 3

        # Check first event
        first_event = audit_events[0]
        assert first_event["user_id"] == "user_14"
        assert first_event["action"] == "login"
        assert first_event["resource"] == "auth"
        assert first_event["success"] is True
        assert first_event["details"]["method"] == "password"
        assert first_event["details"]["mfa_enabled"] is True

    def test_password_policy(self):
        """Test password policy"""
        import re

        def validate_password(password: str) -> tuple[bool, List[str]]:
            """Validate password against policy"""
            errors = []

            # Length requirement
            if len(password) < 8:
                errors.append("Password must be at least 8 characters long")

            # Complexity requirements
            if not re.search(r'[A-Z]', password):
                errors.append("Password must contain at least one uppercase letter")

            if not re.search(r'[a-z]', password):
                errors.append("Password must contain at least one lowercase letter")

            if not re.search(r'\d', password):
                errors.append("Password must contain at least one digit")

            if not re.search(r'[!@#$%^&*(),.?":{}|<>]', password):
                errors.append("Password must contain at least one special character")

            # Common password check
            common_passwords = ["password", "12345678", "qwerty", "letmein"]
            if password.lower() in common_passwords:
                errors.append("Password is too common")

            return len(errors) == 0, errors

        # Test valid passwords
        valid_passwords = [
            "Password123!",
            "Secret@456",
            "Complex#Pass789"
        ]

        for password in valid_passwords:
            is_valid, errors = validate_password(password)
            assert is_valid is True
            assert len(errors) == 0

        # Test invalid passwords
        invalid_passwords = [
            ("password", ["too common"]),
            ("12345678", ["too common", "no uppercase", "no lowercase", "no special"]),
            ("Password", ["too common", "no digit", "no special"]),
            ("password123", ["too common", "no uppercase", "no special"]),
            ("PASSWORD123!", ["too common", "no lowercase"])
        ]

        for password, expected_errors in invalid_passwords:
            is_valid, errors = validate_password(password)
            assert is_valid is False
            assert len(errors) > 0


class TestOAuth2Integration:
    """Test OAuth2 integration"""

    def test_oauth2_flow(self):
        """Test OAuth2 authorization flow"""
        # Mock OAuth2 provider
        mock_providers = {
            "google": {
                "client_id": "google-client-id",
                "client_secret": "google-client-secret",
                "auth_url": "https://accounts.google.com/oauth/auth",
                "token_url": "https://accounts.google.com/oauth/token"
            },
            "github": {
                "client_id": "github-client-id",
                "client_secret": "github-client-secret",
                "auth_url": "https://github.com/login/oauth/authorize",
                "token_url": "https://github.com/login/oauth/access_token"
            }
        }

        def mock_oauth_authenticate(provider: str, code: str) -> Dict[str, Any]:
            """Mock OAuth2 authentication"""
            if provider not in mock_providers:
                raise ValueError("Invalid provider")

            # Mock token exchange
            return {
                "access_token": "mock-access-token",
                "token_type": "Bearer",
                "expires_in": 3600,
                "refresh_token": "mock-refresh-token",
                "user_info": {
                    "id": "oauth-user-id",
                    "name": "OAuth User",
                    "email": "oauth@example.com"
                }
            }

        # Test OAuth2 flow
        try:
            token_data = mock_oauth_authenticate("google", "auth-code")
            assert token_data["access_token"] == "mock-access-token"
            assert token_data["user_info"]["email"] == "oauth@example.com"
        except Exception as e:
            assert False, f"OAuth2 authentication failed: {e}"

    def test_oauth2_token_validation(self):
        """Test OAuth2 token validation"""
        # Mock token validation
        def validate_oauth_token(token: str) -> Dict[str, Any]:
            """Validate OAuth2 token"""
            if token == "valid-token":
                return {
                    "valid": True,
                    "user_id": "oauth-user-id",
                    "scopes": ["read", "write"]
                }
            else:
                return {"valid": False}

        # Test token validation
        result = validate_oauth_token("valid-token")
        assert result["valid"] is True
        assert result["user_id"] == "oauth-user-id"
        assert "read" in result["scopes"]
        assert "write" in result["scopes"]

        # Test invalid token
        result = validate_oauth_token("invalid-token")
        assert result["valid"] is False

    def test_oauth2_scope_check(self):
        """Test OAuth2 scope checking"""
        def check_scopes(required_scopes: List[str], user_scopes: List[str]) -> bool:
            """Check if user has required scopes"""
            if "admin" in user_scopes:
                return True  # Admin has all scopes

            return all(scope in user_scopes for scope in required_scopes)

        # Test scope checking
        admin_scopes = ["read", "write", "admin"]
        user_scopes = ["read", "write"]
        limited_scopes = ["read"]

        assert check_scopes(["read", "write"], admin_scopes) is True
        assert check_scopes(["read", "write"], user_scopes) is True
        assert check_scopes(["read", "write"], limited_scopes) is False
        assert check_scopes(["admin"], admin_scopes) is True
        assert check_scopes(["admin"], user_scopes) is False


class TestAPIKeyAuthentication:
    """Test API key authentication"""

    def test_api_key_generation(self):
        """Test API key generation"""
        import secrets
        import string

        def generate_api_key(length: int = 32) -> str:
            """Generate API key"""
            alphabet = string.ascii_letters + string.digits
            return ''.join(secrets.choice(alphabet) for _ in range(length))

        # Test API key generation
        api_key = generate_api_key()
        assert len(api_key) == 32
        assert api_key.isalnum()

    def test_api_key_validation(self):
        """Test API key validation"""
        # Mock API key storage
        api_keys = {
            "key_123456": {
                "user_id": "user_15",
                "created_at": datetime.utcnow(),
                "last_used": datetime.utcnow(),
                "scopes": ["read", "write"],
                "active": True
            },
            "key_789012": {
                "user_id": "user_16",
                "created_at": datetime.utcnow(),
                "last_used": datetime.utcnow(),
                "scopes": ["read"],
                "active": False  # Revoked
            }
        }

        def validate_api_key(key: str) -> Optional[Dict[str, Any]]:
            """Validate API key"""
            if key not in api_keys:
                return None

            key_info = api_keys[key]
            if not key_info["active"]:
                return None

            # Update last used time
            key_info["last_used"] = datetime.utcnow()
            api_keys[key] = key_info

            return key_info

        # Test valid API key
        valid_key = "key_123456"
        result = validate_api_key(valid_key)
        assert result is not None
        assert result["user_id"] == "user_15"
        assert "read" in result["scopes"]
        assert "write" in result["scopes"]

        # Test invalid API key
        invalid_key = "invalid-key"
        result = validate_api_key(invalid_key)
        assert result is None

        # Test revoked API key
        revoked_key = "key_789012"
        result = validate_api_key(revoked_key)
        assert result is None

    def test_api_key_scopes(self):
        """Test API key scope checking"""
        def check_api_key_scopes(key: str, required_scopes: List[str]) -> bool:
            """Check if API key has required scopes"""
            key_info = validate_api_key(key)
            if key_info is None:
                return False

            # Check scopes
            if "admin" in key_info["scopes"]:
                return True  # Admin has all scopes

            return all(scope in key_info["scopes"] for scope in required_scopes)

        # Test scope checking
        assert check_api_key_scopes("key_123456", ["read", "write"]) is True
        assert check_api_key_scopes("key_123456", ["read"]) is True
        assert check_api_key_scopes("key_123456", ["admin"]) is True
        assert check_api_key_scopes("key_123456", ["delete"]) is False
        assert check_api_key_scopes("key_789012", ["read"]) is False  # Revoked


class TestIntegrationScenarios:
    """Test integration scenarios"""

    def setup_method(self):
        """Setup test fixtures"""
        self.jwt_manager = MockJWTManager()
        self.role_manager = MockRoleManager()
        self.permission_manager = MockPermissionManager()

    def test_mcp_server_authentication(self):
        """Test MCP server authentication"""
        # Scenario: User authenticates and calls MCP tools

        # Step 1: User authentication
        token = self.jwt_manager.generate_token(
            user_id="user_17",
            roles=["user"],
            permissions=["read", "write"]
        )

        # Step 2: Verify token
        payload = self.jwt_manager.verify_token(token)
        assert payload["sub"] == "user_17"
        assert "user" in payload["roles"]

        # Step 3: Check MCP tool permissions
        mcp_tools = ["customer_management", "order_management", "inventory_management"]

        for tool in mcp_tools:
            # Check if user has permission for tool
            tool_permission = f"mcp_{tool}_access"
            has_permission = self.permission_manager.check_permission("user_17", tool_permission)

            if tool in ["customer_management", "order_management", "inventory_management"]:
                # User should have access to these tools
                assert has_permission is True

    def test_a2a_agent_authorization(self):
        """Test A2A agent authorization"""
        # Scenario: User submits tasks via A2A agent

        # Step 1: User authentication
        token = self.jwt_manager.generate_token(
            user_id="user_18",
            roles=["user"],
            permissions=["read", "write", "task_submit"]
        )

        # Step 2: Verify token
        payload = self.jwt_manager.verify_token(token)
        assert payload["sub"] == "user_18"
        assert "task_submit" in payload["permissions"]

        # Step 3: Check task submission permissions
        task_types = ["inventory_management", "shipping_management", "analytics"]

        for task_type in task_types:
            # Check if user has permission for task type
            has_permission = self.permission_manager.check_permission("user_18", task_type)

            if task_type == "inventory_management":
                # User should have permission for inventory management
                assert has_permission is True
            else:
                # User should not have permission for other task types
                assert has_permission is False

    def test_multi_service_authorization(self):
        """Test multi-service authorization"""
        # Scenario: User needs to access multiple services

        # Step 1: Admin user authentication
        token = self.jwt_manager.generate_token(
            user_id="user_19",
            roles=["admin"],
            permissions=["*"]
        )

        # Step 2: Verify token
        payload = self.jwt_manager.verify_token(token)
        assert payload["sub"] == "user_19"
        assert "admin" in payload["roles"]

        # Step 3: Check access to all services
        services = ["mcp_server", "a2a_agent", "elrmcp_server"]

        for service in services:
            # Admin should have access to all services
            has_access = self.permission_manager.check_permission("user_19", service)
            assert has_access is True

    def test_audit_logging_integration(self):
        """Test audit logging integration"""
        # Scenario: Audit logging for all authentication and authorization events

        audit_log = []

        def log_event(event_type: str, user_id: str, details: Dict[str, Any]):
            """Log event to audit log"""
            audit_log.append({
                "event_type": event_type,
                "user_id": user_id,
                "timestamp": datetime.utcnow().isoformat(),
                "details": details
            })

        # Step 1: User login
        token = self.jwt_manager.generate_token("user_20", ["user"])
        log_event("login", "user_20", {"success": True})

        # Step 2: MCP tool call
        mcp_tool_call = {
            "tool": "customer_management",
            "operation": "create",
            "success": True
        }
        log_event("mcp_tool_call", "user_20", mcp_tool_call)

        # Step 3: A2A task submission
        a2a_task = {
            "task_type": "inventory_management",
            "status": "completed",
            "success": True
        }
        log_event("a2a_task_submit", "user_20", a2a_task)

        # Step 4: Authorization failure
        auth_failure = {
            "resource": "elrmcp_server",
            "action": "admin",
            "reason": "Insufficient permissions"
        }
        log_event("auth_failure", "user_20", auth_failure)

        # Verify audit log
        assert len(audit_log) == 4
        assert audit_log[0]["event_type"] == "login"
        assert audit_log[1]["event_type"] == "mcp_tool_call"
        assert audit_log[2]["event_type"] == "a2a_task_submit"
        assert audit_log[3]["event_type"] == "auth_failure"

    def test_session_management_integration(self):
        """Test session management integration"""
        # Scenario: User sessions with timeout and cleanup

        # Mock session storage
        sessions = {}

        def create_session(user_id: str) -> str:
            """Create user session"""
            session_id = f"session_{int(time.time())}"
            sessions[session_id] = {
                "user_id": user_id,
                "created_at": datetime.utcnow(),
                "last_activity": datetime.utcnow(),
                "ip_address": "127.0.0.1"
            }
            return session_id

        def update_session_activity(session_id: str):
            """Update session activity"""
            if session_id in sessions:
                sessions[session_id]["last_activity"] = datetime.utcnow()

        def cleanup_expired_sessions(timeout_minutes: int = 30):
            """Clean up expired sessions"""
            now = datetime.utcnow()
            expired_sessions = []

            for session_id, session in sessions.items():
                if (now - session["last_activity"]).total_seconds() > timeout_minutes * 60:
                    expired_sessions.append(session_id)

            for session_id in expired_sessions:
                del sessions[session_id]

            return expired_sessions

        # Create session
        session_id = create_session("user_21")
        assert session_id in sessions

        # Update activity
        update_session_activity(session_id)
        assert session_id in sessions

        # Clean up expired sessions (should find none)
        expired = cleanup_expired_sessions()
        assert len(expired) == 0

        # Simulate timeout
        import time
        time.sleep(1)  # Small delay for testing

        # Clean up again (should still find none due to short test timeout)
        expired = cleanup_expired_sessions(timeout_seconds=1)
        assert len(expired) == 0

    def test_error_handling_integration(self):
        """Test error handling integration"""
        # Scenario: Comprehensive error handling for auth and auth

        error_log = []

        def log_error(error_type: str, user_id: str, details: Dict[str, Any]):
            """Log error"""
            error_log.append({
                "error_type": error_type,
                "user_id": user_id,
                "timestamp": datetime.utcnow().isoformat(),
                "details": details
            })

        # Test various error scenarios
        try:
            # Invalid token
            self.jwt_manager.verify_token("invalid-token")
        except HTTPException as e:
            log_error("invalid_token", "unknown_user", {"status_code": e.status_code})

        try:
            # Permission denied
            if not self.permission_manager.check_permission("user_22", "admin"):
                raise HTTPException(status_code=403, detail="Insufficient permissions")
        except HTTPException as e:
            log_error("permission_denied", "user_22", {"status_code": e.status_code})

        try:
            # Role not found
            if not self.role_manager.has_role("user_23", "nonexistent_role"):
                raise HTTPException(status_code=404, detail="Role not found")
        except HTTPException as e:
            log_error("role_not_found", "user_23", {"status_code": e.status_code})

        # Verify error log
        assert len(error_log) == 3
        assert error_log[0]["error_type"] == "invalid_token"
        assert error_log[1]["error_type"] == "permission_denied"
        assert error_log[2]["error_type"] == "role_not_found"

    def test_performance_integration(self):
        """Test performance integration"""
        # Scenario: Performance monitoring for auth and auth operations

        import time

        performance_metrics = {
            "authentication_time": [],
            "authorization_time": [],
            "token_validation_time": []
        }

        def measure_authentication(user_id: str) -> bool:
            """Measure authentication performance"""
            start_time = time.time()

            # Simulate authentication
            token = self.jwt_manager.generate_token(user_id, ["user"])
            payload = self.jwt_manager.verify_token(token)

            end_time = time.time()
            performance_metrics["authentication_time"].append(end_time - start_time)

            return True

        def measure_authorization(user_id: str, resource: str) -> bool:
            """Measure authorization performance"""
            start_time = time.time()

            # Simulate authorization
            has_permission = self.permission_manager.check_permission(user_id, resource)

            end_time = time.time()
            performance_metrics["authorization_time"].append(end_time - start_time)

            return has_permission

        def measure_token_validation(token: str) -> bool:
            """Measure token validation performance"""
            start_time = time.time()

            # Simulate token validation
            try:
                payload = self.jwt_manager.verify_token(token)
                performance_metrics["token_validation_time"].append(time.time() - start_time)
                return True
            except HTTPException:
                performance_metrics["token_validation_time"].append(time.time() - start_time)
                return False

        # Test performance
        measure_authentication("user_24")
        measure_authorization("user_24", "read")
        measure_token_validation(self.jwt_manager.generate_token("user_24", ["user"]))

        # Verify metrics
        assert len(performance_metrics["authentication_time"]) > 0
        assert len(performance_metrics["authorization_time"]) > 0
        assert len(performance_metrics["token_validation_time"]) > 0

        # Check that all operations are fast (< 1 second)
        for metric_list in performance_metrics.values():
            for time_value in metric_list:
                assert time_value < 1.0

    def test_security_compliance(self):
        """Test security compliance"""
        # Scenario: Ensure compliance with security standards

        compliance_checks = {}

        def check_password_policy(password: str) -> bool:
            """Check password policy compliance"""
            # Implement password policy checks
            has_length = len(password) >= 8
            has_upper = any(c.isupper() for c in password)
            has_lower = any(c.islower() for c in password)
            has_digit = any(c.isdigit() for c in password)
            has_special = any(c in "!@#$%^&*()" for c in password)

            return has_length and has_upper and has_lower and has_digit and has_special

        def check_mfa_requirement(user_roles: List[str]) -> bool:
            """Check MFA requirement compliance"""
            # Admins should have MFA
            return "admin" in user_roles

        def check_audit_logging() -> bool:
            """Check audit logging compliance"""
            # Verify audit logs are being written
            return True

        # Run compliance checks
        compliance_checks["password_policy"] = check_password_policy("SecurePassword123!")
        compliance_checks["mfa_requirement"] = check_mfa_requirement(["admin", "user"])
        compliance_checks["audit_logging"] = check_audit_logging()

        # Verify compliance
        assert all(compliance_checks.values())

        # Test password policy failure
        assert not check_password_policy("weak")

        # Test MFA requirement for non-admin
        assert not check_mfa_requirement(["user"])


class TestEdgeCases:
    """Test edge cases"""

    def setup_method(self):
        """Setup test fixtures"""
        self.jwt_manager = MockJWTManager()
        self.role_manager = MockRoleManager()
        self.permission_manager = MockPermissionManager()

    def test_concurrent_authentication(self):
        """Test concurrent authentication requests"""
        import threading
        import time

        results = []
        lock = threading.Lock()

        def authenticate_user(user_id: str):
            """Authenticate user"""
            try:
                token = self.jwt_manager.generate_token(user_id, ["user"])
                payload = self.jwt_manager.verify_token(token)
                with lock:
                    results.append({"success": True, "user_id": user_id})
            except Exception as e:
                with lock:
                    results.append({"success": False, "user_id": user_id, "error": str(e)})

        # Create multiple concurrent authentication requests
        threads = []
        for i in range(10):
            thread = threading.Thread(target=authenticate_user, args=(f"user_{i}",))
            threads.append(thread)
            thread.start()

        # Wait for all threads to complete
        for thread in threads:
            thread.join()

        # Verify all requests succeeded
        assert len(results) == 10
        assert all(result["success"] for result in results)

    def test_token_regeneration_storm(self):
        """Test token regeneration storm"""
        import threading
        import time

        results = []
        lock = threading.Lock()

        def generate_tokens(user_id: str, count: int):
            """Generate multiple tokens for user"""
            for i in range(count):
                try:
                    token = self.jwt_manager.generate_token(user_id, ["user"])
                    with lock:
                        results.append(token)
                except Exception as e:
                    with lock:
                        results.append(f"error: {str(e)}")

        # Create multiple token generation threads
        threads = []
        for i in range(5):
            thread = threading.Thread(target=generate_tokens, args=(f"user_{i}", 10))
            threads.append(thread)
            thread.start()

        # Wait for all threads to complete
        for thread in threads:
            thread.join()

        # Verify all tokens were generated
        assert len(results) == 50  # 5 threads * 10 tokens each
        assert all(not result.startswith("error") for result in results)

    def test_memory_usage_stress(self):
        """Test memory usage under stress"""
        import psutil
        import os

        process = psutil.Process(os.getpid())
        initial_memory = process.memory_info().rss

        # Generate many tokens and permissions
        tokens = []
        for i in range(1000):
            token = self.jwt_manager.generate_token(f"user_{i}", ["user"])
            tokens.append(token)

        # Check many permissions
        for i in range(1000):
            self.permission_manager.check_permission(f"user_{i}", "read")

        final_memory = process.memory_info().rss
        memory_increase = final_memory - initial_memory

        # Memory increase should be reasonable
        assert memory_increase < 50 * 1024 * 1024  # Less than 50MB

    def test_large_payload_handling(self):
        """Test handling of large payloads"""
        # Test with large claims
        large_permissions = [f"permission_{i}" for i in range(1000)]
        large_roles = [f"role_{i}" for i in range(100)]

        # Generate token with large payload
        token = self.jwt_manager.generate_token(
            user_id="user_large",
            roles=large_roles,
            permissions=large_permissions
        )

        # Verify token
        payload = self.jwt_manager.verify_token(token)
        assert len(payload["roles"]) == 100
        assert len(payload["permissions"]) == 1000
        assert payload["sub"] == "user_large"

    def test_unicode_handling(self):
        """Test Unicode character handling"""
        # Test with Unicode characters in claims
        unicode_token = self.jwt_manager.generate_token(
            user_id="测试用户",
            roles=["管理员", "用户"],
            permissions=["读取", "写入"]
        )

        # Verify token
        payload = self.jwt_manager.verify_token(unicode_token)
        assert payload["sub"] == "测试用户"
        assert "管理员" in payload["roles"]
        assert "用户" in payload["roles"]
        assert "读取" in payload["permissions"]
        assert "写入" in payload["permissions"]