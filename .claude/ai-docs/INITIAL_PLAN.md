# Tempo CRM - Product Requirements Document
## MVP Proof of Concept

**Version:** 1.0
**Date:** 2025-10-30
**Status:** Draft - Planning Phase
**Purpose:** Demonstrate Pattern Stack framework capabilities through functional CRM prototype

---

## 1. Executive Summary

### Product Vision
Tempo is a modern sales intelligence CRM that aggregates context from multiple sources (meetings, emails, notes) and uses AI to provide actionable next steps for sales teams. Unlike traditional CRMs that are data entry burdens, Tempo focuses on intelligence augmentation and collaborative deal management.

### MVP Objectives
1. **Prove Pattern Stack Viability**: Demonstrate that Pattern Stack can rapidly build production-ready applications with clean, maintainable architecture
2. **Showcase Framework Features**: Utilize Pattern Stack's patterns (Catalog, Actor, Event, Temporal) in real-world scenarios
3. **Deliver Functional Prototype**: Build working software that demonstrates core value proposition
4. **Validate Architecture**: Show that the atomic architecture scales from simple CRUD to complex workflows

### Success Criteria
- ✅ Sales reps can manage deals through pipeline stages
- ✅ Team can see real-time activity feed of deal changes
- ✅ AI generates context-aware next steps for deals
- ✅ Semantic search finds deals by meeting/conversation content
- ✅ Code demonstrates clean Pattern Stack architecture patterns
- ✅ Deployment-ready with authentication and authorization

---

## 2. User Personas

### Primary: Sarah (Sales Representative)
- **Role**: Individual contributor closing deals
- **Goals**:
  - Track multiple deals through pipeline efficiently
  - Remember context from past conversations
  - Know what to do next on each deal
  - Update deal status quickly
- **Pain Points**:
  - Forgetting details from meetings weeks ago
  - Context switching between many deals
  - Not knowing which deals need attention
  - CRM data entry taking time from selling

### Secondary: Marcus (Sales Manager)
- **Role**: Team lead managing 5-10 sales reps
- **Goals**:
  - Visibility into team's pipeline health
  - Understand blockers on key deals
  - Coach team based on deal activity
  - Forecast revenue accurately
- **Pain Points**:
  - Reps not updating CRM consistently
  - Lack of context on deal status
  - Can't see what reps are actually doing
  - Forecasting based on guesses

### Tertiary: Alex (System Administrator)
- **Role**: Technical admin managing Tempo deployment
- **Goals**:
  - Easy deployment and configuration
  - User management and permissions
  - Data security and backup
  - Integration with company tools
- **Pain Points**:
  - Complex enterprise software setup
  - Security compliance requirements
  - Managing user access
  - System monitoring and maintenance

---

## 3. Core User Stories

### Epic 1: Account Management
**As a sales rep, I want to manage my accounts so that I can track deals through my pipeline**

#### US-1.1: Create Account
```
Given I am authenticated as a sales rep
When I create a new account with company name "Acme Corp"
Then the account appears in my accounts list
And the account starts in "Prospect" stage
And I am set as the account owner
```

#### US-1.2: View Accounts Table
```
Given I have multiple accounts in the system
When I view my accounts page
Then I see a table showing:
  - Account name
  - Current stage (Prospect, Qualifying, Presenting, Closing)
  - Actual Value ($)
  - ACV (Annual Contract Value)
  - Next meeting date
  - AI-generated next steps
  - Last updated timestamp
And I can sort by any column
And I can filter by stage
And I can search by account name
```

#### US-1.3: Update Account Stage
```
Given I have an account in "Qualifying" stage
When I move it to "Presenting" stage
Then the stage updates immediately
And an activity is logged: "Sarah moved Acme Corp to Presenting"
And all team members see the update in real-time
And the AI regenerates next steps for the new stage
```

#### US-1.4: Inline Edit Account Fields
```
Given I am viewing an account in the table
When I click on the "Actual Value" field
Then the field becomes editable in-place
When I update the value to $125,000
Then the change saves automatically
And an activity is logged
And the table updates without page refresh
```

### Epic 2: AI-Powered Intelligence

#### US-2.1: Add Context to Account
```
Given I have an account "Acme Corp"
When I add context: "Had great meeting with CTO. They love our API integration story but concerned about pricing for their volume. Mentioned they're also talking to competitor XYZ."
Then the context is stored with embedding for semantic search
And the context appears in the account's activity feed
And the AI next steps regenerate to address pricing concerns
```

