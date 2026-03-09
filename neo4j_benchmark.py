"""
Neo4j Aura Benchmark for Egregore-Core
=======================================
Simulates real egregore query patterns to help decide:
  - Business Critical vs Professional tier
  - 4GB vs 2GB memory
  - Impact of concurrent connections

Usage:
  pip install neo4j rich
  python neo4j_benchmark.py --uri neo4j+s://xxxxx.databases.neo4j.io --user neo4j --password YOUR_PASSWORD

What it measures:
  1. Data footprint (nodes, relationships, per-org breakdown)
  2. Read latency (simulating /activity, /ask, /quest queries)
  3. Write latency (simulating /handoff, /add, /save)
  4. Concurrent connection handling (simulating multiple users)
  5. Memory pressure indicators
"""

import argparse
import time
import statistics
import json
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from typing import Optional

try:
    from neo4j import GraphDatabase
except ImportError:
    print("Install the driver first:  pip install neo4j")
    sys.exit(1)

try:
    from rich.console import Console
    from rich.table import Table
    from rich.panel import Panel
    from rich import box
    HAS_RICH = True
except ImportError:
    HAS_RICH = False


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class BenchmarkResult:
    name: str
    latencies_ms: list = field(default_factory=list)
    errors: int = 0

    @property
    def count(self): return len(self.latencies_ms)
    @property
    def mean(self): return statistics.mean(self.latencies_ms) if self.latencies_ms else 0
    @property
    def median(self): return statistics.median(self.latencies_ms) if self.latencies_ms else 0
    @property
    def p95(self):
        if not self.latencies_ms: return 0
        s = sorted(self.latencies_ms)
        return s[int(len(s) * 0.95)]
    @property
    def p99(self):
        if not self.latencies_ms: return 0
        s = sorted(self.latencies_ms)
        return s[int(len(s) * 0.99)]
    @property
    def max_ms(self): return max(self.latencies_ms) if self.latencies_ms else 0


# ---------------------------------------------------------------------------
# Queries — mirrors real egregore commands
# ---------------------------------------------------------------------------

# /activity command runs these 6 in parallel
ACTIVITY_QUERIES = {
    "my_projects": """
        MATCH (p:Person {name: $me})-[:INVOLVES]->(proj:Project)
        RETURN proj.name AS project, proj.status AS status
    """,
    "recent_sessions": """
        MATCH (s:Session)-[:BY]->(p:Person {name: $me})
        RETURN s.id AS id, s.summary AS summary, s.date AS date
        ORDER BY s.date DESC LIMIT 5
    """,
    "team_activity_7d": """
        MATCH (s:Session)-[:BY]->(p:Person)
        WHERE s.date >= date() - duration('P7D')
        RETURN p.name AS person, s.summary AS summary, s.date AS date
        ORDER BY s.date DESC LIMIT 5
    """,
    "active_quests": """
        MATCH (q:Quest {status: 'active'})
        OPTIONAL MATCH (q)<-[:PART_OF]-(a:Artifact)
        RETURN q.name AS quest, q.description AS desc, count(a) AS artifacts
    """,
    "pending_questions": """
        MATCH (qs:QuestionSet)-[:ASKED_TO]->(p:Person {name: $me})
        WHERE qs.status = 'pending'
        RETURN qs.id AS id, qs.topic AS topic
        ORDER BY qs.date DESC LIMIT 5
    """,
    "answered_questions": """
        MATCH (qs:QuestionSet)-[:ASKED_BY]->(p:Person {name: $me})
        WHERE qs.status = 'answered'
        RETURN qs.id AS id, qs.topic AS topic
        ORDER BY qs.date DESC LIMIT 5
    """,
}

# /ask context gathering
ASK_CONTEXT_QUERY = """
    MATCH (p:Person {name: $me})
    OPTIONAL MATCH (s:Session)-[:BY]->(p)
    WITH p, s ORDER BY s.date DESC LIMIT 3
    WITH p, collect(s) AS sessions
    OPTIONAL MATCH (a:Artifact)-[:CONTRIBUTED_BY]->(p)
    WITH p, sessions, a ORDER BY a.date DESC LIMIT 5
    WITH p, sessions, collect(a) AS artifacts
    OPTIONAL MATCH (q:Quest {status: 'active'})-[:INVOLVES]->(p)
    RETURN p.name AS person,
           [s IN sessions | s.summary] AS recent_sessions,
           [a IN artifacts | a.title] AS recent_artifacts,
           [q IN collect(q) | q.name] AS active_quests
"""

