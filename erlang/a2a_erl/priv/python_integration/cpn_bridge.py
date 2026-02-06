#!/usr/bin/env python3
"""
CPN-Py Bridge: Colored Petri Nets Python/Erlang Integration

This module provides a bridge between Erlang YAWL workflow system and
Python's process mining ecosystem (PM4Py, CPN Tools).

Reference: van der Aalst et al. (Mar 2025) "CPN-Py: Colored Petri Nets
with Python/PM4Py Integration"

Author: A2A Team
"""

import json
import os
import sys
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, field
from datetime import datetime
import logging

# Try to import pm4py
try:
    import pm4py
    from pm4py.objects.log.importer.xes import importer as xes_importer
    from pm4py.objects.log.exporter.xes import exporter as xes_exporter
    from pm4py.algo.discovery.alpha import alpha_miner
    from pm4py.algo.conformance.alignments import factory as alignment_factory
    from pm4py.visualization.petri_net import visualizer as pn_visualizer
    PM4PY_AVAILABLE = True
except ImportError:
    PM4PY_AVAILABLE = False
    logging.warning("PM4Py not available. Some features will be limited.")

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@dataclass
class ColorSet:
    """Represents a color set in CPN (Colored Petri Net)."""
    name: str
    type: str  # 'boolean', 'integer', 'float', 'string', 'list', 'record', 'product'
    constraints: List[str] = field(default_factory=list)


@dataclass
class ColoredToken:
    """A token with data (color) in a CPN."""
    data: Any
    color_set: str
    timestamp: Optional[int] = None
    attributes: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert token to dictionary representation."""
        return {
            'data': self.data,
            'color_set': self.color_set,
            'timestamp': self.timestamp,
            'attributes': self.attributes
        }


@dataclass
class CPNPlace:
    """A place in a Colored Petri Net."""
    id: str
    name: str
    initial_tokens: List[ColoredToken] = field(default_factory=list)
    color_set: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert place to dictionary representation."""
        return {
            'id': self.id,
            'name': self.name,
            'initialTokens': len(self.initial_tokens),
            'colorSet': self.color_set
        }


@dataclass
class CPNTransition:
    """A transition in a Colored Petri Net."""
    id: str
    name: str
    guard: Optional[str] = None
    variables: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        """Convert transition to dictionary representation."""
        return {
            'id': self.id,
            'name': self.name,
            'guard': self.guard,
            'variables': self.variables
        }


@dataclass
class CPNArc:
    """An arc in a Colored Petri Net."""
    source: str
    target: str
    expression: Optional[str] = None
    arc_type: str = "normal"  # 'normal', 'inhibitor', 'reset'

    def to_dict(self) -> Dict[str, Any]:
        """Convert arc to dictionary representation."""
        return {
            'source': self.source,
            'target': self.target,
            'expression': self.expression,
            'type': self.arc_type
        }


@dataclass
class ColoredPetriNet:
    """A Colored Petri Net (CPN) representation."""
    id: str
    name: str
    places: List[CPNPlace] = field(default_factory=list)
    transitions: List[CPNTransition] = field(default_factory=list)
    arcs: List[CPNArc] = field(default_factory=list)
    color_sets: Dict[str, ColorSet] = field(default_factory=dict)

    def to_json(self) -> str:
        """Convert CPN to JSON format."""
        return json.dumps({
            'version': '1.0',
            'format': 'cpn-json',
            'id': self.id,
            'name': self.name,
            'places': [p.to_dict() for p in self.places],
            'transitions': [t.to_dict() for t in self.transitions],
            'arcs': [a.to_dict() for a in self.arcs],
            'colorSets': {
                name: {
                    'type': cs.type,
                    'constraints': cs.constraints
                }
                for name, cs in self.color_sets.items()
            }
        }, indent=2)

    @classmethod
    def from_json(cls, json_str: str) -> 'ColoredPetriNet':
        """Load CPN from JSON format."""
        data = json.loads(json_str)

        cpn = cls(
            id=data.get('id', ''),
            name=data.get('name', '')
        )

        # Load color sets
        for name, cs_data in data.get('colorSets', {}).items():
            cpn.color_sets[name] = ColorSet(
                name=name,
                type=cs_data.get('type', 'any'),
                constraints=cs_data.get('constraints', [])
            )

        # Load places
        for p_data in data.get('places', []):
            place = CPNPlace(
                id=p_data.get('id', ''),
                name=p_data.get('name', ''),
                color_set=p_data.get('colorSet')
            )
            cpn.places.append(place)

        # Load transitions
        for t_data in data.get('transitions', []):
            transition = CPNTransition(
                id=t_data.get('id', ''),
                name=t_data.get('name', ''),
                guard=t_data.get('guard'),
                variables=t_data.get('variables', [])
            )
            cpn.transitions.append(transition)

        # Load arcs
        for a_data in data.get('arcs', []):
            arc = CPNArc(
                source=a_data.get('source', ''),
                target=a_data.get('target', ''),
                expression=a_data.get('expression'),
                arc_type=a_data.get('type', 'normal')
            )
            cpn.arcs.append(arc)

        return cpn


