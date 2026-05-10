# Pattern Stack Project Configuration

**Purpose**: Centralized configuration for Pattern Stack backend framework commands and workflows.
**Usage**: All atomic commands and orchestrators should reference this file for project-specific paths, validation, and architecture rules.

## Project Overview

**Name**: Tempo Sales Context System
**Type**: Monorepo (Frontend + Backend)
**Architecture**: Atomic Architecture v2.5 (both stacks)
**Backend Stack**: Python 3.11+, FastAPI, SQLAlchemy 2.0+, PostgreSQL, Pattern Stack
**Frontend Stack**: React 18+, TypeScript, Vite, Pattern Stack Frontend
**Package Manager**: uv (backend), npm (frontend)
**Testing**: pytest (backend), vitest (frontend)

## Monorepo Structure

```
tempo-demo/
├── .claude/              # Shared commands and config
├── backend/              # FastAPI + Pattern Stack Backend
│   ├── app/
│   │   ├── atoms/
│   │   ├── features/
│   │   ├── molecules/
│   │   └── organisms/
│   ├── specs/            # Backend-specific specs
│   └── pyproject.toml
├── frontend/             # React + Vite + Pattern Stack Frontend
│   ├── src/
│   │   ├── atoms/
│   │   ├── molecules/
│   │   ├── organisms/
│   │   └── pages/
│   ├── specs/            # Frontend-specific specs
│   └── package.json
├── specs/                # Fullstack specs (cross-cutting features)
├── agent-logs/           # Session logs (shared)
└── ENTITIES_AND_SERVICES.md  # Domain model reference
```

### Stack Labels

**REQUIRED for all issues**: One `stack:*` label to indicate which codebase is affected.

- `stack:backend` - Backend-only work (API, database, services)
- `stack:frontend` - Frontend-only work (UI, components, pages)
- `stack:fullstack` - Spans both stacks (end-to-end features)

**Examples:**
```yaml
# Backend API endpoint
labels: [stack:backend, type:feature, layer:organisms]

# React component
labels: [stack:frontend, type:feature, layer:molecules]

# Complete feature (API + UI)
labels: [stack:fullstack, type:epic]
  children:
    - labels: [stack:backend, type:feature, layer:organisms]  # API first
    - labels: [stack:frontend, type:feature, layer:molecules]  # UI second
```

## File Structure

### Backend Layer Paths
```
backend/app/
├── atoms/              # Shared utilities, infrastructure (domain-agnostic)
│   ├── shared/         # Core dependencies, settings, events
│   ├── data/           # Database layer (SQLAlchemy base, sessions)
│   ├── security/       # Auth, JWT, hashing
│   ├── config/         # Application configuration
│   ├── validators/     # Reusable field validators
│   ├── api/            # API utilities (pagination, responses, exceptions)
│   └── patterns/       # Pattern base classes (BasePattern, ActorPattern, etc)
├── features/           # Data services for specific models (CRUD only)
│   └── {feature}/
│       ├── models.py   # SQLAlchemy models
│       ├── schemas/    # Pydantic schemas
│       ├── service.py  # CRUD service
│       └── repository.py # Data access (optional)
├── molecules/          # Domain entities & orchestration (business logic)
│   ├── entities/       # Domain objects composing multiple services
│   ├── apis/           # Permission facades for entities
│   └── workflows/      # Multi-entity orchestration
└── organisms/          # User interfaces (HTTP, CLI, MCP)
    ├── api/            # FastAPI HTTP APIs
    └── cli/            # Command-line interfaces
```

### Frontend Layer Paths
```
frontend/src/
├── atoms/              # Base UI components (Button, Input, Card)
│   ├── ui/             # Core UI primitives
│   ├── types/          # Shared TypeScript types
│   └── hooks/          # Reusable React hooks
├── molecules/          # Composed UI patterns (SearchBar, FormGroup)
│   ├── forms/          # Form compositions
│   ├── layout/         # Layout components
│   └── data-display/   # Data visualization components
├── organisms/          # Complete UI modules (Header, Sidebar, Timeline)
│   ├── navigation/     # Navigation components
│   ├── providers/      # React context providers
│   └── sections/       # Page sections
└── pages/              # Full page components (AccountDetail, AccountsList)
```

