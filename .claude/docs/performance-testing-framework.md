# Pattern Stack Performance Testing Framework

## Overview

A comprehensive performance regression testing framework for Pattern Stack that provides reproducible, environment-aware performance testing across different deployment targets.

## Core Architecture

### 1. Environment Profiles

Predefined hardware profiles that match common deployment environments:

```python
# pattern_stack/testing/performance/profiles.py
from dataclasses import dataclass
from enum import Enum

class EnvironmentProfile(Enum):
    """Predefined environment profiles matching common deployments"""
    # GitHub Actions standard runner
    CI_STANDARD = "ci-standard"  # 2 vCPU, 7GB RAM

    # AWS Instance equivalents
    AWS_T2_MICRO = "aws-t2-micro"  # 1 vCPU, 1GB RAM
    AWS_T3_SMALL = "aws-t3-small"  # 2 vCPU, 2GB RAM
    AWS_T3_MEDIUM = "aws-t3-medium"  # 2 vCPU, 4GB RAM

    # GCP equivalents
    GCP_E2_MICRO = "gcp-e2-micro"  # 0.25-2 vCPU, 1GB RAM
    GCP_E2_SMALL = "gcp-e2-small"  # 0.5-2 vCPU, 2GB RAM

    # Container orchestration
    K8S_SMALL_POD = "k8s-small"  # 0.5 CPU, 512MB RAM
    K8S_MEDIUM_POD = "k8s-medium"  # 1 CPU, 2GB RAM

@dataclass
class PerformanceProfile:
    """Hardware constraints for performance testing"""
    cpu_cores: float
    memory_gb: float
    disk_iops: int = 3000
    network_mbps: int = 1000
```

### 2. Docker-Based Test Environments

Containerized environments with resource constraints matching target deployments:

```yaml
# docker/performance-profiles.yml
version: '3.8'

x-test-defaults: &test-defaults
  build:
    context: ..
    dockerfile: docker/performance.dockerfile
  environment:
    - PATTERN_STACK_PERF_PROFILE=${PROFILE}
  volumes:
    - ../pattern_stack:/app/pattern_stack
    - ../tests:/app/tests
    - perf-results:/app/.performance

services:
  ci-standard:
    <<: *test-defaults
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 7G
        reservations:
          cpus: '2.0'
          memory: 6G

  aws-t2-micro:
    <<: *test-defaults
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 1G

  aws-t3-medium:
    <<: *test-defaults
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G
```

### 3. Baseline Management System

Track and compare performance metrics over time:

```python
# pattern_stack/testing/performance/baseline.py
import json
from pathlib import Path
from typing import Dict, Optional
import statistics

class PerformanceBaseline:
    """Manages performance baselines for regression testing"""

    def __init__(self, profile: str, baseline_dir: Path = Path(".performance")):
        self.profile = profile
        self.baseline_file = baseline_dir / f"baseline_{profile}.json"
        self.current_run = {}
        self.baseline = self._load_baseline()

    def _load_baseline(self) -> Dict:
        """Load existing baseline or return empty dict"""
        if self.baseline_file.exists():
            return json.loads(self.baseline_file.read_text())
        return {}

    def record(self, operation: str, duration: float):
        """Record a performance measurement"""
        if operation not in self.current_run:
            self.current_run[operation] = []
        self.current_run[operation].append(duration)

    def check_regression(self, operation: str, threshold: float = 1.5) -> bool:
        """Check if current performance regressed vs baseline"""
        if operation not in self.baseline:
            return False  # No baseline to compare

        baseline_p95 = self.baseline[operation]["p95"]
        current_p95 = self._calculate_percentile(
            self.current_run.get(operation, []), 95
        )

        return current_p95 > baseline_p95 * threshold

    def establish_baseline(self, runs: int = 10):
        """Run operations multiple times to establish baseline"""
        # Implementation for baseline establishment
        pass

    def save_baseline(self):
        """Save current measurements as new baseline"""
        baseline_data = {}
        for operation, measurements in self.current_run.items():
            baseline_data[operation] = {
                "p50": self._calculate_percentile(measurements, 50),
                "p95": self._calculate_percentile(measurements, 95),
                "p99": self._calculate_percentile(measurements, 99),
                "mean": statistics.mean(measurements),
                "stdev": statistics.stdev(measurements) if len(measurements) > 1 else 0,
                "samples": len(measurements)
            }
        self.baseline_file.parent.mkdir(exist_ok=True)
        self.baseline_file.write_text(json.dumps(baseline_data, indent=2))
```

