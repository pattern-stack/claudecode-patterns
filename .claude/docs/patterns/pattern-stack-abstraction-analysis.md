# Pattern Stack: Abstraction Layer Analysis

## The Challenge

We need to identify the right abstraction buckets that are:
1. **Generic enough** to apply across different CRM-style applications
2. **Specific enough** to provide real value and functionality
3. **Flexible enough** to be extended/overridden for specific use cases

## Core Pattern Categories

### 1. Transactional Pattern
**Core Concept**: Entities that represent state-changing operations with audit trails

#### Universal Properties
- Has a **lifecycle** (states that change over time)
- Requires **audit trail** (who did what when)
- Often has **monetary value** or **measurable impact**
- Usually **immutable** after certain states
- Needs **event emission** for downstream effects

#### Real-World Applications NOTES: Let's add the numeric (if exists) in this list - I'm wondering if it should be included ny deafault or if it should be left out. The word choice "Transactional" seems to have influenced plans a bit more than intended - this may be more of an `EventPattern` vs anything else.
| Domain | Entity | States |
|--------|--------|--------|
| E-commerce | Order | draft → pending → processing → completed → archived |
| Finance | Invoice | draft → sent → overdue → paid → cancelled |
| Task Management | Task | todo → in_progress → blocked → review → done |
| Analytics | SiteVisit | active → idle → completed → analyzed |
| Support | Ticket | open → assigned → investigating → resolved → closed |
| HR | TimeEntry | draft → submitted → approved → processed → paid |
| Logistics | Shipment | prepared → dispatched → in_transit → delivered → returned |

#### Generic State Machine

NOTE: I'm uncertain how I feel about the defaults - should this be more generic? Should it not be? If its too generic
does it confuse the user? If it's too specific do we risk influencing direction too much?
```python
class TransactionalStates:
    # Universal states that map to domain-specific states
    INITIAL = "initial"        # draft, new, created
    ACTIVE = "active"          # in_progress, processing, assigned
    WAITING = "waiting"        # blocked, pending_approval, on_hold
    REVIEWING = "reviewing"    # in_review, validating, checking
    COMPLETED = "completed"    # done, resolved, delivered
    CANCELLED = "cancelled"    # cancelled, rejected, failed
    ARCHIVED = "archived"      # archived, deleted, purged

    # State categories for business rules
    EDITABLE_STATES = [INITIAL, ACTIVE]
    TERMINAL_STATES = [COMPLETED, CANCELLED, ARCHIVED]
    REVERSIBLE_STATES = [ACTIVE, WAITING, REVIEWING]
```

### 2. Catalog Pattern
**Core Concept**: Entities that represent reference data, inventory, or collectible items

#### Universal Properties
- **Categorizable** (belongs to hierarchical categories)
- **Searchable** (needs filtering, faceting)
- **Versionable** (properties change over time)
- Has **variants** or **configurations**
- Often has **media** (images, documents)
- Requires **availability** tracking

#### Real-World Applications
| Domain | Entity | Variants |
|--------|--------|----------|
| E-commerce | Product | Size, Color, Material |
| Real Estate | Property | Units, Floors, Amenities |
| HR | Position | Level, Department, Location |
| Facilities | Location | Buildings, Floors, Rooms |
| Education | Course | Sections, Semesters, Formats |
| Healthcare | Service | Providers, Durations, Locations |
| Inventory | Asset | Conditions, Warranties, Assignments |

#### Generic Catalog Structure

Why is this so different from transactional above? Is this just deomnstrating a different way of organizing it or is this an oversight?
```python
class CatalogPattern:
    # Universal catalog properties
    categorization = {
        "primary_category": str,      # Main classification
        "tags": List[str],            # Flexible tagging
        "attributes": Dict[str, Any], # Key-value properties
    }

    availability = {
        "status": Enum["available", "unavailable", "limited"],
        "quantity": Optional[int],
        "constraints": List[dict],    # Rules for availability
    }

    variants = {
        "variant_type": str,          # What varies (size, color, etc)
        "variant_options": List[dict], # Available options
        "variant_matrix": dict,       # Combination rules
    }
```

### 3. Actor Pattern (formerly UserType)
**Core Concept**: Entities that perform actions in the system (users, systems, organizations)