#### US-2.2: Generate AI Next Steps
```
Given an account has context from multiple meetings/emails
When the account stage changes or new context is added
Then the AI analyzes all context and generates 2-3 actionable next steps
Such as: "Schedule pricing discussion with finance team to address volume concerns"
And these next steps appear in the account table view
And next steps are updated as context evolves
```

#### US-2.3: Semantic Search
```
Given multiple accounts with various meeting notes
When I search for "pricing concerns"
Then I see all accounts where pricing was discussed
Even if the exact phrase "pricing concerns" wasn't used
And results are ranked by relevance
And I can filter by: Account, Source, Last Updated
```

#### US-2.4: Natural Language Search
```
Given I search for "Starbucks at every meeting"
Then the system finds accounts where "Starbucks" appears in meeting context
And understands this is searching meeting content, not account names
And shows relevant accounts with highlighted matching context
```

### Epic 3: Team Collaboration

#### US-3.1: Activity Feed
```
Given I am viewing an account
When team members make changes
Then I see a real-time activity feed showing:
  - Who made the change
  - What changed
  - When it happened (relative time: "2 hr. ago")
  - The change content
And new activities appear without page refresh
And I can see my own changes immediately (optimistic updates)
```

#### US-3.2: Comment on Account
```
Given I am viewing an account
When I add a comment: "Should we have more than 20 accounts per page?"
Then the comment appears in the activity feed
And team members are notified
And the comment is timestamped and attributed to me
```

#### US-3.3: Activity Notifications
```
Given I am collaborating on shared accounts
When a team member updates an account I'm watching
Then I see an "Updates" counter in the navigation (e.g., "25")
And I can click to see which accounts have new activity
And the counter clears when I view the updates
```

### Epic 4: User Management

#### US-4.1: User Authentication
```
Given I am a registered user
When I log in with email and password
Then I receive a JWT token
And I can access protected account routes
And my token expires after 24 hours
```

#### US-4.2: User Authorization
```
Given I am authenticated as a sales rep
When I try to view accounts
Then I only see accounts I own or are shared with me
And I cannot see other reps' private accounts
And I cannot access admin functions
```

#### US-4.3: Team Management
```
Given I am an admin
When I invite a new team member
Then they receive an invitation email
And they can set their password
And they are assigned a default role (sales_rep)
And they appear in the team directory
```

---

## 4. Functional Requirements

### 4.1 Account Management (Core)

#### FR-1.1: Account Data Model
- **Fields:**
  - `id` (UUID, primary key)
  - `name` (String, required, max 255 chars)
  - `stage` (Enum: prospect, qualifying, presenting, closing, won, lost)
  - `actual_value` (Decimal, nullable)
  - `acv` (Decimal, nullable) - Annual Contract Value
  - `next_meeting` (DateTime, nullable)
  - `ai_next_steps` (Text, nullable) - AI-generated
  - `owner_id` (UUID, foreign key to users)
  - `created_at` (DateTime, auto)
  - `updated_at` (DateTime, auto)
  - `created_by` (UUID, foreign key to users)
  - `updated_by` (UUID, foreign key to users)

- **Stage Transitions (State Machine):**
  ```
  prospect → [qualifying, archived]
  qualifying → [presenting, prospect, archived]
  presenting → [closing, qualifying, archived]
  closing → [won, lost]
  won → []
  lost → [prospect]  (reopen capability)
  ```

- **Business Rules:**
  - Account name must be unique per owner
  - Stage transitions must follow state machine
  - Moving to "won" requires actual_value > 0
  - Cannot delete accounts with stage "won" (archive only)

#### FR-1.2: Account CRUD Operations
- **Create:** POST /api/v1/accounts
  - Validates required fields
  - Sets owner to current user
  - Initial stage = "prospect"
  - Triggers AI next steps generation
  - Logs creation activity

- **Read:** GET /api/v1/accounts
  - Returns paginated list (default 20, configurable)
  - Supports filtering: stage, owner_id, date_range
  - Supports sorting: name, stage, actual_value, next_meeting, updated_at
  - Supports search: name (full-text)
  - Only returns accounts user has access to

- **Update:** PATCH /api/v1/accounts/{id}
  - Validates stage transitions
  - Updates updated_at and updated_by
  - Logs field changes as activities
  - Triggers AI next steps regeneration on stage change
  - Emits WebSocket event for real-time updates