### 4. Pytest Integration

Seamless integration with existing test suite:

```python
# pattern_stack/testing/performance/fixtures.py
import os
import pytest
from typing import Generator

@pytest.fixture(scope="session")
def performance_profile() -> str:
    """Get the current performance profile from environment"""
    return os.getenv("PATTERN_STACK_PERF_PROFILE", "ci-standard")

@pytest.fixture
def perf_tracker(performance_profile: str) -> Generator[PerformanceBaseline, None, None]:
    """Provide performance tracking for tests"""
    tracker = PerformanceBaseline(performance_profile)
    yield tracker

    # After test, check for regressions
    for operation, measurements in tracker.current_run.items():
        if tracker.check_regression(operation):
            # In CI, this could fail the build
            # In baseline mode, this updates the baseline
            if os.getenv("UPDATE_BASELINE") != "true":
                pytest.fail(f"Performance regression detected in {operation}")

# Usage in tests
async def test_token_validation(db: AsyncSession, perf_tracker: PerformanceBaseline):
    service = AuthService()

    start = time.time()
    result = await service.validate_token(db, token)
    duration = time.time() - start

    perf_tracker.record("auth.token_validation", duration)
    assert result is not None
```

### 5. CLI Commands

Command-line interface for performance testing:

```python
# pattern_stack/cli/performance.py
import click

@click.group()
def performance():
    """Performance testing commands"""
    pass

@performance.command()
@click.option('--profile', type=click.Choice(['ci-standard', 'aws-t2-micro', ...]))
@click.option('--runs', default=10, help='Number of runs for baseline')
def establish_baseline(profile: str, runs: int):
    """Establish performance baseline for the given profile"""
    click.echo(f"Establishing baseline for {profile} with {runs} runs...")
    # Run performance tests in Docker with specified profile
    # Store results in .performance/baseline_{profile}.json

@performance.command()
@click.option('--profile', type=click.Choice(['ci-standard', 'aws-t2-micro', ...]))
@click.option('--compare', is_flag=True, help='Compare against baseline')
def test(profile: str, compare: bool):
    """Run performance tests for the given profile"""
    # docker-compose run --rm {profile} pytest -m performance

@performance.command()
@click.option('--from-profile', required=True)
@click.option('--to-profile', required=True)
def compare_profiles(from_profile: str, to_profile: str):
    """Compare performance between two profiles"""
    # Load baselines and generate comparison report
```

## Usage Guide

### For Framework Users

#### 1. Initial Setup

```bash
# Choose the profile matching your deployment target
pattern-stack performance establish-baseline --profile aws-t3-medium --runs 20

# This creates .performance/baseline_aws-t3-medium.json
```

#### 2. Local Development

```bash
# Run tests in containerized environment matching CI
pattern-stack performance test --profile ci-standard --compare

# Update baseline after intentional performance improvements
PATTERN_STACK_UPDATE_BASELINE=true pattern-stack performance test --profile ci-standard
```

#### 3. CI/CD Integration

```yaml
# .github/workflows/performance.yml
name: Performance Regression Tests

on:
  pull_request:
    paths:
      - 'pattern_stack/**'
      - 'tests/**'

jobs:
  performance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Download baseline
        uses: actions/cache@v3
        with:
          path: .performance
          key: perf-baseline-${{ hashFiles('pattern_stack/**') }}
          restore-keys: |
            perf-baseline-

      - name: Run performance tests
        run: |
          docker-compose -f docker/performance-profiles.yml \
            run --rm ci-standard \
            pytest -m performance --perf-compare

      - name: Upload results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: performance-results
          path: .performance/
```