### Spec Paths
```
backend/specs/                            # Backend-only specs
└── issue-{ID}-{description}.md

frontend/specs/                           # Frontend-only specs
└── issue-{ID}-{description}.md

specs/                                    # Fullstack specs
└── issue-{ID}-{description}.md
```

**Spec Location Rules:**
- `stack:backend` → `backend/specs/`
- `stack:frontend` → `frontend/specs/`
- `stack:fullstack` → `specs/` (root)

### Test Paths

**Backend:**
```
backend/tests/
├── atoms/              # Atom layer tests
├── features/           # Feature layer tests
├── molecules/          # Molecule layer tests
├── organisms/          # Organism layer tests
└── integration/        # Cross-layer integration tests
```

**Frontend:**
```
frontend/src/__tests__/
├── atoms/              # Component unit tests
├── molecules/          # Composed component tests
├── organisms/          # Module integration tests
└── e2e/                # End-to-end tests
```

## Validation Commands

### Backend Quality Gates (in backend/)

**1. Format** (Auto-fix)
```bash
cd backend && uv run format
# Runs: ruff format .
```

**2. Lint**
```bash
cd backend && uv run lint
# Runs: ruff check --select ALL .
```

**3. Type Check**
```bash
cd backend && uv run typecheck
# Runs: mypy --strict app/
```

**4. Tests**
```bash
cd backend && uv run test
# Runs: pytest with coverage
# Requires: 80% minimum coverage
```

**5. Combined**
```bash
cd backend && uv run ci
# Runs all gates
```

### Frontend Quality Gates (in frontend/)

**1. Lint**
```bash
cd frontend && npm run lint
# Runs: eslint + prettier check
```

**2. Type Check**
```bash
cd frontend && npm run type-check
# Runs: tsc --noEmit
```

**3. Tests**
```bash
cd frontend && npm run test
# Runs: vitest
```

**4. Build**
```bash
cd frontend && npm run build
# Validates production build
```

**5. Combined**
```bash
cd frontend && npm run ci
# Runs all gates
```

### Full Monorepo Validation

**From project root:**
```bash
# Backend
cd backend && uv run ci && cd ..

# Frontend
cd frontend && npm run ci && cd ..

# Both (sequential)
(cd backend && uv run ci) && (cd frontend && npm run ci)
```

## Architecture Rules (Atomic Architecture v2.1)

### Layer Dependencies (Unidirectional Flow)
```
Organisms ────→ Molecules ────→ Features ────→ Atoms
   (UI)        (Business Logic)   (CRUD)    (Utilities)
```

**Rules**:
- ✅ Organisms CAN import from: Molecules, Features, Atoms
- ✅ Molecules CAN import from: Features, Atoms
- ✅ Features CAN import from: Atoms ONLY (preferably atoms/shared/)
- ✅ Atoms CAN import from: Other atoms ONLY (preferably atoms/shared/)
- ❌ NEVER import backwards (e.g., Atoms importing Features)
- ❌ NEVER cross-import within same layer (e.g., Feature A importing Feature B)

### Layer Responsibilities

**Atoms** - Foundation building blocks:
- Domain-agnostic utilities
- Infrastructure subsystems (cache, rate_limit)
- Database configuration (sessions, base models)
- Security primitives (JWT, hashing)
- Shared patterns (BasePattern, ActorPattern, CatalogPattern, etc)

**Features** - Data services:
- ONE model/table per feature
- Pure CRUD operations
- NO business logic
- NO cross-feature dependencies
- Service + Repository pattern

**Molecules** - Domain entities:
- Compose multiple feature services
- Business logic and orchestration
- Domain-specific workflows
- Permission facades (APIs)

**Organisms** - User interfaces:
- HTTP APIs (FastAPI routers)
- CLI commands
- MCP servers
- NO business logic (delegate to Molecules)

### Import Examples

**✅ CORRECT**:
```python
# In features/users/service.py
from pattern_stack.atoms.data import AsyncSession  # Atom
from pattern_stack.atoms.security import hash_password  # Atom

# In molecules/entities/user_profile.py
from pattern_stack.features.users import UserService  # Feature
from pattern_stack.features.preferences import PreferenceService  # Feature
from pattern_stack.atoms.cache import cache_get  # Atom

# In organisms/api/users.py
from pattern_stack.molecules.entities import UserProfile  # Molecule
from pattern_stack.features.users import UserResponse  # Feature
```