- **Delete:** DELETE /api/v1/accounts/{id}
  - Soft delete (sets archived flag)
  - Requires permission check
  - Logs deletion activity

#### FR-1.3: Stage Management
- **Transition Account:** POST /api/v1/accounts/{id}/transition
  - Request body: `{ "new_stage": "presenting" }`
  - Validates transition is allowed
  - Updates account.stage
  - Triggers activity log: "User moved Account to Presenting"
  - Triggers AI next steps regeneration
  - Emits WebSocket event

### 4.2 Activity Tracking

#### FR-2.1: Activity Data Model
- **Fields:**
  - `id` (UUID, primary key)
  - `account_id` (UUID, foreign key, required)
  - `actor_id` (UUID, foreign key to users, required)
  - `activity_type` (String: comment, context_add, field_edit, stage_change)
  - `content` (JSONB) - Polymorphic content by type
  - `created_at` (DateTime, auto)
  - `metadata` (JSONB, nullable) - Additional structured data

- **Activity Types:**
  - `comment`: User comment on account
    ```json
    {
      "comment_text": "Should we have more than 20 accounts per page?",
      "mentions": ["user_id_1", "user_id_2"]
    }
    ```

  - `context_add`: Context/notes added
    ```json
    {
      "context": "Great meeting with CTO...",
      "source": "manual"
    }
    ```

  - `field_edit`: Field value changed
    ```json
    {
      "field": "actual_value",
      "old_value": 100000,
      "new_value": 125000
    }
    ```

  - `stage_change`: Deal stage transition
    ```json
    {
      "from_stage": "qualifying",
      "to_stage": "presenting"
    }
    ```

#### FR-2.2: Activity Feed API
- **Get Activities:** GET /api/v1/accounts/{id}/activities
  - Returns paginated list (default 50)
  - Sorted by created_at DESC (newest first)
  - Includes actor information (name, avatar)
  - Supports filtering by activity_type
  - Supports date range filtering

- **Create Activity (automatic):**
  - Activities are auto-created by system on account changes
  - No direct POST endpoint (except comments)

- **Add Comment:** POST /api/v1/accounts/{id}/activities
  - Request body: `{ "activity_type": "comment", "content": { "comment_text": "..." } }`
  - Creates activity record
  - Emits WebSocket event
  - Notifies mentioned users (future)

### 4.3 Context & AI Intelligence

#### FR-3.1: Context Data Model
- **Fields:**
  - `id` (UUID, primary key)
  - `account_id` (UUID, foreign key, required)
  - `source_type` (Enum: manual, email, meeting, integration)
  - `content` (Text, required) - The actual context/note
  - `embedding` (Vector, 1536 dimensions) - OpenAI embedding
  - `extracted_entities` (JSONB, nullable) - AI-extracted: people, topics, dates
  - `created_by` (UUID, foreign key to users)
  - `created_at` (DateTime, auto)

- **Indexes:**
  - Vector index on embedding (HNSW for fast similarity search)
  - Full-text index on content (PostgreSQL tsvector)
  - B-tree index on account_id, created_at

#### FR-3.2: Context Management API
- **Add Context:** POST /api/v1/accounts/{id}/context
  - Request: `{ "content": "Meeting notes...", "source_type": "manual" }`
  - Generates embedding (async)
  - Stores context
  - Triggers AI next steps regeneration
  - Logs activity

- **Get Context:** GET /api/v1/accounts/{id}/context
  - Returns all context for account
  - Ordered by created_at DESC
  - Includes source_type and creator info

#### FR-3.3: AI Next Steps Generation
- **Trigger:** Automatic on:
  - Account stage change
  - New context added
  - Manual regeneration request

- **Process:**
  1. Fetch all context for account (last 30 days)
  2. Construct prompt with:
     - Account name and stage
     - Aggregated context (max 4000 tokens)
     - Previous next steps (for continuity)
  3. Call LLM (GPT-4) with prompt
  4. Parse response into 2-3 actionable steps
  5. Update account.ai_next_steps field
  6. Log generation activity

- **Prompt Template:**
  ```
  You are a sales assistant analyzing a deal.

  Account: {account_name}
  Stage: {stage}
  Value: ${actual_value}

  Recent Context:
  {aggregated_context}

  Previous Next Steps:
  {previous_steps}

  Based on this information, provide 2-3 specific, actionable next steps
  for the sales rep to move this deal forward. Focus on:
  - Addressing mentioned concerns
  - Building momentum for next stage
  - Concrete actions with clear outcomes

  Format as a brief list.
  ```