class CPNBridge:
    """
    Bridge between Erlang YAWL and Python CPN/PM4Py ecosystem.

    Provides methods for:
    - Converting between YAWL and CPN formats
    - Process discovery using PM4Py
    - Conformance checking
    - Stochastic replay
    """

    def __init__(self):
        """Initialize the CPN bridge."""
        self.logger = logging.getLogger(f"{__name__}.CPNBridge")
        self.cpn_cache: Dict[str, ColoredPetriNet] = {}

    def convert_yawl_to_cpn(self, yawl_json: Dict[str, Any]) -> ColoredPetriNet:
        """
        Convert YAWL workflow JSON to Colored Petri Net.

        Args:
            yawl_json: YAWL workflow in JSON format

        Returns:
            ColoredPetriNet representation
        """
        self.logger.info(f"Converting YAWL workflow {yawl_json.get('workflow_id', 'unknown')} to CPN")

        cpn = ColoredPetriNet(
            id=yawl_json.get('workflow_id', ''),
            name=yawl_json.get('pattern_type', 'YAWL Workflow')
        )

        # Add default color sets
        cpn.color_sets['any'] = ColorSet('any', 'any')
        cpn.color_sets['boolean'] = ColorSet('boolean', 'boolean')
        cpn.color_sets['integer'] = ColorSet('integer', 'integer')
        cpn.color_sets['string'] = ColorSet('string', 'string')

        # Convert places
        for p_data in yawl_json.get('places', []):
            place = CPNPlace(
                id=p_data.get('id', ''),
                name=p_data.get('name', ''),
                color_set='any'  # Default color set
            )
            cpn.places.append(place)

        # Convert transitions
        for t_data in yawl_json.get('transitions', []):
            transition = CPNTransition(
                id=t_data.get('id', ''),
                name=t_data.get('name', ''),
                guard=t_data.get('guard')
            )
            cpn.transitions.append(transition)

        # Convert arcs
        for a_data in yawl_json.get('arcs', []):
            arc = CPNArc(
                source=a_data.get('source', ''),
                target=a_data.get('target', ''),
                expression=a_data.get('expression')
            )
            cpn.arcs.append(arc)

        return cpn

    def convert_cpn_to_pm4py(self, cpn: ColoredPetriNet):
        """
        Convert CPN to PM4Py Petri net format.

        Args:
            cpn: Colored Petri Net

        Returns:
            PM4Py Petri net (places, transitions, arcs)
        """
        if not PM4PY_AVAILABLE:
            self.logger.warning("PM4Py not available, returning placeholder")
            return None, None, None

        # Convert to PM4Py format
        # This is a simplified conversion - full implementation would handle
        # colored tokens properly

        import pm4py.objects.petri_net.petri_net as pn

        places = {}
        transitions = {}
        arcs = []

        for place in cpn.places:
            pn_place = pn.Place(place.id, name=place.name)
            places[place.id] = pn_place

        for trans in cpn.transitions:
            pn_trans = pn.Transition(trans.id, name=trans.name)
            transitions[trans.id] = pn_trans

        for arc in cpn.arcs:
            if arc.source in places and arc.target in transitions:
                pn_arc = pn.PetriNet.Arc(
                    places[arc.source],
                    transitions[arc.target]
                )
                arcs.append(pn_arc)
            elif arc.source in transitions and arc.target in places:
                pn_arc = pn.PetriNet.Arc(
                    transitions[arc.source],
                    places[arc.target]
                )
                arcs.append(pn_arc)

        # Create Petri net
        net = pn.PetriNet(places.values(), transitions.values(), arcs)

        return net, places.values(), transitions.values()

    def discover_process_from_xes(self, xes_path: str) -> Dict[str, Any]:
        """
        Discover a process model from XES event log.

        Args:
            xes_path: Path to XES file

        Returns:
            Discovered process model information
        """
        if not PM4PY_AVAILABLE:
            return {'error': 'PM4Py not available'}

        self.logger.info(f"Discovering process from {xes_path}")

        try:
            # Import XES log
            log = xes_importer.apply(xes_path)

            # Discover using Alpha Miner
            net, initial_marking, final_marking = alpha_miner.apply(log)

            # Get model statistics
            places = list(net.places)
            transitions = list(net.transitions)

            return {
                'status': 'success',
                'places': [{'id': p.name, 'name': p.name} for p in places],
                'transitions': [{'id': t.name, 'name': t.name} for t in transitions],
                'place_count': len(places),
                'transition_count': len(transitions),
                'discovery_algorithm': 'alpha_miner'
            }
        except Exception as e:
            self.logger.error(f"Process discovery failed: {e}")
            return {'status': 'error', 'message': str(e)}

    def stochastic_replay(self, xes_path: str, model_path: str) -> Dict[str, Any]:
        """
        Perform stochastic replay of traces on model.

        Args:
            xes_path: Path to XES event log
            model_path: Path to model file (optional)

        Returns:
            Replay results with confidence scores
        """
        if not PM4PY_AVAILABLE:
            return {'error': 'PM4Py not available'}

        try:
            log = xes_importer.apply(xes_path)

            # Discover model if not provided
            if not model_path:
                net, im, fm = alpha_miner.apply(log)
            else:
                # Load model from file (would need implementation)
                pass

            # Perform alignment
            result = alignment_factory.apply_log(log, net, im, fm,
                                                   variant=alignment_factory.TOKEN_BASED)

            # Calculate fitness
            fitness = result['fitness']

            return {
                'status': 'success',
                'fitness': fitness,
                'aligned_traces': len(result['alignments']),
                'total_traces': len(log)
            }
        except Exception as e:
            self.logger.error(f"Stochastic replay failed: {e}")
            return {'status': 'error', 'message': str(e)}

    def export_to_xes(self, events: List[Dict[str, Any]], output_path: str) -> bool:
        """
        Export events to XES format.

        Args:
            events: List of event dictionaries
            output_path: Output XES file path

        Returns:
            True if successful
        """
        if not PM4PY_AVAILABLE:
            self.logger.warning("PM4Py not available, using fallback XES export")
            return self._fallback_xes_export(events, output_path)

        try:
            from pm4py.objects.log.obj import EventLog

            log = EventLog()
            # Convert events to PM4Py format
            # ... (implementation depends on PM4Py version)

            xes_exporter.apply(log, output_path)
            return True
        except Exception as e:
            self.logger.error(f"XES export failed: {e}")
            return False

    def _fallback_xes_export(self, events: List[Dict[str, Any]], output_path: str) -> bool:
        """Fallback XES export when PM4Py is not available."""
        import xml.etree.ElementTree as ET

        # Create XES structure
        log = ET.Element('log', {
            'xes.version': '1.0',
            'xes.xmlns': 'http://www.xes-standard.org/'
        })

        # Add extensions
        ext = ET.SubElement(log, 'extension', {
            'name': 'Concept',
            'prefix': 'concept',
            'uri': 'http://www.xes-standard.org/concept.xesext'
        })

        # Add trace
        trace = ET.SubElement(log, 'trace')

        # Add events
        for event in events:
            evt = ET.SubElement(trace, 'event')

            # Add concept name
            ET.SubElement(evt, 'string', {
                'key': 'concept:name',
                'value': str(event.get('activity', event.get('concept:name', 'unknown')))
            })

            # Add timestamp
            if 'timestamp' in event:
                ET.SubElement(evt, 'date', {
                    'key': 'time:timestamp',
                    'value': str(event['timestamp'])
                })

        # Write to file
        tree = ET.ElementTree(log)
        tree.write(output_path, encoding='UTF-8', xml_declaration=True)

        return True

    def validate_cpn_json(self, json_str: str) -> Dict[str, Any]:
        """
        Validate CPN JSON format.

        Args:
            json_str: CPN JSON string

        Returns:
            Validation result
        """
        try:
            data = json.loads(json_str)

            # Check required fields
            if 'places' not in data or 'transitions' not in data:
                return {
                    'valid': False,
                    'errors': ['Missing required fields: places or transitions']
                }

            # Validate arc references
            place_ids = {p['id'] for p in data['places']}
            transition_ids = {t['id'] for t in data['transitions']}

            for arc in data.get('arcs', []):
                if arc['source'] not in place_ids and arc['source'] not in transition_ids:
                    return {
                        'valid': False,
                        'errors': [f"Invalid arc source: {arc['source']}"]
                    }
                if arc['target'] not in place_ids and arc['target'] not in transition_ids:
                    return {
                        'valid': False,
                        'errors': [f"Invalid arc target: {arc['target']}"]
                    }

            return {'valid': True, 'errors': []}

        except json.JSONDecodeError as e:
            return {
                'valid': False,
                'errors': [f'Invalid JSON: {e}']
            }


