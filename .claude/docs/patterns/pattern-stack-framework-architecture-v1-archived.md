# Pattern Stack Framework Architecture

## Overview

Pattern Stack is an importable Python framework that enforces Atomic Architecture while providing base classes, automatic API/CLI generation, and built-in domains for rapid application development.

## Core Concept

**Users write features and molecules, Pattern Stack generates everything else.**

## Package Structure

```
pattern_stack/
├── __init__.py          # Main PatternStack class
├── base/               # Base classes for users to extend
│   ├── features.py     # TransactionalFeature, CatalogFeature, etc
│   ├── molecules.py    # Entity bases with common patterns
│   └── organisms.py    # AutoAPI, AutoCLI
├── decorators/         # @feature, @molecule, @organism
├── domains/            # Built-in complete domains
│   ├── auth/          # Complete auth implementation
│   └── users/         # Complete user management
├── types/             # Domain-specific types
│   ├── money.py       # Money, Currency types
│   ├── contact.py     # Email, Phone types
│   └── temporal.py    # DateRange, Schedule types
├── testing/           # Test utilities
│   ├── fixtures.py
│   ├── factories.py
│   └── testcase.py
└── cli/               # CLI implementation
    ├── init.py        # Project initialization
    ├── generate.py    # Code generation
    └── validate.py    # Architecture validation
```

## Import Strategy

```python
# User application imports
from pattern_stack import PatternStack                           # Core
from pattern_stack.base import TransactionalFeature, CatalogEntity  # Base classes
from pattern_stack.decorators import feature, molecule, organism    # Registration
from pattern_stack.testing import TestCase, Factory, fixtures       # Testing
from pattern_stack.domains import auth, users                       # Built-in domains
from pattern_stack.types import Money, Email, PhoneNumber          # Domain types
```

## Base Class Hierarchy

### Feature Base Classes

```python
# pattern_stack/base/features.py
from typing import Generic, TypeVar, Optional
from ..atoms.data import Model
from ..atoms.shared.events import emit_event

T = TypeVar('T', bound=Model)

class TransactionalFeature(Generic[T]):
    """
    Base for transactional entities (payments, orders, invoices).
    Provides automatic event emission, audit trails, and state management.
    """

    model: T

    async def create_transaction(self, data: dict) -> T:
        """Create with automatic event emission."""
        # Pre-transaction hook
        await emit_event(f"{self.model.__name__}.creating", data)

        # Create transaction
        transaction = await self._create(data)

        # Automatic audit trail
        await self._create_audit_entry("created", transaction)

        # Post-transaction event
        await emit_event(f"{self.model.__name__}.created", transaction)

        return transaction

    async def transition_state(self, id: str, new_state: str) -> T:
        """State machine transitions with validation."""
        transaction = await self.get(id)

        # Validate state transition
        if not self._is_valid_transition(transaction.state, new_state):
            raise InvalidStateTransition()

        # Update with events
        transaction.state = new_state
        await self.update(transaction)
        await emit_event(f"{self.model.__name__}.state_changed", {
            "id": id,
            "from": transaction.state,
            "to": new_state
        })

        return transaction

class CatalogFeature(Generic[T]):
    """
    Base for catalog items (products, services, SKUs).
    Provides categorization, variants, pricing.
    """

    async def get_by_category(self, category: str) -> List[T]:
        """Get items by category with caching."""
        pass

    async def update_pricing(self, id: str, pricing: dict) -> T:
        """Update pricing with history tracking."""
        pass

class UserTypeFeature(Generic[T]):
    """
    Base for user-related entities (customers, employees, vendors).
    Provides profile management, permissions, preferences.
    """

    async def get_by_email(self, email: str) -> Optional[T]:
        """Get user by email with caching."""
        pass

    async def update_permissions(self, id: str, permissions: List[str]) -> T:
        """Update user permissions with audit."""
        pass

class TemporalFeature(Generic[T]):
    """
    Base for time-based data (schedules, appointments, events).
    Provides recurrence, timezone handling, conflict detection.
    """

    async def get_by_date_range(self, start: datetime, end: datetime) -> List[T]:
        """Get items within date range."""
        pass

    async def check_conflicts(self, item: T) -> List[T]:
        """Check for scheduling conflicts."""
        pass

class HierarchicalFeature(Generic[T]):
    """
    Base for tree structures (categories, organizations, folders).
    Provides parent-child relationships, path operations.
    """

    async def get_children(self, parent_id: str) -> List[T]:
        """Get child nodes."""
        pass

    async def get_ancestors(self, node_id: str) -> List[T]:
        """Get all ancestors up to root."""
        pass
```

### Molecule Base Classes