#### FR-3.4: Semantic Search
- **Endpoint:** GET /api/v1/search
- **Query Parameters:**
  - `q` (string, required) - Search query
  - `search_type` (enum: semantic, fulltext, hybrid) - Default: hybrid
  - `account_filter` (string) - Filter by account name
  - `source_filter` (string) - Filter by context source
  - `date_from` (date) - Filter by date range
  - `date_to` (date)
  - `limit` (int) - Max results (default 20)

- **Search Process (Hybrid):**
  1. **Semantic Search:**
     - Generate embedding for query
     - Vector similarity search against context.embedding
     - Returns top 100 by cosine similarity

  2. **Full-Text Search:**
     - PostgreSQL full-text search on context.content
     - Returns top 100 by BM25 rank

  3. **Hybrid Ranking:**
     - Combine results with weighted scores
     - Semantic: 0.6, Full-text: 0.4
     - Deduplicate and re-rank
     - Return top N

- **Response:**
  ```json
  {
    "results": [
      {
        "account_id": "uuid",
        "account_name": "Acme Corp",
        "context_preview": "...pricing concerns...",
        "match_score": 0.87,
        "created_at": "2025-01-15T10:00:00Z"
      }
    ],
    "total": 15,
    "search_type": "hybrid"
  }
  ```

### 4.4 Real-Time Updates

#### FR-4.1: WebSocket Connection
- **Endpoint:** WS /api/v1/ws
- **Authentication:** JWT token in query param or header
- **Connection Lifecycle:**
  - Client connects with auth token
  - Server validates token
  - Server subscribes client to their account channels
  - Heartbeat every 30 seconds

#### FR-4.2: Event Broadcasting
- **Events to Broadcast:**
  - `account.updated` - Any account field change
  - `account.stage_changed` - Stage transition
  - `activity.created` - New activity on account
  - `comment.created` - New comment

- **Event Payload:**
  ```json
  {
    "event": "account.updated",
    "account_id": "uuid",
    "changes": {
      "field": "actual_value",
      "old": 100000,
      "new": 125000
    },
    "actor": {
      "id": "uuid",
      "name": "Sarah Smith"
    },
    "timestamp": "2025-01-15T10:30:00Z"
  }
  ```

- **Channel Subscriptions:**
  - User subscribes to: `accounts:owned:user_id` (their accounts)
  - User subscribes to: `accounts:shared:user_id` (shared accounts)
  - Admin subscribes to: `accounts:all` (all accounts)

#### FR-4.3: Optimistic Updates
- Frontend immediately reflects user's own changes
- Backend confirms or rolls back via WebSocket
- Conflict resolution: last-write-wins with notification

### 4.5 User Management & Authentication

#### FR-5.1: User Data Model
- **Fields:**
  - `id` (UUID, primary key)
  - `email` (String, unique, required)
  - `full_name` (String, required)
  - `password_hash` (String, required) - bcrypt
  - `role` (Enum: admin, sales_manager, sales_rep, viewer)
  - `is_active` (Boolean, default true)
  - `last_login_at` (DateTime, nullable)
  - `created_at` (DateTime, auto)

- **Roles & Permissions:**
  - `admin`: Full system access, user management
  - `sales_manager`: View team accounts, limited admin
  - `sales_rep`: CRUD own accounts, view shared accounts
  - `viewer`: Read-only access to shared accounts

#### FR-5.2: Authentication API
- **Register:** POST /api/v1/auth/register
  - Request: `{ "email": "...", "password": "...", "full_name": "..." }`
  - Validates email uniqueness
  - Hashes password (bcrypt)
  - Creates user with role "sales_rep"
  - Returns JWT token

- **Login:** POST /api/v1/auth/login
  - Request: `{ "email": "...", "password": "..." }`
  - Validates credentials
  - Updates last_login_at
  - Returns JWT token (24hr expiry)
  - Token payload: `{ "user_id": "...", "role": "...", "exp": ... }`

- **Logout:** POST /api/v1/auth/logout
  - Invalidates token (via blacklist or short expiry)

- **Refresh Token:** POST /api/v1/auth/refresh
  - Accepts valid JWT
  - Issues new token with extended expiry
  - Returns new JWT

#### FR-5.3: Authorization Middleware
- **Protected Routes:**
  - All `/api/v1/accounts/*` require authentication
  - All `/api/v1/search/*` require authentication
  - `/api/v1/admin/*` require role=admin

