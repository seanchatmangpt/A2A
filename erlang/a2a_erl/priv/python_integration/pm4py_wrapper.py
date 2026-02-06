#!/usr/bin/env python3
"""
PM4Py Wrapper: Python Process Mining Library Interface

This module provides wrapper functions for PM4Py library to be used
from Erlang via the CPN bridge.

Features:
- Process discovery (Alpha Miner, Heuristics Miner, Inductive Miner)
- Conformance checking (alignments, token replay)
- Performance analysis (bottlenecks, case durations)
- Visualization export

Author: A2A Team
"""

import logging
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass

# Try to import pm4py
try:
    import pm4py
    from pm4py.objects.log.importer.xes import importer as xes_importer
    from pm4py.objects.log.importer.csv import importer as csv_importer
    from pm4py.objects.log.exporter.xes import exporter as xes_exporter
    from pm4py.algo.discovery.alpha import alpha_miner
    from pm4py.algo.discovery.heuristics import heuristics_miner
    from pm4py.algo.discovery.inductive import inductive_miner
    from pm4py.algo.conformance.alignments import factory as alignment_factory
    from pm4py.algo.conformance.tokenreplay import factory as token_replay_factory
    from pm4py.statistics.traces.generic.log import case_statistics
    PM4PY_AVAILABLE = True
except ImportError:
    PM4PY_AVAILABLE = False
    logging.warning("PM4Py not available. Install with: pip install pm4py")


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@dataclass
class DiscoveryResult:
    """Result of process discovery."""
    net: Any
    initial_marking: Any
    final_marking: Any
    algorithm: str
    place_count: int
    transition_count: int


@dataclass
class ConformanceResult:
    """Result of conformance checking."""
    fitness: float
    is_fit: bool
    aligned_traces: int
    total_traces: int
    deviations: List[str]


class PM4PyWrapper:
    """Wrapper for PM4Py process mining functions."""

    def __init__(self):
        """Initialize PM4Py wrapper."""
        self.logger = logging.getLogger(f"{__name__}.PM4PyWrapper")
        self.available = PM4PY_AVAILABLE

    def import_xes(self, file_path: str):
        """
        Import XES event log.

        Args:
            file_path: Path to XES file

        Returns:
            Event log object or None if PM4Py unavailable
        """
        if not self.available:
            self.logger.error("PM4Py not available")
            return None

        try:
            log = xes_importer.apply(file_path)
            self.logger.info(f"Imported XES log: {file_path}")
            return log
        except Exception as e:
            self.logger.error(f"Failed to import XES: {e}")
            return None

    def import_csv(self, file_path: str, case_id_key: str = 'case:concept:name',
                   activity_key: str = 'concept:name', timestamp_key: str = 'time:timestamp'):
        """
        Import CSV event log.

        Args:
            file_path: Path to CSV file
            case_id_key: Column name for case ID
            activity_key: Column name for activity
            timestamp_key: Column name for timestamp

        Returns:
            Event log object or None
        """
        if not self.available:
            return None

        try:
            log = csv_importer.apply(file_path,
                                   variant={
                                       'case_id_key': case_id_key,
                                       'activity_key': activity_key,
                                       'timestamp_key': timestamp_key
                                   })
            return log
        except Exception as e:
            self.logger.error(f"Failed to import CSV: {e}")
            return None

    def export_xes(self, log, file_path: str) -> bool:
        """
        Export log to XES format.

        Args:
            log: Event log object
            file_path: Output file path

        Returns:
            True if successful
        """
        if not self.available:
            return False

        try:
            xes_exporter.apply(log, file_path)
            return True
        except Exception as e:
            self.logger.error(f"Failed to export XES: {e}")
            return False

    def discover_alpha_miner(self, log) -> Optional[DiscoveryResult]:
        """
        Discover process using Alpha Miner.

        Args:
            log: Event log

        Returns:
            Discovery result
        """
        if not self.available or log is None:
            return None

        try:
            net, im, fm = alpha_miner.apply(log)

            return DiscoveryResult(
                net=net,
                initial_marking=im,
                final_marking=fm,
                algorithm='alpha_miner',
                place_count=len(net.places),
                transition_count=len(net.transitions)
            )
        except Exception as e:
            self.logger.error(f"Alpha miner failed: {e}")
            return None

    def discover_heuristics_miner(self, log, dependency_threshold: float = 0.5):
        """
        Discover process using Heuristics Miner.

        Args:
            log: Event log
            dependency_threshold: Dependency threshold

        Returns:
            Discovery result
        """
        if not self.available or log is None:
            return None

        try:
            net, im, fm = heuristics_miner.apply(log,
                                                    dep_thres=dependency_threshold)

            return DiscoveryResult(
                net=net,
                initial_marking=im,
                final_marking=fm,
                algorithm='heuristics_miner',
                place_count=len(net.places),
                transition_count=len(net.transitions)
            )
        except Exception as e:
            self.logger.error(f"Heuristics miner failed: {e}")
            return None

    def discover_inductive_miner(self, log, noise_threshold: float = 0.0):
        """
        Discover process using Inductive Miner.

        Args:
            log: Event log
            noise_threshold: Noise threshold

        Returns:
            Discovery result
        """
        if not self.available or log is None:
            return None

        try:
            net, im, fm = inductive_miner.apply(log, noise_threshold=noise_threshold)

            return DiscoveryResult(
                net=net,
                initial_marking=im,
                final_marking=fm,
                algorithm='inductive_miner',
                place_count=len(net.places),
                transition_count=len(net.transitions)
            )
        except Exception as e:
            self.logger.error(f"Inductive miner failed: {e}")
            return None

    def conformance_alignments(self, log, net, im, fm) -> Optional[ConformanceResult]:
        """
        Perform conformance checking using alignments.

        Args:
            log: Event log
            net: Petri net
            im: Initial marking
            fm: Final marking

        Returns:
            Conformance result
        """
        if not self.available:
            return None

        try:
            alignments = alignment_factory.apply_log(log, net, im, fm,
                                                        variant=alignment_factory.TOKEN_BASED)

            # Calculate overall fitness
            fitness = alignments['fitness']
            aligned_traces = len(alignments['alignments'])

            return ConformanceResult(
                fitness=fitness,
                is_fit=fitness >= 0.8,
                aligned_traces=aligned_traces,
                total_traces=len(log),
                deviations=[]
            )
        except Exception as e:
            self.logger.error(f"Alignment failed: {e}")
            return None

    def conformance_token_replay(self, log, net, im, fm) -> Optional[Dict[str, Any]]:
        """
        Perform conformance checking using token replay.

        Args:
            log: Event log
            net: Petri net
            im: Initial marking
            fm: Final marking

        Returns:
            Token replay results
        """
        if not self.available:
            return None

        try:
            replayed_traces = token_replay_factory.apply(log, net, im, fm)

            return {
                'replayed_traces': len(replayed_traces),
                'trace_is_fit': [t['trace_is_fit'] for t in replayed_traces],
                'returned_traces': replayed_traces
            }
        except Exception as e:
            self.logger.error(f"Token replay failed: {e}")
            return None

    def get_case_statistics(self, log) -> Dict[str, Any]:
        """
        Get case statistics from event log.

        Args:
            log: Event log

        Returns:
            Case statistics
        """
        if not self.available:
            return {}

        try:
            case_stats = case_statistics.get_case_statistics(log,
                                                                 parameters={case_statistics.Parameters.ACTIVITY: 'concept:name'})

            return {
                'case_count': len(case_stats),
                'statistics': case_stats
            }
        except Exception as e:
            self.logger.error(f"Failed to get case statistics: {e}")
            return {}

    def export_petri_net(self, net, im, fm, output_path: str, format: str = 'pnml') -> bool:
        """
        Export Petri net to file.

        Args:
            net: Petri net
            im: Initial marking
            fm: Final marking
            output_path: Output file path
            format: Output format ('pnml', 'png')

        Returns:
            True if successful
        """
        if not self.available:
            return False

        try:
            if format == 'pnml':
                from pm4py.objects.petri_net.exporter import exporter as pnml_exporter
                pnml_exporter.apply(net, im, output_path)
                return True
            elif format == 'png':
                from pm4py.visualization.petri_net import visualizer as pn_visualizer
                pn_visualizer.save(net, im, output_path)
                return True
            else:
                self.logger.error(f"Unknown format: {format}")
                return False
        except Exception as e:
            self.logger.error(f"Failed to export Petri net: {e}")
            return False