```python
# pattern_stack/base/molecules.py

class TransactionalEntity:
    """
    Entity for handling transactions with automatic events and audit.
    """

    def __init__(self, service: TransactionalFeature):
        self.service = service

    async def process_payment(self, transaction_id: str, payment_data: dict):
        """Process payment with state transitions."""
        await self.service.transition_state(transaction_id, "processing")
        # Payment logic
        await self.service.transition_state(transaction_id, "completed")

class CatalogEntity:
    """
    Entity for product/service catalog management.
    """

    def __init__(self, service: CatalogFeature):
        self.service = service

    async def apply_discount(self, product_id: str, discount: float):
        """Apply discount with pricing history."""
        product = await self.service.get(product_id)
        new_price = product.price * (1 - discount)
        await self.service.update_pricing(product_id, {"price": new_price})

class UserTypeEntity:
    """
    Entity for user management with profiles and permissions.
    """

    def __init__(self, service: UserTypeFeature):
        self.service = service

    async def grant_role(self, user_id: str, role: str):
        """Grant role with permission updates."""
        permissions = self._get_role_permissions(role)
        await self.service.update_permissions(user_id, permissions)

class WorkflowEntity:
    """
    Base for multi-step business processes.
    """

    steps: List[str] = []

    async def execute(self, context: dict):
        """Execute workflow steps in order."""
        for step in self.steps:
            method = getattr(self, f"step_{step}")
            context = await method(context)
        return context
```

## Framework Core

### PatternStack Application Class

```python
# pattern_stack/__init__.py

class PatternStack:
    """
    Main framework class for Pattern Stack applications.

    Example:
        app = PatternStack(
            name="My E-Commerce App",
            domains=['auth', 'users'],  # Built-in functionality
            auto_api=True,              # Auto-generate REST endpoints
            auto_cli=True,              # Auto-generate CLI commands
        )

        @app.feature
        class OrderService(TransactionalFeature):
            model = Order

        @app.molecule
        class CheckoutWorkflow(WorkflowEntity):
            steps = ['cart', 'shipping', 'payment', 'confirmation']

        app.run()  # Starts FastAPI with uvicorn
    """

    def __init__(
        self,
        name: str,
        domains: List[str] = None,
        auto_api: bool = True,
        auto_cli: bool = False,
        strict_mode: bool = True,
    ):
        self.name = name
        self.domains = domains or []
        self.auto_api = auto_api
        self.auto_cli = auto_cli
        self.strict_mode = strict_mode

        # Component registries
        self.features = {}
        self.molecules = {}
        self.organisms = {}

        # Core framework components
        self.loader = AtomicLoader()
        self.registry = DomainRegistry()
        self.validator = ArchitectureValidator() if strict_mode else None

        # Enable built-in domains
        self._enable_domains()

    def _enable_domains(self):
        """Enable built-in domains like auth and users."""
        for domain in self.domains:
            if domain == 'auth':
                from .domains.auth import enable_auth
                enable_auth(self)
            elif domain == 'users':
                from .domains.users import enable_users
                enable_users(self)

    def feature(self, cls):
        """Decorator to register a feature."""
        if self.strict_mode:
            self._validate_feature(cls)

        self.features[cls.__name__] = cls

        if self.auto_api:
            self._generate_api_for_feature(cls)
        if self.auto_cli:
            self._generate_cli_for_feature(cls)

        return cls

    def molecule(self, cls):
        """Decorator to register a molecule."""
        if self.strict_mode:
            self._validate_molecule(cls)

        self.molecules[cls.__name__] = cls

        if self.auto_api:
            self._generate_api_for_molecule(cls)
        if self.auto_cli:
            self._generate_cli_for_molecule(cls)

        return cls

    def run(self, host: str = "0.0.0.0", port: int = 8000):
        """Start the application with uvicorn."""
        import uvicorn
        app = self._create_fastapi_app()
        uvicorn.run(app, host=host, port=port)

    def _create_fastapi_app(self) -> FastAPI:
        """Create FastAPI application with all components."""
        from fastapi import FastAPI

        app = FastAPI(title=self.name)

        # Add framework middleware
        self._setup_middleware(app)

        # Add health endpoints
        self._setup_health_endpoints(app)

        # Register all organism routers
        for organism in self.organisms.values():
            if hasattr(organism, 'router'):
                app.include_router(organism.router)

        return app
```

## Automatic API Generation

