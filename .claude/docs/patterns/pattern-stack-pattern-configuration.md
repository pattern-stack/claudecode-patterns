# PatternStack: Pattern Configuration System

## Core Philosophy

**Configuration is code.** Pattern configuration defines fundamental application building blocks, not deployment settings. Changes to patterns should go through code review, not accidental YAML edits.

## The `Pattern` Inner Class

Every PatternStack entity configures its behavior through an inner `Pattern` class:

```python
class Order(EventPattern):
    """Order entity."""

    class Pattern:
        """Pattern configuration for Order."""
        reference_prefix = "ORD"
        reference_reset = "yearly"
        features = ["state_machine", "audit", "events"]
```

This is **THE** way to configure patterns in PatternStack.

## Why Inner Class?

1. **Type-safe**: IDE knows types and provides autocomplete
2. **Versioned**: Configuration changes are code commits
3. **Discoverable**: Always look in the class for its config
4. **Testable**: Can assert on Pattern attributes
5. **Refactorable**: IDE can rename across codebase
6. **Namespaced**: Config doesn't pollute entity namespace

## Configuration Hierarchy

Configuration follows a clear precedence:

```python
# 1. Framework defaults (lowest priority)
PATTERN_DEFAULTS = {
    "reference_prefix": "REF",
    "audit": True,
}

# 2. Module-level overrides (my_app/features/commerce/__init__.py)
__pattern_defaults__ = {
    "schema": "commerce",  # Database schema for module
}

# 3. Entity Pattern class (highest priority)
class Order(EventPattern):
    class Pattern:
        reference_prefix = "ORD"  # Wins
```

## Complete Pattern Configuration

```python
class Order(EventPattern, CatalogPattern):
    """Order with comprehensive Pattern configuration."""

    class Pattern:
        # === IDENTITY ===
        # Human-readable reference numbers
        reference_prefix = "ORD"
        reference_reset = "yearly"  # ORD-2024-0001, ORD-2025-0001
        reference_format = "{prefix}-{year}-{number:04d}"
        reference_immutable = True  # Cannot change after creation

        # === FEATURES ===
        # Explicit feature flags
        features = [
            "state_machine",     # State transitions
            "audit",            # Track changes
            "events",           # Emit domain events
            "soft_delete",      # Never hard delete
            "reference_numbers", # Human-friendly IDs
            "versioning",       # Track version history
            "search",           # Full-text search
        ]

        # === STATE MACHINE ===
        states = {
            "draft": ["pending", "cancelled"],
            "pending": ["processing", "cancelled"],
            "processing": ["shipped", "failed"],
            "shipped": ["delivered", "returned"],
            "delivered": [],  # Terminal
            "cancelled": [],  # Terminal
            "returned": ["processing"],  # Can retry
        }
        initial_state = "draft"
        terminal_states = ["delivered", "cancelled"]
        state_field = "status"  # Override default "state"

        # === DATABASE ===
        table_name = "orders"          # Override plural
        schema = "commerce"             # PostgreSQL schema
        indexes = [
            "customer_id",
            "state",
            ("created_at", "state"),    # Composite index
        ]
        unique_constraints = [
            ["reference_number", "reference_year"],
        ]

        # === AUDIT ===
        audit_exclude = ["last_viewed", "view_count"]
        audit_user_field = "modified_by"
        track_changes = True  # Store field diffs
        track_user = True     # Who made changes

        # === EVENTS ===
        event_prefix = "order"  # order.created, order.shipped
        event_async = True      # Async event emission
        event_retry = True      # Retry failed events

        # === API GENERATION ===
        api_path = "/orders"           # Endpoint path
        api_plural = "orders"          # For consistency
        api_exclude = ["delete"]       # No hard delete via API
        api_include_relations = True   # Include related data
        api_pagination = 50            # Default page size

        # === PERMISSIONS ===
        require_auth = True
        admin_only = ["delete", "force_transition"]
        owner_field = "customer_id"  # For ownership checks
        team_field = "store_id"      # For team access

        # === CACHING ===
        cache_ttl = 300  # 5 minutes
        cache_key = "order:{id}"
        cache_invalidate_on = ["update", "delete", "transition"]

        # === VALIDATION ===
        required_fields = ["customer_id", "items"]
        immutable_fields = ["customer_id"]  # After creation

        # === SEARCH ===
        searchable_fields = ["reference_number", "customer_email"]
        search_boost = {
            "reference_number": 2.0,  # Boost importance
        }

    # === ACTUAL ENTITY FIELDS ===
    customer_id: UUID = Field(nullable=False)
    items: List['OrderItem'] = relationship("OrderItem")
    total: Decimal = Column(Decimal(10, 2))

    # === BUSINESS METHODS ===
    async def calculate_tax(self) -> Decimal:
        return self.total * Decimal("0.10")

    async def can_cancel(self) -> bool:
        return self.state in ["draft", "pending"]
```

## Pattern Inheritance

Child classes can inherit and override parent Pattern configuration:

