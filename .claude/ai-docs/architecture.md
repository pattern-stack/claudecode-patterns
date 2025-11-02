# Atomic Architecture v2.5.1
## Advanced Pattern Stack Framework for Enterprise Applications

### Changelog

#### Version 2.5.1 (2025-01-06)
- **CLARIFIED**: Entity vs Workflow separation in Molecules layer
- **ADDED**: Explicit single-domain vs multi-domain rule
- **REFINED**: Entity ownership model (one service per entity)
- **IMPROVED**: Decision tree for entity vs workflow placement
- **UPDATED**: Examples to demonstrate proper separation

### Table of Contents
1. [Philosophy & Core Principles](#philosophy--core-principles)
2. [Architecture Overview](#architecture-overview)
3. [Layer Definitions](#layer-definitions)
4. [Pattern System](#pattern-system)
5. [Services vs Domain Entities](#services-vs-domain-entities)
6. [Data Flow Patterns](#data-flow-patterns)
7. [Schema Architecture](#schema-architecture)
8. [Testing Architecture](#testing-architecture)
9. [Implementation Patterns](#implementation-patterns)
10. [Common Patterns & Anti-Patterns](#common-patterns--anti-patterns)
11. [Advanced Patterns](#advanced-patterns)
12. [Migration Guide](#migration-guide)
13. [Reference Implementation](#reference-implementation)

---

## Philosophy & Core Principles

### Core Tenets

1. **Unidirectional Dependencies**: Dependencies flow downward only (Organisms → Molecules → Features → Atoms)
2. **Single Responsibility**: Each layer has one clear, focused purpose
3. **Clean Boundaries**: No business logic in models, no permissions in services
4. **Explicit Over Implicit**: Clear imports, no magic, predictable behavior
5. **Composition Over Inheritance**: Combine simple pieces over complex hierarchies
6. **Testability First**: Every component must be independently testable
7. **Pattern-Based Architecture**: Reusable patterns for common enterprise needs
8. **Type Safety**: Full type hints with runtime validation

### The Five Questions

Every architectural decision should answer:
1. **Where does this belong?** (Which layer?)
2. **What pattern should it use?** (Base, Catalog, Actor, Temporal, Hierarchical)
3. **What can it import?** (Dependency rules)
4. **Who can use it?** (Consumer rules)
5. **How is it tested?** (Testing strategy)

### The Service/Entity/Pattern Trinity

- **Patterns (Atoms)**: Reusable behaviors and capabilities
- **Services (Features)**: Handle data operations for specific tables/models
- **Domain Entities (Molecules)**: Compose multiple services into cohesive business objects
- **Workflows (Molecules)**: Orchestrate operations across multiple entities
- **APIs (Organisms)**: Expose functionality through various interfaces

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        ORGANISMS                             │
│                    (User Interfaces)                         │
│    • HTTP APIs  • GraphQL  • CLI  • WebSockets  • MCP       │
│    • Dependencies  • Middleware  • Authentication           │
└────────────────────────┬────────────────────────────────────┘
                         │ exposes
┌────────────────────────▼────────────────────────────────────┐
│                       MOLECULES                              │
│              (Domain Entities & Workflows)                   │
│    • entities/  - Composed domain objects                   │
│    • apis/      - Permission facades                        │
│    • workflows/ - Cross-entity orchestration                │
│    • aggregates/ - Complex domain aggregates                │
└────────────────────────┬────────────────────────────────────┘
                         │ uses
┌────────────────────────▼────────────────────────────────────┐
│                       FEATURES                               │
│                   (Data Services)                            │
│    • Models (with patterns)  • Schemas  • Services          │
│    • Repositories  • Queries  • Commands                    │
└────────────────────────┬────────────────────────────────────┘
                         │ uses
┌────────────────────────▼────────────────────────────────────┐
│                        ATOMS                                 │
│                 (Foundation Layer)                           │
│    • Patterns  • Shared  • Data  • Security                │
│    • Config  • Validators  • API  • Cache  • Events         │
└─────────────────────────────────────────────────────────────┘
```

---

## Layer Definitions

### 1. Atoms Layer - Foundation Building Blocks

**Purpose**: Provide reusable, domain-agnostic utilities, patterns, and base functionality

**Structure**:
```
app/atoms/
├── patterns/                # Reusable behavioral patterns
│   ├── base.py             # BasePattern with change tracking
│   ├── catalog.py          # CatalogPattern for reference data
│   ├── actor.py            # ActorPattern for entity ownership
│   ├── temporal.py         # TemporalPattern for time-based data
│   ├── hierarchical.py     # HierarchicalPattern for tree structures
│   └── mixins.py           # Pattern mixins and utilities
├── shared/                  # Core dependencies
│   ├── settings.py         # Application configuration
│   ├── events.py           # Event system and pub/sub
│   ├── infra.py            # Infrastructure utilities
│   └── dependencies.py     # Dependency injection
├── data/                    # Database layer
│   ├── base.py             # SQLAlchemy Base
│   ├── session.py          # Session management
│   ├── mixins.py           # Reusable model mixins
│   ├── types.py            # Custom SQLAlchemy types
│   └── repositories.py     # Base repository patterns
├── models/                  # Shared domain types
│   ├── enums.py            # Application-wide enums
│   ├── types.py            # Custom type definitions
│   └── value_objects.py    # Immutable value objects
├── security/                # Auth & security
│   ├── auth.py             # Authentication utilities
│   ├── hashing.py          # Password hashing
│   ├── tokens.py           # JWT handling
│   ├── permissions.py      # Permission system
│   └── rbac.py             # Role-based access control
├── validators/              # Reusable validators
│   ├── common.py           # Common field validators
│   ├── business.py         # Business rule validators
│   └── composite.py        # Complex validation rules
├── api/                     # API utilities
│   ├── pagination.py       # Pagination helpers
│   ├── responses.py        # Standard responses
│   ├── exceptions.py       # Custom exceptions
│   └── filters.py          # Query filtering
├── cache/                   # Caching infrastructure
│   ├── base.py             # Cache interfaces
│   ├── memory.py           # In-memory cache
│   └── redis.py            # Redis cache backend
└── config/                  # Configuration management
    ├── base.py             # Base configuration
    ├── development.py      # Dev settings
    ├── production.py       # Prod settings
    └── testing.py          # Test settings
```

**Import Rules**:
- `shared/` imports nothing (it's the foundation)
- `patterns/` can import from `shared/` and `data/`
- Other atoms import from `shared/` and `patterns/` only
- No cross-imports between atoms subdirectories (except into `shared/` and `patterns/`)
- No imports from features or higher layers

#### Pattern System

The pattern system provides reusable behaviors that can be mixed into models:

**BasePattern**: Foundation for all patterns with change tracking
```python
class BasePattern(Base):
    """Base pattern with change tracking and common fields."""
    __abstract__ = True

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(onupdate=datetime.utcnow)

    _changes: Dict[str, Any] = {}  # Track field changes

    @property
    def has_changes(self) -> bool:
        return bool(self._changes)
```

**CatalogPattern**: For reference data (categories, types, statuses)
```python
class CatalogPattern(BasePattern):
    """Pattern for catalog/reference data."""
    __abstract__ = True

    name: Mapped[str] = mapped_column(String(100), unique=True)
    code: Mapped[str] = mapped_column(String(50), unique=True)
    description: Mapped[Optional[str]] = mapped_column(Text)
    display_order: Mapped[int] = mapped_column(default=0)
    is_active: Mapped[bool] = mapped_column(default=True)
    metadata: Mapped[Dict] = mapped_column(JSON, default=dict)
```

**ActorPattern**: For entities with ownership/authorship
```python
class ActorPattern(BasePattern):
    """Pattern for entities with actors/owners."""
    __abstract__ = True

    actor_type: Mapped[ActorType] = mapped_column(Enum(ActorType))
    actor_id: Mapped[UUID] = mapped_column(index=True)
    created_by: Mapped[UUID] = mapped_column()
    updated_by: Mapped[Optional[UUID]] = mapped_column()

    @validates('actor_type')
    def validate_actor_type(self, key, value):
        """Ensure actor_type is set for the specific model."""
        if not value:
            # Auto-set based on model class
            return self.__class__.__actor_type__
        return value
```

**TemporalPattern**: For time-series and historical data
```python
class TemporalPattern(BasePattern):
    """Pattern for temporal/time-based data."""
    __abstract__ = True

    valid_from: Mapped[datetime] = mapped_column(default=datetime.utcnow)
    valid_to: Mapped[Optional[datetime]] = mapped_column()
    is_current: Mapped[bool] = mapped_column(default=True)
    version: Mapped[int] = mapped_column(default=1)

    @property
    def is_valid(self) -> bool:
        now = datetime.utcnow()
        return (self.valid_from <= now and
                (self.valid_to is None or self.valid_to > now))
```

**HierarchicalPattern**: For tree structures and nested entities
```python
class HierarchicalPattern(BasePattern):
    """Pattern for hierarchical/tree structures."""
    __abstract__ = True

    parent_id: Mapped[Optional[UUID]] = mapped_column(ForeignKey('self.id'))
    path: Mapped[str] = mapped_column(Text)  # Materialized path
    depth: Mapped[int] = mapped_column(default=0)
    position: Mapped[int] = mapped_column(default=0)

    # Relationships
    parent: Mapped[Optional['Self']] = relationship(back_populates='children')
    children: Mapped[List['Self']] = relationship(back_populates='parent')

    @property
    def ancestors(self) -> List[UUID]:
        """Get ancestor IDs from path."""
        if not self.path:
            return []
        return [UUID(id) for id in self.path.split('/') if id]

    def add_child(self, child: 'Self') -> None:
        """Add a child with proper path management."""
        child.parent_id = self.id
        child.path = f"{self.path}/{self.id}" if self.path else str(self.id)
        child.depth = self.depth + 1
```

### 2. Features Layer - Data Services

**Purpose**: Implement data operations for specific database models using patterns

**Structure**:
```
app/features/{feature}/
├── __init__.py              # Public exports
├── models.py                # SQLAlchemy models using patterns
├── schemas/                 # Pydantic schemas (organized by type)
│   ├── __init__.py         # Re-exports all schemas
│   ├── input.py            # Input schemas (Create, Update, Filter)
│   ├── internal.py         # Internal schemas (InDB)
│   ├── output.py           # Output schemas (Response, Summary, Reference)
│   └── specialized.py      # Specialized schemas (Stats, Export, etc.)
├── service.py               # Data operations for this model
├── repository.py            # Complex queries (optional)
├── queries.py               # Query builders (optional)
└── commands.py              # Command handlers (optional)
```

**Key Principles**:
- **Models**: Use patterns for common behaviors, pure data representation
- **Services**: Data operations ONLY for their specific model
- **No Cross-Feature Logic**: Services don't know about other features
- **No Permissions**: Services assume permission to operate
- **Pattern Usage**: Models inherit from appropriate patterns

**Import Rules**:
- Import from atoms layer only (especially patterns)
- No imports from other features
- No imports from molecules or organisms

#### Example Feature Using Patterns

```python
# features/category/models.py
from app.atoms.patterns.catalog import CatalogPattern
from app.atoms.patterns.actor import ActorPattern
from sqlalchemy import String, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

class Category(CatalogPattern, ActorPattern):
    """Category model using Catalog and Actor patterns."""
    __tablename__ = "categories"
    __actor_type__ = ActorType.HOUSEHOLD  # Categories owned by households

    # Additional fields beyond patterns
    icon: Mapped[Optional[str]] = mapped_column(String(50))
    color: Mapped[Optional[str]] = mapped_column(String(7))  # Hex color
    budget_limit: Mapped[Optional[Decimal]] = mapped_column(Numeric(10, 2))

# features/transaction/models.py
from app.atoms.patterns.base import BasePattern
from app.atoms.patterns.temporal import TemporalPattern
from app.atoms.patterns.actor import ActorPattern

class Transaction(BasePattern, TemporalPattern, ActorPattern):
    """Financial transaction using multiple patterns."""
    __tablename__ = "transactions"
    __actor_type__ = ActorType.USER  # Transactions owned by users

    amount: Mapped[Decimal] = mapped_column(Numeric(10, 2))
    description: Mapped[str] = mapped_column(Text)
    category_id: Mapped[UUID] = mapped_column(ForeignKey("categories.id"))
    account_id: Mapped[UUID] = mapped_column(ForeignKey("accounts.id"))
    transaction_date: Mapped[datetime] = mapped_column()

    # Relationships
    category: Mapped["Category"] = relationship()
    account: Mapped["Account"] = relationship()

# features/organization/models.py
from app.atoms.patterns.hierarchical import HierarchicalPattern
from app.atoms.patterns.actor import ActorPattern

class Organization(HierarchicalPattern, ActorPattern):
    """Organization with hierarchical structure."""
    __tablename__ = "organizations"
    __actor_type__ = ActorType.SYSTEM  # System-level entities

    name: Mapped[str] = mapped_column(String(255))
    type: Mapped[OrgType] = mapped_column(Enum(OrgType))

    @property
    def full_name(self) -> str:
        """Get full hierarchical name."""
        if self.parent:
            return f"{self.parent.full_name} / {self.name}"
        return self.name
```

#### Feature Service Patterns

```python
# features/category/service.py
from typing import Optional, List
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from app.features.category.models import Category
from app.features.category.schemas import CategoryCreate, CategoryUpdate

class CategoryService:
    """Service for Category data operations."""

    async def create(
        self,
        db: AsyncSession,
        data: CategoryCreate,
        actor_id: UUID
    ) -> Category:
        """Create a new category."""
        category = Category(
            **data.model_dump(),
            actor_id=actor_id,
            created_by=actor_id
        )
        db.add(category)
        await db.commit()
        await db.refresh(category)
        return category

    async def get_by_code(
        self,
        db: AsyncSession,
        code: str,
        actor_id: Optional[UUID] = None
    ) -> Optional[Category]:
        """Get category by code, optionally filtered by actor."""
        query = select(Category).where(Category.code == code)
        if actor_id:
            query = query.where(Category.actor_id == actor_id)
        result = await db.execute(query)
        return result.scalar_one_or_none()

    async def get_active(
        self,
        db: AsyncSession,
        actor_id: UUID
    ) -> List[Category]:
        """Get all active categories for an actor."""
        result = await db.execute(
            select(Category)
            .where(Category.actor_id == actor_id)
            .where(Category.is_active == True)
            .order_by(Category.display_order, Category.name)
        )
        return result.scalars().all()

    async def update_metadata(
        self,
        db: AsyncSession,
        category: Category,
        metadata: Dict[str, Any]
    ) -> Category:
        """Update category metadata."""
        category.metadata.update(metadata)
        await db.commit()
        await db.refresh(category)
        return category
```

### 3. Molecules Layer - Domain Entities & Orchestration

**Purpose**: Compose services into domain entities, add business logic, and orchestrate complex operations

**Structure**:
```
app/molecules/
├── entities/                # Single-domain business logic
│   ├── __init__.py
│   ├── user.py             # User entity (owns UserService only)
│   ├── household.py        # Household entity (owns HouseholdService only)
│   ├── account.py          # Account entity (owns AccountService only)
│   └── transaction.py      # Transaction entity (owns TransactionService only)
├── workflows/               # Multi-domain orchestration
│   ├── __init__.py
│   ├── onboarding.py       # User + Household + Account creation
│   ├── budget_workflow.py  # Budget + Category + Transaction orchestration
│   ├── reporting.py        # Cross-domain report generation
│   └── reconciliation.py   # Account + Transaction reconciliation
├── apis/                    # Permission facades
│   ├── __init__.py
│   ├── user_api.py         # Combines user entity + workflows
│   ├── household_api.py    # Combines household entity + workflows
│   └── finance_api.py      # Combines financial entities + workflows
└── aggregates/              # Complex domain aggregates (optional)
    ├── __init__.py
    ├── budget_aggregate.py  # Budget with categories and limits
    └── portfolio.py         # Investment portfolio aggregate
```

#### Critical Design Rule: Single-Domain vs Multi-Domain

**The Core Rule**:
- **Entities**: ALL logic for a SINGLE domain (owns exactly ONE service)
- **Workflows**: EXCLUSIVELY multi-domain orchestration (uses multiple services/entities)

**Decision Tree**:
```
Does this operation touch multiple domains?
├─ NO → Entity (single domain logic)
│   └─ Examples:
│       • Validate user email format → UserEntity
│       • Calculate account balance → AccountEntity
│       • Mark transaction as reconciled → TransactionEntity
└─ YES → Workflow (multi-domain orchestration)
    └─ Examples:
        • Create user with household → OnboardingWorkflow
        • Process transaction with budget check → BudgetWorkflow
        • Generate financial report → ReportingWorkflow
```

**Key Principles**:
- **Entities**:
  - Own exactly ONE service
  - Contain ALL single-domain business logic
  - Validate, calculate, transform within their domain
  - NO orchestration of other domains
- **Workflows**:
  - Orchestrate multiple services AND/OR entities
  - NO single-domain business logic
  - Handle multi-step processes
  - Coordinate cross-domain operations
- **API Facades**:
  - Combine entities AND workflows
  - Add permission checks
  - Decide whether to call entity or workflow
- **Business Logic**: Lives in entities (single-domain) or workflows (multi-domain)

**Import Rules**:
- Import from features and atoms
- Can import from other molecules (carefully, avoid circular deps)
- No imports from organisms

#### Example Single-Domain Entities

```python
# molecules/entities/account.py
from app.features.account.service import AccountService
from decimal import Decimal

class AccountEntity:
    """Single-domain entity for account business logic.

    Owns AccountService exclusively - no other entity can use AccountService.
    """

    def __init__(self):
        self.service = AccountService()

    async def calculate_balance(
        self,
        db: AsyncSession,
        account_id: UUID
    ) -> Decimal:
        """Calculate current account balance (single-domain logic)."""
        account = await self.service.get(db, account_id)
        if not account:
            raise ValueError(f"Account {account_id} not found")

        # Business logic for balance calculation
        return account.current_balance + account.pending_credits - account.pending_debits

    async def validate_withdrawal(
        self,
        db: AsyncSession,
        account_id: UUID,
        amount: Decimal
    ) -> bool:
        """Validate if withdrawal is allowed (single-domain logic)."""
        balance = await self.calculate_balance(db, account_id)
        account = await self.service.get(db, account_id)

        # Business rules
        if account.is_frozen:
            raise ValueError("Account is frozen")
        if amount > balance:
            return False
        if amount > account.daily_limit:
            return False

        return True

# molecules/entities/transaction.py
from app.features.transaction.service import TransactionService

class TransactionEntity:
    """Single-domain entity for transaction business logic.

    Owns TransactionService exclusively.
    """

    def __init__(self):
        self.service = TransactionService()

    async def mark_as_reconciled(
        self,
        db: AsyncSession,
        transaction_id: UUID,
        reconciliation_date: datetime
    ) -> Transaction:
        """Mark transaction as reconciled (single-domain logic)."""
        transaction = await self.service.get(db, transaction_id)
        if not transaction:
            raise ValueError(f"Transaction {transaction_id} not found")

        # Business rules
        if transaction.is_reconciled:
            raise ValueError("Transaction already reconciled")
        if reconciliation_date < transaction.transaction_date:
            raise ValueError("Cannot reconcile before transaction date")

        return await self.service.update(
            db,
            transaction_id,
            is_reconciled=True,
            reconciliation_date=reconciliation_date
        )
```

#### Example Multi-Domain Workflows

```python
# molecules/workflows/transaction_workflow.py
from app.features.account.service import AccountService
from app.features.transaction.service import TransactionService
from app.features.budget.service import BudgetService
from app.molecules.entities.account import AccountEntity
from app.molecules.entities.transaction import TransactionEntity

class TransactionWorkflow:
    """Multi-domain workflow for transaction processing.

    Orchestrates accounts, transactions, and budgets.
    """

    def __init__(self):
        # Services for direct data operations
        self.account_service = AccountService()
        self.transaction_service = TransactionService()
        self.budget_service = BudgetService()

        # Entities for business logic
        self.account_entity = AccountEntity()
        self.transaction_entity = TransactionEntity()

    async def process_transaction(
        self,
        db: AsyncSession,
        account_id: UUID,
        amount: Decimal,
        category_id: UUID,
        description: str
    ) -> dict:
        """Process a complete transaction with validation and budget checks.

        Multi-domain orchestration:
        1. Validate account can withdraw (Account domain)
        2. Check budget limits (Budget domain)
        3. Create transaction (Transaction domain)
        4. Update account balance (Account domain)
        5. Update budget spent (Budget domain)
        """

        # 1. Use account entity for validation (single-domain logic)
        if not await self.account_entity.validate_withdrawal(db, account_id, amount):
            raise ValueError("Withdrawal not allowed")

        # 2. Check budget limits (direct service call for data)
        budget = await self.budget_service.get_by_category(db, category_id)
        if budget and budget.remaining < amount:
            raise ValueError("Exceeds budget limit")

        # 3. Create transaction (direct service call)
        from app.features.transaction.schemas import TransactionCreate
        transaction_data = TransactionCreate(
            account_id=account_id,
            amount=amount,
            category_id=category_id,
            description=description,
            transaction_date=datetime.utcnow()
        )
        transaction = await self.transaction_service.create(db, transaction_data)

        # 4. Update account balance (direct service call)
        await self.account_service.update(
            db,
            account_id,
            current_balance=F('current_balance') - amount
        )

        # 5. Update budget spent (direct service call)
        if budget:
            await self.budget_service.update(
                db,
                budget.id,
                amount_spent=F('amount_spent') + amount
            )

        return {
            "transaction": transaction,
            "new_balance": await self.account_entity.calculate_balance(db, account_id),
            "budget_remaining": budget.remaining - amount if budget else None
        }

    # Composite operations
    async def get_financial_summary(
        self,
        user_id: UUID,
        period: DateRange
    ) -> FinancialSummary:
        """Get complete financial summary for a period."""
        accounts = await self._account_service.get_by_user(self.db, user_id)

        # Get transactions for all accounts
        all_transactions = []
        for account in accounts:
            transactions = await self._transaction_service.get_by_period(
                self.db,
                account.id,
                period
            )
            all_transactions.extend(transactions)

        # Get budget vs actual
        budgets = await self._budget_service.get_active(self.db, user_id)
        budget_status = await self._calculate_budget_status(
            budgets,
            all_transactions,
            period
        )

        return FinancialSummary(
            accounts=accounts,
            transactions=all_transactions,
            budget_status=budget_status,
            total_income=self._sum_by_type(all_transactions, 'income'),
            total_expenses=self._sum_by_type(all_transactions, 'expense'),
            net_cash_flow=self._calculate_net_flow(all_transactions)
        )

    async def categorize_transaction(
        self,
        transaction_id: UUID,
        category_code: str,
        user_id: UUID
    ) -> Transaction:
        """Categorize a transaction with validation."""
        # Get transaction
        transaction = await self._transaction_service.get(
            self.db,
            transaction_id
        )
        if not transaction:
            raise NotFoundError("Transaction not found")

        # Validate ownership
        if transaction.actor_id != user_id:
            raise PermissionError("Cannot modify this transaction")

        # Get and validate category
        category = await self._category_service.get_by_code(
            self.db,
            category_code,
            user_id
        )
        if not category:
            raise NotFoundError("Category not found")

        # Update transaction
        return await self._transaction_service.update(
            self.db,
            transaction,
            TransactionUpdate(category_id=category.id)
        )

class TransactionOperations:
    """Transaction operations namespace."""

    def __init__(
        self,
        db: AsyncSession,
        transaction_service: TransactionService,
        category_service: CategoryService
    ):
        self.db = db
        self._transaction_service = transaction_service
        self._category_service = category_service

    async def create_with_auto_categorization(
        self,
        data: TransactionCreate,
        user_id: UUID
    ) -> Transaction:
        """Create transaction with automatic categorization."""
        # Try to auto-categorize based on description
        category = await self._auto_categorize(data.description, user_id)
        if category:
            data.category_id = category.id

        return await self._transaction_service.create(
            self.db,
            data,
            user_id
        )

    async def _auto_categorize(
        self,
        description: str,
        user_id: UUID
    ) -> Optional[Category]:
        """Auto-categorize based on rules."""
        # Implementation of categorization rules
        pass
```

#### Example Workflow

```python
# molecules/workflows/budget_workflow.py
from app.molecules.entities.financial import FinancialEntity
from app.molecules.entities.notification import NotificationEntity

class BudgetWorkflow:
    """Workflow for budget management."""

    async def create_monthly_budget(
        self,
        db: AsyncSession,
        user_id: UUID,
        month: date,
        template_id: Optional[UUID] = None
    ) -> BudgetCreationResult:
        """Create monthly budget with categories."""
        financial = FinancialEntity(db)
        notifications = NotificationEntity(db)

        async with db.begin():
            # Get or create budget template
            if template_id:
                template = await financial.budgets.get_template(template_id)
            else:
                template = await financial.budgets.get_default_template(user_id)

            # Create budget from template
            budget = await financial.budgets.create_from_template(
                user_id,
                month,
                template
            )

            # Set up category limits
            for category_limit in template.category_limits:
                await financial.budgets.set_category_limit(
                    budget.id,
                    category_limit.category_id,
                    category_limit.amount
                )

            # Set up alerts
            await notifications.create_budget_alerts(budget)

            # Send confirmation
            await notifications.send(
                user_id,
                NotificationType.BUDGET_CREATED,
                {"budget_id": budget.id, "month": month.isoformat()}
            )

        return BudgetCreationResult(
            budget=budget,
            categories_configured=len(template.category_limits),
            alerts_created=True
        )

    async def check_budget_status(
        self,
        db: AsyncSession,
        budget_id: UUID
    ) -> BudgetStatus:
        """Check budget status and send alerts if needed."""
        financial = FinancialEntity(db)
        notifications = NotificationEntity(db)

        # Get budget with spending
        budget = await financial.budgets.get_with_spending(budget_id)

        # Check thresholds
        alerts_triggered = []
        for category in budget.categories:
            percentage = (category.spent / category.limit) * 100

            if percentage >= 90 and not category.alert_90_sent:
                await notifications.send_budget_alert(
                    budget.user_id,
                    budget_id,
                    category.id,
                    90
                )
                alerts_triggered.append((category.name, 90))
            elif percentage >= 75 and not category.alert_75_sent:
                await notifications.send_budget_alert(
                    budget.user_id,
                    budget_id,
                    category.id,
                    75
                )
                alerts_triggered.append((category.name, 75))

        return BudgetStatus(
            budget=budget,
            total_spent=sum(c.spent for c in budget.categories),
            total_limit=sum(c.limit for c in budget.categories),
            alerts_triggered=alerts_triggered
        )
```

### 4. Organisms Layer - User Interfaces

**Purpose**: Expose functionality through various interfaces (HTTP, CLI, MCP, etc.)

**Structure**:
```
app/organisms/
├── api/                     # HTTP APIs
│   ├── v1/                  # API version 1
│   │   ├── __init__.py      # Router aggregation
│   │   ├── auth/            # Auth endpoints
│   │   │   ├── __init__.py
│   │   │   ├── login.py
│   │   │   ├── register.py
│   │   │   └── tokens.py
│   │   ├── finance/         # Financial endpoints
│   │   │   ├── accounts.py
│   │   │   ├── transactions.py
│   │   │   ├── budgets.py
│   │   │   └── reports.py
│   │   └── admin/           # Admin endpoints
│   ├── dependencies/        # Shared dependencies
│   │   ├── __init__.py      # Re-exports common deps
│   │   ├── database.py      # Database session deps
│   │   ├── auth.py          # Auth validation deps
│   │   ├── entities.py      # Entity injection deps
│   │   ├── pagination.py    # Pagination deps
│   │   └── permissions.py   # Permission checking
│   └── middleware/          # HTTP middleware
│       ├── __init__.py
│       ├── cors.py          # CORS configuration
│       ├── auth.py          # Auth middleware
│       ├── logging.py       # Request logging
│       └── rate_limit.py    # Rate limiting
├── cli/                     # Command line interface
│   ├── __init__.py
│   ├── commands/
│   │   ├── auth.py          # Auth CLI commands
│   │   ├── admin.py         # Admin CLI commands
│   │   ├── migrate.py       # Migration commands
│   │   └── validate.py      # Architecture validation
│   └── utils.py
├── graphql/                 # GraphQL interface
│   ├── __init__.py
│   ├── schema.py
│   └── resolvers/
└── mcp/                     # Model Context Protocol
    ├── __init__.py
    └── handlers/
```

**Key Principles**:
- Thin wrappers around molecules
- NO business logic
- Handle protocol-specific concerns only
- Use dependency injection for entities
- Comprehensive error handling
- Request/response transformation

**Dependency Injection Pattern**:

```python
# organisms/api/dependencies/auth.py
from typing import Optional
from fastapi import Depends, HTTPException, Header
from app.atoms.security.tokens import decode_token
from app.molecules.entities.user import UserEntity

async def get_current_token(
    authorization: Optional[str] = Header(None)
) -> TokenPayload:
    """Extract and validate token from header."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Invalid authorization header")

    token = authorization[7:]  # Remove "Bearer " prefix
    try:
        return decode_token(token)
    except InvalidTokenError as e:
        raise HTTPException(401, str(e))

async def get_current_user(
    token: TokenPayload = Depends(get_current_token),
    db: AsyncSession = Depends(get_db)
) -> User:
    """Get current authenticated user."""
    user_entity = UserEntity(db)
    user = await user_entity.get(token.user_id)
    if not user or not user.is_active:
        raise HTTPException(401, "User not found or inactive")
    return user

class RequirePermissions:
    """Dependency for permission checking."""

    def __init__(self, *permissions: str):
        self.permissions = set(permissions)

    async def __call__(
        self,
        user: User = Depends(get_current_user)
    ) -> User:
        """Check if user has required permissions."""
        user_permissions = set(user.permissions)
        if not self.permissions.issubset(user_permissions):
            missing = self.permissions - user_permissions
            raise HTTPException(
                403,
                f"Missing permissions: {', '.join(missing)}"
            )
        return user

# organisms/api/dependencies/entities.py
async def get_financial_entity(
    db: AsyncSession = Depends(get_db)
) -> FinancialEntity:
    """Inject Financial entity with db session."""
    return FinancialEntity(db)

async def get_financial_api() -> FinancialAPI:
    """Inject Financial API facade."""
    return FinancialAPI()

# organisms/api/v1/finance/transactions.py
from fastapi import APIRouter, Depends, Query
from app.organisms.api.dependencies import (
    get_db,
    get_current_user,
    get_financial_api,
    RequirePermissions,
    Pagination
)

router = APIRouter(prefix="/transactions", tags=["Transactions"])

@router.post("/", response_model=TransactionResponse)
async def create_transaction(
    data: TransactionCreate,
    db: AsyncSession = Depends(get_db),
    financial_api: FinancialAPI = Depends(get_financial_api),
    current_user: User = Depends(get_current_user)
) -> TransactionResponse:
    """Create a new transaction."""
    try:
        transaction = await financial_api.create_transaction(
            db,
            data,
            current_user
        )
        return TransactionResponse.from_orm(transaction)
    except ValidationError as e:
        raise HTTPException(400, str(e))
    except PermissionError as e:
        raise HTTPException(403, str(e))

@router.get("/", response_model=PaginatedResponse[TransactionResponse])
async def list_transactions(
    account_id: Optional[UUID] = Query(None),
    category_id: Optional[UUID] = Query(None),
    date_from: Optional[date] = Query(None),
    date_to: Optional[date] = Query(None),
    pagination: Pagination = Depends(),
    db: AsyncSession = Depends(get_db),
    financial_api: FinancialAPI = Depends(get_financial_api),
    current_user: User = Depends(get_current_user)
) -> PaginatedResponse[TransactionResponse]:
    """List transactions with filtering."""
    filters = TransactionFilters(
        account_id=account_id,
        category_id=category_id,
        date_from=date_from,
        date_to=date_to
    )

    result = await financial_api.list_transactions(
        db,
        current_user,
        filters,
        pagination
    )

    return PaginatedResponse(
        items=[TransactionResponse.from_orm(t) for t in result.items],
        total=result.total,
        page=pagination.page,
        size=pagination.size
    )

@router.put("/{transaction_id}/categorize")
async def categorize_transaction(
    transaction_id: UUID,
    category_code: str,
    db: AsyncSession = Depends(get_db),
    financial_api: FinancialAPI = Depends(get_financial_api),
    current_user: User = Depends(get_current_user)
) -> TransactionResponse:
    """Categorize a transaction."""
    transaction = await financial_api.categorize_transaction(
        db,
        transaction_id,
        category_code,
        current_user
    )
    return TransactionResponse.from_orm(transaction)

# Admin endpoint with permissions
@router.delete("/{transaction_id}")
async def delete_transaction(
    transaction_id: UUID,
    db: AsyncSession = Depends(get_db),
    financial_api: FinancialAPI = Depends(get_financial_api),
    current_user: User = Depends(RequirePermissions("admin", "finance_manager"))
) -> dict:
    """Delete a transaction (requires special permissions)."""
    await financial_api.delete_transaction(
        db,
        transaction_id,
        current_user
    )
    return {"status": "deleted"}
```

---

## Pattern System

### Pattern Composition Rules

1. **BasePattern**: Always the foundation, provides ID and timestamps
2. **Mixing Patterns**: Patterns can be mixed using multiple inheritance
3. **Pattern Order**: More specific patterns should come first in inheritance
4. **Conflict Resolution**: Use explicit property definitions to resolve conflicts

### Pattern Selection Guide

| Use Case | Recommended Pattern(s) | Example |
|----------|------------------------|---------|
| Reference/lookup data | CatalogPattern | Categories, Types, Statuses |
| User-owned entities | ActorPattern | Transactions, Documents |
| Historical tracking | TemporalPattern | Price history, Audit logs |
| Tree structures | HierarchicalPattern | Organizations, Folders |
| Complex entities | Multiple patterns | Transaction (Base + Actor + Temporal) |

### Pattern Implementation Examples

```python
# Combining patterns for complex requirements
class Document(BasePattern, ActorPattern, TemporalPattern, HierarchicalPattern):
    """Document with ownership, versioning, and folder structure."""
    __tablename__ = "documents"
    __actor_type__ = ActorType.USER

    title: Mapped[str] = mapped_column(String(255))
    content: Mapped[str] = mapped_column(Text)
    mime_type: Mapped[str] = mapped_column(String(100))
    size_bytes: Mapped[int] = mapped_column()

    # Override temporal pattern for document versioning
    @property
    def is_latest_version(self) -> bool:
        """Check if this is the latest version."""
        return self.is_current and self.valid_to is None

# Service handling pattern-aware operations
class DocumentService:
    """Service leveraging pattern capabilities."""

    async def create_version(
        self,
        db: AsyncSession,
        document_id: UUID,
        content: str,
        user_id: UUID
    ) -> Document:
        """Create a new version of a document."""
        # Get current version
        current = await self.get(db, document_id)
        if not current:
            raise NotFoundError("Document not found")

        # Mark current as non-current
        current.is_current = False
        current.valid_to = datetime.utcnow()

        # Create new version
        new_version = Document(
            **{k: v for k, v in current.__dict__.items()
               if k not in ['id', 'version', 'created_at', 'updated_at']},
            content=content,
            version=current.version + 1,
            updated_by=user_id
        )

        db.add(new_version)
        await db.commit()
        return new_version

    async def get_hierarchy(
        self,
        db: AsyncSession,
        folder_id: UUID
    ) -> List[Document]:
        """Get all documents in a folder hierarchy."""
        folder = await self.get(db, folder_id)
        if not folder:
            raise NotFoundError("Folder not found")

        # Use hierarchical pattern's path
        result = await db.execute(
            select(Document)
            .where(Document.path.like(f"{folder.path}%"))
            .order_by(Document.path, Document.position)
        )
        return result.scalars().all()
```

---

## Services vs Domain Entities

### The Key Distinction

**Services (Features Layer)**:
- Handle data operations for ONE model/table
- No cross-domain knowledge
- No permission checks
- Pure CRUD + data-specific business logic
- Pattern-aware operations

**Domain Entities (Molecules Layer)**:
- Compose multiple services
- Provide intuitive API
- Handle composite operations
- Implement business rules
- Orchestrate complex workflows

### Visual Representation

```
User Request
    ↓
API Facade (permissions)
    ↓
Domain Entity (business logic)
    ├── ServiceA (data for ModelA)
    ├── ServiceB (data for ModelB)
    └── ServiceC (data for ModelC)
         ↓
    Database
```

### Service vs Entity Examples

```python
# ❌ BAD: Service with cross-domain logic
class TransactionService:
    async def create_with_budget_check(self, ...):  # ❌ Knows about budgets
        # Check budget limits
        # Create transaction
        pass

# ✅ GOOD: Service focused on its domain
class TransactionService:
    async def create(self, db, data, user_id):  # ✅ Just transaction data
        transaction = Transaction(**data.model_dump(), actor_id=user_id)
        db.add(transaction)
        await db.commit()
        return transaction

# ✅ GOOD: Entity orchestrating multiple services
class FinancialEntity:
    async def create_transaction_with_budget_check(self, ...):
        # Use budget service to check limits
        budget = await self._budget_service.get_current(...)
        if not budget.has_room_for(amount):
            raise BudgetExceededError()

        # Use transaction service to create
        return await self._transaction_service.create(...)
```

---

## Data Flow Patterns

### 1. Request Flow (Top-Down)
```
HTTP Request
    ↓ [validates format]
Organism (Router)
    ↓ [checks auth token]
Auth Dependency
    ↓ [checks permissions]
Permission Dependency
    ↓ [injects db session]
Database Dependency
    ↓ [creates entity]
API Facade
    ↓ [business logic]
Domain Entity
    ↓ [coordinates]
Multiple Services
    ↓ [data operations]
Models (with patterns)
    ↓ [persistence]
Database
```

### 2. Entity Composition Pattern
```
FinancialEntity
    ├── AccountService (account data)
    ├── TransactionService (transaction data)
    ├── CategoryService (category data)
    ├── BudgetService (budget data)
    └── ReportingService (analytics)
```

### 3. Workflow Orchestration Pattern
```
MonthEndWorkflow
    ├── FinancialEntity
    │   ├── Close period transactions
    │   ├── Calculate totals
    │   └── Update account balances
    ├── BudgetEntity
    │   ├── Finalize budget actuals
    │   └── Generate variance report
    ├── ReportEntity
    │   ├── Generate monthly report
    │   └── Create visualizations
    └── NotificationEntity
        └── Send summary email
```

---

## Schema Architecture

### Schema Organization

Each feature organizes schemas by purpose:

```python
# features/{feature}/schemas/input.py
class TransactionCreate(BaseModel):
    """Schema for creating a transaction."""
    amount: Decimal
    description: str
    category_id: UUID
    account_id: UUID
    transaction_date: datetime

    @field_validator('amount')
    def validate_amount(cls, v):
        if v <= 0:
            raise ValueError("Amount must be positive")
        return v

class TransactionUpdate(BaseModel):
    """Schema for updating a transaction."""
    amount: Optional[Decimal] = None
    description: Optional[str] = None
    category_id: Optional[UUID] = None

    class Config:
        extra = "forbid"  # Prevent unknown fields

class TransactionFilter(BaseModel):
    """Schema for filtering transactions."""
    account_id: Optional[UUID] = None
    category_id: Optional[UUID] = None
    date_from: Optional[date] = None
    date_to: Optional[date] = None
    amount_min: Optional[Decimal] = None
    amount_max: Optional[Decimal] = None

# features/{feature}/schemas/output.py
class TransactionResponse(BaseModel):
    """Schema for transaction responses."""
    id: UUID
    amount: Decimal
    description: str
    category: CategoryReference
    account: AccountReference
    transaction_date: datetime
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

class TransactionSummary(BaseModel):
    """Summary schema for lists."""
    id: UUID
    amount: Decimal
    description: str
    category_name: str
    transaction_date: datetime

class TransactionStats(BaseModel):
    """Statistical information."""
    total_amount: Decimal
    transaction_count: int
    average_amount: Decimal
    largest_transaction: Optional[TransactionSummary]
    categories: List[CategoryBreakdown]

# features/{feature}/schemas/internal.py
class TransactionInDB(BaseModel):
    """Internal schema with all fields."""
    id: UUID
    amount: Decimal
    description: str
    category_id: UUID
    account_id: UUID
    transaction_date: datetime
    actor_id: UUID
    actor_type: ActorType
    created_at: datetime
    updated_at: datetime
    created_by: UUID
    updated_by: Optional[UUID]
```

### Schema Inheritance Pattern

```python
# Base schemas for common fields
class TimestampedSchema(BaseModel):
    created_at: datetime
    updated_at: datetime

class ActorSchema(BaseModel):
    actor_id: UUID
    actor_type: ActorType
    created_by: UUID
    updated_by: Optional[UUID]

# Composed schemas
class TransactionResponse(TimestampedSchema, ActorSchema):
    id: UUID
    amount: Decimal
    # ... other fields
```

---

## Testing Architecture

### Test Structure

```
app/__tests__/
├── unit/                    # Unit tests (isolated)
│   ├── atoms/
│   │   ├── patterns/
│   │   │   ├── test_base_pattern.py
│   │   │   ├── test_catalog_pattern.py
│   │   │   └── test_hierarchical_pattern.py
│   │   └── validators/
│   ├── features/
│   │   ├── test_transaction_service.py
│   │   └── test_category_service.py
│   └── molecules/
│       └── test_financial_entity.py
├── integration/             # Integration tests
│   ├── test_transaction_workflow.py
│   ├── test_budget_management.py
│   └── test_reporting.py
├── e2e/                     # End-to-end tests
│   ├── test_user_journey.py
│   └── test_api_flows.py
├── performance/             # Performance tests
│   ├── test_query_performance.py
│   └── test_load_handling.py
├── architecture/            # Architecture validation
│   ├── test_dependencies.py
│   └── test_patterns.py
└── fixtures/                # Shared test fixtures
    ├── __init__.py
    ├── database.py
    ├── factories.py
    └── mocks.py
```

### Testing Patterns

```python
# Unit test for pattern
class TestCatalogPattern:
    def test_catalog_pattern_fields(self):
        """Test catalog pattern provides expected fields."""
        class TestCatalog(CatalogPattern):
            __tablename__ = "test_catalog"

        instance = TestCatalog(
            name="Test",
            code="TEST",
            display_order=1
        )

        assert instance.name == "Test"
        assert instance.code == "TEST"
        assert instance.is_active is True
        assert instance.metadata == {}

    def test_catalog_pattern_validation(self):
        """Test catalog pattern validation."""
        # Test implementation

# Integration test for service
@pytest.mark.asyncio
class TestTransactionService:
    async def test_create_transaction_with_patterns(
        self,
        db_session: AsyncSession,
        transaction_service: TransactionService,
        sample_user: User
    ):
        """Test creating transaction uses patterns correctly."""
        data = TransactionCreate(
            amount=Decimal("100.50"),
            description="Test transaction",
            category_id=uuid4(),
            account_id=uuid4(),
            transaction_date=datetime.utcnow()
        )

        transaction = await transaction_service.create(
            db_session,
            data,
            sample_user.id
        )

        # Verify pattern fields are set
        assert transaction.actor_id == sample_user.id
        assert transaction.actor_type == ActorType.USER
        assert transaction.created_by == sample_user.id
        assert transaction.created_at is not None
        assert transaction.version == 1
        assert transaction.is_current is True

# E2E test for workflow
@pytest.mark.asyncio
class TestBudgetWorkflow:
    async def test_complete_budget_cycle(
        self,
        client: AsyncClient,
        auth_headers: dict
    ):
        """Test complete budget creation and monitoring cycle."""
        # Create budget
        response = await client.post(
            "/api/v1/budgets",
            json={
                "month": "2024-01",
                "categories": [
                    {"code": "FOOD", "limit": 500},
                    {"code": "TRANSPORT", "limit": 200}
                ]
            },
            headers=auth_headers
        )
        assert response.status_code == 201
        budget_id = response.json()["id"]

        # Create transactions
        for _ in range(3):
            await client.post(
                "/api/v1/transactions",
                json={
                    "amount": 50,
                    "description": "Grocery shopping",
                    "category_code": "FOOD",
                    "account_id": "...",
                    "transaction_date": "2024-01-15"
                },
                headers=auth_headers
            )

        # Check budget status
        response = await client.get(
            f"/api/v1/budgets/{budget_id}/status",
            headers=auth_headers
        )
        assert response.status_code == 200
        status = response.json()
        assert status["categories"]["FOOD"]["spent"] == 150
        assert status["categories"]["FOOD"]["remaining"] == 350

# Architecture test
class TestArchitectureCompliance:
    def test_no_upward_dependencies(self):
        """Test that dependencies only flow downward."""
        validator = ArchitectureValidator()
        violations = validator.check_dependencies()
        assert len(violations) == 0, f"Found violations: {violations}"

    def test_features_isolated(self):
        """Test that features don't import from each other."""
        validator = ArchitectureValidator()
        violations = validator.check_feature_isolation()
        assert len(violations) == 0, f"Found violations: {violations}"
```

---

## Implementation Patterns

### Service Implementation Pattern

```python
# Base service class
class BaseService(Generic[ModelT, CreateT, UpdateT]):
    """Base service with common CRUD operations."""

    def __init__(self, model_class: Type[ModelT]):
        self.model_class = model_class

    async def create(
        self,
        db: AsyncSession,
        data: CreateT,
        **extra_fields
    ) -> ModelT:
        """Create a new record."""
        instance = self.model_class(
            **data.model_dump(exclude_unset=True),
            **extra_fields
        )
        db.add(instance)
        await db.commit()
        await db.refresh(instance)
        return instance

    async def get(
        self,
        db: AsyncSession,
        id: UUID
    ) -> Optional[ModelT]:
        """Get record by ID."""
        return await db.get(self.model_class, id)

    async def update(
        self,
        db: AsyncSession,
        instance: ModelT,
        data: UpdateT
    ) -> ModelT:
        """Update a record."""
        for field, value in data.model_dump(exclude_unset=True).items():
            setattr(instance, field, value)
        await db.commit()
        await db.refresh(instance)
        return instance

    async def delete(
        self,
        db: AsyncSession,
        instance: ModelT
    ) -> None:
        """Delete a record."""
        await db.delete(instance)
        await db.commit()

# Specific service extending base
class CategoryService(BaseService[Category, CategoryCreate, CategoryUpdate]):
    """Service for Category with pattern-specific operations."""

    def __init__(self):
        super().__init__(Category)

    async def get_active_by_actor(
        self,
        db: AsyncSession,
        actor_id: UUID
    ) -> List[Category]:
        """Get active categories for an actor."""
        result = await db.execute(
            select(Category)
            .where(Category.actor_id == actor_id)
            .where(Category.is_active == True)
            .order_by(Category.display_order, Category.name)
        )
        return result.scalars().all()

    async def reorder(
        self,
        db: AsyncSession,
        actor_id: UUID,
        category_codes: List[str]
    ) -> List[Category]:
        """Reorder categories by code."""
        categories = await self.get_active_by_actor(db, actor_id)
        code_to_category = {c.code: c for c in categories}

        for index, code in enumerate(category_codes):
            if code in code_to_category:
                code_to_category[code].display_order = index

        await db.commit()
        return await self.get_active_by_actor(db, actor_id)
```

### Entity Implementation Pattern

```python
# Base entity class
class BaseEntity:
    """Base class for domain entities."""

    def __init__(self, db: AsyncSession):
        self.db = db
        self._init_services()

    def _init_services(self):
        """Initialize required services."""
        raise NotImplementedError

    async def validate_ownership(
        self,
        resource: Any,
        user_id: UUID,
        field: str = "actor_id"
    ) -> None:
        """Validate user owns the resource."""
        if getattr(resource, field) != user_id:
            raise PermissionError(f"User does not own this {resource.__class__.__name__}")

# Specific entity
class BudgetEntity(BaseEntity):
    """Budget management entity."""

    def _init_services(self):
        self._budget_service = BudgetService()
        self._category_service = CategoryService()
        self._transaction_service = TransactionService()

    async def create_with_categories(
        self,
        user_id: UUID,
        month: date,
        category_limits: List[CategoryLimit]
    ) -> Budget:
        """Create budget with category limits."""
        # Create budget
        budget = await self._budget_service.create(
            self.db,
            BudgetCreate(
                user_id=user_id,
                month=month,
                total_limit=sum(cl.amount for cl in category_limits)
            )
        )

        # Set category limits
        for limit in category_limits:
            await self._budget_service.set_category_limit(
                self.db,
                budget.id,
                limit.category_id,
                limit.amount
            )

        return budget

    async def get_spending_summary(
        self,
        budget_id: UUID,
        user_id: UUID
    ) -> SpendingSummary:
        """Get spending summary for budget."""
        budget = await self._budget_service.get(self.db, budget_id)
        if not budget:
            raise NotFoundError("Budget not found")

        await self.validate_ownership(budget, user_id, "user_id")

        # Get transactions for budget period
        transactions = await self._transaction_service.get_by_period(
            self.db,
            user_id,
            DateRange(
                start=budget.month,
                end=budget.month + relativedelta(months=1)
            )
        )

        # Calculate spending by category
        spending_by_category = defaultdict(Decimal)
        for transaction in transactions:
            spending_by_category[transaction.category_id] += transaction.amount

        return SpendingSummary(
            budget=budget,
            spending_by_category=dict(spending_by_category),
            total_spent=sum(spending_by_category.values()),
            remaining=budget.total_limit - sum(spending_by_category.values())
        )
```

### API Facade Pattern

```python
class BudgetAPI:
    """Budget API with permission checks."""

    async def create_budget(
        self,
        db: AsyncSession,
        data: BudgetCreate,
        current_user: User
    ) -> Budget:
        """Create budget with permission check."""
        # Check if user can create budgets
        if not current_user.can_create_budgets:
            raise PermissionError("User cannot create budgets")

        # Create entity and delegate
        entity = BudgetEntity(db)
        return await entity.create_with_categories(
            current_user.id,
            data.month,
            data.category_limits
        )

    async def share_budget(
        self,
        db: AsyncSession,
        budget_id: UUID,
        share_with: UUID,
        current_user: User
    ) -> BudgetShare:
        """Share budget with another user."""
        entity = BudgetEntity(db)

        # Get budget and validate ownership
        budget = await entity._budget_service.get(db, budget_id)
        if not budget:
            raise NotFoundError("Budget not found")

        if budget.user_id != current_user.id:
            raise PermissionError("Cannot share budget you don't own")

        # Create share
        return await entity.share_with_user(budget_id, share_with)
```

---

## Common Patterns & Anti-Patterns

### ✅ DO: Use Patterns for Common Behaviors

```python
# GOOD: Leveraging patterns
class Category(CatalogPattern, ActorPattern):
    __tablename__ = "categories"
    __actor_type__ = ActorType.HOUSEHOLD

    # Only add domain-specific fields
    budget_limit: Mapped[Optional[Decimal]] = mapped_column(Numeric(10, 2))
```

### ❌ DON'T: Duplicate Pattern Logic

```python
# BAD: Re-implementing pattern logic
class Category(Base):
    __tablename__ = "categories"

    # ❌ Duplicating what CatalogPattern provides
    id: Mapped[UUID] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100))
    code: Mapped[str] = mapped_column(String(50))
    is_active: Mapped[bool] = mapped_column(default=True)
    # ... etc
```

### ✅ DO: Keep Services Focused

```python
# GOOD: Service handles one model
class AccountService:
    async def get_balance(self, db, account_id):
        """Get account balance."""
        # Only deals with Account model
```

### ❌ DON'T: Mix Concerns in Services

```python
# BAD: Service knows about multiple domains
class AccountService:
    async def get_with_transactions(self, db, account_id):
        """Get account with transactions."""
        account = await self.get(db, account_id)
        # ❌ Service shouldn't know about transactions
        transactions = await db.execute(
            select(Transaction).where(Transaction.account_id == account_id)
        )
```

### ✅ DO: Compose in Entities

```python
# GOOD: Entity coordinates multiple services
class AccountEntity:
    async def get_with_transactions(self, account_id):
        """Get account with transactions."""
        account = await self._account_service.get(self.db, account_id)
        transactions = await self._transaction_service.get_by_account(
            self.db,
            account_id
        )
        return AccountWithTransactions(account=account, transactions=transactions)
```

### ❌ DON'T: Put Business Logic in Models

```python
# BAD: Model with business logic
class Transaction(BasePattern):
    def can_be_edited_by(self, user):  # ❌ Business logic in model
        return self.user_id == user.id
```

### ✅ DO: Business Logic in Entities

```python
# GOOD: Business logic in entity
class TransactionEntity:
    def can_user_edit(self, transaction, user):
        """Check if user can edit transaction."""
        # Business rule: can edit own transactions within 30 days
        if transaction.actor_id != user.id:
            return False
        days_old = (datetime.utcnow() - transaction.created_at).days
        return days_old <= 30
```

---

## Advanced Patterns

### Event-Driven Architecture

```python
# atoms/events/base.py
class EventBus:
    """Central event bus for pub/sub."""

    def __init__(self):
        self._handlers: Dict[str, List[Callable]] = defaultdict(list)

    def subscribe(self, event_type: str, handler: Callable):
        """Subscribe to an event type."""
        self._handlers[event_type].append(handler)

    async def publish(self, event: Event):
        """Publish an event to all subscribers."""
        for handler in self._handlers[event.type]:
            await handler(event)

# Usage in entity
class TransactionEntity:
    async def create(self, data, user_id):
        """Create transaction and publish event."""
        transaction = await self._transaction_service.create(
            self.db,
            data,
            user_id
        )

        # Publish event
        await event_bus.publish(
            TransactionCreatedEvent(
                transaction_id=transaction.id,
                amount=transaction.amount,
                category_id=transaction.category_id,
                user_id=user_id
            )
        )

        return transaction
```

### Saga Pattern for Distributed Transactions

```python
# molecules/sagas/payment_saga.py
class PaymentSaga:
    """Saga for handling payment processing."""

    async def execute(
        self,
        db: AsyncSession,
        payment_data: PaymentData
    ) -> PaymentResult:
        """Execute payment saga with compensations."""
        steps_completed = []

        try:
            # Step 1: Reserve funds
            reservation = await self._reserve_funds(
                db,
                payment_data.account_id,
                payment_data.amount
            )
            steps_completed.append(("reserve_funds", reservation))

            # Step 2: Process payment
            payment = await self._process_payment(
                db,
                payment_data
            )
            steps_completed.append(("process_payment", payment))

            # Step 3: Update balances
            await self._update_balances(
                db,
                payment_data.account_id,
                payment_data.amount
            )
            steps_completed.append(("update_balances", None))

            # Step 4: Send notification
            await self._send_notification(
                payment_data.user_id,
                payment
            )

            return PaymentResult(success=True, payment=payment)

        except Exception as e:
            # Compensate in reverse order
            await self._compensate(db, steps_completed)
            raise SagaFailedError(f"Payment saga failed: {e}")

    async def _compensate(
        self,
        db: AsyncSession,
        steps: List[Tuple[str, Any]]
    ):
        """Compensate completed steps in reverse order."""
        for step_name, step_data in reversed(steps):
            if step_name == "reserve_funds":
                await self._release_funds(db, step_data)
            elif step_name == "process_payment":
                await self._reverse_payment(db, step_data)
            elif step_name == "update_balances":
                await self._restore_balances(db, step_data)
```

### CQRS Pattern

```python
# features/transaction/commands.py
class TransactionCommands:
    """Command side of CQRS."""

    async def create_transaction(
        self,
        db: AsyncSession,
        command: CreateTransactionCommand
    ) -> UUID:
        """Handle create transaction command."""
        transaction = Transaction(
            **command.to_dict(),
            id=uuid4()
        )
        db.add(transaction)
        await db.commit()

        # Publish event for read model update
        await event_bus.publish(
            TransactionCreatedEvent(transaction_id=transaction.id)
        )

        return transaction.id

# features/transaction/queries.py
class TransactionQueries:
    """Query side of CQRS."""

    async def get_monthly_summary(
        self,
        db: AsyncSession,
        user_id: UUID,
        month: date
    ) -> MonthlySummary:
        """Get monthly summary from read model."""
        # Query optimized read model
        result = await db.execute(
            select(TransactionSummary)
            .where(TransactionSummary.user_id == user_id)
            .where(TransactionSummary.month == month)
        )
        return result.scalar_one_or_none()
```

### Repository Pattern with Specification

```python
# atoms/data/specifications.py
class Specification:
    """Base specification for queries."""

    def to_expression(self) -> Any:
        raise NotImplementedError

    def __and__(self, other: 'Specification') -> 'AndSpecification':
        return AndSpecification(self, other)

    def __or__(self, other: 'Specification') -> 'OrSpecification':
        return OrSpecification(self, other)

# features/transaction/specifications.py
class TransactionByDateRange(Specification):
    def __init__(self, start: date, end: date):
        self.start = start
        self.end = end

    def to_expression(self):
        return and_(
            Transaction.transaction_date >= self.start,
            Transaction.transaction_date <= self.end
        )

class TransactionByCategory(Specification):
    def __init__(self, category_id: UUID):
        self.category_id = category_id

    def to_expression(self):
        return Transaction.category_id == self.category_id

# Usage
class TransactionRepository:
    async def find_by_specification(
        self,
        db: AsyncSession,
        spec: Specification
    ) -> List[Transaction]:
        """Find transactions matching specification."""
        result = await db.execute(
            select(Transaction).where(spec.to_expression())
        )
        return result.scalars().all()

# Using specifications
spec = TransactionByDateRange(start_date, end_date) & TransactionByCategory(category_id)
transactions = await repo.find_by_specification(db, spec)
```

---

## Migration Guide

### From v2.1 to v2.5

1. **Adopt Pattern System**
   ```python
   # Before: Plain SQLAlchemy model
   class Category(Base):
       __tablename__ = "categories"
       id: Mapped[UUID] = mapped_column(primary_key=True)
       name: Mapped[str] = mapped_column(String(100))
       # ... many common fields

   # After: Using patterns
   from app.atoms.patterns.catalog import CatalogPattern
   from app.atoms.patterns.actor import ActorPattern

   class Category(CatalogPattern, ActorPattern):
       __tablename__ = "categories"
       __actor_type__ = ActorType.HOUSEHOLD
       # Only domain-specific fields needed
   ```

2. **Update Services for Patterns**
   ```python
   # Services can now leverage pattern fields
   class CategoryService:
       async def get_active(self, db, actor_id):
           # Use pattern fields: is_active, actor_id
           return await db.execute(
               select(Category)
               .where(Category.actor_id == actor_id)
               .where(Category.is_active == True)
           )
   ```

3. **Enhance Entities with Pattern Awareness**
   ```python
   class CategoryEntity:
       async def deactivate_old_versions(self, category_id):
           """Deactivate old versions using temporal pattern."""
           categories = await self._service.get_versions(
               self.db,
               category_id
           )
           for cat in categories:
               if not cat.is_current:  # Using temporal pattern
                   cat.is_active = False  # Using catalog pattern
   ```

4. **Add Pattern-Specific Tests**
   ```python
   def test_actor_pattern_sets_actor_type():
       """Test actor pattern auto-sets actor_type."""
       class TestModel(ActorPattern):
           __tablename__ = "test"
           __actor_type__ = ActorType.USER

       instance = TestModel(actor_id=uuid4())
       assert instance.actor_type == ActorType.USER
   ```

### Database Migration for Patterns

```sql
-- Add pattern fields to existing tables
ALTER TABLE categories
    ADD COLUMN display_order INTEGER DEFAULT 0,
    ADD COLUMN is_active BOOLEAN DEFAULT TRUE,
    ADD COLUMN metadata JSONB DEFAULT '{}',
    ADD COLUMN actor_type VARCHAR(50),
    ADD COLUMN actor_id UUID,
    ADD COLUMN created_by UUID,
    ADD COLUMN updated_by UUID;

-- Add indexes for pattern fields
CREATE INDEX idx_categories_actor ON categories(actor_id, actor_type);
CREATE INDEX idx_categories_active ON categories(is_active);
CREATE INDEX idx_categories_display ON categories(display_order);
```

---

## Reference Implementation

### Complete Example: Financial Tracker

```python
# atoms/patterns/catalog.py
class CatalogPattern(BasePattern):
    """Pattern for catalog/reference data."""
    __abstract__ = True

    name: Mapped[str] = mapped_column(String(100), unique=True)
    code: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    description: Mapped[Optional[str]] = mapped_column(Text)
    display_order: Mapped[int] = mapped_column(default=0)
    is_active: Mapped[bool] = mapped_column(default=True, index=True)
    metadata: Mapped[Dict] = mapped_column(JSON, default=dict)

# features/category/models.py
class Category(CatalogPattern, ActorPattern):
    """Financial category using patterns."""
    __tablename__ = "categories"
    __actor_type__ = ActorType.HOUSEHOLD

    icon: Mapped[Optional[str]] = mapped_column(String(50))
    color: Mapped[Optional[str]] = mapped_column(String(7))
    budget_limit: Mapped[Optional[Decimal]] = mapped_column(Numeric(10, 2))
    parent_category_id: Mapped[Optional[UUID]] = mapped_column(
        ForeignKey("categories.id")
    )

# features/category/service.py
class CategoryService(BaseService[Category, CategoryCreate, CategoryUpdate]):
    """Category service with pattern-aware operations."""

    def __init__(self):
        super().__init__(Category)

    async def create_default_categories(
        self,
        db: AsyncSession,
        household_id: UUID,
        user_id: UUID
    ) -> List[Category]:
        """Create default categories for new household."""
        defaults = [
            ("FOOD", "Food & Dining", "🍔", "#FF6B6B"),
            ("TRANSPORT", "Transportation", "🚗", "#4ECDC4"),
            ("UTILITIES", "Utilities", "💡", "#45B7D1"),
            ("ENTERTAINMENT", "Entertainment", "🎮", "#96CEB4"),
            ("HEALTHCARE", "Healthcare", "🏥", "#DDA77B")
        ]

        categories = []
        for order, (code, name, icon, color) in enumerate(defaults):
            category = Category(
                code=f"{household_id[:8]}_{code}",
                name=name,
                icon=icon,
                color=color,
                display_order=order,
                actor_id=household_id,
                actor_type=ActorType.HOUSEHOLD,
                created_by=user_id
            )
            db.add(category)
            categories.append(category)

        await db.commit()
        return categories

# molecules/entities/household.py
class HouseholdEntity(BaseEntity):
    """Household management entity."""

    def _init_services(self):
        self._household_service = HouseholdService()
        self._user_service = UserService()
        self._category_service = CategoryService()
        self._budget_service = BudgetService()

    async def create_with_defaults(
        self,
        data: HouseholdCreate,
        creator_id: UUID
    ) -> HouseholdComplete:
        """Create household with default setup."""
        async with self.db.begin():
            # Create household
            household = await self._household_service.create(
                self.db,
                data,
                creator_id
            )

            # Add creator as admin
            await self._household_service.add_member(
                self.db,
                household.id,
                creator_id,
                HouseholdRole.ADMIN
            )

            # Create default categories
            categories = await self._category_service.create_default_categories(
                self.db,
                household.id,
                creator_id
            )

            # Create initial budget
            budget = await self._budget_service.create_initial(
                self.db,
                household.id,
                creator_id
            )

        return HouseholdComplete(
            household=household,
            members=[creator_id],
            categories=categories,
            budget=budget
        )

# molecules/workflows/monthly_close.py
class MonthlyCloseWorkflow:
    """Workflow for closing a financial month."""

    async def execute(
        self,
        db: AsyncSession,
        household_id: UUID,
        month: date
    ) -> MonthlyCloseResult:
        """Execute monthly close process."""
        financial = FinancialEntity(db)
        reporting = ReportingEntity(db)
        notification = NotificationEntity(db)

        async with db.begin():
            # 1. Finalize all pending transactions
            pending = await financial.transactions.get_pending(
                household_id,
                month
            )
            for transaction in pending:
                await financial.transactions.finalize(transaction.id)

            # 2. Calculate budget actuals
            budget = await financial.budgets.get_by_month(
                household_id,
                month
            )
            actuals = await financial.budgets.calculate_actuals(
                budget.id
            )

            # 3. Generate monthly report
            report = await reporting.generate_monthly_report(
                household_id,
                month,
                actuals
            )

            # 4. Archive the month
            await financial.archive_month(household_id, month)

            # 5. Send notifications
            members = await self._get_household_members(household_id)
            for member_id in members:
                await notification.send(
                    member_id,
                    NotificationType.MONTHLY_CLOSE,
                    {
                        "month": month.isoformat(),
                        "report_id": report.id,
                        "budget_variance": actuals.variance
                    }
                )

        return MonthlyCloseResult(
            transactions_finalized=len(pending),
            report=report,
            actuals=actuals,
            notifications_sent=len(members)
        )

# organisms/api/v1/finance/categories.py
@router.post("/", response_model=CategoryResponse)
async def create_category(
    data: CategoryCreate,
    db: AsyncSession = Depends(get_db),
    financial_api: FinancialAPI = Depends(get_financial_api),
    current_user: User = Depends(get_current_user)
) -> CategoryResponse:
    """Create a new category."""
    # API facade handles permissions
    category = await financial_api.create_category(
        db,
        data,
        current_user
    )
    return CategoryResponse.from_orm(category)

@router.get("/", response_model=List[CategoryResponse])
async def list_categories(
    active_only: bool = Query(True),
    db: AsyncSession = Depends(get_db),
    financial_api: FinancialAPI = Depends(get_financial_api),
    current_user: User = Depends(get_current_user)
) -> List[CategoryResponse]:
    """List user's categories."""
    categories = await financial_api.list_categories(
        db,
        current_user,
        active_only
    )
    return [CategoryResponse.from_orm(c) for c in categories]

@router.put("/reorder", response_model=List[CategoryResponse])
async def reorder_categories(
    order: List[str],  # List of category codes in desired order
    db: AsyncSession = Depends(get_db),
    financial_api: FinancialAPI = Depends(get_financial_api),
    current_user: User = Depends(get_current_user)
) -> List[CategoryResponse]:
    """Reorder categories."""
    categories = await financial_api.reorder_categories(
        db,
        current_user,
        order
    )
    return [CategoryResponse.from_orm(c) for c in categories]
```

---

## Conclusion

Atomic Architecture v2.5 with Pattern Stack provides:

1. **Pattern-Based Development**: Reusable patterns for common behaviors
2. **Clear Layer Separation**: Each layer has a specific, well-defined purpose
3. **Scalable Architecture**: From simple CRUD to complex enterprise workflows
4. **Type Safety**: Full type hints with runtime validation
5. **Testability**: Every component can be tested in isolation
6. **Flexibility**: Patterns can be mixed and matched as needed
7. **Maintainability**: Clear boundaries and single responsibilities

The architecture scales from simple applications to complex enterprise systems while maintaining clarity and maintainability through its pattern-based approach and strict architectural boundaries.
