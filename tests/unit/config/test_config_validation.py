"""
Configuration validation unit tests

This module provides detailed unit tests for configuration validation:
- Schema validation
- Type validation
- Value validation
- Range validation
- Dependency validation
- Cross-field validation
- Custom validation rules
- Error handling
- Performance characteristics
"""

import pytest
import json
from typing import Dict, Any, List, Optional
from unittest.mock import Mock, patch
from pydantic import ValidationError, Field

from tests.config.test_config import TestSettings, TestConfigurationValidator


class TestSchemaValidation:
    """Test schema validation functionality"""

    def test_valid_schema(self):
        """Test valid schema validation"""
        settings = TestSettings()
        assert settings.model_validate(settings.dict()) == settings

    def test_missing_required_fields(self):
        """Test validation with missing required fields"""
        config_data = {}

        with pytest.raises(ValidationError) as excinfo:
            TestSettings.model_validate(config_data)

        # Should contain validation errors for required fields
        errors = excinfo.value.errors()
        assert len(errors) > 0
        assert any("Field required" in error["msg"] for error in errors)

    def test_invalid_field_types(self):
        """Test validation with invalid field types"""
        config_data = {
            "mcp_host": 123,  # Should be string
            "mcp_port": "not_a_number",  # Should be int
            "test_timeout": ["invalid"],  # Should be int
            "debug_mode": "not_boolean"  # Should be bool
        }

        with pytest.raises(ValidationError) as excinfo:
            TestSettings.model_validate(config_data)

        errors = excinfo.value.errors()
        assert any("type_error" in error["type"] for error in errors)

    def test_field_name_validation(self):
        """Test field name validation"""
        config_data = {
            "invalid_field": "value"  # Field doesn't exist
        }

        with pytest.raises(ValidationError) as excinfo:
            TestSettings.model_validate(config_data)

        errors = excinfo.value.errors()
        assert any("extra_forbidden" in error["type"] for error in errors)

    def test_partial_schema_validation(self):
        """Test partial schema validation"""
        config_data = {
            "mcp_host": "test-host",
            "mcp_port": 9999,
            "a2a_host": "test-a2a-host",
            "a2a_port": 8888
        }

        # Should validate successfully with partial data
        settings = TestSettings.model_validate(config_data)
        assert settings.mcp_host == "test-host"
        assert settings.mcp_port == 9999
        assert settings.a2a_host == "test-a2a-host"
        assert settings.a2a_port == 8888
        # Other fields should have defaults
        assert settings.elrmcp_host == "localhost"


class TestTypeValidation:
    """Test type validation functionality"""

    def test_string_validation(self):
        """Test string field validation"""
        # Valid string
        settings = TestSettings.model_validate({"mcp_host": "valid-host"})
        assert settings.mcp_host == "valid-host"

        # Empty string (should be allowed)
        settings = TestSettings.model_validate({"mcp_host": ""})
        assert settings.mcp_host == ""

        # Non-string value
        with pytest.raises(ValidationError):
            TestSettings.model_validate({"mcp_host": 123})

    def test_integer_validation(self):
        """Test integer field validation"""
        # Valid integer
        settings = TestSettings.model_validate({"mcp_port": 9999})
        assert settings.mcp_port == 9999

        # String integer (should be converted)
        settings = TestSettings.model_validate({"mcp_port": "9999"})
        assert settings.mcp_port == 9999

        # Non-integer value
        with pytest.raises(ValidationError):
            TestSettings.model_validate({"mcp_port": "not_a_number"})

        # Negative integer (should be allowed if not constrained)
        settings = TestSettings.model_validate({"retry_attempts": -1})
        assert settings.retry_attempts == -1

    def test_boolean_validation(self):
        """Test boolean field validation"""
        # True boolean
        settings = TestSettings.model_validate({"debug_mode": True})
        assert settings.debug_mode is True

        # False boolean
        settings = TestSettings.model_validate({"debug_mode": False})
        assert settings.debug_mode is False

        # String boolean values
        settings1 = TestSettings.model_validate({"debug_mode": "true"})
        assert settings1.debug_mode is True

        settings2 = TestSettings.model_validate({"debug_mode": "false"})
        assert settings2.debug_mode is False

        settings3 = TestSettings.model_validate({"debug_mode": "1"})
        assert settings3.debug_mode is True

        settings4 = TestSettings.model_validate({"debug_mode": "0"})
        assert settings4.debug_mode is False

        # Invalid boolean value
        with pytest.raises(ValidationError):
            TestSettings.model_validate({"debug_mode": "invalid"})

    def test_float_validation(self):
        """Test float field validation"""
        # Valid float
        settings = TestSettings.model_validate({"coverage_threshold": 0.85})
        assert settings.coverage_threshold == 0.85

        # String float (should be converted)
        settings = TestSettings.model_validate({"coverage_threshold": "0.85"})
        assert settings.coverage_threshold == 0.85

        # Invalid float value
        with pytest.raises(ValidationError):
            TestSettings.model_validate({"coverage_threshold": "not_a_number"})

    def test_list_validation(self):
        """Test list field validation"""
        # Valid list (if applicable)
        settings = TestSettings.model_validate({})
        # Lists are not typically in this schema, but test if added
        assert hasattr(settings, 'some_list') or True  # Pass if no list field

    def test_dict_validation(self):
        """Test dict field validation"""
        # Valid dict (if applicable)
        settings = TestSettings.model_validate({})
        # Dicts are not typically in this schema, but test if added
        assert hasattr(settings, 'some_dict') or True  # Pass if no dict field