#### Universal Properties
- Has **identity** and **authentication**
- Has **permissions** and **roles**
- Maintains **relationships** with other actors
- Has **preferences** and **settings**
- Generates **activity** history
- Can be **delegated** or **impersonated**

#### Real-World Applications
| Domain | Entity | Roles |
|--------|--------|-------|
| B2B | Organization | Customer, Vendor, Partner |
| B2C | Customer | Guest, Member, VIP |
| Internal | Employee | Admin, Manager, Analyst |
| Healthcare | Patient | Active, Inactive, Discharged |
| Education | Student | Enrolled, Alumni, Prospective |
| IoT | Device | Sensor, Gateway, Controller |
| API | Service | Internal, External, Third-party |

### 4. Temporal Pattern
**Core Concept**: Entities bound by time constraints, schedules, or recurring patterns

#### Universal Properties
- Has **start** and **end** times
- May **recur** (daily, weekly, custom)
- Can **conflict** with other temporal entities
- Requires **timezone** awareness
- Supports **reminders** and **notifications**
- Has **duration** and **capacity** constraints

#### Real-World Applications
| Domain | Entity | Recurrence |
|--------|--------|------------|
| Calendar | Event | Daily, Weekly, Monthly |
| Scheduling | Appointment | One-time, Series |
| Project Mgmt | Milestone | Fixed, Floating |
| Subscription | Billing Cycle | Monthly, Annual |
| Maintenance | Service Window | Scheduled, Ad-hoc |
| Education | Class Schedule | Semester-based |

### 5. Hierarchical Pattern
**Core Concept**: Entities that form tree structures with parent-child relationships

#### Universal Properties
- Has **parent** reference (except root)
- Can have **children** collection
- Maintains **path** from root
- Supports **depth** constraints
- Allows **traversal** operations
- Handles **inheritance** of properties

#### Real-World Applications
| Domain | Entity | Hierarchy |
|--------|--------|-----------|
| Org Structure | Department | Company → Division → Department → Team |
| Content | Category | Root → Category → Subcategory → Item |
| Geographic | Location | Country → State → City → District |
| Filesystem | Folder | Drive → Folder → Subfolder → File |
| Comments | Thread | Post → Comment → Reply → Sub-reply |

### 6. Categorical Pattern
**Core Concept**: Entities that classify, tag, or provide metadata for other entities

#### Universal Properties
- Provides **classification** for other entities
- Often **lightweight** (just name and metadata)
- Can be **hierarchical** (category → subcategory)
- Supports **multiple assignment** (many-to-many)
- Has **display properties** (color, icon, order)
- May have **rules** or **constraints**

#### Real-World Applications
| Domain | Entity | Usage |
|--------|--------|-------|
| Project Mgmt | Tag | Issue tagging, filtering |
| E-commerce | Category | Product classification |
| CRM | Status | Lead status, Deal stage |
| Content | Topic | Article categorization |
| Support | Priority | Ticket prioritization |
| Finance | AccountType | GL account classification |
| HR | Department | Employee grouping |

### 7. Relational Pattern
**Core Concept**: Entities that primarily represent relationships between other entities

#### Universal Properties
- Links **source** and **target** entities
- Has **relationship type** (many-to-many, one-to-many)
- May have **strength** or **weight**
- Can be **directional** or **bidirectional**
- Includes **metadata** about the relationship
- Supports **constraints** and **rules**

#### Real-World Applications
| Domain | Entity | Relationship |
|--------|--------|--------------|
| Social | Friendship | User ↔ User |
| Org | Assignment | Employee → Role |
| E-commerce | CartItem | Cart → Product |
| Project | Dependency | Task → Task |
| Knowledge | Association | Concept → Concept |

## Proposed Base Class Hierarchy