# /handoff write pattern
HANDOFF_WRITE = """
    MATCH (p:Person {name: $me})
    CREATE (s:Session {
        id: $session_id,
        summary: $summary,
        date: date(),
        org: p.org
    })
    CREATE (s)-[:BY]->(p)
    RETURN s.id AS id
"""

# /add artifact write pattern
ADD_ARTIFACT = """
    MATCH (p:Person {name: $me})
    CREATE (a:Artifact {
        id: $artifact_id,
        title: $title,
        type: $type,
        date: date(),
        org: p.org
    })
    CREATE (a)-[:CONTRIBUTED_BY]->(p)
    RETURN a.id AS id
"""

# Full graph stats
FOOTPRINT_QUERY = """
    CALL {
        MATCH (n) RETURN count(n) AS total_nodes
    }
    CALL {
        MATCH ()-[r]->() RETURN count(r) AS total_rels
    }
    CALL {
        MATCH (n) WITH labels(n) AS lbls, count(*) AS cnt
        UNWIND lbls AS lbl
        RETURN lbl, sum(cnt) AS cnt ORDER BY cnt DESC
    }
    RETURN *
"""

FOOTPRINT_SIMPLE_NODES = "MATCH (n) RETURN count(n) AS total_nodes"
FOOTPRINT_SIMPLE_RELS = "MATCH ()-[r]->() RETURN count(r) AS total_rels"
FOOTPRINT_LABELS = """
    MATCH (n)
    WITH labels(n) AS lbls, n
    UNWIND lbls AS lbl
    RETURN lbl AS label, count(*) AS count
    ORDER BY count DESC
"""
FOOTPRINT_REL_TYPES = """
    MATCH ()-[r]->()
    RETURN type(r) AS rel_type, count(*) AS count
    ORDER BY count DESC
"""
FOOTPRINT_ORGS = """
    MATCH (n)
    WHERE n.org IS NOT NULL
    RETURN n.org AS org, count(*) AS nodes
    ORDER BY nodes DESC
"""

MEMORY_QUERY = """
    CALL dbms.queryJmx('java.lang:type=Memory')
    YIELD name, attributes
    RETURN attributes
"""


# ---------------------------------------------------------------------------
# Benchmark runner
# ---------------------------------------------------------------------------