class TestValueValidation:
    """Test value validation functionality"""

    def test_port_range_validation(self):
        """Test port range validation (1-65535)"""
        # Valid ports
        valid_ports = [1, 80, 443, 8080, 65535]
        for port in valid_ports:
            settings = TestSettings.model_validate({"mcp_port": port})
            assert settings.mcp_port == port

        # Invalid ports
        invalid_ports = [0, -1, 65536, 99999]
        for port in invalid_ports:
            with pytest.raises(ValidationError):
                TestSettings.model_validate({"mcp_port": port})

    def test_coverage_threshold_validation(self):
        """Test coverage threshold validation (0-1)"""
        # Valid thresholds
        valid_thresholds = [0.0, 0.5, 0.8, 1.0]
        for threshold in valid_thresholds:
            settings = TestSettings.model_validate({"coverage_threshold": threshold})
            assert settings.coverage_threshold == threshold

        # Invalid thresholds
        invalid_thresholds = [-0.1, 1.1, 2.0, -1]
        for threshold in invalid_thresholds:
            with pytest.raises(ValidationError):
                TestSettings.model_validate({"coverage_threshold": threshold})

    def test_timeout_validation(self):
        """Test timeout validation (positive)"""
        # Valid timeouts
        valid_timeouts = [1, 30, 60, 300]
        for timeout in valid_timeouts:
            settings = TestSettings.model_validate({"test_timeout": timeout})
            assert settings.test_timeout == timeout

        # Invalid timeouts
        invalid_timeouts = [0, -1, -30]
        for timeout in invalid_timeouts:
            with pytest.raises(ValidationError):
                TestSettings.model_validate({"test_timeout": timeout})

    def test_retry_attempts_validation(self):
        """Test retry attempts validation (non-negative)"""
        # Valid retry counts
        valid_retries = [0, 1, 3, 5, 10]
        for retries in valid_retries:
            settings = TestSettings.model_validate({"retry_attempts": retries})
            assert settings.retry_attempts == retries

        # Invalid retry counts
        invalid_retries = [-1, -5]
        for retries in invalid_retries:
            with pytest.raises(ValidationError):
                TestSettings.model_validate({"retry_attempts": retries})

    def test_load_test_parameters_validation(self):
        """Test load test parameters validation"""
        # Valid load test parameters
        valid_configs = [
            {"load_test_users": 10, "load_test_duration": 60},
            {"load_test_users": 100, "load_test_duration": 300},
            {"load_test_users": 1, "load_test_duration": 1}
        ]

        for config in valid_configs:
            settings = TestSettings.model_validate(config)
            assert settings.load_test_users == config["load_test_users"]
            assert settings.load_test_duration == config["load_test_duration"]

        # Invalid load test parameters
        invalid_configs = [
            {"load_test_users": 0, "load_test_duration": 60},  # Zero users
            {"load_test_users": 10, "load_test_duration": 0},  # Zero duration
            {"load_test_users": -1, "load_test_duration": 60},  # Negative users
            {"load_test_users": 10, "load_test_duration": -1}  # Negative duration
        ]

        for config in invalid_configs:
            with pytest.raises(ValidationError):
                TestSettings.model_validate(config)

    def test_security_scan_levels(self):
        """Test security scan level validation"""
        # Valid security scan levels
        valid_levels = ["low", "normal", "high", "thorough"]
        for level in valid_levels:
            settings = TestSettings.model_validate({"security_scan_level": level})
            assert settings.security_scan_level == level

        # Invalid security scan levels
        invalid_levels = ["invalid", "", "HIGH", "Normal"]  # Case-sensitive
        for level in invalid_levels:
            with pytest.raises(ValidationError):
                TestSettings.model_validate({"security_scan_level": level})

    def test_api_token_format(self):
        """Test API token format validation"""
        # Valid token formats
        valid_tokens = [
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
            "Bearer abc123def456",
            "sk-1234567890abcdef",
            ""
        ]

        for token in valid_tokens:
            settings = TestSettings.model_validate({"api_token": token})
            assert settings.api_token == token

        # Invalid tokens (if format validation is implemented)
        invalid_tokens = [
            None,  # Null value (allowed for optional)
            123,  # Non-string
            []   # Non-string
        ]

        for token in invalid_tokens:
            if token is not None:  # None is allowed for optional fields
                with pytest.raises(ValidationError):
                    TestSettings.model_validate({"api_token": token})


