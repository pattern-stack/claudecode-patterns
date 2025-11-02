# Pattern Stack: Multi-Pattern Examples

## Overview

Entities in Pattern Stack can inherit from multiple patterns when they exhibit multiple behaviors. This document shows common combinations and best practices.

## Common Multi-Pattern Combinations

### 1. Category with Subcategories
**Patterns: Categorical + Hierarchical**

```python
class Category(CategoricalPattern, HierarchicalPattern):
    """
    Category that can have subcategories.
    - CategoricalPattern: Classification behavior, display properties
    - HierarchicalPattern: Parent-child relationships, tree traversal
    """

    fields = [
        Field("name", str),           # "Electronics"
        Field("slug", str),            # "electronics"
        Field("color", str),           # "#0066CC"
        Field("icon", str),            # "laptop-icon"
        Field("is_active", bool),      # Can items be assigned?
        Field("tax_rate", Decimal),    # Category-specific tax
    ]

    # Usage:
    electronics = Category(name="Electronics")
    computers = Category(name="Computers", parent_id=electronics.id)
    laptops = Category(name="Laptops", parent_id=computers.id)

    # Both pattern methods available:
    laptops.path  # "/Electronics/Computers/Laptops" (Hierarchical)
    laptops.usage_count  # 1523 products use this (Categorical)
    await laptops.get_ancestors()  # [Computers, Electronics] (Hierarchical)
    await laptops.get_tagged_items()  # Products in this category (Categorical)
```

### 2. Employee with Reporting Structure
**Patterns: Actor + Hierarchical**

```python
class Employee(ActorPattern, HierarchicalPattern):
    """
    Employee with identity/permissions and reporting structure.
    """

    fields = [
        Field("email", str),           # Actor identity
        Field("department", str),
        Field("title", str),
        Field("salary", Decimal),
    ]

    # Manager relationship is the hierarchical parent
    @property
    def parent_id(self):
        return self.manager_id

    # Combined capabilities:
    async def can_approve_expense(self, amount: Decimal):
        # Actor: Check permission
        if not await self.has_permission("approve_expense"):
            return False

        # Hierarchical: Check approval limits up the chain
        if amount > self.approval_limit:
            manager = await self.get_parent()
            return await manager.can_approve_expense(amount)

        return True

    async def get_team_budget(self):
        # Get all reports recursively
        team = await self.get_descendants()
        return sum(e.salary for e in team) + self.salary
```

### 3. Task with Subtasks and Deadlines
**Patterns: Transactional + Hierarchical + Temporal**

```python
class Task(TransactionalPattern, HierarchicalPattern, TemporalPattern):
    """
    Task with state machine, subtasks, and scheduling.
    """

    fields = [
        Field("title", str),
        Field("description", str),
        Field("assignee_id", UUID),
        Field("priority", int),
        Field("estimated_hours", float),
    ]

    # State machine from Transactional
    state_machine = {
        "todo": ["in_progress", "cancelled"],
        "in_progress": ["blocked", "review", "done"],
        "blocked": ["in_progress", "cancelled"],
        "review": ["in_progress", "done"],
        "done": ["archived"],
    }

    # Complex business logic using all patterns:
    async def start_work(self):
        """Start work on task - checks multiple constraints."""

        # Temporal: Check if scheduled to start
        if self.start_time > datetime.now():
            raise ValueError("Task not scheduled to start yet")

        # Hierarchical: Check parent task is started
        if self.parent_id:
            parent = await self.get_parent()
            if parent.state == "todo":
                raise ValueError("Parent task must be started first")

        # Transactional: Transition state
        await self.transition_state("in_progress")

        # Temporal: Check for conflicts
        conflicts = await self.check_schedule_conflicts()
        if conflicts:
            await self.notify_conflicts(conflicts)

    async def complete(self):
        """Complete task - ensures subtasks are done."""

        # Hierarchical: Check all subtasks completed
        children = await self.get_children()
        incomplete = [c for c in children if c.state != "done"]
        if incomplete:
            raise ValueError(f"{len(incomplete)} subtasks still incomplete")

        # Temporal: Record actual completion time
        self.actual_end_time = datetime.now()

        # Transactional: Transition to done
        await self.transition_state("done")

        # Calculate metrics for parent
        if self.parent_id:
            parent = await self.get_parent()
            await parent.update_progress()
```