class EgregoreBenchmark:
    def __init__(self, uri: str, user: str, password: str, iterations: int = 20):
        self.driver = GraphDatabase.driver(uri, auth=(user, password))
        self.iterations = iterations
        self.results: dict[str, BenchmarkResult] = {}

    def close(self):
        self.driver.close()

    # -- helpers --

    def _timed_read(self, query: str, params: dict = None) -> tuple[float, list]:
        """Run a read query, return (elapsed_ms, records)."""
        with self.driver.session() as session:
            start = time.perf_counter()
            result = session.run(query, params or {})
            records = [r.data() for r in result]
            elapsed = (time.perf_counter() - start) * 1000
        return elapsed, records

    def _timed_write(self, query: str, params: dict) -> tuple[float, list]:
        """Run a write query inside a transaction, return (elapsed_ms, records)."""
        def _tx(tx):
            result = tx.run(query, params)
            return [r.data() for r in result]

        with self.driver.session() as session:
            start = time.perf_counter()
            records = session.execute_write(_tx)
            elapsed = (time.perf_counter() - start) * 1000
        return elapsed, records

    def _find_person(self) -> Optional[str]:
        """Find an existing Person node to use in queries."""
        _, records = self._timed_read("MATCH (p:Person) RETURN p.name AS name LIMIT 1")
        return records[0]["name"] if records else None

    # -- phases --

    def phase_footprint(self):
        """Phase 1: Measure current data footprint."""
        print("\n" + "=" * 60)
        print("PHASE 1: DATA FOOTPRINT")
        print("=" * 60)

        _, nodes = self._timed_read(FOOTPRINT_SIMPLE_NODES)
        _, rels = self._timed_read(FOOTPRINT_SIMPLE_RELS)
        _, labels = self._timed_read(FOOTPRINT_LABELS)
        _, rel_types = self._timed_read(FOOTPRINT_REL_TYPES)
        _, orgs = self._timed_read(FOOTPRINT_ORGS)

        total_nodes = nodes[0]["total_nodes"] if nodes else 0
        total_rels = rels[0]["total_rels"] if rels else 0

        print(f"\n  Total nodes:         {total_nodes:,}")
        print(f"  Total relationships: {total_rels:,}")

        print("\n  By label:")
        for row in labels:
            print(f"    {row['label']:20s} {row['count']:>8,}")

        print("\n  By relationship type:")
        for row in rel_types:
            print(f"    {row['rel_type']:20s} {row['count']:>8,}")

        if orgs:
            print("\n  By org:")
            for row in orgs:
                print(f"    {row['org']:20s} {row['nodes']:>8,} nodes")

        # Rough memory estimate: ~500 bytes per node, ~200 bytes per rel
        est_memory_mb = (total_nodes * 500 + total_rels * 200) / (1024 * 1024)
        print(f"\n  Estimated in-memory footprint: ~{est_memory_mb:.1f} MB")
        print(f"  → 1GB instance headroom:       ~{1024 - est_memory_mb:.0f} MB free")
        print(f"  → 2GB instance headroom:       ~{2048 - est_memory_mb:.0f} MB free")
        print(f"  → 4GB instance headroom:       ~{4096 - est_memory_mb:.0f} MB free")

        return total_nodes, total_rels

    def phase_read_latency(self, person_name: str):
        """Phase 2: Read latency — simulating /activity and /ask."""
        print("\n" + "=" * 60)
        print(f"PHASE 2: READ LATENCY ({self.iterations} iterations each)")
        print("=" * 60)

        params = {"me": person_name}

        # Test each /activity query
        for qname, query in ACTIVITY_QUERIES.items():
            result = BenchmarkResult(name=f"/activity → {qname}")
            for _ in range(self.iterations):
                try:
                    elapsed, _ = self._timed_read(query, params)
                    result.latencies_ms.append(elapsed)
                except Exception as e:
                    result.errors += 1
            self.results[qname] = result

        # Test /ask context query
        result = BenchmarkResult(name="/ask → context_gather")
        for _ in range(self.iterations):
            try:
                elapsed, _ = self._timed_read(ASK_CONTEXT_QUERY, params)
                result.latencies_ms.append(elapsed)
            except Exception as e:
                result.errors += 1
        self.results["ask_context"] = result

        # Full /activity simulation (all 6 in parallel, like the real command)
        result = BenchmarkResult(name="/activity → all 6 parallel")
        for _ in range(self.iterations):
            start = time.perf_counter()
            with ThreadPoolExecutor(max_workers=6) as pool:
                futures = []
                for query in ACTIVITY_QUERIES.values():
                    futures.append(pool.submit(self._timed_read, query, params))
                for f in as_completed(futures):
                    try:
                        f.result()
                    except Exception:
                        result.errors += 1
            elapsed = (time.perf_counter() - start) * 1000
            result.latencies_ms.append(elapsed)
        self.results["activity_parallel"] = result

        self._print_latency_table("Read Queries", [
            self.results.get(k) for k in
            list(ACTIVITY_QUERIES.keys()) + ["ask_context", "activity_parallel"]
        ])

    def phase_write_latency(self, person_name: str):
        """Phase 3: Write latency — simulating /handoff and /add."""
        print("\n" + "=" * 60)
        print(f"PHASE 3: WRITE LATENCY ({self.iterations} iterations each)")
        print("=" * 60)

        # /handoff writes
        result_handoff = BenchmarkResult(name="/handoff → create session")
        for i in range(self.iterations):
            params = {
                "me": person_name,
                "session_id": f"bench-session-{time.time_ns()}",
                "summary": f"Benchmark test session {i}",
            }
            try:
                elapsed, _ = self._timed_write(HANDOFF_WRITE, params)
                result_handoff.latencies_ms.append(elapsed)
            except Exception as e:
                result_handoff.errors += 1
        self.results["write_handoff"] = result_handoff

        # /add artifact writes
        result_add = BenchmarkResult(name="/add → create artifact")
        for i in range(self.iterations):
            params = {
                "me": person_name,
                "artifact_id": f"bench-artifact-{time.time_ns()}",
                "title": f"Benchmark artifact {i}",
                "type": "thought",
            }
            try:
                elapsed, _ = self._timed_write(ADD_ARTIFACT, params)
                result_add.latencies_ms.append(elapsed)
            except Exception as e:
                result_add.errors += 1
        self.results["write_add"] = result_add

        self._print_latency_table("Write Queries", [result_handoff, result_add])

    def phase_concurrent(self, person_name: str, max_workers: int = 10):
        """Phase 4: Concurrent connections — simulate multiple users."""
        print("\n" + "=" * 60)
        print(f"PHASE 4: CONCURRENT CONNECTIONS (up to {max_workers} parallel)")
        print("=" * 60)

        params = {"me": person_name}
        query = ACTIVITY_QUERIES["recent_sessions"]

        for n_workers in [1, 3, 5, 10]:
            if n_workers > max_workers:
                break
            result = BenchmarkResult(name=f"{n_workers} concurrent readers")
            errors = 0

            for _ in range(5):  # 5 rounds per concurrency level
                with ThreadPoolExecutor(max_workers=n_workers) as pool:
                    futures = [
                        pool.submit(self._timed_read, query, params)
                        for _ in range(n_workers)
                    ]
                    round_latencies = []
                    for f in as_completed(futures):
                        try:
                            elapsed, _ = f.result()
                            round_latencies.append(elapsed)
                        except Exception:
                            errors += 1
                    if round_latencies:
                        # record the slowest in each round (tail latency)
                        result.latencies_ms.append(max(round_latencies))

            result.errors = errors
            self.results[f"concurrent_{n_workers}"] = result

        self._print_latency_table("Concurrent Reads (worst per round)", [
            self.results.get(f"concurrent_{n}")
            for n in [1, 3, 5, 10] if f"concurrent_{n}" in self.results
        ])

    def phase_cleanup(self, person_name: str):
        """Remove benchmark artifacts from the graph."""
        print("\n  Cleaning up benchmark data...")
        cleanup_q = """
            MATCH (n)
            WHERE n.id STARTS WITH 'bench-session-' OR n.id STARTS WITH 'bench-artifact-'
            DETACH DELETE n
            RETURN count(n) AS deleted
        """
        _, records = self._timed_read(cleanup_q)
        deleted = records[0]["deleted"] if records else 0
        print(f"  Deleted {deleted} benchmark nodes.")

    def phase_memory(self):
        """Phase 5: Try to get memory utilization (may fail on Aura)."""
        print("\n" + "=" * 60)
        print("PHASE 5: MEMORY UTILIZATION")
        print("=" * 60)
        try:
            _, records = self._timed_read(MEMORY_QUERY)
            if records:
                attrs = records[0].get("attributes", {})
                heap = attrs.get("HeapMemoryUsage", {})
                if isinstance(heap, dict):
                    used_mb = heap.get("used", 0) / (1024 * 1024)
                    max_mb = heap.get("max", 0) / (1024 * 1024)
                    print(f"  Heap used:  {used_mb:.0f} MB")
                    print(f"  Heap max:   {max_mb:.0f} MB")
                    print(f"  Utilization: {used_mb/max_mb*100:.1f}%")
                else:
                    print(f"  Raw memory attributes: {json.dumps(attrs, indent=2)[:500]}")
            else:
                print("  No memory data returned.")
        except Exception as e:
            print(f"  Memory JMX query not available on Aura (expected): {type(e).__name__}")
            print("  → Use the Aura Console Metrics tab to check memory utilization.")

    # -- output --

    def _print_latency_table(self, title: str, results: list[BenchmarkResult]):
        if HAS_RICH:
            console = Console()
            table = Table(title=title, box=box.ROUNDED, show_lines=True)
            table.add_column("Query", style="cyan", max_width=35)
            table.add_column("Mean", justify="right")
            table.add_column("Median", justify="right")
            table.add_column("P95", justify="right")
            table.add_column("P99", justify="right")
            table.add_column("Max", justify="right")
            table.add_column("Errors", justify="right")
            for r in results:
                if r is None:
                    continue
                style = "red" if r.mean > 500 else "yellow" if r.mean > 200 else "green"
                table.add_row(
                    r.name,
                    f"[{style}]{r.mean:.0f}ms[/]",
                    f"{r.median:.0f}ms",
                    f"{r.p95:.0f}ms",
                    f"{r.p99:.0f}ms",
                    f"{r.max_ms:.0f}ms",
                    f"[red]{r.errors}[/]" if r.errors else "0",
                )
            console.print(table)
        else:
            print(f"\n  {title}")
            print(f"  {'Query':<35} {'Mean':>8} {'Median':>8} {'P95':>8} {'Max':>8} {'Err':>5}")
            print(f"  {'-'*35} {'-'*8} {'-'*8} {'-'*8} {'-'*8} {'-'*5}")
            for r in results:
                if r is None:
                    continue
                print(f"  {r.name:<35} {r.mean:>7.0f}ms {r.median:>7.0f}ms {r.p95:>7.0f}ms {r.max_ms:>7.0f}ms {r.errors:>5}")

    def print_recommendation(self, total_nodes: int, total_rels: int):
        print("\n" + "=" * 60)
        print("RECOMMENDATION")
        print("=" * 60)

        read_results = [self.results.get(k) for k in ACTIVITY_QUERIES.keys() if k in self.results]
        avg_read = statistics.mean([r.mean for r in read_results if r]) if read_results else 0
        max_p95 = max([r.p95 for r in read_results if r], default=0)

        write_results = [self.results.get(k) for k in ["write_handoff", "write_add"] if k in self.results]
        avg_write = statistics.mean([r.mean for r in write_results if r]) if write_results else 0

        concurrent_10 = self.results.get("concurrent_10")
        concurrent_degradation = ""
        if concurrent_10 and "concurrent_1" in self.results:
            ratio = concurrent_10.mean / self.results["concurrent_1"].mean
            concurrent_degradation = f"{ratio:.1f}x slowdown at 10 concurrent"

        est_mb = (total_nodes * 500 + total_rels * 200) / (1024 * 1024)

        # 50-org projection
        proj_nodes = total_nodes * 50 if total_nodes < 1000 else total_nodes + 49 * 1000
        proj_mb = (proj_nodes * 500 + proj_nodes * 2 * 200) / (1024 * 1024)

        print(f"\n  Current footprint: {total_nodes:,} nodes, {total_rels:,} rels (~{est_mb:.0f} MB)")
        print(f"  50-org projection: ~{proj_nodes:,} nodes (~{proj_mb:.0f} MB)")
        print(f"  Avg read latency:  {avg_read:.0f}ms")
        print(f"  Max P95 read:      {max_p95:.0f}ms")
        print(f"  Avg write latency: {avg_write:.0f}ms")
        if concurrent_degradation:
            print(f"  Concurrency:       {concurrent_degradation}")

        print("\n  SIZING VERDICT:")
        if est_mb < 500:
            print("  ✓ 1GB Professional could work for current data")
        if proj_mb < 1500:
            print("  ✓ 2GB Professional should handle 50-org projection")
        if proj_mb < 3500:
            print("  ✓ 4GB Professional is safe for 50-org scale")
        if proj_mb >= 3500:
            print("  ⚠ Consider 4GB+ — projected data approaches memory limits")

        print("\n  TIER VERDICT:")
        if max_p95 < 500 and (not concurrent_10 or concurrent_10.p95 < 1000):
            print("  ✓ Professional tier is sufficient for current workload")
            print("    (no HA needed at this stage — queries are fast, data is small)")
        else:
            print("  ⚠ Consider keeping Business Critical if latency spikes concern you")

        print("\n  COST COMPARISON:")
        costs = {
            "Current (4GB Business Critical)":  0.80 * 24 * 30,
            "4GB Professional":                 0.09 * 4 * 24 * 30,
            "2GB Professional":                 0.09 * 2 * 24 * 30,
            "1GB Professional":                 0.09 * 1 * 24 * 30,
            "2GB Prof + pause nights/weekends": 0.09 * 2 * 12 * 22,
        }
        for label, cost in costs.items():
            marker = " ← current" if "Current" in label else ""
            print(f"    {label:<40s}  ${cost:>7.2f}/month{marker}")