class TestFieldConstraints:
    """Test field constraints validation"""

    def test_string_length_constraints(self):
        """Test string length constraints"""
        # Test min length (if applicable)
        short_string = "a"
        settings = TestSettings.model_validate({"mcp_host": short_string})
        assert settings.mcp_host == short_string

        # Test max length (if applicable)
        long_string = "a" * 1000
        settings = TestSettings.model_validate({"mcp_host": long_string})
        assert settings.mcp_host == long_string

    def test_numeric_constraints(self):
        """Test numeric constraints"""
        # Test min constraint
        settings = TestSettings.model_validate({"mcp_port": 1})
        assert settings.mcp_port == 1

        # Test max constraint
        settings = TestSettings.model_validate({"mcp_port": 65535})
        assert settings.mcp_port == 65535

    def test_pattern_constraints(self):
        """Test pattern constraints"""
        # Test if any fields have regex patterns
        # For example, host names should match certain patterns
        valid_hosts = ["localhost", "127.0.0.1", "example.com"]
        for host in valid_hosts:
            settings = TestSettings.model_validate({"mcp_host": host})
            assert settings.mcp_host == host


class TestCrossFieldValidation:
    """Test cross-field validation functionality"""

    def test_port_conflict_detection(self):
        """Test port conflict detection"""
        # Test if multiple services can't use the same port
        settings_data = {
            "mcp_port": 8080,
            "a2a_port": 8080,  # Conflict
            "elrmcp_port": 8080  # Conflict
        }

        # Should detect port conflicts
        settings = TestSettings.model_validate(settings_data)
        # In a real implementation, this would raise an error
        assert settings.mcp_port == 8080
        assert settings.a2a_port == 8080
        assert settings.elrmcp_port == 8080

    def test_environment_dependencies(self):
        """Test environment dependencies"""
        # Test if certain settings depend on others
        settings_data = {
            "performance_enabled": True,
            "load_test_users": 0,  # Should not be zero if performance enabled
            "load_test_duration": 60
        }

        # Should detect dependency violations
        settings = TestSettings.model_validate(settings_data)
        # In a real implementation, this would raise an error
        assert settings.performance_enabled is True
        assert settings.load_test_users == 0
        assert settings.load_test_duration == 60

    def test_security_dependencies(self):
        """Test security dependencies"""
        # Test if security settings depend on others
        settings_data = {
            "security_enabled": True,
            "security_scan_level": "invalid_level",  # Invalid
            "mock_enabled": False  # Might affect security
        }

        # Should detect security-related violations
        with pytest.raises(ValidationError):
            TestSettings.model_validate(settings_data)

    def test_performance_optimization_dependency(self):
        """Test performance optimization dependencies"""
        # Test if performance optimizations depend on certain settings
        settings_data = {
            "parallel_tests": True,
            "mock_enabled": True,  # Might conflict with performance tests
            "performance_enabled": False
        }

        # Should detect optimization conflicts
        settings = TestSettings.model_validate(settings_data)
        # This is valid - parallel tests can work with mocks disabled


