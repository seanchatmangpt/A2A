#!/usr/bin/env python3
"""
Generate HTML Report from Benchmark Results
"""

import json
import glob
import os
from datetime import datetime


def generate_html_report():
    """Generate HTML report from JSON results"""

    # Find latest results
    benchmark_files = sorted(glob.glob("/home/user/A2A/tests/performance/benchmark_results_*.json"), reverse=True)
    sla_files = sorted(glob.glob("/home/user/A2A/tests/performance/sla_validation_*.json"), reverse=True)

    if not benchmark_files and not sla_files:
        print("No result files found")
        return

    html = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>A2A Performance Benchmark Report</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background-color: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        h1 {
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }
        h2 {
            color: #34495e;
            margin-top: 30px;
        }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        .metric-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 8px;
            text-align: center;
        }
        .metric-card.success {
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
        }
        .metric-card.warning {
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
        }
        .metric-value {
            font-size: 36px;
            font-weight: bold;
            margin: 10px 0;
        }
        .metric-label {
            font-size: 14px;
            opacity: 0.9;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background-color: #3498db;
            color: white;
        }
        tr:hover {
            background-color: #f5f5f5;
        }
        .pass {
            color: #27ae60;
            font-weight: bold;
        }
        .fail {
            color: #e74c3c;
            font-weight: bold;
        }
        .critical {
            background-color: #e74c3c;
            color: white;
            padding: 2px 6px;
            border-radius: 3px;
            font-size: 11px;
        }
        .timestamp {
            color: #7f8c8d;
            font-style: italic;
        }
        .chart-container {
            margin: 30px 0;
            padding: 20px;
            background-color: #f8f9fa;
            border-radius: 8px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>A2A Protocol - Performance Benchmark Report</h1>
        <p class="timestamp">Generated: {timestamp}</p>
"""

    html += f"<p class='timestamp'>Report generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>"

    # Add benchmark results
    if benchmark_files:
        with open(benchmark_files[0], 'r') as f:
            benchmark_data = json.load(f)

        html += f"""
        <h2>Performance Benchmark Results</h2>
        <div class="summary">
            <div class="metric-card">
                <div class="metric-label">Total Tests</div>
                <div class="metric-value">{benchmark_data['summary']['total_tests']}</div>
            </div>
            <div class="metric-card success">
                <div class="metric-label">Passed SLA</div>
                <div class="metric-value">{benchmark_data['summary']['passed_sla']}</div>
            </div>
            <div class="metric-card warning">
                <div class="metric-label">Failed SLA</div>
                <div class="metric-value">{benchmark_data['summary']['failed_sla']}</div>
            </div>
        </div>

        <h3>Test Results</h3>
        <table>
            <thead>
                <tr>
                    <th>Test Name</th>
                    <th>Requests</th>
                    <th>Success Rate</th>
                    <th>Avg Latency</th>
                    <th>P95 Latency</th>
                    <th>P99 Latency</th>
                    <th>Throughput</th>
                    <th>SLA</th>
                </tr>
            </thead>
            <tbody>
        """

        for result in benchmark_data['results']:
            sla_status = '<span class="pass">PASS</span>' if result['sla_overall_pass'] else '<span class="fail">FAIL</span>'
            success_rate = (result['successful_requests'] / result['total_requests'] * 100) if result['total_requests'] > 0 else 0

            html += f"""
                <tr>
                    <td>{result['test_name']}</td>
                    <td>{result['total_requests']}</td>
                    <td>{success_rate:.2f}%</td>
                    <td>{result['avg_latency']:.2f}ms</td>
                    <td>{result['p95_latency']:.2f}ms</td>
                    <td>{result['p99_latency']:.2f}ms</td>
                    <td>{result['requests_per_second']:.2f} req/s</td>
                    <td>{sla_status}</td>
                </tr>
            """

        html += """
            </tbody>
        </table>
        """

    # Add SLA validation results
    if sla_files:
        with open(sla_files[0], 'r') as f:
            sla_data = json.load(f)

        html += f"""
        <h2>SLA Validation Results</h2>
        <div class="summary">
            <div class="metric-card">
                <div class="metric-label">Total SLAs</div>
                <div class="metric-value">{sla_data['summary']['total_slas']}</div>
            </div>
            <div class="metric-card success">
                <div class="metric-label">Passed</div>
                <div class="metric-value">{sla_data['summary']['passed']}</div>
            </div>
            <div class="metric-card warning">
                <div class="metric-label">Failed</div>
                <div class="metric-value">{sla_data['summary']['failed']}</div>
            </div>
            <div class="metric-card warning">
                <div class="metric-label">Critical Failures</div>
                <div class="metric-value">{sla_data['summary']['critical_failures']}</div>
            </div>
        </div>

        <h3>SLA Validation Details</h3>
        <table>
            <thead>
                <tr>
                    <th>SLA Name</th>
                    <th>Measured Value</th>
                    <th>Threshold</th>
                    <th>Status</th>
                </tr>
            </thead>
            <tbody>
        """

        for result in sla_data['results']:
            sla_status = '<span class="pass">PASS</span>' if result['passed'] else '<span class="fail">FAIL</span>'
            critical = '<span class="critical">CRITICAL</span>' if result.get('details', {}).get('critical') and not result['passed'] else ''

            html += f"""
                <tr>
                    <td>{result['sla_name']} {critical}</td>
                    <td>{result['measured_value']:.2f}</td>
                    <td>{result['threshold']:.2f}</td>
                    <td>{sla_status}</td>
                </tr>
            """

        html += """
            </tbody>
        </table>
        """

    html += """
    </div>
</body>
</html>
"""

    # Save report
    output_file = f"/home/user/A2A/tests/performance/benchmark_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.html"
    with open(output_file, 'w') as f:
        f.write(html)

    print(f"HTML report generated: {output_file}")
    return output_file


if __name__ == "__main__":
    generate_html_report()