def main():
    parser = argparse.ArgumentParser(description="Egregore-Core Neo4j Benchmark")
    parser.add_argument("--uri", required=True, help="Neo4j connection URI (neo4j+s://...)")
    parser.add_argument("--user", default="neo4j", help="Neo4j username")
    parser.add_argument("--password", required=True, help="Neo4j password")
    parser.add_argument("--iterations", type=int, default=20, help="Iterations per query (default: 20)")
    parser.add_argument("--max-concurrent", type=int, default=10, help="Max concurrent connections to test")
    parser.add_argument("--skip-writes", action="store_true", help="Skip write benchmarks")
    args = parser.parse_args()

    print("╔══════════════════════════════════════════════════╗")
    print("║   Egregore-Core Neo4j Aura Benchmark            ║")
    print("║   Testing: latency, concurrency, memory fit     ║")
    print("╚══════════════════════════════════════════════════╝")

    bench = EgregoreBenchmark(args.uri, args.user, args.password, args.iterations)

    try:
        # Phase 1: Data footprint
        total_nodes, total_rels = bench.phase_footprint()

        # Find a person to use in queries
        person = bench._find_person()
        if not person:
            print("\n  ⚠ No Person nodes found — cannot run query benchmarks.")
            print("    Run this after at least one person has onboarded.")
            return
        print(f"\n  Using person '{person}' for query benchmarks.")

        # Phase 2: Read latency
        bench.phase_read_latency(person)

        # Phase 3: Write latency
        if not args.skip_writes:
            bench.phase_write_latency(person)
            bench.phase_cleanup(person)
        else:
            print("\n  (write benchmarks skipped)")

        # Phase 4: Concurrent connections
        bench.phase_concurrent(person, args.max_concurrent)

        # Phase 5: Memory
        bench.phase_memory()

        # Recommendation
        bench.print_recommendation(total_nodes, total_rels)

    finally:
        bench.close()


if __name__ == "__main__":
    main()