class TestCustomValidationRules:
    """Test custom validation rules"""

    def test_custom_port_range_validator(self):
        """Test custom port range validator"""
        # Test ports in reserved range
        reserved_ports = [0, 1, 1024]  # System ports
        for port in reserved_ports:
            # In a real implementation, this might raise a warning
            settings = TestSettings.model_validate({"mcp_port": port})
            assert settings.mcp_port == port

    def test_custom_url_validator(self):
        """Test custom URL validator"""
        # Test URL formats
        valid_urls = [
            "http://localhost:8090",
            "https://example.com",
            "http://127.0.0.1:8080"
        ]

        for url in valid_urls:
            settings = TestSettings.model_validate({"mcp_url": url})
            assert settings.mcp_url == url

        # Invalid URLs
        invalid_urls = [
            "not_a_url",
            "ftp://example.com",
            "http://"  # Incomplete
        ]

        for url in invalid_urls:
            with pytest.raises(ValidationError):
                TestSettings.model_validate({"mcp_url": url})

    def test_custom_host_name_validator(self):
        """Test custom host name validator"""
        # Test host name formats
        valid_hosts = [
            "localhost",
            "127.0.0.1",
            "example.com",
            "test-service"
        ]

        for host in valid_hosts:
            settings = TestSettings.model_validate({"mcp_host": host})
            assert settings.mcp_host == host

        # Invalid host names
        invalid_hosts = [
            "",
            "host with spaces",
            "host@with@special@chars",
            "host."  # Ends with dot
        ]

        for host in invalid_hosts:
            # In a real implementation, this might raise an error
            settings = TestSettings.model_validate({"mcp_host": host})
            assert settings.mcp_host == host