**❌ INCORRECT**:
```python
# In features/users/service.py
from pattern_stack.features.preferences import PreferenceService  # ❌ Feature → Feature

# In atoms/cache/redis.py
from pattern_stack.features.users import User  # ❌ Atom → Feature

# In molecules/entities/user.py
from pattern_stack.molecules.entities import Organization  # ❌ Molecule → Molecule
```

## Testing Strategy

### Test Requirements

**Coverage**:
- Minimum: 80% overall coverage
- New code: 90%+ coverage preferred
- Critical paths: 100% coverage + edge cases

**Test Types**:
1. **Unit Tests**: Isolated component testing, mocked dependencies
2. **Integration Tests**: Cross-layer interactions, real database (testcontainers)
3. **Benchmarks**: Performance regression detection

**TDD Requirements** (when applicable):
- **Bugs**: TDD required (write failing test first)
- **Features**: TDD optional but recommended
- **Refactoring**: Maintain existing test coverage

### Test Fixtures

Use `pattern_stack.testing` utilities:
```python
from pattern_stack.testing import async_session_fixture, test_user_factory
```

## Guidance Documents

### Primary References
- `CLAUDE.md` - Main project guidance for AI assistants
- `.claude/docs/agentic-workflow-architecture.md` - Workflow system architecture
- `.claude/patterns/core-principles.md` - Development principles
- `.claude/patterns/commit-patterns.md` - Git commit standards

### Architecture Documentation
- `docs/FIELD_ABSTRACTION.md` - Field pattern usage
- `docs/patterns/pattern-stack-framework-architecture-v2.md` - Framework architecture
- `docs/patterns/ADR-001-pattern-stack-framework-design.md` - Architecture decisions

### For Specific Patterns
- `docs/patterns/catalog-pattern-guide.md` - Catalog pattern implementation
- `docs/patterns/pattern-stack-pattern-configuration.md` - Pattern configuration
- `docs/patterns/pattern-stack-progressive-enhancement.md` - Progressive enhancement

## Commit Standards

### Format
```
<type>(<scope>): <description> (BE-XXX)

[optional body]

[optional footer]
```

### Types
- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Code restructuring
- `test`: Test additions/changes
- `docs`: Documentation updates
- `chore`: Maintenance tasks

### Scopes
Use layer-specific scopes:
- `atoms/<component>`: e.g., `atoms/cache`, `atoms/security`
- `features/<feature>`: e.g., `features/users`, `features/tasks`
- `molecules/<component>`: e.g., `molecules/entities`, `molecules/workflows`
- `organisms/<interface>`: e.g., `organisms/api`, `organisms/cli`

### Examples
```
feat(features/users): add user profile CRUD service (BE-101)
fix(atoms/cache): correct Redis connection timeout handling (BE-102)
test(molecules/entities): add comprehensive user entity tests (BE-103)
docs: update field abstraction guide with new patterns (BE-104)
```

## Development Workflow

### Standard Flow
1. Create Linear issue with proper labels (`type:feature`, `layer:*`)
2. Create feature branch: `feature/BE-XXX-description`
3. Generate spec in `specs/issue-BE-XXX-*.md`
4. Implement following spec (TDD if applicable)
5. Run quality gates: `make ci`
6. Create PR with spec links
7. Merge when approved + CI passes

### TDD Flow (for bugs)
1. Create failing test reproducing bug
2. Run `make test-ci` - verify failure
3. Implement minimal fix
4. Run `make test-ci` - verify pass
5. Refactor for quality
6. Run `make ci` - full validation

## Tool Configuration

### Package Management
```bash
uv sync --extra dev --extra test  # Install dependencies
uv add <package>                   # Add runtime dependency
uv add --dev <package>             # Add dev dependency
```

### Pre-commit Hooks
```bash
make pre-commit-install  # Install hooks
make pre-commit-run      # Run manually
```

### Database
```bash
make db-up              # Start PostgreSQL
make db-reset           # Reset database
make migrate            # Run migrations
make db-shell           # PostgreSQL CLI
```

## Common Patterns

### Creating a New Feature
```
1. Model in features/{name}/models.py (extends BasePattern)
2. Schemas in features/{name}/schemas/ (Pydantic)
3. Service in features/{name}/service.py (extends BaseService)
4. Tests in pattern_stack/__tests__/features/{name}/
5. Validation: make ci
```