### 4. Physical Location
**Patterns: Catalog + Hierarchical + Categorical**

```python
class Location(CatalogPattern, HierarchicalPattern, CategoricalPattern):
    """
    Bookable location with hierarchy and classification.
    """

    fields = [
        Field("name", str),            # "Conference Room A"
        Field("capacity", int),         # From Catalog
        Field("equipment", List[str]),  # From Catalog
        Field("floor_number", int),
        Field("room_number", str),
    ]

    # Classification from Categorical
    location_types = ["office", "meeting_room", "lab", "storage", "common_area"]

    # Example usage:
    async def find_available_meeting_room(self,
                                          attendees: int,
                                          start: datetime,
                                          duration: timedelta):
        """Find available meeting room using all patterns."""

        # Categorical: Filter by type
        meeting_rooms = await Location.filter(
            location_type="meeting_room"
        )

        # Catalog: Check capacity
        suitable_rooms = [r for r in meeting_rooms
                         if r.capacity >= attendees]

        # Temporal: Check availability
        available = []
        for room in suitable_rooms:
            if await room.is_available(start, start + duration):
                available.append(room)

        # Hierarchical: Prefer same floor/building
        if self.parent_id:  # User's office location
            building = await self.get_root()
            available.sort(
                key=lambda r: (
                    r.get_root().id != building.id,  # Same building first
                    abs(r.floor_number - self.floor_number)  # Closest floor
                )
            )

        return available[0] if available else None
```

### 5. Product with Variants
**Patterns: Catalog + Hierarchical**

```python
class Product(CatalogPattern, HierarchicalPattern):
    """
    Product with variants as children in hierarchy.
    """

    fields = [
        Field("name", str),
        Field("base_sku", str),
        Field("base_price", Decimal),
        Field("weight", float),
    ]

    # Parent product vs variant
    @property
    def is_variant(self):
        return self.parent_id is not None

    @property
    def is_parent_product(self):
        return not self.is_variant and self.has_children

    async def get_all_variants(self):
        """Get all variants with availability."""

        if self.is_variant:
            # Return siblings including self
            parent = await self.get_parent()
            return await parent.get_children()
        else:
            # Return all child variants
            return await self.get_children()

    async def get_price_range(self):
        """Get min/max price across variants."""

        if not self.has_children:
            return (self.base_price, self.base_price)

        variants = await self.get_all_variants()
        prices = [v.base_price for v in variants if v.is_available]

        return (min(prices), max(prices)) if prices else (None, None)
```

### 6. Organization Account
**Patterns: Actor + Hierarchical + Transactional**

```python
class Organization(ActorPattern, HierarchicalPattern, TransactionalPattern):
    """
    B2B organization with hierarchy and subscription states.
    """

    fields = [
        Field("company_name", str),
        Field("tax_id", str),
        Field("billing_email", str),
        Field("subscription_tier", str),
        Field("contract_value", Decimal),
    ]

    # Subscription states from Transactional
    state_machine = {
        "trial": ["active", "expired"],
        "active": ["suspended", "cancelled", "renewed"],
        "suspended": ["active", "cancelled"],
        "cancelled": ["archived"],
        "expired": ["active", "archived"],
    }

    # Complex B2B logic
    async def upgrade_subscription(self, new_tier: str):
        """Upgrade org and all subsidiaries."""

        # Actor: Check permissions
        if not await self.has_permission("manage_subscription"):
            raise PermissionError()

        # Transactional: Must be in valid state
        if self.state not in ["trial", "active"]:
            raise ValueError(f"Cannot upgrade from {self.state}")

        # Update this org
        old_tier = self.subscription_tier
        self.subscription_tier = new_tier

        # Hierarchical: Upgrade subsidiaries
        children = await self.get_children()
        for child in children:
            if child.subscription_tier < new_tier:
                await child.upgrade_subscription(new_tier)

        # Transactional: Emit event
        await self.emit_event("subscription.upgraded", {
            "from": old_tier,
            "to": new_tier,
            "affected_orgs": len(children) + 1
        })
```

