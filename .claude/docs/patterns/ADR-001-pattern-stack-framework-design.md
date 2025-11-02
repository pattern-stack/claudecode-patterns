# ADR-001: Pattern Stack Framework Design Process

**Date**: 2025-01-11
**Status**: Accepted
**Authors**: Dug McFarlane (with AI assistance)
**Deciders**: Dug McFarlane

## Context

Pattern Stack needed to evolve from an internal application architecture into a reusable Python framework. This ADR documents the design process and key decisions made through iterative AI-assisted development.

## Design Process Timeline

### Phase 1: Initial Exploration
**Starting Point**: "I want Pattern Stack to be an importable framework"

**Key Questions Raised**:
1. How much should the framework provide vs what users build?
2. Should we provide full vertical slices or just services?
3. How do we handle the complexity of models, schemas, services, repositories?

**AI Collaboration Method**:
- Started with open-ended exploration
- AI provided three architecture options
- Iterated through pros/cons of each approach

### Phase 2: Pattern Discovery
**Breakthrough**: Identified 7 core patterns that cover 90% of business applications

**Patterns Identified** (through analyzing real-world applications):
1. **TransactionalPattern** → **EventPattern** (renamed after discussion)
2. **CatalogPattern** - Inventory/resource items
3. **ActorPattern** - Entities that perform actions
4. **TemporalPattern** - Time-bound entities
5. **HierarchicalPattern** - Tree structures
6. **CategoricalPattern** - Classification/tagging (added after review)
7. **RelationalPattern** - Entity relationships

**Design Method**:
- Analyzed common CRM/business app entities
- Grouped by behavior, not domain
- Validated against multiple industries (e-commerce, task management, analytics)
- Added marketplace examples (AirBnb) for validation

### Phase 3: Progressive Enhancement Design
**Innovation**: Three-stage development approach

```
Magic Mode → Enhanced Magic → Explicit Mode
(Prototype)   (Production)     (Scale)
```

**Key Insights**:
- Users should start simple and add complexity without rewriting
- Framework provides "Rails magic" with Python idioms
- Every stage maintains full framework benefits

**Design Refinement Process**:
1. Initial concept: Decorators in main.py
2. Challenge: "This doesn't feel right - where do these classes come from?"
3. Solution: Auto-discovery with base class inheritance
4. Further refinement: Full vertical slices, not just services

### Phase 4: Configuration Philosophy
**Evolution of Config Approach**:

