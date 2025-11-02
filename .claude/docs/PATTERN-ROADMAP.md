# Pattern Stack - Pattern Implementation Roadmap

## Current Status (as of 2024-12-27)

### ✅ Completed Patterns (4/7)
1. **EventPattern** (formerly TransactionalPattern) - State machines & transitions
2. **CatalogPattern** - Inventory management with stock tracking
3. **CategoricalPattern** - Tags/classification (needs simplification)
4. **RelationalPattern** - Many-to-many associations

### 🚧 In Progress
- **PR #71**: CatalogPattern enhancements (ready to merge)
- **BE-44**: Simplify CategoricalPattern (remove hierarchy)

### ⏳ Not Implemented (3/7)
5. **HierarchicalPattern** - Tree structures with parent-child relationships
6. **ActorPattern** - Users, organizations, systems representation
7. **TemporalPattern** - Time-bound entities with scheduling

## Immediate Next Steps (Priority Order)

### 1. 🔥 **CRITICAL: BE-44 - Simplify CategoricalPattern**
**Why First**: Currently blocking proper pattern composition because hierarchy is mixed in
**Branch**: `feat/be-44-simplify-categorical-pattern`
**Tasks**:
- Remove `parent_id` field and foreign key
- Remove all hierarchy methods (`get_ancestors()`, `get_descendants()`, etc.)
- Simplify from ~380 lines to ~100 lines
- Update tests to remove hierarchy tests
**Enables**: Clean separation of concerns, proper HierarchicalPattern implementation

### 2. 🔥 **CRITICAL: Implement HierarchicalPattern**
**Why Second**: Many patterns need hierarchy (categories, organizations, comments)
**Branch**: `feat/hierarchical-pattern`
**Tasks**:
- Self-referencing parent_id foreign key
- Materialized path for efficient queries
- Methods: `get_ancestors()`, `get_descendants()`, `get_siblings()`
- Depth tracking and sibling ordering
**Use Cases**: Org charts, file systems, category trees, comment threads

### 3. **HIGH: BE-38 - EventPattern Business Events**
**Why Third**: Completes EventPattern functionality
**Branch**: `feat/be-38-event-business-emission`
**Tasks**:
- Add business event emission alongside state transitions
- Implement event query methods
- Integration with EventBus for real-time
- Add comprehensive timeline methods

### 4. **MEDIUM: Implement ActorPattern**
**Branch**: `feat/actor-pattern`
**Tasks**:
- User/org/system representation
- Profile data and contact info
- Activity tracking
- Integration with auth atoms (not duplication)

### 5. **MEDIUM: Implement TemporalPattern**
**Branch**: `feat/temporal-pattern`
**Tasks**:
- Time boundaries with timezone support
- Recurrence patterns (RRULE)
- Duration and buffers
- Overlap detection

## Pattern Composition Examples Needed

Once HierarchicalPattern exists, we can demonstrate:
```python
# Hierarchical categories
class ProductCategory(CategoricalPattern, HierarchicalPattern):
    """Categories with subcategories"""
    pass

# Task management
class Task(EventPattern, HierarchicalPattern, TemporalPattern):
    """Tasks with subtasks, states, and deadlines"""
    pass

# Organization structure
class Department(ActorPattern, HierarchicalPattern):
    """Departments with sub-departments"""
    pass
```

## Architecture Principles to Maintain

1. **Single Responsibility**: Each pattern does ONE thing well
2. **Composability**: Patterns mix through multiple inheritance
3. **No Base Class Inheritance**: EventPattern is composable, not a base
4. **Clean Boundaries**: No overlap between pattern functionalities

## Success Metrics

- [ ] All 7 patterns implemented
- [ ] Each pattern has >90% test coverage
- [ ] Pattern composition examples for common use cases
- [ ] Documentation for each pattern
- [ ] Performance benchmarks pass
- [ ] No circular dependencies

## Timeline Estimate

**Week 1 (Current)**:
- Day 1: Merge CatalogPattern PR, start BE-44
- Day 2-3: Complete BE-44 (CategoricalPattern simplification)
- Day 4-5: Implement HierarchicalPattern

**Week 2**:
- Day 1-2: Test HierarchicalPattern compositions
- Day 3-4: BE-38 (EventPattern business events)
- Day 5: Documentation and examples

**Week 3**:
- Day 1-3: ActorPattern implementation
- Day 4-5: TemporalPattern implementation

**Week 4**:
- Pattern composition cookbook
- Performance optimization
- Final documentation

## Notes

- CatalogPattern naming is correct (industry standard for product catalogs)
- EventPattern is a business pattern, not a technical base class
- BasePattern provides technical foundation (not one of the 7)
- Focus on composition over inheritance
