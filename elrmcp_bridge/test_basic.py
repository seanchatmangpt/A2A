#!/usr/bin/env python3
"""
Basic test to verify the elrmcp_bridge implementation
"""

import sys
import os
from pathlib import Path

# Add the src directory to Python path
src_path = Path(__file__).parent / "src"
sys.path.insert(0, str(src_path))

def test_basic_imports():
    """Test basic imports"""
    print("Testing basic imports...")

    try:
        from elrmcp_bridge.src.config import BridgeConfig
        print("✅ BridgeConfig imported successfully")

        from elrmcp_bridge.src.utils import generate_message_id, validate_message
        print("✅ Utils imported successfully")

        # Test basic functionality
        msg_id = generate_message_id()
        print(f"✅ Generated message ID: {msg_id}")

        test_message = {"id": "test-123", "type": "mcp_request", "method": "tools/call"}
        is_valid = validate_message(test_message)
        print(f"✅ Message validation: {is_valid}")

        return True
    except Exception as e:
        print(f"❌ Import test failed: {e}")
        return False

def test_basic_functionality():
    """Test basic functionality"""
    print("\nTesting basic functionality...")

    try:
        from elrmcp_bridge.src.config import BridgeConfig

        # Create config
        config = BridgeConfig(host="localhost", port=8001)
        print(f"✅ Created config: {config.host}:{config.port}")

        # Test config validation
        is_valid = config.validate()
        print(f"✅ Config validation: {is_valid}")

        # Test config to dict
        config_dict = config.to_dict()
        print(f"✅ Config to dict: {len(config_dict)} keys")

        return True
    except Exception as e:
        print(f"❌ Functionality test failed: {e}")
        return False

def test_protocol():
    """Test protocol functionality"""
    print("\nTesting protocol functionality...")

    try:
        from elrmcp_bridge.src.protocol import A2AProtocol, MCPMessage

        # Create protocol
        protocol = A2AProtocol()
        print("✅ A2AProtocol created successfully")

        # Test MCP message creation
        mcp_message = MCPMessage(
            id="msg-123",
            method="tools/call",
            params={"name": "test", "arguments": {}}
        )
        print(f"✅ MCPMessage created: {mcp_message.method}")

        return True
    except Exception as e:
        print(f"❌ Protocol test failed: {e}")
        return False

def test_agents():
    """Test agents functionality"""
    print("\nTesting agents functionality...")

    try:
        from elrmcp_bridge.src.agents import Agent, AgentStatus

        # Create agent
        agent = Agent(
            agent_id="test-agent",
            name="Test Agent",
            version="1.0.0",
            capabilities=["test"],
            endpoints={},
            metadata={},
            status=AgentStatus.ACTIVE,
            last_seen=0
        )
        print(f"✅ Agent created: {agent.name}")

        return True
    except Exception as e:
        print(f"❌ Agents test failed: {e}")
        return False

def test_workflows():
    """Test workflows functionality"""
    print("\nTesting workflows functionality...")

    try:
        from elrmcp_bridge.src.workflows import WorkflowDefinition, TaskDefinition

        # Create task
        task = TaskDefinition(
            task_id="test-task",
            name="Test Task",
            type="agent",
            parameters={"test": "value"}
        )
        print(f"✅ Task created: {task.name}")

        # Create workflow
        workflow = WorkflowDefinition(
            workflow_id="test-workflow",
            name="Test Workflow",
            description="Test workflow",
            tasks=[task]
        )
        print(f"✅ Workflow created: {workflow.name}")

        # Test workflow to dict
        workflow_dict = workflow.to_dict()
        print(f"✅ Workflow to dict: {len(workflow_dict)} keys")

        return True
    except Exception as e:
        print(f"❌ Workflows test failed: {e}")
        return False

def test_transport():
    """Test transport functionality"""
    print("\nTesting transport functionality...")

    try:
        from elrmcp_bridge.src.transport import TransportManager

        # Create transport manager
        transport = TransportManager()
        print(f"✅ TransportManager created: {transport.transport_type}")

        return True
    except Exception as e:
        print(f"❌ Transport test failed: {e}")
        return False

def main():
    """Main test function"""
    print("🚀 Starting elrmcp_bridge basic tests...")
    print("=" * 60)

    tests = [
        test_basic_imports,
        test_basic_functionality,
        test_protocol,
        test_agents,
        test_workflows,
        test_transport
    ]

    results = []
    for test in tests:
        try:
            result = test()
            results.append(result)
        except Exception as e:
            print(f"❌ Test failed with exception: {e}")
            results.append(False)

    print("\n" + "=" * 60)
    print("📊 Test Results:")
    print(f"✅ Passed: {sum(results)}/{len(results)}")
    print(f"❌ Failed: {len(results) - sum(results)}/{len(results)}")

    if all(results):
        print("🎉 All tests passed!")
        return 0
    else:
        print("💥 Some tests failed!")
        return 1

if __name__ == "__main__":
    exit(main())