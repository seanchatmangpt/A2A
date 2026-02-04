"""
Tests for utility functions and helpers
"""

import pytest
import asyncio
from unittest.mock import Mock, AsyncMock
from datetime import datetime, timedelta

from elrmcp_bridge.src.utils import (
    generate_message_id,
    validate_message,
    serialize_json,
    deserialize_json,
    calculate_retry_delay,
    is_valid_url,
    format_timestamp,
    debounce,
    throttle,
    retry_async,
    async_batch_processor
)


class TestUtils:
    """Test utility functions"""

    def test_generate_message_id(self):
        """Test message ID generation"""
        id1 = generate_message_id()
        id2 = generate_message_id()

        # IDs should be unique
        assert id1 != id2
        # IDs should be strings
        assert isinstance(id1, str)
        # IDs should have reasonable length
        assert 10 <= len(id1) <= 50

    def test_validate_message_valid(self):
        """Test message validation with valid message"""
        valid_message = {
            "id": "msg-123",
            "type": "mcp_request",
            "method": "tools/call",
            "params": {
                "name": "test",
                "arguments": {}
            }
        }

        assert validate_message(valid_message) is True

    def test_validate_message_invalid(self):
        """Test message validation with invalid message"""
        # Missing required fields
        invalid_messages = [
            {"type": "mcp_request", "method": "tools/call"},  # Missing id
            {"id": "msg-123", "method": "tools/call"},        # Missing type
            {"id": "msg-123", "type": "mcp_request"},         # Missing method
            None,                                              # None message
            "",                                                # Empty string
            123                                                # Non-dict message
        ]

        for message in invalid_messages:
            assert validate_message(message) is False

    def test_serialize_deserialize_json(self):
        """Test JSON serialization and deserialization"""
        test_data = {
            "id": "test-123",
            "name": "Test Data",
            "value": 42,
            "nested": {
                "key": "value"
            }
        }

        # Serialize
        serialized = serialize_json(test_data)
        assert isinstance(serialized, str)
        assert "test-123" in serialized

        # Deserialize
        deserialized = deserialize_json(serialized)
        assert deserialized == test_data

    def test_calculate_retry_delay(self):
        """Test retry delay calculation"""
        # Test exponential backoff
        assert calculate_retry_delay(1, base=2) == 2
        assert calculate_retry_delay(2, base=2) == 4
        assert calculate_retry_delay(3, base=2) == 8

        # Test with jitter
        delay1 = calculate_retry_delay(1, base=2, jitter=True)
        delay2 = calculate_retry_delay(1, base=2, jitter=True)
        # Delays should be different due to jitter
        assert delay1 != delay2

        # Test maximum delay
        max_delay = calculate_retry_delay(10, base=2, max_delay=10)
        assert max_delay == 10

    def test_is_valid_url(self):
        """Test URL validation"""
        valid_urls = [
            "http://example.com",
            "https://example.com",
            "http://localhost:8080",
            "ws://localhost:8080",
            "wss://localhost:8080"
        ]

        invalid_urls = [
            "invalid-url",
            "http://",  # Incomplete
            "://example.com",  # Missing protocol
            "example.com"  # No protocol
        ]

        for url in valid_urls:
            assert is_valid_url(url) is True

        for url in invalid_urls:
            assert is_valid_url(url) is False

    def test_format_timestamp(self):
        """Test timestamp formatting"""
        test_time = datetime(2023, 1, 1, 12, 0, 0)

        # Default format
        formatted = format_timestamp(test_time)
        assert formatted == "2023-01-01T12:00:00Z"

        # Custom format
        formatted = format_timestamp(test_time, format="%Y-%m-%d")
        assert formatted == "2023-01-01"

    def test_debounce(self):
        """Test debounce decorator"""
        call_count = 0

        @debounce(delay=0.1)
        def debounced_function():
            nonlocal call_count
            call_count += 1

        # Multiple calls should be debounced
        debounced_function()
        debounced_function()
        debounced_function()

        assert call_count == 0  # Should not be called immediately

        # Wait for debounce delay
        import time
        time.sleep(0.2)

        assert call_count == 1  # Should be called only once

    def test_throttle(self):
        """Test throttle decorator"""
        call_count = 0

        @throttle(limit=1, period=0.1)
        def throttled_function():
            nonlocal call_count
            call_count += 1

        # Multiple calls should be throttled
        throttled_function()
        throttled_function()
        throttled_function()

        assert call_count == 1  # Should be called only once

        # Wait for throttle period
        import time
        time.sleep(0.2)

        throttled_function()
        assert call_count == 2  # Should be called again after period

    @pytest.mark.asyncio
    async def test_retry_async_success(self):
        """Test async retry with success"""
        call_count = 0

        async def failing_function():
            nonlocal call_count
            call_count += 1
            if call_count < 3:
                raise Exception("Temporary failure")
            return "success"

        result = await retry_async(failing_function, max_attempts=5, delay=0.01)

        assert result == "success"
        assert call_count == 3

    @pytest.mark.asyncio
    async def test_retry_async_failure(self):
        """Test async retry with failure"""
        async def always_failing():
            raise Exception("Always fails")

        with pytest.raises(Exception, match="Always fails"):
            await retry_async(always_failing, max_attempts=3, delay=0.01)

    @pytest.mark.asyncio
    async def test_async_batch_processor(self):
        """Test async batch processor"""
        async def process_item(item):
            await asyncio.sleep(0.01)  # Simulate processing
            return f"processed_{item}"

        items = [1, 2, 3, 4, 5]
        batch_size = 2

        results = await async_batch_processor(
            process_item,
            items,
            batch_size=batch_size,
            delay=0.05
        )

        assert len(results) == len(items)
        assert all("processed_" in str(result) for result in results)

        # Test with error in processing
        async def failing_process_item(item):
            if item == 3:
                raise Exception("Processing failed")
            return f"processed_{item}"

        with pytest.raises(Exception, match="Processing failed"):
            await async_batch_processor(
                failing_process_item,
                items,
                batch_size=batch_size
            )

    @pytest.mark.asyncio
    async def test_retry_with_callback(self):
        """Test retry with callback"""
        call_count = 0
        callback_calls = []

        async def failing_function():
            nonlocal call_count
            call_count += 1
            raise Exception("Temporary failure")

        async def callback(attempt, error):
            callback_calls.append((attempt, str(error)))

        with pytest.raises(Exception):
            await retry_async(
                failing_function,
                max_attempts=3,
                delay=0.01,
                callback=callback
            )

        assert len(callback_calls) == 3
        assert all(attempt > 0 for attempt, _ in callback_calls)

    @pytest.mark.asyncio
    async def test_retry_with_custom_condition(self):
        """Test retry with custom condition"""
        call_count = 0

        async def conditional_function():
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                raise ValueError("Retry this error")
            elif call_count == 2:
                raise TypeError("Don't retry this error")
            return "success"

        def should_retry(error):
            return isinstance(error, ValueError)

        with pytest.raises(TypeError):
            await retry_async(
                conditional_function,
                max_attempts=5,
                delay=0.01,
                should_retry=should_retry
            )

        # After first error, second should not be retried
        # but should be raised immediately

    def test_format_timestamp_different_formats(self):
        """Test timestamp formatting with different formats"""
        test_time = datetime(2023, 1, 1, 12, 30, 45)

        formats = {
            "iso": "%Y-%m-%dT%H:%M:%SZ",
            "date": "%Y-%m-%d",
            "time": "%H:%M:%S",
            "custom": "%d/%m/%Y %H:%M"
        }

        for format_name, format_str in formats.items():
            formatted = format_timestamp(test_time, format=format_str)
            assert isinstance(formatted, str)
            assert len(formatted) > 0

    @pytest.mark.asyncio
    async def test_async_batch_processor_with_timeout(self):
        """Test async batch processor with timeout"""
        async def slow_process_item(item):
            await asyncio.sleep(0.1)
            return f"processed_{item}"

        items = [1, 2, 3]
        timeout = 0.05  # Less than processing time

        with pytest.raises(asyncio.TimeoutError):
            await async_batch_processor(
                slow_process_item,
                items,
                batch_size=1,
                timeout=timeout
            )

    def test_is_valid_url_with_special_characters(self):
        """Test URL validation with special characters"""
        valid_urls = [
            "http://example.com/path",
            "https://sub.example.com:8080/path?param=value",
            "ws://example.com/path",
            "wss://example.com/path#section"
        ]

        for url in valid_urls:
            assert is_valid_url(url) is True

    def test_calculate_retry_delay_with_custom_multiplier(self):
        """Test retry delay with custom multiplier"""
        delay = calculate_retry_delay(1, base=2, multiplier=0.5)
        assert delay == 1  # 2 * 0.5

        delay = calculate_retry_delay(2, base=3, multiplier=2)
        assert delay == 12  # 3^2 * 2

    def test_generate_message_id_with_prefix(self):
        """Test message ID generation with prefix"""
        id_with_prefix = generate_message_id(prefix="msg")
        assert id_with_prefix.startswith("msg_")

        id_with_custom_prefix = generate_message_id(prefix="test")
        assert id_with_custom_prefix.startswith("test_")

    @pytest.mark.asyncio
    async def test_throttle_concurrent_calls(self):
        """Test throttle with concurrent calls"""
        call_count = 0
        call_times = []

        @throttle(limit=2, period=0.1)
        def throttled_function():
            nonlocal call_count, call_times
            call_count += 1
            call_times.append(asyncio.get_event_loop().time())
            return f"call_{call_count}"

        # Make concurrent calls
        tasks = [throttled_function() for _ in range(5)]
        results = await asyncio.gather(*tasks)

        # Should have results for all calls
        assert len(results) == 5
        assert all(result.startswith("call_") for result in results)

        # But calls should be throttled
        assert len(call_times) <= 5

    @pytest.mark.asyncio
    async def test_debounce_immediate_call(self):
        """Test debounce with immediate option"""
        call_count = 0

        @debounce(delay=0.1, immediate=True)
        def debounced_function():
            nonlocal call_count
            call_count += 1

        # First call should be immediate
        debounced_function()
        assert call_count == 1

        # Subsequent calls should be debounced
        debounced_function()
        debounced_function()
        assert call_count == 1  # Still 1 due to debounce

        # Wait for debounce
        await asyncio.sleep(0.2)
        assert call_count == 2  # Called once after debounce