1. **First thought**: YAML configuration files
2. **Realization**: "YAML makes sense for deployments, not for defining core structure"
3. **Second thought**: Module-level `__init__.py` configuration
4. **Final decision**: Inner `Pattern` class (like Django's Meta)

**Key Quote**:
> "A misplaced space in a YAML shouldn't break your domain model!"

**Final Configuration Design**:
```python
class Order(EventPattern):
    class Pattern:  # Not PatternMeta - this is PatternStack!
        reference_prefix = "ORD"
        reference_reset = "yearly"
```

## Key Architectural Decisions

### Decision 1: Full Vertical Slices
**Options Considered**:
- Just service classes
- Service + Repository
- Full vertical (Model + Schema + Service)

**Decision**: Full vertical slices with base classes for each layer

**Rationale**:
- Services alone don't provide enough value
- Full slices enable true rapid development
- Base classes eliminate boilerplate while maintaining flexibility

### Decision 2: Multi-Pattern Inheritance
**Challenge**: Many entities exhibit multiple patterns (e.g., Task = Event + Hierarchical + Temporal)

**Decision**: Support multiple pattern inheritance with property mapping

**Implementation**:
```python
class Task(EventPattern, HierarchicalPattern, TemporalPattern):
    # Gets capabilities from all three patterns
```

### Decision 3: Reference Numbers
**Discussion Points**:
- UUID vs human-friendly IDs
- Global vs per-entity sequences
- Immutability requirements

**Decision**:
- Both UUID (primary) and reference numbers (display)
- Per-entity sequences (Order #1, Task #1)
- Immutable once assigned
- Configurable format via Pattern class

### Decision 4: State Machine Abstraction
**Challenge**: Generic enough for all uses, specific enough to be useful

**Options**:
1. Hard-coded states (too restrictive)
2. Completely generic STATE_1, STATE_2 (too abstract)
3. Semantic generic states with mapping

**Decision**: Semantic generic states with domain mapping
```python
CREATED → PROCESSING → SUSPENDED → FINALIZING → CLOSED
# Maps to domain-specific: draft → in_progress → blocked → review → done
```

### Decision 5: No Repository Pattern (Initially)
**Reasoning**:
- Keep services simple (CRUD + business logic)
- Build reporting layer separately later
- Avoid premature abstraction

## Implementation Roadmap

### Phase 1: Core Framework (4 weeks)
- Week 1: Framework foundation (BE-10 to BE-12)
- Week 2: Auto-generation systems (BE-13, BE-14)
- Week 3: Built-in domains (BE-15, BE-16)
- Week 4: Developer tools (BE-17, BE-18)

### Phase 2: Progressive Enhancement (2 weeks)
- Magic mode implementation (BE-19 to BE-21)
- Multi-pattern support (BE-22, BE-23)

### Phase 3: Enterprise Features (2 weeks)
- Advanced patterns (BE-24, BE-25)
- Integration capabilities (BE-26, BE-27)

## Lessons Learned from Design Process

### 1. Iterative Refinement Works
- Started with vague concept
- Through discussion, identified concrete patterns
- Each challenge led to better solutions

### 2. Real Examples Drive Design
- Abstract patterns became clear with real entities
- AirBnb example validated marketplace applications
- Task management validated multi-pattern approach

### 3. Configuration is Architecture
- Config approach shapes how developers think
- Code-as-config (Pattern class) better than YAML for core structure
- Explicit with escape hatches is the sweet spot

### 4. Naming Matters
- "TransactionalPattern" → "EventPattern" (better mental model)
- "PatternMeta" → "Pattern" (brand reinforcement)
- Reference to "magic" helps set expectations

## Design Artifacts Created

1. **pattern-stack-abstraction-analysis.md** - 7 core patterns analysis
2. **pattern-stack-framework-architecture-v2.md** - Complete architecture
3. **pattern-stack-progressive-enhancement.md** - Three-stage approach
4. **pattern-stack-multi-pattern-examples.md** - Pattern composition
5. **pattern-stack-roadmap.md** - Implementation plan with tickets

## Success Metrics for Design

✅ **Clear value proposition**: Start simple, scale without rewriting
✅ **Concrete patterns**: 7 patterns cover most business needs
✅ **Implementation path**: 27 tickets (BE-10 to BE-27) defined
✅ **Validation**: Patterns tested against multiple domains
✅ **Flexibility**: Multi-pattern support for complex entities

## Decision Outcome

The framework design is approved for implementation with:
- 7 core patterns as the foundation
- Progressive enhancement approach (Magic → Enhanced → Explicit)
- Inner `Pattern` class for configuration
- Full vertical slice base classes
- 4-week initial implementation timeline

## AI Collaboration Reflection

### What Worked Well

1. **Exploratory Discussion**: Starting with "what if" questions led to concrete patterns
2. **Challenge-Response**: Questioning decisions ("this doesn't feel right") improved design
3. **Real-World Validation**: Testing patterns against actual applications
4. **Iterative Refinement**: Each pass made the design clearer and more practical

### Design Process Pattern

```
Vague Idea → Exploration → Options → Challenge →
Refinement → Validation → Documentation → Tickets
```

### Key Success Factors

1. **Domain Expertise**: Understanding of CRM/business applications
2. **Technical Depth**: Knowledge of frameworks (Rails, Django) for comparison
3. **Willingness to Iterate**: Not accepting first solution
4. **Concrete Examples**: Using real entities to validate abstractions
5. **Clear Documentation**: Recording decisions as we go

## Next Steps

1. Review this ADR with CTO
2. Begin implementation with BE-10 (PatternStack Core)
3. Build proof of concept with one pattern
4. Validate with real application
5. Iterate based on usage

---

## Appendix: Key Design Conversations

### On Configuration Philosophy
> **Human**: "I work in analytics/data engineering so my mind is wired to think about .yml as config first. but that doesn't make sense in an application that you're building and deploying as a product"

> **Decision**: Configuration as code via inner `Pattern` class

### On Naming
> **Human**: "Pattern Stack, baby!"

> **Decision**: Use "Pattern" not "PatternMeta" for brand consistency

### On Pattern Naming
> **Human**: "The word choice 'Transactional' seems to have influenced plans a bit more than intended - this may be more of an 'EventPattern'"

> **Decision**: Renamed to EventPattern for clarity

### On Reference Numbers
> **Human**: "I think they should be [immutable]. Is there a reason to not?"

> **Decision**: Reference numbers are immutable for audit trail integrity