def get_wrapper() -> PM4PyWrapper:
    """Get PM4Py wrapper instance."""
    return PM4PyWrapper()


# Erlang port communication
def erlang_main():
    """
    Main entry point for Erlang port communication.

    Reads JSON commands from stdin and writes responses to stdout.
    """
    import sys
    import json

    wrapper = PM4PyWrapper()

    for line in sys.stdin:
        try:
            command = json.loads(line.strip())
            result = process_command(wrapper, command)
            print(json.dumps(result))
            sys.stdout.flush()
        except Exception as e:
            print(json.dumps({'error': str(e)}))
            sys.stdout.flush()


def process_command(wrapper: PM4PyWrapper, command: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process a command from Erlang.

    Args:
        wrapper: PM4Py wrapper instance
        command: Command dictionary

    Returns:
        Result dictionary
    """
    cmd_type = command.get('type', '')
    params = command.get('params', {})

    if cmd_type == 'import_xes':
        log = wrapper.import_xes(params.get('file_path'))
        return {'status': 'ok' if log else 'error', 'log_count': len(log) if log else 0}

    elif cmd_type == 'discover':
        algorithm = params.get('algorithm', 'alpha')
        log_path = params.get('xes_path')

        log = wrapper.import_xes(log_path)
        if log is None:
            return {'status': 'error', 'message': 'Failed to import log'}

        if algorithm == 'alpha':
            result = wrapper.discover_alpha_miner(log)
        elif algorithm == 'heuristics':
            result = wrapper.discover_heuristics_miner(log)
        elif algorithm == 'inductive':
            result = wrapper.discover_inductive_miner(log)
        else:
            result = wrapper.discover_alpha_miner(log)

        if result:
            return {
                'status': 'ok',
                'algorithm': result.algorithm,
                'places': result.place_count,
                'transitions': result.transition_count
            }
        else:
            return {'status': 'error', 'message': 'Discovery failed'}

    elif cmd_type == 'conformance':
        log_path = params.get('xes_path')
        log = wrapper.import_xes(log_path)

        if log:
            # Need model from params
            result = wrapper.conformance_alignments(
                log,
                params.get('net'),
                params.get('initial_marking'),
                params.get('final_marking')
            )
            if result:
                return {
                    'status': 'ok',
                    'fitness': result.fitness,
                    'is_fit': result.is_fit
                }

        return {'status': 'error', 'message': 'Conformance check failed'}

    elif cmd_type == 'export':
        log = wrapper.import_xes(params.get('xes_path'))
        if log:
            success = wrapper.export_xes(log, params.get('output_path'))
            return {'status': 'ok' if success else 'error'}
        return {'status': 'error', 'message': 'Failed to import log'}

    else:
        return {'status': 'error', 'message': f'Unknown command: {cmd_type}'}


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--erlang':
        erlang_main()
    else:
        print("PM4Py Wrapper for YAWL-Erlang Integration")
        print("Use --erlang flag for Erlang port mode")
