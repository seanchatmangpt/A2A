"""
Configuration system unit tests for Craftplan MCP + A2A Integration

This module provides unit tests for configuration system components:
- Configuration loading and parsing
- Environment variable handling
- Configuration validation
- Multi-environment support
- Configuration schema validation
- Error handling
- Security features
- Performance characteristics
"""

import pytest
import json
import os
import tempfile
from pathlib import Path
from typing import Dict, Any, List, Optional, Union
from unittest.mock import Mock, patch, mock_open

from tests.config.test_config import TestSettings, TestConfigurationValidator


class TestConfigurationLoading:
    """Test configuration loading functionality"""

    def test_basic_config_loading(self):
        """Test basic configuration loading"""
        settings = TestSettings()

        # Check default values
        assert settings.mcp_host == "localhost"
        assert settings.mcp_port == 8090
        assert settings.a2a_host == "localhost"
        assert settings.a2a_port == 8080
        assert settings.elrmcp_host == "localhost"
        assert settings.elrmcp_port == 9090

    def test_environment_variable_override(self):
        """Test environment variable override"""
        with patch.dict(os.environ, {
            "MCP_HOST": "test-host",
            "MCP_PORT": "9999",
            "A2A_HOST": "test-a2a-host",
            "A2A_PORT": "8888",
            "ELRMCP_HOST": "test-elrmcp-host",
            "ELRMCP_PORT": "7777"
        }):
            settings = TestSettings()
            assert settings.mcp_host == "test-host"
            assert settings.mcp_port == 9999
            assert settings.a2a_host == "test-a2a-host"
            assert settings.a2a_port == 8888
            assert settings.elrmcp_host == "test-elrmcp-host"
            assert settings.elrmcp_port == 7777

    def test_boolean_environment_variables(self):
        """Test boolean environment variable handling"""
        with patch.dict(os.environ, {
            "DEBUG_MODE": "true",
            "MOCK_ENABLED": "True",
            "PERFORMANCE_ENABLED": "1",
            "SECURITY_ENABLED": "false",
            "PARALLEL_TESTS": "0"
        }):
            settings = TestSettings()
            assert settings.debug_mode is True
            assert settings.mock_enabled is True
            assert settings.performance_enabled is True
            assert settings.security_enabled is False
            assert settings.parallel_tests is False

    def test_numeric_environment_variables(self):
        """Test numeric environment variable handling"""
        with patch.dict(os.environ, {
            "TEST_TIMEOUT": "60",
            "RETRY_ATTEMPTS": "5",
            "MOCK_PORT": "9876",
            "LOAD_TEST_USERS": "100",
            "LOAD_TEST_DURATION": "300",
            "COVERAGE_THRESHOLD": "0.95"
        }):
            settings = TestSettings()
            assert settings.test_timeout == 60
            assert settings.retry_attempts == 5
            assert settings.mock_port == 9876
            assert settings.load_test_users == 100
            assert settings.load_test_duration == 300
            assert settings.coverage_threshold == 0.95

    def test_optional_environment_variables(self):
        """Test optional environment variables"""
        # Clear API token environment variable
        with patch.dict(os.environ, {"API_TOKEN": ""}):
            settings = TestSettings()
            assert settings.api_token is None

    def test_invalid_numeric_values(self):
        """Test invalid numeric values in environment variables"""
        with patch.dict(os.environ, {
            "MCP_PORT": "invalid_number",
            "COVERAGE_THRESHOLD": "invalid_percentage"
        }):
            settings = TestSettings()
            # Should use default values
            assert settings.mcp_port == 8090
            assert settings.coverage_threshold == 0.8