```python
# pattern_stack/base/patterns.py

#NOTE - is there any value in adding an incremental ID? Or is this just an optional thing we add later? Just thinking about user interactions for admin panels and whatnot but UUID is obviously better from an operational perspective
class BasePattern:
    """Root pattern with common functionality."""

    # Universal fields
    id: UUID
    created_at: datetime
    updated_at: datetime
    deleted_at: Optional[datetime]  # Soft delete

    # Universal capabilities
    - Audit trail
    - Event emission
    - Validation hooks
    - Serialization

class TransactionalPattern(BasePattern):
    """For state-changing operations."""

    # Generic state machine
    state: str  # Maps to domain states
    state_history: List[StateChange]

    # Lifecycle hooks
    - before_state_change()
    - after_state_change()
    - validate_transition()

    # Business fields (commonly overridden)
    amount: Optional[Decimal]
    reference_number: Optional[str]
    metadata: Dict[str, Any]

class CatalogPattern(BasePattern):
    """For reference/inventory items."""

    # Categorization
    category: str
    tags: List[str]
    attributes: Dict[str, Any]

    # Availability
    is_available: bool
    availability_rules: List[Rule]

    # Variants
    has_variants: bool
    variant_matrix: Dict

    # Media
    images: List[MediaItem]
    documents: List[Document]

class ActorPattern(BasePattern):
    """For entities that perform actions."""

    # Identity
    identifier: str  # email, username, device_id
    display_name: str

    # Access
    roles: List[str]
    permissions: List[str]

    # Activity
    last_active: datetime
    activity_count: int

    # Preferences
    settings: Dict[str, Any]
    timezone: str
    locale: str

class TemporalPattern(BasePattern):
    """For time-bound entities."""

    # Time bounds
    #NOTE - this is incredibly pedantic but do we need all 3? What happens if start time and end time dont compute to the supplied duration? We probably want to enforce 2 of 3 then calculate the 3rd? Maybe im overthinking
    start_time: datetime
    end_time: Optional[datetime]
    duration: Optional[timedelta]

    # Recurrence
    recurrence_rule: Optional[str]  # RFC 5545
    recurrence_exceptions: List[datetime]

    # Constraints
    capacity: Optional[int]
    buffer_before: Optional[timedelta]
    buffer_after: Optional[timedelta]

class HierarchicalPattern(BasePattern):
    """For tree structures."""

    # Structure
    parent_id: Optional[UUID]
    children_ids: List[UUID]
    path: str  # /root/parent/self
    depth: int

    # Operations
    - get_ancestors()
    - get_descendants()
    - move_to_parent()
    - inherit_properties()

class CategoricalPattern(BasePattern):
    """For classification/tagging entities."""

    # Core properties
    name: str
    slug: str  # URL-safe identifier
    description: Optional[str]

    # Display
    color: Optional[str]  # Hex color for UI
    icon: Optional[str]   # Icon identifier
    display_order: int    # Sorting order

    # Hierarchy (optional)
    parent_category_id: Optional[UUID]
    is_active: bool

    # Rules
    is_exclusive: bool  # Can only have one per entity
    allowed_entities: List[str]  # Which entities can use this
    validation_rules: Dict[str, Any]

    # Usage tracking
    usage_count: int
    last_used: Optional[datetime]

class RelationalPattern(BasePattern):
    """For relationships between entities."""

    # Relationship
    source_id: UUID
    source_type: str
    target_id: UUID
    target_type: str
    relationship_type: str

    # Properties
    strength: Optional[float]
    metadata: Dict[str, Any]
    is_bidirectional: bool
```

## State Machine Abstraction

Instead of hard-coding states, we use a mapping system:

```python
class StateMapping:
    """Maps generic states to domain-specific states."""

    #note - love this - just want to make sure we're covering all cases - do we want to predefine the inactive/active/waiting as we have or  should we be keeping it more generic? state_1, state_2, state_3 ? I genuinely don't know what i prefer as a baseline/
    GENERIC_STATES = {
        "initial": ["draft", "new", "created", "pending"],
        "active": ["in_progress", "processing", "working", "assigned"],
        "waiting": ["blocked", "on_hold", "pending_review", "awaiting"],
        "reviewing": ["in_review", "checking", "validating", "approving"],
        "completed": ["done", "finished", "resolved", "delivered", "paid"],
        "cancelled": ["cancelled", "rejected", "failed", "abandoned"],
        "archived": ["archived", "deleted", "purged", "expired"],
    }

    @classmethod
    def map_to_generic(cls, domain_state: str) -> str:
        """Map domain state to generic state."""
        for generic, domains in cls.GENERIC_STATES.items():
            if domain_state.lower() in domains:
                return generic
        return "custom"

    @classmethod
    def get_valid_transitions(cls, current_generic: str) -> List[str]:
        """Get valid state transitions."""
        transitions = {
            "initial": ["active", "cancelled"],
            "active": ["waiting", "reviewing", "completed", "cancelled"],
            "waiting": ["active", "cancelled"],
            "reviewing": ["active", "completed", "cancelled"],
            "completed": ["archived"],
            "cancelled": ["archived"],
            "archived": [],
        }
        return transitions.get(current_generic, [])
```