def to_pm4py_petri_net(cpn_json: Dict[str, Any]) -> Dict[str, Any]:
    """
    Convert CPN JSON to PM4Py Petri net format.

    This is a standalone function callable from Erlang via the Python bridge.
    It performs the conversion from CPN (Colored Petri Net) JSON format to
    PM4Py-compatible Petri net representation.

    Reference: arXiv:2506.12238 - Berti, van der Aalst (Mar 2025)
    "CPN-Py: Colored Petri Nets with Python/PM4Py Integration"

    Args:
        cpn_json: CPN in JSON format (dict with places, transitions, arcs)

    Returns:
        Dictionary containing:
        - net: Petri net metadata (type, counts)
        - places: List of place objects
        - transitions: List of transition objects
        - arcs: List of arc objects
        - conversion_method: 'pm4py' if PM4Py available, 'native' otherwise
    """
    logger.info("Converting CPN to PM4Py Petri net format")

    # Extract CPN components
    places_data = cpn_json.get('places', [])
    transitions_data = cpn_json.get('transitions', [])
    arcs_data = cpn_json.get('arcs', [])

    if PM4PY_AVAILABLE:
        # Use PM4Py for full conversion
        try:
            return _convert_with_pm4py(places_data, transitions_data, arcs_data)
        except Exception as e:
            logger.warning(f"PM4Py conversion failed: {e}, falling back to native")
            return _convert_native(places_data, transitions_data, arcs_data)
    else:
        # Use native conversion
        logger.info("PM4Py not available, using native conversion")
        return _convert_native(places_data, transitions_data, arcs_data)