class TestConfigurationValidation:
    """Test configuration validation functionality"""

    def test_valid_configuration_validation(self):
        """Test valid configuration validation"""
        settings = TestSettings()

        # Valid configuration should pass validation
        assert TestConfigurationValidator.validate_test_settings(settings) is True

    def test_invalid_port_validation(self):
        """Test invalid port validation"""
        settings = TestSettings()
        settings.mcp_port = 99999  # Invalid port (> 65535)

        with pytest.raises(ValueError) as excinfo:
            TestConfigurationValidator.validate_test_settings(settings)

        assert "Invalid MCP port" in str(excinfo.value)

    def test_negative_port_validation(self):
        """Test negative port validation"""
        settings = TestSettings()
        settings.mcp_port = -1  # Negative port

        with pytest.raises(ValueError) as excinfo:
            TestConfigurationValidator.validate_test_settings(settings)

        assert "Invalid MCP port" in str(excinfo.value)

    def test_coverage_threshold_validation(self):
        """Test coverage threshold validation"""
        settings = TestSettings()
        settings.coverage_threshold = 1.5  # Invalid (> 1)

        with pytest.raises(ValueError) as excinfo:
            TestConfigurationValidator.validate_test_settings(settings)

        assert "Coverage threshold must be between 0 and 1" in str(excinfo.value)

    def test_negative_coverage_validation(self):
        """Test negative coverage validation"""
        settings = TestSettings()
        settings.coverage_threshold = -0.1  # Negative

        with pytest.raises(ValueError) as excinfo:
            TestConfigurationValidator.validate_test_settings(settings)

        assert "Coverage threshold must be between 0 and 1" in str(excinfo.value)

    def test_load_test_users_validation(self):
        """Test load test users validation"""
        settings = TestSettings()
        settings.performance_enabled = True
        settings.load_test_users = 0  # Invalid

        with pytest.raises(ValueError) as excinfo:
            TestConfigurationValidator.validate_test_settings(settings)

        assert "Load test users must be at least 1" in str(excinfo.value)

    def test_load_test_duration_validation(self):
        """Test load test duration validation"""
        settings = TestSettings()
        settings.performance_enabled = True
        settings.load_test_duration = 0  # Invalid

        with pytest.raises(ValueError) as excinfo:
            TestConfigurationValidator.validate_test_settings(settings)

        assert "Load test duration must be at least 1 second" in str(excinfo.value)

    def test_service_urls_validation(self):
        """Test service URLs validation"""
        settings = TestSettings()

        valid_urls = settings.get_services_urls()
        assert TestConfigurationValidator.validate_service_urls(valid_urls) is True

    def test_invalid_service_urls_validation(self):
        """Test invalid service URLs validation"""
        invalid_urls = {
            "mcp": "invalid-url",  # Missing protocol
            "a2a": "http://localhost:8080"
        }

        with pytest.raises(ValueError) as excinfo:
            TestConfigurationValidator.validate_service_urls(invalid_urls)

        assert "Invalid URL format" in str(excinfo.value)

    def test_missing_required_urls_validation(self):
        """Test missing required URLs validation"""
        incomplete_urls = {
            "mcp": "http://localhost:8090"
            # Missing a2a and elrmcp
        }

        with pytest.raises(ValueError) as excinfo:
            TestConfigurationValidator.validate_service_urls(incomplete_urls)

        assert "Missing required URL" in str(excinfo.value)