## Usage Examples

### E-commerce Order (Transactional)
```python
class Order(TransactionalPattern):
    fields = [
        Field("customer_id", UUID),
        Field("items", List[OrderItem]),
    ]

    # Map to generic states
    state_mapping = {
        "draft": "initial",
        "pending_payment": "waiting",
        "processing": "active",
        "shipped": "active",
        "delivered": "completed",
    }
```

### Task Management (Transactional)
```python
class Task(TransactionalPattern):
    fields = [
        Field("title", str),
        Field("assignee_id", UUID),
    ]

    state_mapping = {
        "todo": "initial",
        "in_progress": "active",
        "blocked": "waiting",
        "in_review": "reviewing",
        "done": "completed",
    }
```

### Product Catalog (Catalog)
```python
class Product(CatalogPattern):
    fields = [
        Field("sku", str),
        Field("price", Decimal),
    ]

    variants = {
        "size": ["S", "M", "L", "XL"],
        "color": ["Red", "Blue", "Green"],
    }
```

### Office Location (Catalog + Hierarchical)
```python
class Location(CatalogPattern, HierarchicalPattern):
    fields = [
        Field("building_name", str),
        Field("floor", int),
        Field("capacity", int),
    ]

    # Can be both in catalog and hierarchy
    # Building → Floor → Room → Desk
```

### Issue Tags (Categorical)
```python
class IssueTag(CategoricalPattern):
    fields = [
        Field("name", str),           # "bug", "feature", "enhancement"
        Field("color", str),          # "#FF0000"
        Field("icon", str),           # "bug-icon"
    ]

    # Lightweight classification
    # Many-to-many with issues
    # Just metadata, not a full entity
```

### Product vs Product Category
```python
# Product is Catalog - it's an actual item with inventory
class Product(CatalogPattern):
    fields = [
        Field("sku", str),
        Field("price", Decimal),
        Field("stock_quantity", int),
    ]

# ProductCategory is Categorical - it classifies products
class ProductCategory(CategoricalPattern):
    fields = [
        Field("name", str),  # "Electronics", "Clothing"
        Field("tax_rate", Decimal),  # Category-specific rules
    ]

    # Can be hierarchical
    # Electronics → Computers → Laptops
```

## Key Design Decisions

### 1. Multiple Inheritance
Entities can combine patterns:
```python
class Employee(ActorPattern, HierarchicalPattern):
    # Has both actor properties (roles, permissions)
    # And hierarchical properties (reports to manager)
```

### 2. Generic State Mapping
Instead of forcing specific states, we map between generic and domain states, allowing flexibility while maintaining common behavior.

### 3. Composition Over Configuration
Rather than complex configuration, users compose patterns:
```python
class Meeting(TemporalPattern, RelationalPattern):
    # Temporal: scheduled time
    # Relational: links attendees
```

### 4. Progressive Enhancement
Start with pattern defaults, override as needed:
```python
# Simple
class Task(TransactionalPattern):
    fields = [Field("title", str)]

# Complex
class Task(TransactionalPattern):
    # Override state machine completely
    custom_states = {...}
    custom_transitions = {...}
```

## Questions to Resolve

1. **Pattern Naming**: Are these the right names? (Transactional, Catalog, Actor, etc.)
2. **State Abstraction**: Is the generic state mapping flexible enough?
3. **Multiple Inheritance**: Should we allow combining patterns or keep them separate?
4. **Field Definition**: How much should be in base vs user-defined?
5. **Business Logic**: Where does pattern logic end and domain logic begin?

## Next Steps

1. **Validate patterns** against real applications
2. **Build prototype** of each pattern
3. **Test flexibility** with different domains
4. **Refine abstractions** based on usage
5. **Document patterns** with extensive examples



## NOTES FOR REFINEMENT:
- lets add AirBnb as a primary example across the board - this covers "marketplace" style applications like RIdeShare, Rentals, etc
- add basic code examples aacross the board - only have it now for Transactional and Categorical (and they're both different)