def _convert_with_pm4py(places_data, transitions_data, arcs_data) -> Dict[str, Any]:
    """Convert using PM4Py library for full Petri net support."""
    import pm4py.objects.petri_net.petri_net as pn

    # Create PM4Py places
    places = {}
    for p_data in places_data:
        place_id = p_data.get('id', '')
        place_name = p_data.get('name', place_id)
        pn_place = pn.Place(place_id, name=place_name)
        places[place_id] = pn_place

    # Create PM4Py transitions
    transitions = {}
    for t_data in transitions_data:
        trans_id = t_data.get('id', '')
        trans_name = t_data.get('name', trans_id)
        pn_trans = pn.Transition(trans_id, name=trans_name)
        transitions[trans_id] = pn_trans

    # Create PM4Py arcs
    arcs = []
    for a_data in arcs_data:
        source = a_data.get('source', '')
        target = a_data.get('target', '')

        if source in places and target in transitions:
            # Place to transition arc
            pn_arc = pn.PetriNet.Arc(places[source], transitions[target])
            arcs.append(pn_arc)
        elif source in transitions and target in places:
            # Transition to place arc
            pn_arc = pn.PetriNet.Arc(transitions[source], places[target])
            arcs.append(pn_arc)

    # Create the Petri net
    net = pn.PetriNet(places.values(), transitions.values(), arcs)

    # Return structured result
    return {
        'net': {
            'type': 'pm4py_petri_net',
            'place_count': len(places),
            'transition_count': len(transitions),
            'arc_count': len(arcs),
            'pm4py_available': True
        },
        'places': [
            {
                'id': p.name,
                'name': p.name,
                'in_arcs': len(p.in_arcs),
                'out_arcs': len(p.out_arcs)
            }
            for p in places.values()
        ],
        'transitions': [
            {
                'id': t.name,
                'name': t.name,
                'in_arcs': len(t.in_arcs),
                'out_arcs': len(t.out_arcs)
            }
            for t in transitions.values()
        ],
        'arcs': [
            {
                'source': arc.source.name,
                'target': arc.target.name,
                'type': 'place_to_transition' if arc.source in places.values() else 'transition_to_place'
            }
            for arc in arcs
        ],
        'conversion_method': 'pm4py',
        'timestamp': datetime.now().isoformat()
    }