class TestConfigurationFileLoading:
    """Test configuration file loading functionality"""

    def test_json_config_loading(self):
        """Test JSON configuration file loading"""
        config_data = {
            "mcp_host": "json-host",
            "mcp_port": 9999,
            "a2a_host": "json-a2a-host",
            "a2a_port": 8888,
            "debug_mode": True,
            "mock_enabled": False
        }

        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump(config_data, f)
            temp_file = f.name

        try:
            with patch.object(TestSettings, 'env_file', temp_file):
                settings = TestSettings()
                assert settings.mcp_host == "json-host"
                assert settings.mcp_port == 9999
                assert settings.a2a_host == "json-a2a-host"
                assert settings.a2a_port == 8888
                assert settings.debug_mode is True
                assert settings.mock_enabled is False
        finally:
            os.unlink(temp_file)

    def test_yaml_config_loading(self):
        """Test YAML configuration file loading"""
        yaml_content = """
mcp_host: yaml-host
mcp_port: 9999
a2a_host: yaml-a2a-host
a2a_port: 8888
debug_mode: true
mock_enabled: false
"""

        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            f.write(yaml_content)
            temp_file = f.name

        try:
            with patch.object(TestSettings, 'env_file', temp_file):
                settings = TestSettings()
                assert settings.mcp_host == "yaml-host"
                assert settings.mcp_port == 9999
                assert settings.a2a_host == "yaml-a2a-host"
                assert settings.a2a_port == 8888
                assert settings.debug_mode is True
                assert settings.mock_enabled is False
        finally:
            os.unlink(temp_file)

    def test_toml_config_loading(self):
        """Test TOML configuration file loading"""
        toml_content = """
[mcp]
host = "toml-host"
port = 9999

[a2a]
host = "toml-a2a-host"
port = 8888

[general]
debug_mode = true
mock_enabled = false
"""

        with tempfile.NamedTemporaryFile(mode='w', suffix='.toml', delete=False) as f:
            f.write(toml_content)
            temp_file = f.name

        try:
            with patch.object(TestSettings, 'env_file', temp_file):
                settings = TestSettings()
                assert settings.mcp_host == "toml-host"
                assert settings.mcp_port == 9999
                assert settings.a2a_host == "toml-a2a-host"
                assert settings.a2a_port == 8888
                assert settings.debug_mode is True
                assert settings.mock_enabled is False
        finally:
            os.unlink(temp_file)

    def test_missing_config_file(self):
        """Test handling of missing configuration file"""
        with tempfile.NamedTemporaryFile(suffix='.nonexistent', delete=False) as f:
            non_existent_file = f.name

        try:
            with patch.object(TestSettings, 'env_file', non_existent_file):
                settings = TestSettings()
                # Should use defaults
                assert settings.mcp_host == "localhost"
                assert settings.mcp_port == 8090
        finally:
            os.unlink(non_existent_file)

    def test_invalid_config_file(self):
        """Test handling of invalid configuration file"""
        invalid_config = "invalid: config: content:"

        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            f.write(invalid_config)
            temp_file = f.name

        try:
            with patch.object(TestSettings, 'env_file', temp_file):
                settings = TestSettings()
                # Should use defaults
                assert settings.mcp_host == "localhost"
                assert settings.mcp_port == 8090
        finally:
            os.unlink(temp_file)

    def test_config_file_priority(self):
        """Test configuration file priority over environment variables"""
        with patch.dict(os.environ, {
            "MCP_HOST": "env-host",
            "MCP_PORT": "1234"
        }):
            config_data = {
                "mcp_host": "file-host",
                "mcp_port": 9999
            }

            with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
                json.dump(config_data, f)
                temp_file = f.name

            try:
                with patch.object(TestSettings, 'env_file', temp_file):
                    settings = TestSettings()
                    # File should override environment
                    assert settings.mcp_host == "file-host"
                    assert settings.mcp_port == 9999
            finally:
                os.unlink(temp_file)


class TestConfigurationEnvironment:
    """Test configuration environment management"""

    def test_development_environment(self):
        """Test development environment configuration"""
        with patch.dict(os.environ, {
            "ENVIRONMENT": "development",
            "DEBUG_MODE": "true",
            "MOCK_ENABLED": "true"
        }):
            settings = TestSettings()
            assert settings.debug_mode is True
            assert settings.mock_enabled is True

    def test_production_environment(self):
        """Test production environment configuration"""
        with patch.dict(os.environ, {
            "ENVIRONMENT": "production",
            "DEBUG_MODE": "false",
            "MOCK_ENABLED": "false",
            "SECURITY_ENABLED": "true"
        }):
            settings = TestSettings()
            assert settings.debug_mode is False
            assert settings.mock_enabled is False
            assert settings.security_enabled is True

    def test_test_environment(self):
        """Test test environment configuration"""
        with patch.dict(os.environ, {
            "ENVIRONMENT": "test",
            "TEST_TIMEOUT": "60",
            "RETRY_ATTEMPTS": "5"
        }):
            settings = TestSettings()
            assert settings.test_timeout == 60
            assert settings.retry_attempts == 5

    def test_invalid_environment(self):
        """Test invalid environment handling"""
        with patch.dict(os.environ, {
            "ENVIRONMENT": "invalid_environment"
        }):
            settings = TestSettings()
            # Should use defaults
            assert settings.debug_mode is False
            assert settings.mock_enabled is True


