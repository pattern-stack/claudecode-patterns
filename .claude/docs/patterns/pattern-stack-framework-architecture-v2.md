# Pattern Stack Framework Architecture V2

## Overview

Pattern Stack is an importable Python framework that enforces Atomic Architecture while providing base classes for complete feature vertical slices (model, service, schemas), automatic API/CLI generation, and built-in domains.

## Core Insight: Features as Complete Vertical Slices

A "feature" in Pattern Stack is not just a service - it's a complete vertical slice including:
- **Model** (SQLAlchemy)
- **Schemas** (Pydantic for input/output/internal)
- **Service** (Business logic)
- **Repository** (Optional, often merged with service)

Our base classes need to support this full structure.

## Revised Base Class Architecture

### Complete Feature Base Classes

```python
# pattern_stack/base/features/__init__.py
from .transactional import TransactionalFeature, TransactionalModel, TransactionalSchema
from .catalog import CatalogFeature, CatalogModel, CatalogSchema
from .user_type import UserTypeFeature, UserTypeModel, UserTypeSchema
```

#### Transactional Feature Package

```python
# pattern_stack/base/features/transactional.py
from pattern_stack.atoms.data import Base, Model
from pattern_stack.atoms.shared.events import emit_event
from pydantic import BaseModel
from sqlalchemy import Column, String, DateTime, Decimal, Enum
from typing import Generic, TypeVar
import enum

class TransactionState(str, enum.Enum):
    """Standard transaction states."""
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"

class TransactionalModel(Base):
    """Base SQLAlchemy model for transactional entities."""
    __abstract__ = True

    # Standard transactional fields
    state = Column(Enum(TransactionState), default=TransactionState.PENDING)
    amount = Column(Decimal(10, 2))
    currency = Column(String(3), default="USD")

    # Audit fields
    created_by = Column(String)
    updated_by = Column(String)
    processed_at = Column(DateTime)

    # Relationships (to be extended)
    # parent_id for linked transactions
    # items for line items

class TransactionalSchema:
    """Base schemas for transactional entities."""

    class Input(BaseModel):
        """Base input schema."""
        amount: Decimal
        currency: str = "USD"
        metadata: dict = {}

    class Output(BaseModel):
        """Base output schema."""
        id: UUID
        state: TransactionState
        amount: Decimal
        currency: str
        created_at: datetime
        updated_at: datetime

    class Internal(BaseModel):
        """Internal processing schema."""
        state_history: List[dict]
        audit_trail: List[dict]

T = TypeVar('T', bound=TransactionalModel)

class TransactionalService(Generic[T]):
    """Complete service for transactional features."""

    model: Type[T]  # SQLAlchemy model class

    def __init__(self, session):
        self.session = session

    async def create_transaction(self, data: TransactionalSchema.Input) -> T:
        """Create transaction with events and audit."""
        # Emit pre-creation event
        await emit_event(f"{self.model.__tablename__}.creating", data.dict())

        # Create transaction
        transaction = self.model(**data.dict())
        self.session.add(transaction)

        # Create audit entry
        await self._create_audit_entry("created", transaction)

        # Emit post-creation event
        await emit_event(f"{self.model.__tablename__}.created", transaction.id)

        await self.session.commit()
        return transaction

    async def transition_state(
        self,
        transaction_id: UUID,
        new_state: TransactionState,
        reason: str = None
    ) -> T:
        """Handle state transitions with validation."""
        transaction = await self.get(transaction_id)

        # Validate transition
        if not self._is_valid_transition(transaction.state, new_state):
            raise InvalidStateTransition(
                f"Cannot transition from {transaction.state} to {new_state}"
            )

        # Update state
        old_state = transaction.state
        transaction.state = new_state

        # Record in audit trail
        await self._create_audit_entry("state_changed", {
            "from": old_state,
            "to": new_state,
            "reason": reason
        })

        # Emit event
        await emit_event(f"{self.model.__tablename__}.state_changed", {
            "id": transaction_id,
            "from": old_state,
            "to": new_state
        })

        await self.session.commit()
        return transaction

    def _is_valid_transition(self, from_state: TransactionState, to_state: TransactionState) -> bool:
        """Validate state machine transitions."""
        valid_transitions = {
            TransactionState.PENDING: [TransactionState.PROCESSING, TransactionState.CANCELLED],
            TransactionState.PROCESSING: [TransactionState.COMPLETED, TransactionState.FAILED],
            TransactionState.FAILED: [TransactionState.PROCESSING, TransactionState.CANCELLED],
            # Completed and Cancelled are terminal states
        }
        return to_state in valid_transitions.get(from_state, [])

# Convenience class that bundles everything
class TransactionalFeature:
    """Complete transactional feature with model, schemas, and service."""
    Model = TransactionalModel
    Schema = TransactionalSchema
    Service = TransactionalService
```

### How Users Extend These Base Classes

```python
# my_app/features/orders/models.py
from pattern_stack.base.features import TransactionalModel
from sqlalchemy import Column, String, ForeignKey
from sqlalchemy.orm import relationship

class Order(TransactionalModel):
    """Order model extending transactional base."""
    __tablename__ = "orders"

    # Additional order-specific fields
    customer_id = Column(UUID, ForeignKey("customers.id"))
    shipping_address = Column(String)

    # Relationships
    customer = relationship("Customer", back_populates="orders")
    items = relationship("OrderItem", back_populates="order")
```