- **Resource Permissions:**
  - Users can only access accounts they own
  - Managers can access accounts owned by their team
  - Admins can access all accounts

---

## 5. Non-Functional Requirements

### NFR-1: Performance
- **Response Time:**
  - GET requests: < 200ms (p95)
  - POST/PATCH requests: < 500ms (p95)
  - Search requests: < 1000ms (p95)
  - WebSocket latency: < 100ms

- **Throughput:**
  - Support 100 concurrent users
  - 1000 requests/minute sustained
  - 50 concurrent WebSocket connections

- **Database:**
  - Queries optimized with proper indexes
  - N+1 queries eliminated
  - Connection pooling (max 20 connections)

### NFR-2: Scalability
- **Horizontal Scaling:**
  - Stateless API servers (can run multiple instances)
  - Redis pub/sub for WebSocket scaling
  - Database connection pooling

- **Data Volume:**
  - Support 10,000 accounts per organization
  - 100,000 activities total
  - 50,000 context entries

### NFR-3: Security
- **Authentication:**
  - JWT tokens with expiration
  - Bcrypt password hashing (12 rounds)
  - HTTPS only in production

- **Authorization:**
  - Role-based access control (RBAC)
  - Row-level security on accounts
  - API rate limiting (100 req/min per user)

- **Data Protection:**
  - SQL injection prevention (parameterized queries)
  - XSS prevention (output encoding)
  - CSRF protection (token-based)
  - Secrets in environment variables

### NFR-4: Reliability
- **Availability:**
  - 99% uptime for MVP
  - Graceful degradation (AI optional)
  - Health check endpoint

- **Data Integrity:**
  - Database transactions for multi-table operations
  - Foreign key constraints
  - Validation at API and DB levels

- **Error Handling:**
  - Structured error responses
  - Logging to stdout (JSON format)
  - Error tracking (Sentry integration ready)

### NFR-5: Maintainability
- **Code Quality:**
  - 80%+ test coverage
  - Type hints throughout (MyPy validated)
  - Linting (Ruff) with zero violations
  - Architecture validation (layer boundaries)

- **Documentation:**
  - API documentation (OpenAPI/Swagger)
  - README with setup instructions
  - Architecture decision records (ADRs)
  - Inline code comments for complex logic

---

## 6. Data Model

### 6.1 Entity Relationship Diagram

```
┌─────────────────┐
│     Users       │
│─────────────────│
│ id (PK)         │
│ email (UNIQUE)  │
│ password_hash   │
│ full_name       │
│ role            │
│ is_active       │
│ created_at      │
└────────┬────────┘
         │
         │ owns
         │
         ▼
┌─────────────────┐      ┌──────────────────┐
│    Accounts     │      │    Activities    │
│─────────────────│      │──────────────────│
│ id (PK)         │◄─────│ id (PK)          │
│ name            │      │ account_id (FK)  │
│ stage           │      │ actor_id (FK)    │
│ actual_value    │      │ activity_type    │
│ acv             │      │ content (JSONB)  │
│ next_meeting    │      │ created_at       │
│ ai_next_steps   │      └──────────────────┘
│ owner_id (FK)   │
│ created_by (FK) │      ┌──────────────────┐
│ updated_by (FK) │      │     Contexts     │
│ created_at      │      │──────────────────│
│ updated_at      │◄─────│ id (PK)          │
└─────────────────┘      │ account_id (FK)  │
                         │ source_type      │
                         │ content (TEXT)   │
                         │ embedding (VECTOR)│
                         │ extracted_entities│
                         │ created_by (FK)  │
                         │ created_at       │
                         └──────────────────┘
```

### 6.2 Pattern Stack Pattern Mapping

| Entity | Pattern Stack Patterns | Rationale |
|--------|------------------------|-----------|
| **Account** | CatalogPattern + ActorPattern + EventPattern | - CatalogPattern: Reference data fields (name, code)<br>- ActorPattern: Ownership tracking (owner_id, created_by)<br>- EventPattern: State machine (stage transitions) |
| **Activity** | BasePattern + ActorPattern + TemporalPattern | - BasePattern: Core fields (id, timestamps)<br>- ActorPattern: Who performed activity<br>- TemporalPattern: Time-based ordering, validity |
| **Context** | BasePattern + ActorPattern | - BasePattern: Core fields<br>- ActorPattern: Who added context |
| **User** | ActorPattern + EventPattern | - ActorPattern: User identity<br>- EventPattern: Account state (active, suspended) |