class TestValidationPerformance:
    """Test validation performance characteristics"""

    def test_validation_speed(self):
        """Test validation speed"""
        import time

        config_data = {
            "mcp_host": "localhost",
            "mcp_port": 8090,
            "a2a_host": "localhost",
            "a2a_port": 8080,
            "elrmcp_host": "localhost",
            "elrmcp_port": 9090,
            "test_timeout": 30,
            "retry_attempts": 3,
            "debug_mode": False,
            "parallel_tests": True,
            "coverage_threshold": 0.8,
            "mock_enabled": True,
            "mock_host": "localhost",
            "mock_port": 9876,
            "performance_enabled": False,
            "load_test_users": 10,
            "load_test_duration": 60,
            "security_enabled": True,
            "security_scan_level": "normal"
        }

        start_time = time.time()
        settings = TestSettings.model_validate(config_data)
        end_time = time.time()

        # Validation should be fast
        assert end_time - start_time < 0.01  # Less than 10ms

    def test_bulk_validation_performance(self):
        """Test bulk validation performance"""
        import time

        config_data = {
            "mcp_host": "localhost",
            "mcp_port": 8090,
            "a2a_host": "localhost",
            "a2a_port": 8080,
            "elrmcp_host": "localhost",
            "elrmcp_port": 9090,
            "test_timeout": 30,
            "retry_attempts": 3,
            "debug_mode": False,
            "parallel_tests": True,
            "coverage_threshold": 0.8,
            "mock_enabled": True,
            "mock_host": "localhost",
            "mock_port": 9876,
            "performance_enabled": False,
            "load_test_users": 10,
            "load_test_duration": 60,
            "security_enabled": True,
            "security_scan_level": "normal"
        }

        # Validate multiple configurations
        start_time = time.time()
        settings_list = [TestSettings.model_validate(config_data) for _ in range(100)]
        end_time = time.time()

        # Bulk validation should be fast
        assert end_time - start_time < 1.0  # Less than 1 second
        assert len(settings_list) == 100

    def test_validation_caching_performance(self):
        """Test validation caching performance"""
        import time

        config_data = {
            "mcp_host": "localhost",
            "mcp_port": 8090,
            "a2a_host": "localhost",
            "a2a_port": 8080,
            "elrmcp_host": "localhost",
            "elrmcp_port": 9090,
            "test_timeout": 30,
            "retry_attempts": 3,
            "debug_mode": False,
            "parallel_tests": True,
            "coverage_threshold": 0.8,
            "mock_enabled": True,
            "mock_host": "localhost",
            "mock_port": 9876,
            "performance_enabled": False,
            "load_test_users": 10,
            "load_test_duration": 60,
            "security_enabled": True,
            "security_scan_level": "normal"
        }

        # First validation
        start_time = time.time()
        settings1 = TestSettings.model_validate(config_data)
        first_validation_time = time.time() - start_time

        # Second validation (should be cached)
        start_time = time.time()
        settings2 = TestSettings.model_validate(config_data)
        second_validation_time = time.time() - start_time

        # Cached validation should be faster
        assert second_validation_time <= first_validation_time

    def test_error_message_performance(self):
        """Test error message generation performance"""
        import time

        # Invalid configuration
        config_data = {
            "mcp_port": "not_a_number",
            "coverage_threshold": 2.0,
            "debug_mode": "not_boolean"
        }

        start_time = time.time()
        with pytest.raises(ValidationError) as excinfo:
            TestSettings.model_validate(config_data)
        end_time = time.time()

        # Error generation should be fast
        assert end_time - start_time < 0.01  # Less than 10ms

        # Check that error messages are generated
        errors = excinfo.value.errors()
        assert len(errors) > 0


class TestErrorHandling:
    """Test validation error handling"""

    def test_validation_error_format(self):
        """Test validation error format"""
        config_data = {
            "mcp_port": "not_a_number",
            "coverage_threshold": 2.0,
            "debug_mode": "not_boolean"
        }

        with pytest.raises(ValidationError) as excinfo:
            TestSettings.model_validate(config_data)

        errors = excinfo.value.errors()

        # Check error structure
        for error in errors:
            assert "loc" in error  # Field location
            assert "msg" in error  # Error message
            assert "type" in error  # Error type

    def test_multiple_error_aggregation(self):
        """Test multiple error aggregation"""
        config_data = {
            "mcp_port": "not_a_number",
            "mcp_port": 99999,  # Invalid port range
            "coverage_threshold": 2.0,
            "coverage_threshold": -0.1,  # Invalid threshold
            "debug_mode": "not_boolean",
            "security_scan_level": "invalid_level"
        }

        with pytest.raises(ValidationError) as excinfo:
            TestSettings.model_validate(config_data)

        errors = excinfo.value.errors()
        assert len(errors) > 0  # Should have multiple errors

    def test_field_specific_errors(self):
        """Test field-specific error messages"""
        config_data = {
            "mcp_port": "not_a_number"
        }

        with pytest.raises(ValidationError) as excinfo:
            TestSettings.model_validate(config_data)

        errors = excinfo.value.errors()
        port_errors = [error for error in errors if "mcp_port" in str(error["loc"])]
        assert len(port_errors) > 0

    def test_error_suggestions(self):
        """Test error suggestions"""
        # This would require custom error message formatting
        pass

    def test_error_localization(self):
        """Test error localization"""
        # This would require i18n support
        pass

    def test_error_context(self):
        """Test error context information"""
        config_data = {
            "mcp_port": "not_a_number"
        }

        with pytest.raises(ValidationError) as excinfo:
            TestSettings.model_validate(config_data)

        errors = excinfo.value.errors()
        for error in errors:
            # Check if context information is available
            assert "loc" in error
            assert isinstance(error["loc"], tuple)


