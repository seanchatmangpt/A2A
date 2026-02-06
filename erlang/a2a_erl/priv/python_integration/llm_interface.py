#!/usr/bin/env python3
"""
LLM Interface: Large Language Model Integration for YAWL

This module provides interface functions for LLM-based workflow
generation and validation.

Features:
- LLM model integration (OpenAI, Anthropic, local models)
- Workflow generation from natural language
- Model validation and refinement
- Prompt engineering for YAWL patterns

Author: A2A Team
"""

import json
import os
import logging
from typing import Dict, List, Any, Optional
from dataclasses import dataclass
from abc import ABC, abstractmethod

# Try to import LLM libraries
try:
    import openai
    OPENAI_AVAILABLE = True
except ImportError:
    OPENAI_AVAILABLE = False

try:
    import anthropic
    ANTHROPIC_AVAILABLE = True
except ImportError:
    ANTHROPIC_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@dataclass
class LLMRequest:
    """LLM request container."""
    prompt: str
    model: str
    temperature: float = 0.7
    max_tokens: int = 2000
    system_prompt: Optional[str] = None


@dataclass
class LLMResponse:
    """LLM response container."""
    content: str
    model: str
    finish_reason: str
    usage: Dict[str, int]


class LLMProvider(ABC):
    """Abstract base class for LLM providers."""

    @abstractmethod
    def generate(self, request: LLMRequest) -> LLMResponse:
        """Generate response from LLM."""
        pass


class OpenAIProvider(LLMProvider):
    """OpenAI API provider."""

    def __init__(self, api_key: Optional[str] = None):
        """Initialize OpenAI provider."""
        if not OPENAI_AVAILABLE:
            raise ImportError("OpenAI library not available")
        self.api_key = api_key or os.getenv('OPENAI_API_KEY')
        if not self.api_key:
            raise ValueError("OpenAI API key not provided")
        openai.api_key = self.api_key

    def generate(self, request: LLMRequest) -> LLMResponse:
        """Generate using OpenAI API."""
        try:
            messages = [{'role': 'user', 'content': request.prompt}]
            if request.system_prompt:
                messages.insert(0, {'role': 'system', 'content': request.system_prompt})

            response = openai.ChatCompletion.create(
                model=request.model,
                messages=messages,
                temperature=request.temperature,
                max_tokens=request.max_tokens
            )

            return LLMResponse(
                content=response.choices[0].message.content,
                model=request.model,
                finish_reason=response.choices[0].finish_reason,
                usage=response.usage
            )
        except Exception as e:
            logger.error(f"OpenAI generation failed: {e}")
            raise


class AnthropicProvider(LLMProvider):
    """Anthropic Claude API provider."""

    def __init__(self, api_key: Optional[str] = None):
        """Initialize Anthropic provider."""
        if not ANTHROPIC_AVAILABLE:
            raise ImportError("Anthropic library not available")
        self.api_key = api_key or os.getenv('ANTHROPIC_API_KEY')
        if not self.api_key:
            raise ValueError("Anthropic API key not provided")
        self.client = anthropic.Anthropic(api_key=self.api_key)

    def generate(self, request: LLMRequest) -> LLMResponse:
        """Generate using Anthropic API."""
        try:
            message = self.client.messages.create(
                model=request.model,
                max_tokens=request.max_tokens,
                temperature=request.temperature,
                system=request.system_prompt or "You are a workflow modeling expert.",
                messages=[{"role": "user", "content": request.prompt}]
            )

            return LLMResponse(
                content=message.content[0].text,
                model=request.model,
                finish_reason=message.stop_reason,
                usage={'input_tokens': message.usage.input_tokens,
                       'output_tokens': message.usage.output_tokens}
            )
        except Exception as e:
            logger.error(f"Anthropic generation failed: {e}")
            raise


