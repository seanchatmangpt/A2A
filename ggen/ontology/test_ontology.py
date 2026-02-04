#!/usr/bin/env python3
"""
A2A Protocol Ontology Test Suite
Comprehensive tests for the ontology structure and validation
"""

import os
import sys
import unittest
from rdflib import Graph, URIRef, Namespace
from rdflib.plugins.shacl import validate
from rdflib.namespace import RDF, RDFS, XSD, OWL
import json

# Add current directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

class TestA2AOntology(unittest.TestCase):
    """Test suite for A2A Protocol Ontology"""

    def setUp(self):
        """Setup test data"""
        self.g = Graph()

        # Define namespaces
        self.a2a = Namespace("https://a2a.com/schema/")
        self.ex = Namespace("https://example.org/a2a/examples/")
        self.sh = Namespace("http://www.w3.org/ns/shacl#")

        # Load ontology files
        ontology_file = "a2a-comprehensive-ontology.ttl"
        shacl_file = "a2a-shacl-validation.ttl"
        examples_file = "examples/a2a-protocol-examples.ttl"

        self.g.parse(ontology_file, format="turtle")
        self.g.parse(shacl_file, format="turtle")
        self.g.parse(examples_file, format="turtle")

    def test_ontology_structure(self):
        """Test basic ontology structure"""
        # Check main classes
        self.assertTrue((self.a2a.Task, RDF.type, OWL.Class) in self.g)
        self.assertTrue((self.a2a.Agent, RDF.type, OWL.Class) in self.g)
        self.assertTrue((self.a2a.Message, RDF.type, OWL.Class) in self.g)
        self.assertTrue((self.a2a.Error, RDF.type, OWL.Class) in self.g)

        # Check task states
        expected_states = [
            self.a2a.pending, self.a2a.queued, self.a2a.running,
            self.a2a.completed, self.a2a.failed
        ]

        for state in expected_states:
            self.assertTrue((state, RDF.type, self.a2a.TaskState) in self.g)

    def test_task_validation(self):
        """Test task instances against validation rules"""
        # Check if tasks have required properties
        tasks = list(self.g.subjects(RDF.type, self.a2a.Task))

        for task in tasks:
            # Check required properties
            has_task_id = (task, self.a2a.task_id, None) in self.g
            has_task_name = (task, self.a2a.task_name, None) in self.g
            has_task_state = (task, self.a2a.task_state, None) in self.g

            self.assertTrue(has_task_id, f"Task {task} missing task_id")
            self.assertTrue(has_task_name, f"Task {task} missing task_name")
            self.assertTrue(has_task_state, f"Task {task} missing task_state")

    def test_agent_validation(self):
        """Test agent instances against validation rules"""
        agents = list(self.g.subjects(RDF.type, self.a2a.Agent))

        for agent in agents:
            # Check required properties
            has_agent_id = (agent, self.a2a.agent_id, None) in self.g
            has_agent_name = (agent, self.a2a.agent_name, None) in self.g
            has_agent_state = (agent, self.a2a.agent_state, None) in self.g

            self.assertTrue(has_agent_id, f"Agent {agent} missing agent_id")
            self.assertTrue(has_agent_name, f"Agent {agent} missing agent_name")
            self.assertTrue(has_agent_state, f"Agent {agent} missing agent_state")

    def test_message_validation(self):
        """Test message instances against validation rules"""
        messages = list(self.g.subjects(RDF.type, self.a2a.Message))

        for message in messages:
            # Check required properties
            has_message_id = (message, self.a2a.message_id, None) in self.g
            has_message_type = (message, self.a2a.message_type, None) in self.g
            has_sender = (message, self.a2a.sender, None) in self.g
            has_timestamp = (message, self.a2a.timestamp, None) in self.g

            self.assertTrue(has_message_id, f"Message {message} missing message_id")
            self.assertTrue(has_message_type, f"Message {message} missing message_type")
            self.assertTrue(has_sender, f"Message {message} missing sender")
            self.assertTrue(has_timestamp, f"Message {message} missing timestamp")

    def test_state_machine_validity(self):
        """Test state machine configurations"""
        # Check transitions are valid
        transitions = list(self.g.subjects(RDF.type, self.a2a.Transition))

        for trans in transitions:
            has_from_state = (trans, self.a2a.from_state, None) in self.g
            has_to_state = (trans, self.a2a.to_state, None) in self.g

            self.assertTrue(has_from_state, f"Transition {trans} missing from_state")
            self.assertTrue(has_to_state, f"Transition {trans} missing to_state")

    def test_error_handling(self):
        """Test error instances and recovery strategies"""
        errors = list(self.g.subjects(RDF.type, self.a2a.Error))

        for error in errors:
            has_error_code = (error, self.a2a.error_code, None) in self.g
            has_error_message = (error, self.a2a.error_message, None) in self.g
            has_error_severity = (error, self.a2a.error_severity, None) in self.g

            self.assertTrue(has_error_code, f"Error {error} missing error_code")
            self.assertTrue(has_error_message, f"Error {error} missing error_message")
            self.assertTrue(has_error_severity, f"Error {error} missing error_severity")

    def test_protocol_compliance(self):
        """Test protocol compliance"""
        protocols = list(self.g.subjects(RDF.type, self.a2a.Protocol))

        for protocol in protocols:
            has_protocol_version = (protocol, self.a2a.protocol_version, None) in self.g
            self.assertTrue(has_protocol_version, f"Protocol {protocol} missing protocol_version")

    def test_temporal_consistency(self):
        """Test temporal consistency of task timestamps"""
        tasks = list(self.g.subjects(RDF.type, self.a2a.Task))

        for task in tasks:
            created = self.g.value(task, self.a2a.task_created, None)
            started = self.g.value(task, self.a2a.task_started, None)
            completed = self.g.value(task, self.a2a.task_completed, None)

            # Check temporal ordering
            if created and started:
                self.assertLessEqual(created, started, f"Task start time before creation time")

            if started and completed:
                self.assertLessEqual(started, completed, f"Task completion time before start time")

    def test_unique_constraints(self):
        """Test unique constraints for critical properties"""
        # Check unique task IDs
        task_ids = set()
        for task in self.g.subjects(RDF.type, self.a2a.Task):
            task_id = self.g.value(task, self.a2a.task_id, None)
            if task_id:
                self.assertNotIn(task_id, task_ids, f"Duplicate task ID: {task_id}")
                task_ids.add(task_id)

        # Check unique agent IDs
        agent_ids = set()
        for agent in self.g.subjects(RDF.type, self.a2a.Agent):
            agent_id = self.g.value(agent, self.a2a.agent_id, None)
            if agent_id:
                self.assertNotIn(agent_id, agent_ids, f"Duplicate agent ID: {agent_id}")
                agent_ids.add(agent_id)

    def test_shacl_validation(self):
        """Test SHACL validation"""
        # Run SHACL validation
        conforms, results, _ = validate(self.g)

        if not conforms:
            print("\nSHACL Validation Errors:")
            for result in results:
                print(f"- {result.focus}: {result.message}")

        self.assertTrue(conforms, "SHACL validation failed")

    def test_communication_patterns(self):
        """Test communication pattern validity"""
        messages = list(self.g.subjects(RDF.type, self.a2a.Message))

        valid_patterns = [
            self.a2a.request_response, self.a2a.publish_subscribe,
            self.a2a.point_to_point, self.a2a.broadcast,
            self.a2a.multicast, self.a2a.federated
        ]

        for message in messages:
            pattern = self.g.value(message, self.a2a.communication_pattern, None)
            if pattern:
                self.assertIn(pattern, valid_patterns,
                           f"Invalid communication pattern: {pattern}")

    def test_error_type_recovery_mapping(self):
        """Test error types have appropriate recovery strategies"""
        error_mapping = {
            self.a2a.timeout_error: self.a2a.retry_strategy,
            self.a2a.network_error: self.a2a.retry_strategy,
            self.a2a.protocol_error: self.a2a.escalate_strategy,
            self.a2a.authorization_error: self.a2a.compensate_strategy,
            self.a2a.resource_error: self.a2a.fallback_strategy
        }

        errors = list(self.g.subjects(RDF.type, self.a2a.Error))

        for error in errors:
            error_type = self.g.value(error, self.a2a.error_type, None)
            recovery = self.g.value(error, self.a2a.recovery_strategy, None)

            if error_type and recovery:
                expected_recovery = error_mapping.get(error_type)
                if expected_recovery:
                    self.assertEqual(recovery, expected_recovery,
                                 f"Wrong recovery strategy for {error_type}")

    def test_scheduling_strategies(self):
        """Test scheduling strategy validity"""
        valid_strategies = [
            self.a2a.round_robin, self.a2a.least_loaded,
            self.a2a.skill_based, self.a2a.priority_based,
            self.a2a.resource_aware
        ]

        tasks = list(self.g.subjects(RDF.type, self.a2a.Task))

        for task in tasks:
            strategy = self.g.value(task, self.a2a.scheduling_strategy, None)
            if strategy:
                self.assertIn(strategy, valid_strategies,
                           f"Invalid scheduling strategy: {strategy}")

def run_tests():
    """Run all tests"""
    # Create test suite
    suite = unittest.TestLoader().loadTestsFromTestCase(TestA2AOntology)

    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    return result.wasSuccessful()

if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)