---

## 7. API Design

### 7.1 API Structure

**Base URL:** `/api/v1`

**Authentication:** Bearer token in `Authorization` header

**Response Format:**
```json
{
  "success": true,
  "data": { ... },
  "error": null,
  "meta": {
    "timestamp": "2025-01-15T10:00:00Z",
    "request_id": "uuid"
  }
}
```

### 7.2 Endpoint Summary

#### Authentication
```
POST   /api/v1/auth/register      - Create new user account
POST   /api/v1/auth/login         - Authenticate and get JWT
POST   /api/v1/auth/logout        - Invalidate token
POST   /api/v1/auth/refresh       - Refresh JWT token
GET    /api/v1/auth/me            - Get current user info
```

#### Accounts
```
GET    /api/v1/accounts           - List accounts (paginated, filtered)
POST   /api/v1/accounts           - Create new account
GET    /api/v1/accounts/{id}      - Get account details
PATCH  /api/v1/accounts/{id}      - Update account fields
DELETE /api/v1/accounts/{id}      - Soft delete (archive) account
POST   /api/v1/accounts/{id}/transition - Change account stage
```

#### Activities
```
GET    /api/v1/accounts/{id}/activities     - Get activity feed
POST   /api/v1/accounts/{id}/activities     - Add comment/manual activity
```

#### Context
```
GET    /api/v1/accounts/{id}/context        - Get all context for account
POST   /api/v1/accounts/{id}/context        - Add context/notes
PATCH  /api/v1/accounts/{id}/context/{ctx_id} - Edit context
DELETE /api/v1/accounts/{id}/context/{ctx_id} - Delete context
```

#### Search
```
GET    /api/v1/search             - Semantic + full-text search
GET    /api/v1/search/recent      - Get user's recent searches
```

#### AI
```
POST   /api/v1/accounts/{id}/ai/regenerate  - Manually regenerate next steps
```

#### Admin
```
GET    /api/v1/admin/users        - List all users
POST   /api/v1/admin/users/{id}/activate   - Activate user
POST   /api/v1/admin/users/{id}/deactivate - Deactivate user
PATCH  /api/v1/admin/users/{id}/role       - Change user role
```

#### Health
```
GET    /api/v1/health             - Health check endpoint
GET    /api/v1/health/ready       - Readiness check (DB + dependencies)
```

### 7.3 WebSocket Events

**Connection:** `WS /api/v1/ws?token={jwt}`

**Events Published:**
```
account.created       - New account created
account.updated       - Account field(s) changed
account.stage_changed - Deal stage transitioned
activity.created      - New activity logged
comment.created       - New comment added
```

**Client Subscriptions:**
```javascript
ws.send(JSON.stringify({
  action: "subscribe",
  channel: "accounts:owned:user_id"
}))
```

---

## 8. Technical Architecture

### 8.1 Technology Stack

**Backend:**
- Python 3.11+
- FastAPI (web framework)
- SQLAlchemy 2.0 (ORM)
- PostgreSQL 15+ (database)
- pgvector (vector similarity search)
- Redis (caching, pub/sub for WebSocket)
- OpenAI API (embeddings + LLM)

**Frontend:**
- React 18.3+
- TypeScript 5.0+
- Pattern Stack Frontend Patterns (base components)
- TanStack Query (data fetching)
- Zustand (state management)
- WebSocket (native API)

**Infrastructure:**
- Docker (containerization)
- Docker Compose (local development)
- GitHub Actions (CI/CD)

### 8.2 Pattern Stack Integration

**Backend Structure (Atomic Architecture v2.5):**

