# Pattern Stack: Progressive Enhancement Framework

## Core Philosophy

Pattern Stack provides both "Rails-like magic" for rapid development AND "enterprise patterns" for complex systems. Users can start simple and add complexity as needed without rewriting.

## Progressive Enhancement Stages

### Stage 1: Pure Magic (Prototype Phase)
**One file, full feature**

```python
# my_app/features/orders.py
from pattern_stack.magic import TransactionalFeature, Field
from uuid import UUID

class Orders(TransactionalFeature):
    """Complete order feature in one class definition."""

    # Define additional fields (beyond base transactional fields)
    fields = [
        Field("customer_id", UUID, required=True, foreign_key="customers.id"),
        Field("shipping_address", str, required=True),
        Field("discount_code", str, required=False),
    ]

    # Define relationships
    relationships = {
        "customer": ("Customer", "many-to-one"),
        "items": ("OrderItem", "one-to-many"),
    }

    # Define state machine
    state_machine = {
        "pending": ["processing", "cancelled"],
        "processing": ["shipped", "failed"],
        "shipped": ["delivered", "returned"],
    }
```

**Framework automatically generates:**
- SQLAlchemy model with all fields
- Pydantic schemas (Input/Output/Internal)
- Service with full CRUD operations
- State transition methods
- REST API endpoints
- CLI management commands
- Basic test suite

### Stage 2: Enhanced Magic (Production Phase)
**Same file, custom logic added**

```python
# my_app/features/orders.py
from pattern_stack.magic import TransactionalFeature, Field
from pattern_stack.events import emit
from typing import List
from uuid import UUID

class Orders(TransactionalFeature):
    """Order feature with custom business logic."""

    fields = [
        Field("customer_id", UUID, required=True, foreign_key="customers.id"),
        Field("shipping_address", str, required=True),
        Field("discount_code", str, required=False),
        Field("priority", int, default=0),
    ]

    relationships = {
        "customer": ("Customer", "many-to-one"),
        "items": ("OrderItem", "one-to-many"),
    }

    state_machine = {
        "pending": ["processing", "cancelled"],
        "processing": ["shipped", "failed"],
        "shipped": ["delivered", "returned"],
    }

    # Custom business methods
    async def apply_discount(self, order_id: UUID, code: str) -> float:
        """Apply discount code to order."""
        discount = await self.validate_discount_code(code)
        order = await self.get(order_id)
        order.discount_amount = order.amount * discount.percentage
        await self.save(order)
        await emit("order.discount_applied", {
            "order_id": order_id,
            "discount_code": code,
            "amount": order.discount_amount
        })
        return order.discount_amount

    # Lifecycle hooks
    async def before_create(self, data: dict) -> dict:
        """Validate before creation."""
        # Check customer exists
        customer = await self.db.get("customers", data["customer_id"])
        if not customer:
            raise ValueError("Customer not found")

        # Validate inventory
        for item in data.get("items", []):
            await self.validate_inventory(item)

        return data

    async def after_state_change(self, entity, old_state: str, new_state: str):
        """React to state changes."""
        if new_state == "shipped":
            await self.send_shipping_notification(entity)
        elif new_state == "cancelled":
            await self.restore_inventory(entity)

    # Custom validation
    def validate_shipping_address(self, address: str) -> bool:
        """Custom address validation."""
        # Custom logic here
        return True

    # Override default behavior
    async def delete(self, order_id: UUID) -> bool:
        """Soft delete with cascade handling."""
        order = await self.get(order_id)

        # Cancel instead of delete if processing
        if order.state == "processing":
            return await self.transition_state(order_id, "cancelled")

        # Otherwise use default soft delete
        return await super().delete(order_id)
```

### Stage 3: Explicit Mode (Scale Phase)
**Multi-file structure with full control**