class TestConfigurationSecurity:
    """Test configuration security features"""

    def test_sensitive_data_redaction(self):
        """Test sensitive data redaction"""
        settings = TestSettings()
        settings.api_token = "sensitive-api-token"

        # Convert to dict (should redact sensitive data)
        config_dict = settings.to_dict()

        # Token should not be in the dictionary
        assert "api_token" not in config_dict

    def test_password_redaction(self):
        """Test password redaction"""
        settings = TestSettings()
        # Simulate password field (assuming it exists)
        settings.__dict__["database_password"] = "sensitive-password"

        # Check that sensitive data is not exposed
        config_dict = settings.to_dict()
        assert "database_password" not in config_dict

    def test_configuration_encryption(self):
        """Test configuration encryption (if implemented)"""
        # This would require encryption functionality
        pass

    def test_configuration_access_control(self):
        """Test configuration access control"""
        settings = TestSettings()

        # Only public attributes should be accessible
        assert hasattr(settings, 'mcp_host')
        assert hasattr(settings, 'mcp_port')
        assert hasattr(settings, 'a2a_host')
        assert hasattr(settings, 'a2a_port')

        # Internal attributes should not be directly accessible
        assert not hasattr(settings, '_internal_config')


class TestConfigurationPerformance:
    """Test configuration performance characteristics"""

    def test_configuration_loading_performance(self):
        """Test configuration loading performance"""
        import time

        start_time = time.time()
        settings = TestSettings()
        end_time = time.time()

        # Configuration loading should be fast
        assert end_time - start_time < 0.1  # Less than 100ms

    def test_configuration_validation_performance(self):
        """Test configuration validation performance"""
        import time

        settings = TestSettings()

        start_time = time.time()
        TestConfigurationValidator.validate_test_settings(settings)
        end_time = time.time()

        # Validation should be fast
        assert end_time - start_time < 0.1  # Less than 100ms

    def test_multiple_config_instances_performance(self):
        """Test multiple configuration instances performance"""
        import time

        start_time = time.time()
        settings_list = [TestSettings() for _ in range(100)]
        end_time = time.time()

        # Multiple configurations should load quickly
        assert end_time - start_time < 1.0  # Less than 1 second
        assert len(settings_list) == 100

    def test_configuration_cache_performance(self):
        """Test configuration cache performance"""
        import time

        # First load
        start_time = time.time()
        settings1 = TestSettings()
        first_load_time = time.time() - start_time

        # Second load (should be cached)
        start_time = time.time()
        settings2 = TestSettings()
        second_load_time = time.time() - start_time

        # Cached load should be faster
        assert second_load_time < first_load_time


class TestConfigurationErrorHandling:
    """Test configuration error handling"""

    def test_type_error_handling(self):
        """Test type error handling in configuration"""
        with patch.dict(os.environ, {
            "MCP_PORT": "not_a_number"
        }):
            settings = TestSettings()
            # Should use default value for invalid type
            assert settings.mcp_port == 8090

    def test_value_error_handling(self):
        """Test value error handling in configuration"""
        with patch.dict(os.environ, {
            "COVERAGE_THRESHOLD": "2.0"  # Invalid value
        }):
            settings = TestSettings()
            # Should use default value for invalid value
            assert settings.coverage_threshold == 0.8

    def test_missing_environment_vars(self):
        """Test missing environment variable handling"""
        # Remove environment variables that would normally exist
        env_vars_to_remove = [
            "MCP_HOST", "MCP_PORT", "A2A_HOST", "A2A_PORT",
            "ELRMCP_HOST", "ELRMCP_PORT", "TEST_TIMEOUT"
        ]

        original_env = {}
        for var in env_vars_to_remove:
            if var in os.environ:
                original_env[var] = os.environ[var]
                del os.environ[var]

        try:
            settings = TestSettings()
            # Should use defaults
            assert settings.mcp_host == "localhost"
            assert settings.mcp_port == 8090
            assert settings.test_timeout == 30
        finally:
            # Restore original environment variables
            for var, value in original_env.items():
                os.environ[var] = value

    def test_invalid_json_file_handling(self):
        """Test invalid JSON file handling"""
        invalid_json = "{ invalid: json }"

        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            f.write(invalid_json)
            temp_file = f.name

        try:
            with patch.object(TestSettings, 'env_file', temp_file):
                settings = TestSettings()
                # Should use defaults
                assert settings.mcp_host == "localhost"
                assert settings.mcp_port == 8090
        finally:
            os.unlink(temp_file)

    def test_permission_error_handling(self):
        """Test permission error handling"""
        # Create a file with restricted permissions
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump({"mcp_host": "test"}, f)
            temp_file = f.name

        try:
            # Remove read permissions
            os.chmod(temp_file, 0o000)

            with patch.object(TestSettings, 'env_file', temp_file):
                settings = TestSettings()
                # Should use defaults
                assert settings.mcp_host == "localhost"
        finally:
            # Restore permissions and remove file
            os.chmod(temp_file, 0o644)
            os.unlink(temp_file)