```
tempo-backend/
├── atoms/                      # Foundation layer
│   ├── patterns/              # Pattern base classes (from Pattern Stack)
│   ├── shared/                # Core dependencies
│   ├── security/              # Auth, JWT
│   ├── ai/                    # AI integration utilities (NEW)
│   │   ├── embeddings.py     # Vector embedding generation
│   │   ├── llm.py            # LLM client wrapper
│   │   └── prompts.py        # Prompt templates
│   ├── search/                # Search infrastructure (NEW)
│   │   ├── vector.py         # pgvector integration
│   │   └── fulltext.py       # PostgreSQL FTS
│   └── websocket/             # WebSocket utilities (NEW)
│       └── manager.py        # Connection manager
│
├── features/                   # Data services layer
│   ├── account/
│   │   ├── models.py          # Account model (uses patterns)
│   │   ├── service.py         # Account CRUD service
│   │   ├── schemas/           # Pydantic schemas
│   │   └── repository.py      # Complex queries (optional)
│   ├── activity/
│   │   ├── models.py          # Activity model
│   │   ├── service.py         # Activity service
│   │   └── types.py           # Activity type definitions
│   ├── context/
│   │   ├── models.py          # Context model
│   │   ├── service.py         # Context service
│   │   └── search.py          # Search service
│   └── user/
│       ├── models.py          # User model
│       └── service.py         # User service
│
├── molecules/                  # Domain entities & workflows
│   ├── entities/
│   │   └── sales.py           # SalesEntity (composes services)
│   ├── workflows/
│   │   ├── deal_progression.py      # Deal stage workflow
│   │   ├── context_aggregation.py   # Context + embedding workflow
│   │   └── ai_generation.py         # AI next steps generation
│   └── apis/
│       └── sales_api.py       # Permission facade
│
└── organisms/                  # User interfaces
    ├── api/v1/
    │   ├── accounts.py        # Account endpoints
    │   ├── activities.py      # Activity endpoints
    │   ├── search.py          # Search endpoints
    │   ├── auth.py            # Auth endpoints
    │   └── admin.py           # Admin endpoints
    ├── websocket/
    │   └── activity_feed.py   # WebSocket handler
    └── dependencies/
        ├── auth.py            # Auth dependencies
        └── database.py        # DB session dependencies
```

**Frontend Structure:**

```
tempo-frontend/
├── atoms/                      # Base components (from frontend-patterns)
│   └── @pattern-stack/frontend-patterns
│
├── molecules/                  # Composed components
│   ├── AccountTable/
│   │   ├── AccountRow.tsx
│   │   ├── AccountTableHeader.tsx
│   │   └── InlineEditCell.tsx
│   ├── ActivityFeed/
│   │   ├── ActivityItem.tsx
│   │   └── ActivityList.tsx
│   └── SearchModal/
│       ├── SearchInput.tsx
│       └── SearchResults.tsx
│
├── organisms/                  # Full features
│   ├── AccountList/
│   │   ├── AccountListView.tsx
│   │   ├── FilterPanel.tsx
│   │   └── StageKanban.tsx (future)
│   └── Navigation/
│       ├── Sidebar.tsx
│       └── TopBar.tsx
│
└── pages/
    ├── AccountsPage.tsx
    ├── LoginPage.tsx
    └── SearchPage.tsx
```

### 8.3 External Dependencies

**Required APIs:**
- OpenAI API (embeddings + GPT-4) - $0.10/1M tokens (embedding), $10/1M tokens (GPT-4)
- Alternative: Anthropic Claude API for LLM

**Optional Integrations (Post-MVP):**
- Email (Gmail/Outlook API)
- Calendar (Google/Outlook Calendar API)
- CRM Connectors (Salesforce, HubSpot)

---

## 9. Success Metrics

### 9.1 Technical Metrics
- ✅ All endpoints return < 500ms (p95)
- ✅ 80%+ test coverage
- ✅ Zero critical security vulnerabilities
- ✅ Architecture validation passes (no layer violations)
- ✅ Type checking passes (MyPy strict mode)

### 9.2 Functional Metrics
- ✅ Sales rep can create account in < 30 seconds
- ✅ Search returns relevant results in < 1 second
- ✅ AI next steps generated in < 5 seconds
- ✅ Real-time updates appear in < 1 second
- ✅ No data loss on stage transitions

### 9.3 Demonstration Metrics
- ✅ Can demo full user flow: create account → add context → search → collaborate
- ✅ Code demonstrates all major Pattern Stack patterns
- ✅ Architecture is explained and defensible
- ✅ Deployment is reproducible (Docker Compose)

---

## 10. Out of Scope (Post-MVP)

The following features are **explicitly excluded** from MVP to maintain focus:

### 10.1 Advanced Features
- ❌ Email integration (context from emails)
- ❌ Calendar integration (meeting context)
- ❌ File attachments on accounts
- ❌ Advanced analytics dashboard
- ❌ Revenue forecasting
- ❌ Pipeline reporting
- ❌ Export to CSV/PDF
- ❌ Bulk operations (multi-select, bulk edit)

### 10.2 Enterprise Features
- ❌ Multi-organization/tenancy
- ❌ Custom fields
- ❌ Workflow automation rules
- ❌ Integration marketplace
- ❌ SSO (SAML, OAuth)
- ❌ Audit logs
- ❌ Data retention policies