```python
# my_app/features/orders/models.py
from pattern_stack.base import TransactionalModel
from sqlalchemy import Column, String, Integer, ForeignKey
from sqlalchemy.orm import relationship

class Order(TransactionalModel):
    """Order model with full SQLAlchemy control."""
    __tablename__ = "orders"

    # Additional fields beyond TransactionalModel base
    customer_id = Column(UUID, ForeignKey("customers.id"), nullable=False)
    shipping_address = Column(String, nullable=False)
    discount_code = Column(String)
    priority = Column(Integer, default=0)

    # Complex relationships
    customer = relationship("Customer", back_populates="orders")
    items = relationship("OrderItem", back_populates="order", cascade="all, delete-orphan")
    shipments = relationship("Shipment", back_populates="order")

    # Custom properties
    @property
    def total_with_tax(self):
        return self.amount * 1.1  # 10% tax

    # Custom methods
    def can_cancel(self):
        return self.state in ["pending", "processing"]
```

```python
# my_app/features/orders/schemas.py
from pattern_stack.base import TransactionalSchema
from pydantic import BaseModel, validator
from typing import List, Optional
from decimal import Decimal

class OrderItemSchema(BaseModel):
    product_id: UUID
    quantity: int
    price: Decimal

class OrderSchema(TransactionalSchema):
    """Order schemas with full Pydantic control."""

    class Input(TransactionalSchema.Input):
        customer_id: UUID
        shipping_address: str
        items: List[OrderItemSchema]
        discount_code: Optional[str] = None
        priority: int = 0

        @validator("items")
        def validate_items_not_empty(cls, v):
            if not v:
                raise ValueError("Order must have at least one item")
            return v

        @validator("shipping_address")
        def validate_address_format(cls, v):
            # Custom validation logic
            return v

    class Output(TransactionalSchema.Output):
        customer_id: UUID
        customer_name: str  # Computed field
        shipping_address: str
        item_count: int
        subtotal: Decimal
        tax: Decimal
        total: Decimal

        class Config:
            orm_mode = True

    class Internal(TransactionalSchema.Internal):
        """Internal processing schema."""
        tax_calculation: dict
        shipping_calculation: dict
        inventory_reservations: List[UUID]
```

```python
# my_app/features/orders/service.py
from pattern_stack.base import TransactionalService
from pattern_stack.decorators import transaction, cache, audit
from .models import Order
from .schemas import OrderSchema
from .repository import OrderRepository

class OrderService(TransactionalService[Order]):
    """Order service with full control."""

    model = Order
    repository_class = OrderRepository

    def __init__(self, session, cache, event_bus):
        super().__init__(session)
        self.cache = cache
        self.event_bus = event_bus
        self.repo = OrderRepository(session)

    @transaction
    @audit("order.created")
    async def create_order(self, data: OrderSchema.Input) -> Order:
        """Create order with complex business logic."""
        # Validate customer
        customer = await self._validate_customer(data.customer_id)

        # Reserve inventory
        reservations = await self._reserve_inventory(data.items)

        try:
            # Calculate pricing
            pricing = await self._calculate_pricing(data.items, data.discount_code)

            # Create order
            order_data = data.dict()
            order_data.update(pricing)
            order = await self.create_transaction(order_data)

            # Create order items
            await self._create_order_items(order.id, data.items)

            # Queue for fulfillment
            await self.event_bus.emit("order.ready_for_fulfillment", order.id)

            return order

        except Exception as e:
            # Rollback inventory reservations
            await self._release_inventory(reservations)
            raise

    @cache(ttl=300)
    async def get_customer_orders(self, customer_id: UUID) -> List[Order]:
        """Get customer orders with caching."""
        return await self.repo.find_by_customer(customer_id)

    async def ship_order(self, order_id: UUID, tracking_number: str) -> Order:
        """Ship order with validations."""
        order = await self.get(order_id)

        # Validate can ship
        if order.state != "processing":
            raise InvalidStateError("Order must be processing to ship")

        # Create shipment record
        await self._create_shipment(order_id, tracking_number)

        # Transition state
        order = await self.transition_state(order_id, "shipped")

        # Send notifications
        await self._send_shipping_notifications(order, tracking_number)

        return order
```