```python
# pattern_stack/base/organisms.py

class AutoAPI:
    """Automatically generates REST endpoints from molecules."""

    def __init__(self, molecule: BaseEntity):
        self.molecule = molecule
        self.router = self._generate_router()

    def _generate_router(self) -> APIRouter:
        """Generate CRUD + workflow endpoints."""
        from fastapi import APIRouter

        router = APIRouter(
            prefix=f"/api/v1/{self.molecule.__class__.__name__.lower()}",
            tags=[self.molecule.__class__.__name__]
        )

        # Auto-generate CRUD endpoints
        router.add_api_route("/", self.list, methods=["GET"])
        router.add_api_route("/{id}", self.get, methods=["GET"])
        router.add_api_route("/", self.create, methods=["POST"])
        router.add_api_route("/{id}", self.update, methods=["PUT"])
        router.add_api_route("/{id}", self.delete, methods=["DELETE"])

        # Auto-generate workflow endpoints
        if hasattr(self.molecule, 'workflows'):
            for workflow in self.molecule.workflows:
                router.add_api_route(
                    f"/workflows/{workflow.name}",
                    workflow.execute,
                    methods=["POST"]
                )

        return router

    async def list(self, skip: int = 0, limit: int = 100):
        """List all items."""
        return await self.molecule.service.list(skip=skip, limit=limit)

    async def get(self, id: str):
        """Get single item."""
        return await self.molecule.service.get(id)

    async def create(self, data: dict):
        """Create new item."""
        return await self.molecule.service.create(data)

    async def update(self, id: str, data: dict):
        """Update existing item."""
        return await self.molecule.service.update(id, data)

    async def delete(self, id: str):
        """Delete item."""
        return await self.molecule.service.delete(id)
```

## User Application Structure

Applications using Pattern Stack mirror the framework's atomic structure:

```
my_app/
├── __init__.py
├── atoms/                 # App-specific atoms (if needed)
│   └── integrations/     # External service integrations
│       └── stripe.py
├── features/             # Core data models
│   ├── __init__.py
│   ├── orders/
│   │   ├── __init__.py
│   │   ├── models.py     # SQLAlchemy models
│   │   └── service.py    # Extends TransactionalFeature
│   ├── products/
│   │   ├── models.py
│   │   └── service.py    # Extends CatalogFeature
│   └── customers/
│       ├── models.py
│       └── service.py    # Extends UserTypeFeature
├── molecules/            # Business logic
│   ├── __init__.py
│   ├── checkout/        # Checkout workflow
│   │   ├── __init__.py
│   │   ├── entity.py    # CheckoutEntity
│   │   └── workflows.py # Multi-step checkout
│   └── inventory/
│       ├── entity.py
│       └── workflows.py
├── organisms/            # (Optional - often auto-generated)
│   └── api/
│       └── overrides.py # Custom endpoint overrides
└── main.py              # Application entry point
```

### Example Application

```python
# my_app/main.py
from pattern_stack import PatternStack
from pattern_stack.base import TransactionalFeature, CatalogFeature, WorkflowEntity
from pattern_stack.types import Money, Email

# Import your models
from .features.orders.models import Order
from .features.products.models import Product

# Create app with built-in domains
app = PatternStack(
    name="My E-Commerce App",
    domains=['auth', 'users'],  # Built-in functionality
    auto_api=True,              # Auto-generate REST endpoints
    auto_cli=True,              # Auto-generate CLI commands
)

# Register your features (extending base classes)
@app.feature
class OrderService(TransactionalFeature):
    """Order management with automatic events and audit."""
    model = Order

    # Additional custom methods
    async def calculate_total(self, order_id: str) -> Money:
        order = await self.get(order_id)
        return sum(item.price * item.quantity for item in order.items)

@app.feature
class ProductService(CatalogFeature):
    """Product catalog with categories and variants."""
    model = Product

    async def get_featured(self) -> List[Product]:
        """Get featured products."""
        return await self.query(featured=True)

# Register molecules
@app.molecule
class CheckoutWorkflow(WorkflowEntity):
    """Multi-step checkout process."""
    steps = ['validate_cart', 'calculate_shipping', 'process_payment', 'send_confirmation']

    def __init__(self, orders: OrderService, products: ProductService):
        self.orders = orders
        self.products = products

    async def step_validate_cart(self, context: dict):
        """Validate cart items are in stock."""
        # Implementation
        return context

    async def step_calculate_shipping(self, context: dict):
        """Calculate shipping costs."""
        # Implementation
        return context

    async def step_process_payment(self, context: dict):
        """Process payment transaction."""
        # Implementation
        return context

    async def step_send_confirmation(self, context: dict):
        """Send order confirmation."""
        # Implementation
        return context

# The framework automatically:
# 1. Generates CRUD endpoints for all features
# 2. Creates CLI commands for management
# 3. Sets up event streams
# 4. Configures audit logging
# 5. Validates architecture

if __name__ == "__main__":
    app.run()  # Starts FastAPI with uvicorn
```

## CLI Scaffolding System