## Pattern Interaction Patterns

### Property Mapping
When patterns have overlapping concepts:

```python
class Category(CategoricalPattern, HierarchicalPattern):
    @property
    def parent_category_id(self):  # Categorical expects this
        return self.parent_id  # From Hierarchical

    @property
    def subcategories(self):  # Categorical concept
        return self.children_ids  # From Hierarchical
```

### Method Chaining
Combine methods from multiple patterns:

```python
class Document(CatalogPattern, HierarchicalPattern, TemporalPattern):
    async def archive_old_versions(self):
        """Archive old document versions."""

        # Temporal: Find old documents
        cutoff = datetime.now() - timedelta(days=90)

        # Hierarchical: Get all versions (children)
        versions = await self.get_children()

        # Catalog + Temporal: Filter and archive
        for version in versions:
            if version.created_at < cutoff and version.is_available:
                version.is_available = False  # Catalog
                await version.transition_state("archived")  # Transactional
```

### Constraint Enforcement
Use one pattern to constrain another:

```python
class Milestone(TransactionalPattern, HierarchicalPattern, TemporalPattern):
    async def transition_state(self, new_state: str):
        """Override to add hierarchical constraints."""

        if new_state == "completed":
            # Hierarchical: Check child milestones
            children = await self.get_children()
            if any(c.state != "completed" for c in children):
                raise ValueError("Child milestones must complete first")

            # Temporal: Check deadline
            if datetime.now() > self.end_time:
                await self.emit_event("milestone.completed_late")

        return await super().transition_state(new_state)
```

## Magic Mode with Multiple Patterns

In simplified magic mode, just declare the patterns:

```python
class ProjectTask(MagicFeature):
    """Simple multi-pattern declaration."""

    patterns = ["transactional", "hierarchical", "temporal"]

    fields = [
        Field("title", str, required=True),
        Field("assignee_id", UUID),
        Field("priority", int, default=3),
    ]

    # Framework automatically provides:
    # - State machine with transitions (transactional)
    # - Parent/child relationships (hierarchical)
    # - Scheduling and conflicts (temporal)
    # - All methods from all patterns
```

## Best Practices

### When to Combine Patterns

✅ **DO combine when:**
- Entity genuinely exhibits multiple behaviors
- Patterns complement each other naturally
- Business logic requires interaction between patterns
- Examples: Categories (categorical + hierarchical), Tasks (transactional + hierarchical)

❌ **DON'T combine when:**
- Relationship is external (Product HAS categories, not IS categorical)
- Would create confusion or complexity
- Patterns conflict in their core concepts

### Pattern Selection Guide

| If you need... | Use Pattern(s) |
|----------------|----------------|
| State changes with audit | TransactionalPattern |
| Tree structure with parent/child | HierarchicalPattern |
| Classification and tagging | CategoricalPattern |
| Time-based operations | TemporalPattern |
| Identity and permissions | ActorPattern |
| Inventory with availability | CatalogPattern |
| Many-to-many relationships | RelationalPattern |
| Tasks with subtasks and states | Transactional + Hierarchical |
| Categories with subcategories | Categorical + Hierarchical |
| Bookable resources | Catalog + Temporal |
| Org chart with permissions | Actor + Hierarchical |

### Implementation Tips

1. **Start simple**: Begin with one primary pattern, add others as needed
2. **Map overlapping properties**: When patterns share concepts, create property mappings
3. **Override thoughtfully**: Override methods to combine pattern behaviors
4. **Test interactions**: Ensure patterns work together correctly
5. **Document intent**: Clearly explain why multiple patterns are used

## Migration Path

From single pattern to multiple:

```python
# Stage 1: Single pattern
class Task(TransactionalPattern):
    fields = [Field("title", str)]

# Stage 2: Add hierarchical for subtasks
class Task(TransactionalPattern, HierarchicalPattern):
    fields = [Field("title", str)]
    # Now supports subtasks!

# Stage 3: Add temporal for scheduling
class Task(TransactionalPattern, HierarchicalPattern, TemporalPattern):
    fields = [Field("title", str)]
    # Now supports scheduling too!
```

The framework handles adding new pattern capabilities without breaking existing code.