### 10.3 Mobile & Offline
- ❌ Mobile apps (iOS, Android)
- ❌ Offline mode
- ❌ Mobile-optimized UI

### 10.4 Advanced AI
- ❌ Custom AI models
- ❌ Sentiment analysis
- ❌ Automated email drafting
- ❌ Predictive deal scoring
- ❌ Churn prediction

---

## 11. Development Phases

### Phase 1: Foundation (Week 1)
**Goal:** Basic account management working

- ✅ Set up project structure (Pattern Stack)
- ✅ Database schema + migrations
- ✅ Account model with patterns
- ✅ Account CRUD endpoints
- ✅ Basic auth (register, login)
- ✅ Frontend account list view
- ✅ Tests for core functionality

**Deliverable:** Can create and list accounts via API + UI

### Phase 2: State Management (Week 2)
**Goal:** Deal stages and activity tracking

- ✅ EventPattern for stage transitions
- ✅ Stage transition endpoint
- ✅ Activity model and service
- ✅ Automatic activity logging
- ✅ Activity feed API
- ✅ Frontend stage management UI
- ✅ Inline editing

**Deliverable:** Can move deals through pipeline with activity log

### Phase 3: AI Integration (Week 3)
**Goal:** Context storage and AI next steps

- ✅ Context model with pgvector
- ✅ OpenAI embedding generation
- ✅ Context API endpoints
- ✅ AI next steps generation workflow
- ✅ LLM integration (GPT-4)
- ✅ Frontend context UI

**Deliverable:** Can add context and see AI-generated next steps

### Phase 4: Search & Real-time (Week 4)
**Goal:** Semantic search and live updates

- ✅ Vector similarity search
- ✅ Full-text search
- ✅ Hybrid search ranking
- ✅ Search API endpoint
- ✅ WebSocket setup
- ✅ Real-time activity feed
- ✅ Frontend search modal
- ✅ WebSocket integration

**Deliverable:** Can search by context and see live updates

### Phase 5: Polish & Deploy (Week 5)
**Goal:** Production-ready MVP

- ✅ Authorization & permissions
- ✅ Error handling
- ✅ Loading states
- ✅ Responsive design
- ✅ Docker deployment
- ✅ Documentation
- ✅ Demo script

**Deliverable:** Deployable prototype ready for demo

---

## 12. Risk Assessment

### High Risk
- **OpenAI API Costs**: Embedding 10K contexts = $0.20, acceptable
  - *Mitigation*: Rate limiting, caching embeddings, local fallback

- **Semantic Search Quality**: May not match user expectations
  - *Mitigation*: Hybrid search, tunable weights, user feedback

### Medium Risk
- **Real-time Scaling**: WebSocket connections don't scale horizontally easily
  - *Mitigation*: Redis pub/sub for multi-instance, or accept single-instance for MVP

- **AI Generation Latency**: GPT-4 can take 3-5 seconds
  - *Mitigation*: Async generation, loading indicators, cache results

### Low Risk
- **Pattern Stack Learning Curve**: New framework
  - *Mitigation*: This demo IS the learning process, documentation alongside

---

## 13. Appendix

### A. Glossary
- **ACV**: Annual Contract Value - yearly revenue from account
- **Context**: Notes, meeting summaries, email content related to account
- **Embedding**: Vector representation of text for semantic search
- **Next Steps**: AI-generated actionable recommendations
- **Stage**: Position in sales pipeline (Prospect → Qualifying → Presenting → Closing → Won/Lost)

### B. References
- Pattern Stack Backend: `/Users/dug/Projects/pattern-stack/backend-patterns`
- Pattern Stack Frontend: `/Users/dug/Projects/pattern-stack/frontend-patterns`
- Atomic Architecture v2.5: `tempo-demo/.claude/ai-docs/architecture.md`
- Job Description: https://jobs.ashbyhq.com/find-tempo/b5f28128-b020-4dfa-953d-6e5527924ab9

### C. Open Questions
1. Should we use OpenAI or local embeddings for cost?
2. What's the deployment target (Render, Railway, AWS)?
3. Do we need multi-tenancy from day 1 or single org?
4. Should comments support rich text (Markdown) or plain text?

---

**End of PRD**

*This document serves as the foundation for decomposition into Linear issues and implementation specs via the Pattern Stack agentic development workflow.*