```python
class Order(EventPattern):
    class Pattern:
        reference_prefix = "ORD"
        audit = True
        soft_delete = True

class RushOrder(Order):
    class Pattern(Order.Pattern):  # Inherit parent Pattern
        reference_prefix = "RUSH"   # Override prefix
        # audit = True (inherited)
        # soft_delete = True (inherited)
        priority = 1  # Add new config
```

## Module-Level Configuration

For cross-cutting concerns affecting all entities in a module:

```python
# my_app/features/commerce/__init__.py
"""Commerce module configuration."""

__pattern_defaults__ = {
    # Applies to ALL patterns in this module
    "schema": "commerce",           # Database schema
    "api_prefix": "/api/commerce",  # API namespace
    "cache_prefix": "commerce:",    # Cache keys
    "event_prefix": "commerce.",    # Event names
}

# These are inherited by all entities in the module
# but can be overridden by entity Pattern class
```

## Framework Implementation

```python
class BasePattern:
    """Base class all patterns inherit from."""

    def __init_subclass__(cls, **kwargs):
        super().__init_subclass__(**kwargs)

        # Build configuration from hierarchy
        config = {}

        # 1. Framework defaults
        config.update(PATTERN_DEFAULTS)

        # 2. Module defaults
        module = sys.modules[cls.__module__]
        if hasattr(module, '__pattern_defaults__'):
            config.update(module.__pattern_defaults__)

        # 3. Parent class Pattern
        for base in cls.__mro__[1:]:
            if hasattr(base, 'Pattern'):
                config.update(_pattern_to_dict(base.Pattern))

        # 4. This class Pattern
        if hasattr(cls, 'Pattern'):
            config.update(_pattern_to_dict(cls.Pattern))

        # Store computed configuration
        cls._pattern_config = config

        # Apply configuration
        cls._apply_pattern_config()

    @classmethod
    def _apply_pattern_config(cls):
        """Apply Pattern configuration to class."""
        config = cls._pattern_config

        # Setup features
        if 'state_machine' in config.get('features', []):
            cls._setup_state_machine()

        if 'audit' in config.get('features', []):
            cls._setup_audit()

        if 'events' in config.get('features', []):
            cls._setup_events()

        # Setup reference numbers
        if config.get('reference_prefix'):
            cls._setup_reference_numbers()
```

## Usage Examples

### Simple Configuration
```python
class Task(EventPattern):
    class Pattern:
        reference_prefix = "TSK"
        states = {
            "todo": ["in_progress"],
            "in_progress": ["done", "blocked"],
            "blocked": ["in_progress"],
            "done": [],
        }
```

### Multi-Pattern Configuration
```python
class Meeting(EventPattern, TemporalPattern):
    class Pattern:
        reference_prefix = "MTG"

        # EventPattern config
        states = {
            "scheduled": ["in_progress", "cancelled"],
            "in_progress": ["completed"],
        }

        # TemporalPattern config
        timezone_aware = True
        allow_overlap = False
        buffer_minutes = 15
```

### Marketplace Example (AirBnb-style)
```python
class Listing(CatalogPattern, HierarchicalPattern):
    class Pattern:
        reference_prefix = "LST"

        # Catalog config
        availability_tracking = True
        variant_support = True  # Different room types

        # Hierarchical config
        parent_field = "property_id"
        max_depth = 3  # Property -> Building -> Floor -> Unit

class Booking(EventPattern, TemporalPattern):
    class Pattern:
        reference_prefix = "BKG"
        reference_reset = "monthly"

        # Event config
        states = {
            "requested": ["confirmed", "rejected"],
            "confirmed": ["checked_in", "cancelled"],
            "checked_in": ["checked_out"],
            "checked_out": ["reviewed"],
        }

        # Temporal config
        enforce_boundaries = True  # Must respect check-in/out times
        timezone_field = "property_timezone"
```

## Best Practices

1. **Be Explicit**: List features explicitly rather than assuming defaults
2. **Document Choices**: Comment why certain configs were chosen
3. **Use Constants**: For repeated values (states, prefixes)
4. **Test Config**: Write tests that assert on Pattern values
5. **Keep It Simple**: Start minimal, add config as needed

## Anti-Patterns

❌ **Don't** put business logic in Pattern:
```python
class Pattern:
    # Bad: This is logic, not config
    def calculate_price(self):
        return 100
```

❌ **Don't** use Pattern for deployment config:
```python
class Pattern:
    # Bad: This changes per environment
    database_url = "postgresql://..."
    api_key = "sk_live_..."
```

❌ **Don't** make Pattern dynamic:
```python
class Pattern:
    # Bad: Config should be static
    reference_prefix = os.getenv("ORDER_PREFIX")
```

## The PatternStack Way

This Pattern configuration system embodies PatternStack's philosophy:

1. **Convention over Configuration**: Smart defaults, override only what's different
2. **Explicit is Better**: Features are opt-in, not assumed
3. **Configuration as Code**: Type-safe, versioned, reviewable
4. **Progressive Enhancement**: Start simple, add complexity as needed
5. **Framework, Not Library**: Opinionated about the right way

The `Pattern` inner class is the heart of PatternStack - it's where the magic becomes explicit, where conventions meet customization, and where your domain model declares its behavior.

**This is PatternStack, baby! 🚀**