### Custom Profiles

Define profiles for your specific deployment environment:

```python
# myproject/performance_config.py
from pattern_stack.testing.performance import register_profile

register_profile(
    name="my-production",
    cpu_cores=4,
    memory_gb=16,
    disk_iops=10000,
    network_mbps=10000
)
```

### Configuration

#### Regression Thresholds

Configure acceptable regression per operation:

```yaml
# .performance/config.yml
profiles:
  ci-standard:
    thresholds:
      auth.token_validation: 1.2  # Allow 20% regression
      auth.token_creation: 1.5    # Allow 50% regression
      database.query: 2.0          # Allow 100% regression

  aws-t3-medium:
    thresholds:
      auth.token_validation: 1.1  # Stricter for production-like env
      auth.token_creation: 1.2
      database.query: 1.5
```

#### Statistical Configuration

```yaml
# .performance/config.yml
statistics:
  percentile_for_comparison: 95  # Use P95 for regression detection
  minimum_samples: 5              # Minimum runs before comparison
  warmup_runs: 2                  # Discard first N runs
```

## Benefits

1. **Reproducible**: Consistent containerized environments across all testing locations
2. **Flexible**: Multiple profiles for different deployment targets
3. **Trackable**: Performance baselines are versioned with code
4. **Actionable**: Clear regression detection with configurable thresholds
5. **Framework-Ready**: Users can define custom profiles for their infrastructure
6. **Statistical Rigor**: Uses percentiles and multiple runs for reliable measurements
7. **CI-Friendly**: Designed for automated regression detection

## Implementation Roadmap

### Phase 1: Core Framework
- [ ] Environment profile definitions
- [ ] Docker compose configurations
- [ ] Baseline management system
- [ ] Basic pytest fixtures

### Phase 2: CLI and Tooling
- [ ] CLI commands for baseline management
- [ ] Performance comparison reports
- [ ] Profile migration tools
- [ ] Visualization dashboard

### Phase 3: Advanced Features
- [ ] Multi-dimensional performance tracking (CPU, memory, I/O)
- [ ] Automatic profile recommendation based on cloud provider
- [ ] Performance prediction models
- [ ] Cost-performance optimization suggestions

## Questions to Consider

1. **Profile Granularity**: Should we include network latency simulation?
2. **Baseline Storage**: Should baselines be in git or external storage?
3. **Warm-up Strategy**: How many warm-up runs before measurement?
4. **Statistical Methods**: P95 vs P99 vs mean for comparison?
5. **Failure Modes**: Hard fail vs warning on regression?
6. **Multi-Region**: How to handle geographic distribution testing?
7. **Database Variations**: PostgreSQL vs MySQL performance profiles?
8. **Caching Effects**: How to handle cold vs warm cache scenarios?

## Alternative Approaches Considered

### 1. Cloud-Native Testing
- Use actual cloud instances for testing
- Pros: Most accurate
- Cons: Cost, complexity, slower feedback

### 2. Synthetic Benchmarks
- Use tools like sysbench to characterize environments
- Pros: Standardized measurements
- Cons: May not reflect actual application behavior

### 3. Production Sampling
- Sample performance from production traffic
- Pros: Real-world data
- Cons: Requires production deployment, privacy concerns

### 4. Chaos Engineering Integration
- Combine with tools like Chaos Monkey
- Pros: Tests degraded performance
- Cons: Complexity, may be overkill for many users

## Next Steps

1. Validate the approach with specific use cases
2. Determine which profiles to include by default
3. Design the baseline file format and storage strategy
4. Create proof-of-concept for Docker resource constraints
5. Test statistical methods for regression detection