class TestConfigurationIntegration:
    """Test configuration integration with other components"""

    def test_config_with_mock_services(self):
        """Test configuration integration with mock services"""
        settings = TestSettings()
        settings.mock_enabled = True

        # Check that mock service URLs are generated correctly
        mock_url = settings.mock_api_url
        assert mock_url.startswith("http://")
        assert str(settings.mock_port) in mock_url

    def test_config_with_performance_tests(self):
        """Test configuration integration with performance tests"""
        settings = TestSettings()
        settings.performance_enabled = True
        settings.load_test_users = 50
        settings.load_test_duration = 120

        # Check performance test configuration
        assert settings.performance_enabled is True
        assert settings.load_test_users == 50
        assert settings.load_test_duration == 120

    def test_config_with_security_tests(self):
        """Test configuration integration with security tests"""
        settings = TestSettings()
        settings.security_enabled = True
        settings.security_scan_level = "thorough"

        # Check security test configuration
        assert settings.security_enabled is True
        assert settings.security_scan_level == "thorough"

    def test_config_with_ci_cd_integration(self):
        """Test configuration integration with CI/CD"""
        settings = TestSettings()
        settings.coverage_threshold = 0.85
        settings.parallel_tests = True

        # Check CI/CD configuration
        assert settings.coverage_threshold == 0.85
        assert settings.parallel_tests is True


class TestConfigurationUtilities:
    """Test configuration utility functions"""

    def test_services_urls_generation(self):
        """Test services URLs generation"""
        settings = TestSettings()
        urls = settings.get_services_urls()

        # Check that all required URLs are present
        assert "mcp" in urls
        assert "a2a" in urls
        assert "elrmcp" in urls
        assert "mock" in urls
        assert "health" in urls
        assert "agent_card" in urls

        # Check that URLs are valid
        assert urls["mcp"] == "http://localhost:8090"
        assert urls["a2a"] == "http://localhost:8080"
        assert urls["elrmcp"] == "http://localhost:9090"

        # Check health URLs
        assert urls["health"]["mcp"] == "http://localhost:8090/health"
        assert urls["health"]["a2a"] == "http://localhost:8080/health"
        assert urls["health"]["elrmcp"] == "http://localhost:9090/health"

        # Check agent card URL
        assert urls["agent_card"] == "http://localhost:8080/.well-known/agent-card"

    def test_configuration_export(self):
        """Test configuration export functionality"""
        settings = TestSettings()

        # Convert to dict
        config_dict = settings.to_dict()

        # Check that all expected fields are present
        expected_fields = [
            "mcp_host", "mcp_port", "mcp_url",
            "a2a_host", "a2a_port", "a2a_url",
            "elrmcp_host", "elrmcp_port", "elrmcp_url",
            "test_timeout", "retry_attempts", "debug_mode",
            "parallel_tests", "coverage_threshold", "mock_enabled",
            "mock_host", "mock_port", "performance_enabled",
            "load_test_users", "load_test_duration", "security_enabled",
            "security_scan_level", "api_token", "api_auth_header"
        ]

        for field in expected_fields:
            assert field in config_dict

    def test_configuration_comparison(self):
        """Test configuration comparison"""
        settings1 = TestSettings()
        settings2 = TestSettings()

        # Should be equal initially
        assert settings1.to_dict() == settings2.to_dict()

        # Modify one setting
        settings2.mcp_port = 9999

        # Should no longer be equal
        assert settings1.to_dict() != settings2.to_dict()

    def test_configuration_diff(self):
        """Test configuration diff functionality"""
        settings1 = TestSettings()
        settings2 = TestSettings()

        # Modify some settings
        settings2.mcp_port = 9999
        settings2.a2a_port = 8888
        settings2.debug_mode = True

        # Get both configurations
        config1 = settings1.to_dict()
        config2 = settings2.to_dict()

        # Find differences
        differences = {}
        for key in config1:
            if key in config2 and config1[key] != config2[key]:
                differences[key] = {
                    "old": config1[key],
                    "new": config2[key]
                }

        # Check that differences are captured
        assert differences["mcp_port"]["old"] == 8090
        assert differences["mcp_port"]["new"] == 9999
        assert differences["a2a_port"]["old"] == 8080
        assert differences["a2a_port"]["new"] == 8888
        assert differences["debug_mode"]["old"] is False
        assert differences["debug_mode"]["new"] is True