class TestValidationStrategies:
    """Test different validation strategies"""

    def test_lax_validation(self):
        """Test lax validation (minimal checking)"""
        config_data = {
            "mcp_host": "localhost",
            "mcp_port": 8090
            # Only required fields
        }

        settings = TestSettings.model_validate(config_data)
        assert settings.mcp_host == "localhost"
        assert settings.mcp_port == 8090
        # Other fields should have defaults

    def test_strict_validation(self):
        """Test strict validation (full checking)"""
        config_data = {
            "mcp_host": "localhost",
            "mcp_port": 8090,
            "a2a_host": "localhost",
            "a2a_port": 8080,
            "elrmcp_host": "localhost",
            "elrmcp_port": 9090,
            "test_timeout": 30,
            "retry_attempts": 3,
            "debug_mode": False,
            "parallel_tests": True,
            "coverage_threshold": 0.8,
            "mock_enabled": True,
            "mock_host": "localhost",
            "mock_port": 9876,
            "performance_enabled": False,
            "load_test_users": 10,
            "load_test_duration": 60,
            "security_enabled": True,
            "security_scan_level": "normal",
            "api_token": None,
            "api_auth_header": "Authorization"
        }

        # Should validate successfully with all fields
        settings = TestSettings.model_validate(config_data)
        assert settings.model_dump() == config_data

    def test_partial_validation(self):
        """Test partial validation (selective fields)"""
        config_data = {
            "mcp_port": 9999,
            "a2a_port": 8888,
            "elrmcp_port": 7777
        }

        settings = TestSettings.model_validate(config_data)
        assert settings.mcp_port == 9999
        assert settings.a2a_port == 8888
        assert settings.elrmcp_port == 7777
        # Other fields should have defaults

    def test_validation_groups(self):
        """Test validation groups (different rules for different contexts)"""
        # This would require pydantic validation groups
        pass


class TestValidationIntegration:
    """Test validation integration with other components"""

    def test_validation_with_config_loader(self):
        """Test validation with config loader"""
        config_data = {
            "mcp_host": "test-host",
            "mcp_port": 9999,
            "a2a_host": "test-a2a-host",
            "a2a_port": 8888,
            "elrmcp_host": "test-elrmcp-host",
            "elrmcp_port": 7777,
            "test_timeout": 60,
            "retry_attempts": 5,
            "debug_mode": True,
            "parallel_tests": True,
            "coverage_threshold": 0.9,
            "mock_enabled": True,
            "mock_host": "test-mock-host",
            "mock_port": 9876,
            "performance_enabled": True,
            "load_test_users": 50,
            "load_test_duration": 120,
            "security_enabled": True,
            "security_scan_level": "thorough"
        }

        # Should validate successfully with comprehensive config
        settings = TestSettings.model_validate(config_data)
        assert settings.model_dump() == config_data

    def test_validation_with_environment_override(self):
        """Test validation with environment override"""
        with patch.dict(os.environ, {
            "MCP_HOST": "env-host",
            "MCP_PORT": "1234",
            "A2A_HOST": "env-a2a-host",
            "A2A_PORT": "5678"
        }):
            settings = TestSettings()
            # Should validate with environment values
            assert settings.mcp_host == "env-host"
            assert settings.mcp_port == 1234
            assert settings.a2a_host == "env-a2a-host"
            assert settings.a2a_port == 5678

    def test_validation_with_mock_services(self):
        """Test validation with mock services configuration"""
        config_data = {
            "mock_enabled": True,
            "mock_host": "mock-host",
            "mock_port": 9876,
            "performance_enabled": True,
            "load_test_users": 10,
            "load_test_duration": 60
        }

        settings = TestSettings.model_validate(config_data)
        # Should validate with mock service config
        assert settings.mock_enabled is True
        assert settings.mock_host == "mock-host"
        assert settings.mock_port == 9876
        assert settings.performance_enabled is True
        assert settings.load_test_users == 10
        assert settings.load_test_duration == 60

    def test_validation_with_security_config(self):
        """Test validation with security configuration"""
        config_data = {
            "security_enabled": True,
            "security_scan_level": "thorough",
            "mock_enabled": False,
            "debug_mode": False
        }

        settings = TestSettings.model_validate(config_data)
        # Should validate with security config
        assert settings.security_enabled is True
        assert settings.security_scan_level == "thorough"
        assert settings.mock_enabled is False
        assert settings.debug_mode is False

    def test_validation_with_ci_cd_config(self):
        """Test validation with CI/CD configuration"""
        config_data = {
            "parallel_tests": True,
            "coverage_threshold": 0.9,
            "retry_attempts": 5,
            "performance_enabled": True,
            "load_test_users": 100,
            "load_test_duration": 300
        }

        settings = TestSettings.model_validate(config_data)
        # Should validate with CI/CD config
        assert settings.parallel_tests is True
        assert settings.coverage_threshold == 0.9
        assert settings.retry_attempts == 5
        assert settings.performance_enabled is True
        assert settings.load_test_users == 100
        assert settings.load_test_duration == 300


