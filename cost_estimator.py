#!/usr/bin/env python3
"""
Enterprise Cost Estimation Tool for Fortune 5 Deployment
Uses Infracost and Terraform to provide detailed cost analysis

Author: A2A Team
Version: 1.0.0
"""

import json
import subprocess
import sys
import os
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from datetime import datetime
import argparse


class InfracostEstimator:
    """Enterprise-grade cost estimation using Infracost"""

    def __init__(self, terraform_dir: str, config_file: Optional[str] = None):
        self.terraform_dir = Path(terraform_dir)
        self.config_file = config_file
        self.infracost_path = "/home/user/.local/bin/infracost"
        self.results = {}

        # Ensure PATH includes infracost
        os.environ['PATH'] = f"/home/user/.local/bin:{os.environ.get('PATH', '')}"

    def check_prerequisites(self) -> bool:
        """Check if all prerequisites are met"""
        print("🔍 Checking prerequisites...")

        # Check Terraform
        try:
            result = subprocess.run(['terraform', '--version'],
                                  capture_output=True, text=True, check=True)
            print(f"✓ Terraform installed: {result.stdout.split()[1]}")
        except (subprocess.CalledProcessError, FileNotFoundError):
            print("✗ Terraform not found. Please install Terraform.")
            return False

        # Check Infracost
        if not Path(self.infracost_path).exists():
            print("✗ Infracost not found. Please install Infracost.")
            return False

        try:
            result = subprocess.run([self.infracost_path, '--version'],
                                  capture_output=True, text=True, check=True)
            print(f"✓ Infracost installed: {result.stdout.strip()}")
        except subprocess.CalledProcessError:
            print("✗ Infracost not working properly.")
            return False

        # Check Terraform directory
        if not self.terraform_dir.exists():
            print(f"✗ Terraform directory not found: {self.terraform_dir}")
            return False

        print(f"✓ Terraform directory found: {self.terraform_dir}")
        return True

    def initialize_terraform(self) -> bool:
        """Initialize Terraform in the specified directory"""
        print(f"\n📦 Initializing Terraform in {self.terraform_dir}...")

        try:
            result = subprocess.run(
                ['terraform', 'init', '-backend=false'],
                cwd=self.terraform_dir,
                capture_output=True,
                text=True,
                timeout=300
            )

            if result.returncode == 0:
                print("✓ Terraform initialized successfully")
                return True
            else:
                print(f"✗ Terraform initialization failed: {result.stderr}")
                return False

        except subprocess.TimeoutExpired:
            print("✗ Terraform initialization timed out")
            return False
        except Exception as e:
            print(f"✗ Error initializing Terraform: {e}")
            return False

    def generate_cost_breakdown(self) -> Optional[Dict]:
        """Generate detailed cost breakdown using Infracost"""
        print("\n💰 Generating cost breakdown with Infracost...")

        try:
            # Run infracost breakdown
            result = subprocess.run(
                [self.infracost_path, 'breakdown',
                 '--path', str(self.terraform_dir),
                 '--format', 'json'],
                capture_output=True,
                text=True,
                timeout=600
            )

            if result.returncode == 0:
                cost_data = json.loads(result.stdout)
                print("✓ Cost breakdown generated successfully")
                return cost_data
            else:
                print(f"⚠ Infracost breakdown warning: {result.stderr}")
                # Try to parse anyway
                if result.stdout:
                    try:
                        return json.loads(result.stdout)
                    except:
                        pass
                return None

        except subprocess.TimeoutExpired:
            print("✗ Infracost breakdown timed out")
            return None
        except json.JSONDecodeError as e:
            print(f"✗ Failed to parse Infracost output: {e}")
            return None
        except Exception as e:
            print(f"✗ Error generating cost breakdown: {e}")
            return None

    def analyze_costs(self, cost_data: Dict) -> Dict:
        """Analyze and categorize costs for Fortune 5 deployment"""
        print("\n📊 Analyzing costs for enterprise deployment...")

        analysis = {
            'total_monthly_cost': 0,
            'total_hourly_cost': 0,
            'by_resource_type': {},
            'by_service': {},
            'high_cost_resources': [],
            'optimization_opportunities': [],
            'compliance_considerations': [],
            'multi_region_costs': {}
        }

        if 'projects' not in cost_data:
            return analysis

        for project in cost_data.get('projects', []):
            breakdown = project.get('breakdown', {})
            resources = breakdown.get('resources', [])

            for resource in resources:
                # Extract cost information
                monthly_cost = float(resource.get('monthlyCost', 0) or 0)
                hourly_cost = float(resource.get('hourlyCost', 0) or 0)
                resource_type = resource.get('resourceType', 'unknown')
                name = resource.get('name', 'unnamed')

                analysis['total_monthly_cost'] += monthly_cost
                analysis['total_hourly_cost'] += hourly_cost

                # Categorize by resource type
                if resource_type not in analysis['by_resource_type']:
                    analysis['by_resource_type'][resource_type] = {
                        'count': 0,
                        'monthly_cost': 0,
                        'resources': []
                    }

                analysis['by_resource_type'][resource_type]['count'] += 1
                analysis['by_resource_type'][resource_type]['monthly_cost'] += monthly_cost
                analysis['by_resource_type'][resource_type]['resources'].append({
                    'name': name,
                    'monthly_cost': monthly_cost
                })

                # Identify high-cost resources (>$1000/month)
                if monthly_cost > 1000:
                    analysis['high_cost_resources'].append({
                        'name': name,
                        'type': resource_type,
                        'monthly_cost': monthly_cost,
                        'annual_cost': monthly_cost * 12
                    })

                # Analyze cost components for optimization
                cost_components = resource.get('costComponents', [])
                for component in cost_components:
                    comp_monthly = float(component.get('monthlyCost', 0) or 0)
                    comp_name = component.get('name', '')

                    # Check for optimization opportunities
                    if 'storage' in comp_name.lower() and comp_monthly > 500:
                        analysis['optimization_opportunities'].append({
                            'resource': name,
                            'type': 'storage',
                            'suggestion': 'Consider using lifecycle policies or cheaper storage classes',
                            'potential_savings': comp_monthly * 0.3  # Estimate 30% savings
                        })

                    if 'compute' in comp_name.lower() and comp_monthly > 1000:
                        analysis['optimization_opportunities'].append({
                            'resource': name,
                            'type': 'compute',
                            'suggestion': 'Consider reserved instances or spot instances',
                            'potential_savings': comp_monthly * 0.4  # Estimate 40% savings
                        })

        # Fortune 5 specific compliance considerations
        analysis['compliance_considerations'] = [
            {
                'area': 'Data Residency',
                'requirement': 'Ensure multi-region deployment complies with data sovereignty laws',
                'cost_impact': 'High - requires regional data duplication'
            },
            {
                'area': 'Disaster Recovery',
                'requirement': 'Maintain hot standby in multiple regions',
                'cost_impact': 'Very High - doubles infrastructure costs'
            },
            {
                'area': 'Security & Compliance',
                'requirement': 'Enhanced security monitoring and audit logging',
                'cost_impact': 'Medium - additional logging and monitoring costs'
            },
            {
                'area': 'High Availability',
                'requirement': '99.99% uptime SLA requirement',
                'cost_impact': 'High - redundancy across availability zones'
            }
        ]

        return analysis

    def calculate_fortune5_projections(self, analysis: Dict) -> Dict:
        """Calculate cost projections for Fortune 5 scale deployment"""
        print("\n📈 Calculating Fortune 5 scale projections...")

        base_monthly = analysis['total_monthly_cost']

        projections = {
            'current_monthly': base_monthly,
            'current_annual': base_monthly * 12,
            'with_disaster_recovery': base_monthly * 2.5,  # DR adds 150% overhead
            'with_multi_region': base_monthly * 3.0,  # Multi-region adds 200%
            'with_compliance': base_monthly * 3.5,  # Full compliance adds 250%
            'enterprise_scale': {
                'small_deployment': base_monthly * 5,  # 5x for small Fortune 5
                'medium_deployment': base_monthly * 15,  # 15x for medium
                'large_deployment': base_monthly * 50,  # 50x for large
                'global_deployment': base_monthly * 100  # 100x for global
            },
            'five_year_projection': {
                'year_1': base_monthly * 12 * 3.5,
                'year_2': base_monthly * 12 * 4.0,  # 14% growth
                'year_3': base_monthly * 12 * 4.6,  # 15% growth
                'year_4': base_monthly * 12 * 5.3,  # 15% growth
                'year_5': base_monthly * 12 * 6.1,  # 15% growth
            }
        }

        # Calculate potential savings from optimization
        total_optimization_savings = sum(
            opp.get('potential_savings', 0)
            for opp in analysis.get('optimization_opportunities', [])
        )

        projections['optimization_savings'] = {
            'monthly': total_optimization_savings,
            'annual': total_optimization_savings * 12,
            'five_year': total_optimization_savings * 12 * 5
        }

        return projections

    def generate_report(self, cost_data: Dict, analysis: Dict, projections: Dict) -> str:
        """Generate comprehensive cost estimation report"""
        print("\n📝 Generating comprehensive report...")

        report_lines = [
            "="*80,
            "FORTUNE 5 CLOUD INFRASTRUCTURE COST ESTIMATION REPORT",
            "="*80,
            f"\nGenerated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            f"Terraform Directory: {self.terraform_dir}",
            "\n" + "="*80,
            "\n1. EXECUTIVE SUMMARY",
            "="*80,
        ]

        # Current costs
        report_lines.extend([
            f"\nCurrent Base Infrastructure:",
            f"  Monthly Cost:  ${analysis['total_monthly_cost']:,.2f}",
            f"  Hourly Cost:   ${analysis['total_hourly_cost']:,.2f}",
            f"  Annual Cost:   ${analysis['total_monthly_cost'] * 12:,.2f}",
        ])

        # Fortune 5 projections
        report_lines.extend([
            f"\nFortune 5 Enterprise Deployment Projections:",
            f"  With Disaster Recovery:   ${projections['with_disaster_recovery']:,.2f}/month",
            f"  With Multi-Region:        ${projections['with_multi_region']:,.2f}/month",
            f"  With Full Compliance:     ${projections['with_compliance']:,.2f}/month",
            f"  Annual (Full Compliance): ${projections['with_compliance'] * 12:,.2f}",
        ])

        # Scale projections
        report_lines.extend([
            f"\n2. ENTERPRISE SCALE SCENARIOS",
            "="*80,
            f"\nSmall Deployment (5x):    ${projections['enterprise_scale']['small_deployment']:,.2f}/month",
            f"Medium Deployment (15x):  ${projections['enterprise_scale']['medium_deployment']:,.2f}/month",
            f"Large Deployment (50x):   ${projections['enterprise_scale']['large_deployment']:,.2f}/month",
            f"Global Deployment (100x): ${projections['enterprise_scale']['global_deployment']:,.2f}/month",
        ])

        # 5-year projection
        report_lines.extend([
            f"\n3. FIVE-YEAR COST PROJECTION",
            "="*80,
        ])

        for year, cost in projections['five_year_projection'].items():
            report_lines.append(f"{year.replace('_', ' ').title()}: ${cost:,.2f}")

        total_5_year = sum(projections['five_year_projection'].values())
        report_lines.append(f"\nTotal 5-Year Cost: ${total_5_year:,.2f}")

        # Cost breakdown by resource type
        report_lines.extend([
            f"\n4. COST BREAKDOWN BY RESOURCE TYPE",
            "="*80,
        ])

        sorted_resources = sorted(
            analysis['by_resource_type'].items(),
            key=lambda x: x[1]['monthly_cost'],
            reverse=True
        )

        for resource_type, data in sorted_resources[:10]:  # Top 10
            report_lines.append(
                f"\n{resource_type}:"
                f"\n  Count: {data['count']}"
                f"\n  Monthly Cost: ${data['monthly_cost']:,.2f}"
                f"\n  Annual Cost: ${data['monthly_cost'] * 12:,.2f}"
            )

        # High-cost resources
        if analysis['high_cost_resources']:
            report_lines.extend([
                f"\n5. HIGH-COST RESOURCES (>$1,000/month)",
                "="*80,
            ])

            for resource in sorted(analysis['high_cost_resources'],
                                 key=lambda x: x['monthly_cost'], reverse=True):
                report_lines.append(
                    f"\n{resource['name']} ({resource['type']})"
                    f"\n  Monthly: ${resource['monthly_cost']:,.2f}"
                    f"\n  Annual:  ${resource['annual_cost']:,.2f}"
                )

        # Optimization opportunities
        if analysis['optimization_opportunities']:
            report_lines.extend([
                f"\n6. COST OPTIMIZATION OPPORTUNITIES",
                "="*80,
            ])

            total_savings = projections['optimization_savings']['monthly']
            report_lines.append(
                f"\nPotential Monthly Savings: ${total_savings:,.2f}"
                f"\nPotential Annual Savings: ${projections['optimization_savings']['annual']:,.2f}"
                f"\nPotential 5-Year Savings: ${projections['optimization_savings']['five_year']:,.2f}"
            )

            for i, opp in enumerate(analysis['optimization_opportunities'][:10], 1):
                report_lines.append(
                    f"\n{i}. {opp['resource']} - {opp['type'].title()}"
                    f"\n   Suggestion: {opp['suggestion']}"
                    f"\n   Potential Savings: ${opp['potential_savings']:,.2f}/month"
                )

        # Compliance considerations
        report_lines.extend([
            f"\n7. COMPLIANCE & REGULATORY CONSIDERATIONS",
            "="*80,
        ])

        for consideration in analysis['compliance_considerations']:
            report_lines.append(
                f"\n{consideration['area']}:"
                f"\n  Requirement: {consideration['requirement']}"
                f"\n  Cost Impact: {consideration['cost_impact']}"
            )

        # Recommendations
        report_lines.extend([
            f"\n8. RECOMMENDATIONS FOR FORTUNE 5 DEPLOYMENT",
            "="*80,
            "\n1. Budget Planning:",
            f"   - Allocate ${projections['with_compliance'] * 12:,.2f} annually for full compliance",
            "   - Include 15% annual growth buffer for scaling",
            "   - Reserve additional 20% for unforeseen requirements",
            "\n2. Cost Optimization:",
            f"   - Implement suggested optimizations for ${projections['optimization_savings']['annual']:,.2f}/year savings",
            "   - Use reserved instances for predictable workloads",
            "   - Implement auto-scaling for variable demand",
            "\n3. Multi-Region Strategy:",
            "   - Deploy active-active across 3+ regions for resilience",
            "   - Use global load balancing for optimal performance",
            "   - Implement data replication with regional compliance",
            "\n4. Disaster Recovery:",
            "   - Maintain hot standby in secondary region",
            "   - Regular DR testing (quarterly minimum)",
            "   - Automated failover capabilities",
            "\n5. Security & Compliance:",
            "   - Enhanced logging and monitoring",
            "   - Regular security audits and penetration testing",
            "   - Compliance certification maintenance (SOC 2, ISO 27001, etc.)",
            "\n" + "="*80,
            "\nEND OF REPORT",
            "="*80,
        ])

        return "\n".join(report_lines)

    def save_results(self, cost_data: Dict, analysis: Dict,
                    projections: Dict, report: str):
        """Save all results to files"""
        print("\n💾 Saving results...")

        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_dir = Path('/home/user/A2A/cost_estimates')
        output_dir.mkdir(exist_ok=True)

        # Save raw cost data
        cost_file = output_dir / f'infracost_data_{timestamp}.json'
        with open(cost_file, 'w') as f:
            json.dump(cost_data, f, indent=2)
        print(f"✓ Saved raw cost data: {cost_file}")

        # Save analysis
        analysis_file = output_dir / f'cost_analysis_{timestamp}.json'
        combined = {
            'analysis': analysis,
            'projections': projections,
            'timestamp': timestamp
        }
        with open(analysis_file, 'w') as f:
            json.dump(combined, f, indent=2)
        print(f"✓ Saved cost analysis: {analysis_file}")

        # Save report
        report_file = output_dir / f'cost_report_{timestamp}.txt'
        with open(report_file, 'w') as f:
            f.write(report)
        print(f"✓ Saved cost report: {report_file}")

        # Save latest (for easy access)
        latest_report = output_dir / 'latest_cost_report.txt'
        with open(latest_report, 'w') as f:
            f.write(report)
        print(f"✓ Saved latest report: {latest_report}")

        return {
            'cost_file': str(cost_file),
            'analysis_file': str(analysis_file),
            'report_file': str(report_file)
        }

    def run(self) -> bool:
        """Run the complete cost estimation process"""
        print("\n" + "="*80)
        print("FORTUNE 5 CLOUD COST ESTIMATION TOOL")
        print("="*80)

        # Check prerequisites
        if not self.check_prerequisites():
            return False

        # Initialize Terraform
        if not self.initialize_terraform():
            print("\n⚠ Continuing without Terraform initialization...")

        # Generate cost breakdown
        cost_data = self.generate_cost_breakdown()
        if not cost_data:
            print("\n✗ Failed to generate cost breakdown")
            return False

        # Analyze costs
        analysis = self.analyze_costs(cost_data)

        # Calculate projections
        projections = self.calculate_fortune5_projections(analysis)

        # Generate report
        report = self.generate_report(cost_data, analysis, projections)

        # Display report
        print("\n" + report)

        # Save results
        files = self.save_results(cost_data, analysis, projections, report)

        print("\n" + "="*80)
        print("✓ COST ESTIMATION COMPLETE")
        print("="*80)
        print(f"\nReport saved to: {files['report_file']}")
        print(f"Analysis saved to: {files['analysis_file']}")
        print(f"Raw data saved to: {files['cost_file']}")

        return True


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Enterprise Cost Estimation Tool for Fortune 5 Deployment'
    )
    parser.add_argument(
        '--terraform-dir',
        default='/home/user/A2A/terraform',
        help='Path to Terraform configuration directory'
    )
    parser.add_argument(
        '--config',
        help='Path to configuration file (optional)'
    )

    args = parser.parse_args()

    estimator = InfracostEstimator(args.terraform_dir, args.config)
    success = estimator.run()

    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