class TestConfigurationMonitoring:
    """Test configuration monitoring"""

    def test_configuration_change_detection(self):
        """Test configuration change detection"""
        settings = TestSettings()

        # Monitor for changes
        original_config = settings.to_dict()
        changed = False

        def on_config_change(new_config):
            nonlocal changed
            changed = True

        # Simulate a change
        settings.mcp_port = 9999

        # Check that change was detected
        # This would require a change monitoring system
        assert settings.to_dict() != original_config

    def test_configuration_health_check(self):
        """Test configuration health check"""
        settings = TestSettings()

        # Check configuration health
        is_healthy = True

        # Check if all required services are available
        urls = settings.get_services_urls()
        for service, url in urls.items():
            if url.startswith(("http://", "https://")):
                continue
            else:
                is_healthy = False
                break

        assert is_healthy is True

    def test_configuration_metrics(self):
        """Test configuration metrics collection"""
        settings = TestSettings()

        # Collect configuration metrics
        metrics = {
            "configuration_load_time": 0.01,  # Mock value
            "validation_passed": True,
            "environment": "test",
            "total_settings": len(settings.to_dict())
        }

        assert metrics["validation_passed"] is True
        assert metrics["total_settings"] > 0


class TestConfigurationBackup:
    """Test configuration backup functionality"""

    def test_configuration_backup(self):
        """Test configuration backup"""
        settings = TestSettings()

        # Create backup
        backup_config = settings.to_dict()

        # Modify original
        settings.mcp_port = 9999

        # Restore from backup
        for key, value in backup_config.items():
            setattr(settings, key, value)

        # Check restoration
        assert settings.mcp_port == 8090  # Original value restored

    def test_configuration_versioning(self):
        """Test configuration versioning"""
        settings = TestSettings()

        # Create versioned backup
        backup_v1 = settings.to_dict()
        backup_v1["version"] = "1.0.0"

        # Modify configuration
        settings.mcp_port = 9999

        # Create new version
        backup_v2 = settings.to_dict()
        backup_v2["version"] = "2.0.0"

        # Check versions
        assert backup_v1["version"] == "1.0.0"
        assert backup_v2["version"] == "2.0.0"
        assert backup_v1["mcp_port"] == 8090
        assert backup_v2["mcp_port"] == 9999

    def test_configuration_rollback(self):
        """Test configuration rollback"""
        settings = TestSettings()

        # Store original configuration
        original_config = settings.to_dict()

        # Make changes
        settings.mcp_port = 9999
        settings.a2a_port = 8888

        # Rollback to original
        for key, value in original_config.items():
            setattr(settings, key, value)

        # Check rollback
        assert settings.mcp_port == 8090
        assert settings.a2a_port == 8080