### Creating a New Molecule Entity
```
1. Entity in molecules/entities/{name}.py (composes Feature services)
2. Tests in pattern_stack/__tests__/molecules/entities/
3. Optional: API facade in molecules/apis/
4. Validation: make ci
```

### Creating a New Organism API
```
1. Router in organisms/api/{name}.py (FastAPI)
2. Tests in pattern_stack/__tests__/organisms/api/
3. Register in organisms/api/__init__.py
4. Validation: make ci
```

## Project-Specific Notes

### Field Abstraction
Use `Field()` helper instead of raw SQLAlchemy:
```python
from pattern_stack.atoms.patterns import Field

class User(BasePattern):
    name = Field(str, required=True, max_length=100)
    email = Field(str, unique=True, required=True)
    age = Field(int, min=0, max=150, nullable=True)
```

### Pattern Configuration
Configure patterns via `Pattern` inner class:
```python
class User(BasePattern):
    class Pattern:
        entity = "user"
        reference_prefix = "USR"
        track_changes = True
```

### Async First
All services and repositories should be async:
```python
async def get_user(session: AsyncSession, user_id: UUID) -> User:
    ...
```

## External References

### Linear Integration

**Team**: BE (backend-patterns)

**Workflow States**: Backlog → Refinement → Ready → In Progress → In Review → Done

## Issue Management

### Label Structure

Pattern Stack uses a **multi-dimensional label system** for precise issue categorization:

#### 1. Work Type (`work:*`)
*What kind of work is this?*

- `work:architecture` - Architecture design, ADRs, system design
- `work:infrastructure` - Foundational, cross-cutting systems
- `work:feature` - New user-facing functionality
- `work:enhancement` - Improvements to existing functionality
- `work:documentation` - Docs, guides, examples

**When to use:**
- Architecture: Design docs, architectural decisions, system redesign
- Infrastructure: Logging, caching, database layer, patterns
- Feature: New endpoints, new services, new capabilities
- Enhancement: Performance improvements, UX improvements
- Documentation: README updates, guides, examples

#### 2. Issue Type (`type:*`)
*What type of issue is this?*

- `type:epic` - Parent ticket for multiple related issues
- `type:feature` - Feature development
- `type:enhancement` - Enhancement or improvement
- `type:chore` - Maintenance, refactoring, tooling
- `type:bug` - Bug reports and fixes
- `type:config` - Configuration system changes
- `type:source` - Source connector implementation
- `type:destination` - Destination connector implementation

**When to use:**
- Epic: Parent issue with 3+ sub-issues
- Feature: New functionality (create, not modify)
- Enhancement: Improve existing functionality
- Chore: Refactoring, dependency updates, tooling
- Bug: Fix broken behavior

#### 3. Architecture Layer (`layer:*`)
*Which architectural layer does this affect?*

- `layer:atoms` - Atoms layer (shared utilities, base components)
- `layer:features` - Features layer (data services, CRUD)
- `layer:molecules` - Molecules layer (entities, workflows, facades)
- `layer:organisms` - Organisms layer (HTTP API, CLI, MCP)

**When to use:**
- Atoms: Infrastructure, patterns, utilities, shared code
- Features: Service layer, repositories, models, schemas
- Molecules: Business logic, entities, orchestration
- Organisms: API endpoints, CLI commands, MCP servers

**Multiple layers:** If work spans layers, add multiple layer labels.

#### 4. Component (`component:*`)
*Which component/subsystem is affected?*

- `component:logging` - Logging and observability
- `component:middleware` - Middleware components
- `component:workflow` - Workflow components
- `component:api-facade` - API facade components
- `component:entity` - Entity components

**When to use:** Add when work is focused on a specific subsystem.

#### 5. Domain (`domain:*`)
*Which business domain?*

- `domain:tasks` - Task/issue management features
- `domain:teams` - Team operations and configuration
- `domain:projects` - Project/milestone features
- `domain:labels` - Label management and hierarchy
- `domain:sync` - Integration/sync functionality
- `domain:reporting` - Analytics/insights features

**When to use:** Add when work is domain-specific (mostly for business features).

#### 6. Priority/Context Tags

- `mvp` - Must-have for MVP/v1.0
- `priority:high` - High priority (not blocking, but important)
- `demo` - Demo application related
- `finance-tracker` - Finance tracker example app
- `example` - Example/tutorial code
- `docs` - Documentation
- `backend` - Backend related
- `authentication` - Auth related features