```python
# my_app/features/orders/repository.py
from pattern_stack.base import Repository
from .models import Order
from sqlalchemy import and_, or_
from typing import List
from uuid import UUID

class OrderRepository(Repository[Order]):
    """Custom repository with complex queries."""

    model = Order

    async def find_by_customer(self, customer_id: UUID) -> List[Order]:
        """Find orders by customer."""
        return await self.query(
            Order.customer_id == customer_id,
            Order.deleted_at.is_(None)
        ).order_by(Order.created_at.desc()).all()

    async def find_pending_shipments(self) -> List[Order]:
        """Find orders ready to ship."""
        return await self.query(
            Order.state == "processing",
            Order.shipping_address.isnot(None)
        ).all()

    async def find_high_value_orders(self, threshold: Decimal) -> List[Order]:
        """Complex query example."""
        return await self.query(
            and_(
                Order.amount > threshold,
                Order.state.in_(["completed", "shipped"]),
                or_(
                    Order.priority > 5,
                    Order.customer.has(Customer.tier == "premium")
                )
            )
        ).all()
```

## Migration Between Stages

### From Magic to Enhanced Magic
Simply add methods to your existing feature class:

```python
# Before (Stage 1)
class Orders(TransactionalFeature):
    fields = [...]

# After (Stage 2)
class Orders(TransactionalFeature):
    fields = [...]

    async def custom_logic(self):
        # New business logic
        pass
```

### From Magic to Explicit
Use the CLI to expand:

```bash
# Expand magic feature to full structure
pattern-stack expand orders

# Creates:
# features/orders/
#   ├── models.py    # Generated from fields definition
#   ├── schemas.py   # Generated from fields definition
#   ├── service.py   # Generated with custom methods preserved
#   └── repository.py # Optional
```

## Framework Support for All Stages

### Auto-Discovery
The framework discovers features regardless of structure:

```python
# pattern_stack/core/discovery.py
class ComponentDiscovery:
    def discover_features(self, package: str):
        features = {}

        # Discover magic features (single file)
        features.update(self._discover_magic_features(package))

        # Discover explicit features (multi-file)
        features.update(self._discover_explicit_features(package))

        return features

    def _discover_magic_features(self, package: str):
        """Find single-file magic features."""
        # Look for classes extending magic base classes
        pass

    def _discover_explicit_features(self, package: str):
        """Find multi-file explicit features."""
        # Look for service.py files in feature directories
        pass
```

### Unified API Generation
Both magic and explicit features generate the same APIs:

```python
# pattern_stack/generators/api.py
class APIGenerator:
    def generate_for_feature(self, feature):
        if isinstance(feature, MagicFeature):
            return self._generate_from_magic(feature)
        else:
            return self._generate_from_explicit(feature)

    def _generate_from_magic(self, feature):
        """Generate API from fields and methods."""
        endpoints = []

        # Standard CRUD from fields
        endpoints.extend(self._generate_crud(feature.fields))

        # State machine endpoints
        if feature.state_machine:
            endpoints.extend(self._generate_state_endpoints(feature.state_machine))

        # Custom method endpoints
        for method in feature.get_public_methods():
            endpoints.append(self._method_to_endpoint(method))

        return endpoints
```

## Benefits

1. **Low barrier to entry**: Start with one file, get full functionality
2. **No rewriting**: Enhance in place or expand to full structure
3. **Framework benefits at all stages**: Events, audit, state machines always available
4. **Type safety**: Full typing support throughout
5. **Testing**: Automatic test generation that can be extended
6. **Future-proof**: Can always drop down to more control

## Example: Task Management App

```python
# Stage 1: Get running in minutes
class Tasks(TransactionalFeature):
    fields = [
        Field("title", str, required=True),
        Field("assignee_id", UUID),
        Field("due_date", datetime),
    ]

    state_machine = {
        "todo": ["in_progress"],
        "in_progress": ["blocked", "review", "done"],
        "blocked": ["in_progress"],
        "review": ["in_progress", "done"],
    }

# That's it! Full task management with API, state transitions, audit trail
```

## Design Principles

1. **Convention over Configuration**: Sensible defaults for everything
2. **Progressive Disclosure**: Complexity only when needed
3. **No Lock-in**: Can always move to explicit mode
4. **Full Power Available**: All features accessible at every stage
5. **Developer Joy**: Make the simple things simple, complex things possible