```bash
# Initialize new project with Pattern Stack structure
pattern-stack init my-store --type ecommerce
# Creates:
# - my-store/
#   ├── atoms/
#   ├── features/
#   ├── molecules/
#   ├── main.py (configured)
#   └── settings.py

# Generate a new transactional feature
pattern-stack generate feature invoices --type transactional
# Creates:
# - features/invoices/models.py (with Invoice model)
# - features/invoices/service.py (extending TransactionalFeature)
# - features/invoices/__tests__/

# Generate molecule with workflow
pattern-stack generate molecule returns --with-workflow
# Creates:
# - molecules/returns/entity.py
# - molecules/returns/workflows.py (with ReturnWorkflow)
# - molecules/returns/__tests__/

# The CLI understands your app structure
pattern-stack list features  # Shows all registered features
pattern-stack list molecules  # Shows all molecules
pattern-stack validate       # Checks architecture rules
```

## Built-in Domains

### Auth Domain

```python
# pattern_stack/domains/auth/__init__.py
"""Built-in authentication domain."""

def enable_auth(app: PatternStack):
    """Enable authentication domain in the application."""
    from .features import AuthService
    from .molecules import AuthEntity, AuthWorkflows
    from .organisms import AuthAPI

    # Register with the framework
    app.register_feature(AuthService)
    app.register_molecule(AuthEntity)
    app.register_molecule(AuthWorkflows)
    app.register_organism(AuthAPI)

    # Configure middleware
    from .middleware import JWTMiddleware
    app.add_middleware(JWTMiddleware)

    # Add auth-specific CLI commands
    if app.auto_cli:
        from .cli import auth_commands
        app.add_cli_group(auth_commands)
```

### Users Domain

```python
# pattern_stack/domains/users/__init__.py
"""Built-in user management domain."""

def enable_users(app: PatternStack):
    """Enable user management domain."""
    from .features import UserService
    from .molecules import UserEntity, UserWorkflows
    from .organisms import UserAPI

    # Register components
    app.register_feature(UserService)
    app.register_molecule(UserEntity)
    app.register_molecule(UserWorkflows)
    app.register_organism(UserAPI)

    # Add user management CLI
    if app.auto_cli:
        from .cli import user_commands
        app.add_cli_group(user_commands)
```

## Implementation Plan

### Phase 1: Core Framework (Week 1)

**BE-10: PatternStack Core Class**
- Implement `pattern_stack/__init__.py` with PatternStack class
- Auto-discovery and registration system
- Domain enablement mechanism
- Auto API/CLI generation flags

**BE-11: Base Class Library**
- Create `pattern_stack/base/` module
- Implement TransactionalFeature, CatalogFeature, UserTypeFeature
- Build TransactionalEntity, CatalogEntity, WorkflowEntity
- Add automatic event emission and audit trails

**BE-12: Decorator System**
- Create `pattern_stack/decorators/` module
- Implement @feature, @molecule, @organism decorators
- Add import validation for strict_mode
- Hook into registration system

### Phase 2: Auto-Generation (Week 2)

**BE-13: Automatic API Generation**
- Implement AutoAPI in `base/organisms.py`
- Generate CRUD from features
- Generate workflow endpoints from molecules
- OpenAPI schema generation

**BE-14: Automatic CLI Generation**
- Implement AutoCLI in `base/organisms.py`
- Generate management commands from features
- Generate workflow commands from molecules

### Phase 3: Built-in Domains (Week 3)

**BE-15: Auth Domain Package**
- Move auth to `domains/auth/`
- Implement as complete vertical slice
- Use framework base classes
- Enable via `domains=['auth']`

**BE-16: Users Domain Package**
- Move users to `domains/users/`
- Extend UserTypeFeature base
- Integrate with auth domain
- Profile management workflows

### Phase 4: Developer Tools (Week 4)

**BE-17: CLI Scaffolding Tool**
- `pattern-stack init` command
- `pattern-stack generate` for components
- Template system for different app types
- Architecture validation command

**BE-18: Domain Types Library**
- Create `pattern_stack/types/`
- Money, Currency types with validation
- Email, Phone with formatting
- DateRange, Schedule for temporal data

## Key Architectural Decisions

1. **Import Strategy**: Structured paths (`pattern_stack.base`, `pattern_stack.decorators`) with clear organization
2. **Base Classes**: Common patterns (Transactional, Catalog, UserType) with built-in functionality
3. **Auto-Generation**: Features and molecules automatically generate APIs and CLIs
4. **Built-in Domains**: Self-contained auth/users that can be enabled via configuration
5. **Architecture Enforcement**: Decorators + strict_mode for import validation
6. **User Focus**: Users write features and molecules, framework handles the rest

## Next Steps

1. Update BE-4 to implement PatternStack core class
2. Create Linear tickets BE-10 through BE-18
3. Begin implementation with core framework components
4. Iterate based on feedback and requirements