### Label Combination Patterns

#### Infrastructure Work (Logging Example)
```yaml
labels:
  - type:epic              # It's a parent issue
  - work:infrastructure    # Infrastructure work
  - layer:atoms            # Affects atoms layer
  - component:logging      # Logging subsystem
  - backend                # Backend work
  - mvp                    # Must-have for production
```

#### Feature Development
```yaml
labels:
  - type:feature           # New feature
  - work:feature           # Feature work
  - layer:features         # Service layer
  - domain:tasks           # Task management domain
  - backend                # Backend work
```

#### Bug Fix
```yaml
labels:
  - type:bug               # Bug fix
  - work:enhancement       # Improving behavior
  - layer:organisms        # API layer
  - priority:high          # High priority
```

#### Documentation
```yaml
labels:
  - type:chore             # Maintenance work
  - work:documentation     # Documentation work
  - docs                   # Documentation tag
```

### Label Guidelines

**Minimum Labels (ALWAYS include):**
1. One `type:*` label (what type of issue)
2. One `work:*` label (what kind of work)
3. One or more `layer:*` labels (which layers affected)

**Optional Labels:**
- `component:*` - If work is component-specific
- `domain:*` - If work is domain-specific
- Priority/context tags - As appropriate

**Bad Examples:**
```yaml
# ❌ Too few labels (missing work type and layer)
labels:
  - type:feature

# ❌ Conflicting labels
labels:
  - type:epic
  - type:feature           # Can't be both

# ❌ Wrong work type for issue type
labels:
  - type:bug
  - work:feature           # Bugs are enhancements, not features
```

**Good Examples:**
```yaml
# ✅ Complete labeling
labels:
  - type:feature
  - work:infrastructure
  - layer:atoms
  - component:logging
  - backend
  - mvp

# ✅ Multi-layer work
labels:
  - type:epic
  - work:infrastructure
  - layer:atoms
  - layer:organisms        # Affects multiple layers
  - component:middleware

# ✅ Simple bug fix
labels:
  - type:bug
  - work:enhancement
  - layer:features
  - priority:high
```

### Status Workflow

**Backlog** → **Refinement** → **Ready** → **In Progress** → **In Review** → **Done**

**State Meanings:**
- **Backlog**: Captured but not refined
- **Refinement**: Being refined, needs spec/clarification
- **Ready**: Spec complete, ready for implementation
- **In Progress**: Actively being worked on
- **In Review**: PR open, awaiting review
- **Done**: Merged and complete

**Transitions:**
```bash
tp update BE-XXX --status "Refinement"    # Start refining
tp update BE-XXX --status "Ready"         # Spec complete
tp update BE-XXX --status "In Progress"   # Start working
tp update BE-XXX --status "In Review"     # PR created
tp update BE-XXX --status "Done"          # Merged
```

### Label Management Commands

**Discover Labels:**
```bash
# List all labels for team
tp labels list --team BE

# Show labels on specific issue
tp update BE-XXX --list-labels
```

**Add Labels:**
```bash
# Append labels (keeps existing)
tp update BE-XXX --add-labels "type:feature,layer:atoms,mvp"

# Replace all labels
tp update BE-XXX --set-labels "type:feature,layer:atoms"
```

**Remove Labels:**
```bash
# Remove specific labels
tp update BE-XXX --remove-labels "mvp"
```

**Create New Labels:**
```bash
# Create with description
tp labels create "work:testing" "Testing and QA work" --team BE

# Verify creation
tp labels list --team BE | grep testing
```

### Priority Guidelines

**Use `mvp` for:**
- Production blockers
- Core functionality required for v1.0
- Infrastructure critical for framework operation

**Use `priority:high` for:**
- Important but not blocking
- Should be done soon but can be deferred
- Significant value but not critical path

**Use neither for:**
- Nice-to-have features
- Future enhancements
- Non-urgent improvements

### GitHub
- Branch protection: main (requires PR + CI)
- CI: GitHub Actions (runs `make ci`)
- PR template: Links to specs + Linear issues

---

**Last Updated**: 2025-10-31
**Maintained By**: Pattern Stack Team
**For Questions**: See CLAUDE.md or .claude/docs/