def _convert_native(places_data, transitions_data, arcs_data) -> Dict[str, Any]:
    """Convert using native Python (fallback when PM4Py unavailable)."""
    # Convert places
    places = []
    for p_data in places_data:
        places.append({
            'id': p_data.get('id', ''),
            'name': p_data.get('name', ''),
            'initial_tokens': p_data.get('initialTokens', 0),
            'color_set': p_data.get('colorSet', 'any')
        })

    # Convert transitions
    transitions = []
    for t_data in transitions_data:
        transitions.append({
            'id': t_data.get('id', ''),
            'name': t_data.get('name', ''),
            'guard': t_data.get('guard'),
            'variables': t_data.get('variables', [])
        })

    # Convert arcs
    arcs = []
    for a_data in arcs_data:
        arcs.append({
            'source': a_data.get('source', ''),
            'target': a_data.get('target', ''),
            'expression': a_data.get('expression'),
            'type': a_data.get('type', 'normal')
        })

    return {
        'net': {
            'type': 'native_petri_net',
            'place_count': len(places),
            'transition_count': len(transitions),
            'arc_count': len(arcs),
            'pm4py_available': PM4PY_AVAILABLE
        },
        'places': places,
        'transitions': transitions,
        'arcs': arcs,
        'conversion_method': 'native',
        'timestamp': datetime.now().isoformat()
    }


def erlang_port_main():
    """
    Main entry point for Erlang port communication.

    Reads JSON commands from stdin and writes responses to stdout.
    This allows Erlang to call Python functions via stdio.
    """
    import sys

    logger.info("CPN Bridge: Erlang port mode started")

    bridge = CPNBridge()

    for line in sys.stdin:
        try:
            command = json.loads(line.strip())
            result = process_erlang_command(bridge, command)
            print(json.dumps(result))
            sys.stdout.flush()
        except json.JSONDecodeError as e:
            error_result = {'status': 'error', 'message': f'Invalid JSON: {e}'}
            print(json.dumps(error_result))
            sys.stdout.flush()
        except Exception as e:
            error_result = {'status': 'error', 'message': str(e)}
            print(json.dumps(error_result))
            sys.stdout.flush()


def process_erlang_command(bridge: CPNBridge, command: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process a command from Erlang.

    Args:
        bridge: CPNBridge instance
        command: Command dictionary with 'type' and 'params'

    Returns:
        Result dictionary
    """
    cmd_type = command.get('type', '')
    params = command.get('params', {})

    if cmd_type == 'to_pm4py_petri_net':
        cpn_json = params.get('cpn_json', {})
        result = to_pm4py_petri_net(cpn_json)
        return {'status': 'ok', 'result': result}

    elif cmd_type == 'convert_yawl_to_cpn':
        yawl_json = params.get('yawl_json', {})
        cpn = bridge.convert_yawl_to_cpn(yawl_json)
        return {'status': 'ok', 'cpn_json': json.loads(cpn.to_json())}

    elif cmd_type == 'discover_process':
        xes_path = params.get('xes_path')
        result = bridge.discover_process_from_xes(xes_path)
        return {'status': 'ok', 'result': result}

    elif cmd_type == 'validate_cpn':
        json_str = params.get('json_str', '{}')
        result = bridge.validate_cpn_json(json_str)
        return {'status': 'ok', 'result': result}

    elif cmd_type == 'stochastic_replay':
        xes_path = params.get('xes_path')
        model_path = params.get('model_path', '')
        result = bridge.stochastic_replay(xes_path, model_path)
        return {'status': 'ok', 'result': result}

    else:
        return {'status': 'error', 'message': f'Unknown command type: {cmd_type}'}


def main():
    """Main entry point for command-line usage."""
    import argparse

    parser = argparse.ArgumentParser(description='CPN-Py Bridge')
    parser.add_argument('--convert', help='Convert YAWL JSON to CPN')
    parser.add_argument('--discover', help='Discover process from XES')
    parser.add_argument('--xes', help='XES file path')
    parser.add_argument('--output', help='Output file path')
    parser.add_argument('--validate', help='Validate CPN JSON file')

    args = parser.parse_args()

    bridge = CPNBridge()

    if args.convert:
        with open(args.convert, 'r') as f:
            yawl_json = json.load(f)
        cpn = bridge.convert_yawl_to_cpn(yawl_json)
        print(cpn.to_json())

    elif args.discover:
        result = bridge.discover_process_from_xes(args.discover)
        print(json.dumps(result, indent=2))

    elif args.validate:
        with open(args.validate, 'r') as f:
            json_str = f.read()
        result = bridge.validate_cpn_json(json_str)
        print(json.dumps(result, indent=2))

    else:
        parser.print_help()


if __name__ == '__main__':
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == '--erlang':
        erlang_port_main()
    else:
        main()