class LocalLLMProvider(LLMProvider):
    """Local LLM provider using Ollama or similar."""

    def __init__(self, base_url: str = "http://localhost:11434"):
        """Initialize local LLM provider."""
        self.base_url = base_url
        try:
            import requests
            self.requests = requests
        except ImportError:
            raise ImportError("Requests library not available")

    def generate(self, request: LLMRequest) -> LLMResponse:
        """Generate using local LLM API."""
        try:
            payload = {
                "model": request.model,
                "prompt": request.prompt,
                "stream": False,
                "options": {
                    "temperature": request.temperature,
                    "num_predict": request.max_tokens
                }
            }

            response = self.requests.post(
                f"{self.base_url}/api/generate",
                json=payload,
                timeout=120
            )
            response.raise_for_status()

            data = response.json()

            return LLMResponse(
                content=data.get('response', ''),
                model=request.model,
                finish_reason='stop',
                usage={'prompt_tokens': data.get('prompt_eval_count', 0),
                       'completion_tokens': data.get('eval_count', 0)}
            )
        except Exception as e:
            logger.error(f"Local LLM generation failed: {e}")
            raise


class LLMInterface:
    """
    Main interface for LLM-based workflow generation.

    Provides:
    - Workflow generation from natural language
    - Model validation against evidence
    - Refinement with feedback
    """

    def __init__(self, provider_type: str = 'openai', **kwargs):
        """
        Initialize LLM interface.

        Args:
            provider_type: Type of LLM provider ('openai', 'anthropic', 'local')
            **kwargs: Additional arguments for provider
        """
        self.provider = self._create_provider(provider_type, **kwargs)
        self.logger = logging.getLogger(f"{__name__}.LLMInterface")

    def _create_provider(self, provider_type: str, **kwargs) -> LLMProvider:
        """Create LLM provider instance."""
        if provider_type == 'openai':
            return OpenAIProvider(**kwargs)
        elif provider_type == 'anthropic':
            return AnthropicProvider(**kwargs)
        elif provider_type == 'local':
            return LocalLLMProvider(**kwargs)
        else:
            raise ValueError(f"Unknown provider type: {provider_type}")

    def generate_workflow(self, description: str, pattern_hint: Optional[str] = None) -> Dict[str, Any]:
        """
        Generate YAWL workflow from natural language description.

        Args:
            description: Natural language description of workflow
            pattern_hint: Optional hint about pattern type

        Returns:
            Generated workflow JSON
        """
        system_prompt = self._build_system_prompt()
        user_prompt = self._build_generation_prompt(description, pattern_hint)

        request = LLMRequest(
            prompt=user_prompt,
            model=self._get_default_model(),
            temperature=0.7,
            max_tokens=2000,
            system_prompt=system_prompt
        )

        response = self.provider.generate(request)

        # Try to extract JSON from response
        workflow_json = self._extract_json(response.content)

        return {
            'workflow': workflow_json,
            'raw_response': response.content,
            'model': response.model,
            'tokens_used': response.usage
        }

    def validate_workflow(self, workflow: Dict[str, Any], evidence: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate workflow against evidence using LLM.

        Args:
            workflow: Generated workflow
            evidence: Source evidence (XES log, etc.)

        Returns:
            Validation result
        """
        prompt = self._build_validation_prompt(workflow, evidence)

        request = LLMRequest(
            prompt=prompt,
            model=self._get_default_model(),
            temperature=0.3,
            max_tokens=1500
        )

        response = self.provider.generate(request)

        return {
            'validation': response.content,
            'is_valid': self._parse_validation(response.content)
        }

    def refine_workflow(self, workflow: Dict[str, Any], feedback: str) -> Dict[str, Any]:
        """
        Refine workflow based on feedback.

        Args:
            workflow: Current workflow
            feedback: Feedback for refinement

        Returns:
            Refined workflow
        """
        prompt = self._build_refinement_prompt(workflow, feedback)

        request = LLMRequest(
            prompt=prompt,
            model=self._get_default_model(),
            temperature=0.7,
            max_tokens=2000
        )

        response = self.provider.generate(request)

        refined_workflow = self._extract_json(response.content)

        return {
            'workflow': refined_workflow,
            'raw_response': response.content
        }

    def _build_system_prompt(self) -> str:
        """Build system prompt for LLM."""
        return """You are an expert in YAWL (Yet Another Workflow Language) workflow modeling.

YAWL patterns include:
- Basic patterns: sequential, parallel split/join, exclusive choice, simple merge
- Advanced patterns: multi-instance, deferred choice, interleaved parallelism
- Cancellation patterns: cancellation region, thread, subprocess, etc.
- Resource patterns: with/without allocation

When generating workflows, use valid JSON format with:
- workflow_id: unique identifier
- pattern_type: type of YAWL pattern
- places: list of places with id and name
- transitions: list of transitions with id and name
- arcs: list of arcs with source and target

Respond only with valid JSON."""

    def _build_generation_prompt(self, description: str, pattern_hint: Optional[str]) -> str:
        """Build prompt for workflow generation."""
        hint_text = f"\nPattern hint: {pattern_hint}" if pattern_hint else ""
        return f"""Generate a YAWL workflow for the following process:

{description}{hint_text}

Provide the workflow as valid JSON following the YAWL schema."""

    def _build_validation_prompt(self, workflow: Dict[str, Any], evidence: Dict[str, Any]) -> str:
        """Build prompt for validation."""
        return f"""Validate the following YAWL workflow against the provided evidence.

Workflow:
{json.dumps(workflow, indent=2)}

Evidence:
{json.dumps(evidence, indent=2)}

Check for:
1. Missing activities present in evidence but not in workflow
2. Spurious activities in workflow but not in evidence
3. Causal order violations
4. Structural inconsistencies

Provide validation as JSON with:
- is_valid: boolean
- issues: list of found issues
- suggestions: list of improvement suggestions"""

    def _build_refinement_prompt(self, workflow: Dict[str, Any], feedback: str) -> str:
        """Build prompt for refinement."""
        return f"""Refine the following YAWL workflow based on the feedback.

Current Workflow:
{json.dumps(workflow, indent=2)}

Feedback:
{feedback}

Provide the refined workflow as valid JSON."""

    def _get_default_model(self) -> str:
        """Get default model for current provider."""
        if isinstance(self.provider, OpenAIProvider):
            return 'gpt-4'
        elif isinstance(self.provider, AnthropicProvider):
            return 'claude-3-opus-20240229'
        elif isinstance(self.provider, LocalLLMProvider):
            return 'llama2'
        else:
            return 'gpt-4'

    def _extract_json(self, text: str) -> Dict[str, Any]:
        """Extract JSON from LLM response."""
        import re

        # Try to find JSON block
        json_match = re.search(r'```json\s*(\{.*?\})\s*```', text, re.DOTALL)
        if json_match:
            text = json_match.group(1)

        # Try to find JSON object
        obj_match = re.search(r'\{.*\}', text, re.DOTALL)
        if obj_match:
            text = obj_match.group(0)

        return json.loads(text)

    def _parse_validation(self, response_text: str) -> Optional[bool]:
        """Parse validation result from LLM response."""
        try:
            result = self._extract_json(response_text)
            return result.get('is_valid', None)
        except Exception:
            # Try simple text search
            lower = response_text.lower()
            if 'valid: true' in lower or 'is valid' in lower:
                return True
            elif 'valid: false' in lower or 'not valid' in lower:
                return False
            return None


def erlang_main():
    """Main entry point for Erlang port communication."""
    import sys

    interface = LLMInterface('local')  # Default to local

    for line in sys.stdin:
        try:
            command = json.loads(line.strip())
            result = process_llm_command(interface, command)
            print(json.dumps(result))
            sys.stdout.flush()
        except Exception as e:
            print(json.dumps({'error': str(e)}))
            sys.stdout.flush()


def process_llm_command(interface: LLMInterface, command: Dict[str, Any]) -> Dict[str, Any]:
    """Process LLM command from Erlang."""
    cmd_type = command.get('type', '')
    params = command.get('params', {})

    if cmd_type == 'generate':
        result = interface.generate_workflow(
            params.get('description', ''),
            params.get('pattern_hint')
        )
        return {'status': 'ok', 'result': result}

    elif cmd_type == 'validate':
        result = interface.validate_workflow(
            params.get('workflow', {}),
            params.get('evidence', {})
        )
        return {'status': 'ok', 'result': result}

    elif cmd_type == 'refine':
        result = interface.refine_workflow(
            params.get('workflow', {}),
            params.get('feedback', '')
        )
        return {'status': 'ok', 'result': result}

    else:
        return {'status': 'error', 'message': f'Unknown command: {cmd_type}'}


if __name__ == '__main__':
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == '--erlang':
        erlang_main()
    else:
        print("LLM Interface for YAWL-Erlang Integration")
        print("Use --erlang flag for Erlang port mode")
