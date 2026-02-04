"""
Utility functions for elrmcp_bridge
"""

import uuid
import time
import asyncio
import functools
import threading
from typing import Any, Callable, Dict, List, Optional, Union
from datetime import datetime
import json
from urllib.parse import urlparse


def generate_message_id(prefix: str = "") -> str:
    """Generate a unique message ID"""
    timestamp = int(time.time() * 1000)  # Milliseconds
    unique_id = str(uuid.uuid4())[:8]  # First 8 chars of UUID
    return f"{prefix}_{timestamp}_{unique_id}" if prefix else f"{timestamp}_{unique_id}"


def validate_message(message: Dict[str, Any]) -> bool:
    """Validate a message structure"""
    if not message or not isinstance(message, dict):
        return False

    required_fields = ["id", "type"]
    for field in required_fields:
        if field not in message:
            return False

    return True


def serialize_json(data: Any) -> str:
    """Serialize data to JSON string"""
    return json.dumps(data, default=str)


def deserialize_json(data: str) -> Any:
    """Deserialize JSON string to data"""
    return json.loads(data)


def calculate_retry_delay(
    attempt: int,
    base: int = 2,
    multiplier: float = 1.0,
    max_delay: int = 300,
    jitter: bool = False
) -> float:
    """Calculate retry delay with exponential backoff"""
    delay = base ** attempt * multiplier

    if jitter:
        import random
        delay = delay * (0.5 + random.random() * 0.5)

    return min(delay, max_delay)


def is_valid_url(url: str) -> bool:
    """Validate URL format"""
    try:
        result = urlparse(url)
        return all([result.scheme, result.netloc])
    except Exception:
        return False


def format_timestamp(dt: datetime, format: str = "%Y-%m-%dT%H:%M:%SZ") -> str:
    """Format timestamp to string"""
    return dt.strftime(format)


def debounce(delay: float, immediate: bool = False):
    """Debounce decorator"""
    def decorator(func):
        last_call = [0]
        timer = [None]

        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            def call_later():
                if not immediate:
                    func(*args, **kwargs)
                timer[0] = None

            current_time = time.time()
            if immediate and timer[0] is None:
                func(*args, **kwargs)

            if timer[0] is not None:
                timer[0].cancel()

            time_since_last_call = current_time - last_call[0]
            new_delay = max(0, delay - time_since_last_call)

            timer[0] = threading.Timer(new_delay, call_later)
            timer[0].start()
            last_call[0] = current_time

        return wrapper
    return decorator


def throttle(limit: int, period: float = 1.0):
    """Throttle decorator"""
    def decorator(func):
        calls = []
        lock = threading.Lock()

        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            with lock:
                now = time.time()
                # Remove old calls
                calls[:] = [call_time for call_time in calls if now - call_time < period]

                if len(calls) < limit:
                    calls.append(now)
                    return func(*args, **kwargs)
                else:
                    raise Exception(f"Function call throttled (limit: {limit} calls per {period}s)")

        return wrapper
    return decorator


async def retry_async(
    func: Callable,
    max_attempts: int = 3,
    delay: float = 1.0,
    backoff_factor: float = 2.0,
    exceptions: tuple = (Exception,),
    should_retry: Optional[Callable] = None,
    callback: Optional[Callable] = None
) -> Any:
    """Retry async function with exponential backoff"""
    import logging
    logger = logging.getLogger(__name__)

    last_exception = None

    for attempt in range(max_attempts):
        try:
            return await func()
        except exceptions as e:
            last_exception = e

            if should_retry and not should_retry(e):
                raise e

            if callback:
                await callback(attempt + 1, e)

            if attempt < max_attempts - 1:
                wait_time = delay * (backoff_factor ** attempt)
                logger.warning(f"Attempt {attempt + 1} failed, retrying in {wait_time}s: {e}")
                await asyncio.sleep(wait_time)
            else:
                logger.error(f"All {max_attempts} attempts failed")
                raise e


async def async_batch_processor(
    func: Callable,
    items: List[Any],
    batch_size: int = 10,
    delay: float = 0.1,
    timeout: Optional[float] = None
) -> List[Any]:
    """Process items in batches with async support"""
    results = []

    for i in range(0, len(items), batch_size):
        batch = items[i:i + batch_size]
        batch_results = []

        # Process batch concurrently
        tasks = [func(item) for item in batch]
        if timeout:
            batch_results = await asyncio.wait_for(
                asyncio.gather(*tasks, return_exceptions=True),
                timeout=timeout
            )
        else:
            batch_results = await asyncio.gather(*tasks, return_exceptions=True)

        # Check for exceptions
        for result in batch_results:
            if isinstance(result, Exception):
                raise result

        results.extend(batch_results)

        # Add delay between batches
        if i + batch_size < len(items):
            await asyncio.sleep(delay)

    return results