```python
# my_app/features/orders/schemas.py
from pattern_stack.base.features import TransactionalSchema
from pydantic import BaseModel
from typing import List

class OrderSchema(TransactionalSchema):
    """Order schemas extending transactional base."""

    class Input(TransactionalSchema.Input):
        """Order creation input."""
        customer_id: UUID
        shipping_address: str
        items: List[dict]

    class Output(TransactionalSchema.Output):
        """Order response."""
        customer_id: UUID
        shipping_address: str
        item_count: int
        total: Decimal
```

```python
# my_app/features/orders/service.py
from pattern_stack.base.features import TransactionalService
from .models import Order
from .schemas import OrderSchema

class OrderService(TransactionalService[Order]):
    """Order service with transactional capabilities."""

    model = Order

    async def create_order(self, data: OrderSchema.Input) -> Order:
        """Create order with additional validation."""
        # Validate customer exists
        customer = await self._validate_customer(data.customer_id)

        # Validate items in stock
        await self._validate_inventory(data.items)

        # Use base transaction creation with events
        order = await self.create_transaction(data)

        # Create order items
        await self._create_order_items(order.id, data.items)

        return order

    async def ship_order(self, order_id: UUID) -> Order:
        """Ship order using state transition."""
        # Validate shipping prerequisites
        order = await self.get(order_id)
        if not order.shipping_address:
            raise ValueError("Shipping address required")

        # Use base state transition with events
        return await self.transition_state(
            order_id,
            TransactionState.PROCESSING,
            reason="Order shipped"
        )
```

## Auto-Discovery and Registration

Instead of decorators in main.py, the framework auto-discovers classes:

```python
# pattern_stack/core/discovery.py
import inspect
import importlib
from pathlib import Path

class ComponentDiscovery:
    """Auto-discover Pattern Stack components."""

    def discover_features(self, package_path: str) -> Dict[str, Type]:
        """Find all classes extending base features."""
        features = {}

        # Walk through features directory
        features_path = Path(package_path) / "features"
        for feature_dir in features_path.iterdir():
            if feature_dir.is_dir() and not feature_dir.name.startswith("_"):
                # Import service module
                module_name = f"{package_path}.features.{feature_dir.name}.service"
                try:
                    module = importlib.import_module(module_name)

                    # Find classes extending our base services
                    for name, obj in inspect.getmembers(module, inspect.isclass):
                        if issubclass(obj, (TransactionalService, CatalogService, UserTypeService)):
                            features[name] = obj
                            print(f"Discovered feature: {name}")
                except ImportError:
                    continue

        return features
```

## Simplified Main Application

```python
# my_app/main.py
from pattern_stack import PatternStack

# Just create and run - everything is auto-discovered
app = PatternStack(
    name="My E-Commerce App",
    package="my_app",              # Where to discover components
    domains=['auth', 'users'],     # Enable built-in domains
    auto_api=True,                 # Generate APIs from features
    auto_cli=True,                 # Generate CLI commands
)

if __name__ == "__main__":
    app.run()  # Auto-discovers all features, molecules, and starts server
```

## CLI Scaffolding with Full Structure

```bash
# Generate complete transactional feature
pattern-stack generate feature orders --type transactional

# Creates:
# features/orders/
#   ├── __init__.py
#   ├── models.py       # Extends TransactionalModel
#   ├── schemas.py      # Extends TransactionalSchema
#   ├── service.py      # Extends TransactionalService
#   └── __tests__/
#       ├── test_models.py
#       ├── test_service.py
#       └── test_integration.py
```

## Benefits of This Approach

1. **Complete Vertical Slices**: Base classes provide the full stack (model, schema, service)
2. **Auto-Discovery**: No manual registration needed - just extend base classes
3. **Consistent Structure**: Every feature follows the same pattern
4. **Built-in Functionality**: State machines, events, audit trails come for free
5. **Type Safety**: Full typing with generics throughout
6. **Testing Support**: Base test classes for each component type

## Questions to Resolve

1. **Schema Inheritance**: Should we provide base schemas or let users define their own?
2. **Repository Pattern**: Should we have separate repository classes or merge with service? NOTE: No - we're going to build a reporting service/layer later that will manage this automatically so for now it's just crud and basic operations but no reporting
3. **Model Mixins**: Should common patterns be mixins (TimestampMixin, AuditMixin) or base classes? Note: yes - this is a good idea. Default to it but allow override to remove probably, we generally want audit and created at to be there always. Though i think we have this as part of base already.
4. **Discovery Scope**: Should we discover only in `features/` or scan the entire package? NOTE: Probaly starting just features - do we need to scan? Any way to just infer based on the inheritance? not sure
5. **Override Mechanism**: How do users override auto-generated APIs? NOTE: Not sure - let's chat about it

## Next Evolution

This architecture can evolve to support:
- Automatic GraphQL schema generation
- gRPC service generation
- Event sourcing patterns
- CQRS with separate read/write models
- Multi-tenancy support