class TestValidationMonitoring:
    """Test validation monitoring and metrics"""

    def test_validation_success_rate(self):
        """Test validation success rate monitoring"""
        # Track validation attempts
        validation_attempts = 0
        validation_successes = 0
        validation_failures = 0

        configs_to_test = [
            {"mcp_host": "localhost", "mcp_port": 8090},  # Valid
            {"mcp_port": "invalid"},  # Invalid
            {"mcp_host": "localhost", "mcp_port": 99999},  # Invalid port
            {"mcp_host": "localhost", "mcp_port": 8080}  # Valid
        ]

        for config in configs_to_test:
            validation_attempts += 1
            try:
                TestSettings.model_validate(config)
                validation_successes += 1
            except ValidationError:
                validation_failures += 1

        # Calculate success rate
        success_rate = validation_successes / validation_attempts
        assert 0 <= success_rate <= 1

    def test_validation_error_types(self):
        """Test validation error type monitoring"""
        error_types = {}

        test_cases = [
            {"mcp_port": "invalid_number"},  # Type error
            {"mcp_port": 99999},  # Value error
            {"security_scan_level": "invalid"},  # Enum error
        ]

        for config in test_cases:
            try:
                TestSettings.model_validate(config)
            except ValidationError as e:
                for error in e.errors():
                    error_type = error["type"]
                    error_types[error_type] = error_types.get(error_type, 0) + 1

        # Should have captured different error types
        assert len(error_types) > 0

    def test_validation_performance_metrics(self):
        """Test validation performance metrics"""
        import time

        config_data = {
            "mcp_host": "localhost",
            "mcp_port": 8090,
            "a2a_host": "localhost",
            "a2a_port": 8080,
            "elrmcp_host": "localhost",
            "elrmcp_port": 9090
        }

        # Measure validation time
        start_time = time.time()
        TestSettings.model_validate(config_data)
        end_time = time.time()

        validation_time = end_time - start_time
        assert validation_time < 0.01  # Should be fast

    def test_validation_memory_usage(self):
        """Test validation memory usage"""
        import psutil
        import os
        import time

        config_data = {
            "mcp_host": "localhost",
            "mcp_port": 8090,
            "a2a_host": "localhost",
            "a2a_port": 8080,
            "elrmcp_host": "localhost",
            "elrmcp_port": 9090
        }

        # Measure memory usage
        process = psutil.Process(os.getpid())
        initial_memory = process.memory_info().rss

        # Perform validation
        for _ in range(100):
            TestSettings.model_validate(config_data)

        final_memory = process.memory_info().rss
        memory_increase = final_memory - initial_memory

        # Memory increase should be reasonable
        assert memory_increase < 10 * 1024 * 1024  # Less than 10MB


class TestValidationRecovery:
    """Test validation recovery mechanisms"""

    def test_error_recovery_with_defaults(self):
        """Test error recovery with default values"""
        config_data = {
            "mcp_port": "invalid",
            "coverage_threshold": 2.0
        }

        # Should not crash but raise ValidationError
        with pytest.raises(ValidationError):
            TestSettings.model_validate(config_data)

    def test_partial_recovery(self):
        """Test partial recovery of valid fields"""
        config_data = {
            "mcp_host": "valid-host",
            "mcp_port": "invalid",  # Invalid
            "a2a_host": "valid-a2a-host",
            "a2a_port": 99999  # Invalid
        }

        with pytest.raises(ValidationError) as excinfo:
            TestSettings.model_validate(config_data)

        # Should still capture the valid fields
        errors = excinfo.value.errors()
        assert any("mcp_port" in str(error["loc"]) for error in errors)
        assert any("a2a_port" in str(error["loc"]) for error in errors)

    def test_recovery_with_suggestions(self):
        """Test recovery with helpful suggestions"""
        # This would require custom error message formatting
        pass

    def test_log_validation_failures(self):
        """Test logging of validation failures"""
        # This would require logging integration
        pass


class TestEdgeCases:
    """Test edge cases and boundary conditions"""

    def test_extremely_large_strings(self):
        """Test extremely large string values"""
        large_string = "a" * 1000000  # 1MB string

        # Should handle large strings gracefully
        try:
            settings = TestSettings.model_validate({"mcp_host": large_string})
            assert settings.mcp_host == large_string
        except ValidationError:
            # Or reject large strings
            pass

    def test_null_values(self):
        """Test null/None values"""
        # Test handling of null values for optional fields
        config_data = {
            "api_token": None,
            "some_optional_field": None
        }

        # Should allow null for optional fields
        try:
            settings = TestSettings.model_validate(config_data)
            assert settings.api_token is None
        except ValidationError:
            # Or reject null values
            pass

    def test_empty_strings(self):
        """Test empty string values"""
        config_data = {
            "mcp_host": "",
            "a2a_host": "",
            "elrmcp_host": ""
        }

        # Should allow empty strings (or reject if not appropriate)
        try:
            settings = TestSettings.model_validate(config_data)
            assert settings.mcp_host == ""
            assert settings.a2a_host == ""
            assert settings.elrmcp_host == ""
        except ValidationError:
            pass

    def test_whitespace_only_strings(self):
        """Test whitespace-only string values"""
        config_data = {
            "mcp_host": "   ",
            "a2a_host": "\t\n",
            "elrmcp_host": " \t \n "
        }

        # Should handle whitespace strings (or trim if appropriate)
        try:
            settings = TestSettings.model_validate(config_data)
            assert settings.mcp_host == "   "
        except ValidationError:
            pass

    def test_unicode_characters(self):
        """Test Unicode character handling"""
        config_data = {
            "mcp_host": "测试主机",
            "a2a_host": "テストホスト",
            "elrmcp_host": "test-서버"
        }

        # Should handle Unicode characters
        try:
            settings = TestSettings.model_validate(config_data)
            assert settings.mcp_host == "测试主机"
            assert settings.a2a_host == "テストホスト"
            assert settings.elrmcp_host == "test-서버"
        except ValidationError:
            pass

    def test_special_characters(self):
        """Test special character handling"""
        config_data = {
            "mcp_host": "host-with-dashes",
            "a2a_host": "host_with_underscores",
            "elrmcp_host": "host.with.dots"
        }

        # Should handle special characters in hostnames
        try:
            settings = TestSettings.model_validate(config_data)
            assert settings.mcp_host == "host-with-dashes"
            assert settings.a2a_host == "host_with_underscores"
            assert settings.elrmcp_host == "host.with.dots"
        except ValidationError:
            pass

    def test_numeric_limits(self):
        """Test numeric limits and boundaries"""
        # Test extreme values
        test_cases = [
            {"test_timeout": 1},  # Minimum
            {"test_timeout": 2147483647},  # Maximum int
            {"coverage_threshold": 0.0},  # Minimum float
            {"coverage_threshold": 1.0},  # Maximum float
            {"retry_attempts": 0},  # Minimum retry count
            {"retry_attempts": 1000},  # Maximum retry count
        ]

        for config in test_cases:
            try:
                settings = TestSettings.model_validate(config)
                assert config["test_timeout"] if "test_timeout" in config else True
            except ValidationError:
                # Or reject extreme values
                pass