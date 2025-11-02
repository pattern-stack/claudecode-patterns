# Tempo MVP - Entity & Service Summary

**Purpose:** High-level reference for all entities and their service operations in the Tempo brain dump application.

---

## 1. User

**Purpose:** Sales reps and team members who use the system.

### Fields
- `email` - Login credential
- `first_name`, `last_name` - Display name
- `password_hash` - Authentication
- `is_active` - Account status

### UserService Methods

```python
async def create(data: UserCreate) -> User
    # Create new user account with hashed password

async def authenticate(email: str, password: str) -> User | None
    # Validate credentials and return user if valid

async def get_by_email(email: str) -> User | None
    # Find user by email address

async def get_by_id(user_id: UUID) -> User | None
    # Get user by ID

async def update(user_id: UUID, data: UserUpdate) -> User
    # Update user profile fields

async def deactivate(user_id: UUID) -> User
    # Soft-delete user account
```

---

## 2. Account

**Purpose:** The customer/deal being tracked. Central entity in the system.

### Fields
- `name` - Company name
- `stage` - Pipeline position (prospect, qualifying, presenting, closing, closed_won, closed_lost)
- `actual_value` - Deal value ($)
- `acv` - Annual contract value
- `next_meeting` - Scheduled meeting date
- `next_steps` - Manual next steps (user-entered)
- `ai_next_steps` - AI-generated next steps
- `ai_next_steps_generated_at` - When AI last updated
- `owner_user_id` - Sales rep who owns this account
- `metadata` - Flexible JSON for any additional data

### AccountService Methods

```python
async def create(data: AccountCreate, owner_id: UUID) -> Account
    # Create new account with owner assignment
    # Triggers: Initial AI next steps generation

async def list(
    owner_id: UUID,
    stage: str | None = None,
    search: str | None = None,
    limit: int = 20,
    offset: int = 0
) -> list[Account]
    # Get paginated, filtered list of accounts
    # Supports: stage filter, name search, pagination

async def get_by_id(account_id: UUID) -> Account | None
    # Get single account by ID

async def update(account_id: UUID, data: AccountUpdate) -> Account
    # Update account fields
    # Triggers: Activity log for field changes
    # Triggers: AI next steps regeneration if stage changed

async def transition_stage(account_id: UUID, new_stage: str) -> Account
    # Move account to new pipeline stage
    # Validates: Stage transition is allowed
    # Triggers: Stage change activity
    # Triggers: AI next steps regeneration

async def delete(account_id: UUID) -> None
    # Soft-delete account (sets archived flag)
    # Triggers: Deletion activity log

async def get_with_context(account_id: UUID) -> AccountWithContext
    # Get account with all activities, memories, pending updates
    # Used for: Account detail view
```

---

## 3. Activity

**Purpose:** All interactions with an account. Polymorphic - stores meetings, emails, brain dumps, system events.

### Fields
- `account_id` - Which account this relates to
- `type` - Activity type (voice_capture, file_upload, text_paste, meeting, email_sent, email_received, call, note, field_change, stage_change)
- `title` - Brief description
- `content` - Full content (transcript, email body, notes)
- `searchable_content` - Denormalized for full-text search
- `occurred_at` - When this activity happened
- `created_by_user_id` - Who created this
- `data` - Type-specific JSON data (audio_url, attendees, etc.)

### ActivityService Methods

```python
async def create(data: ActivityCreate) -> Activity
    # Create new activity
    # Sets: searchable_content for FTS
    # Triggers: AI processing (async)

async def list_by_account(
    account_id: UUID,
    activity_type: str | None = None,
    since: datetime | None = None,
    limit: int = 50
) -> list[Activity]
    # Get activity timeline for account
    # Supports: Filter by type, get only new activities since timestamp
    # Used for: Timeline view and polling

async def create_voice_capture(
    account_id: UUID,
    audio_file: bytes,
    created_by_user_id: UUID
) -> Activity
    # Upload voice recording
    # Creates: Activity with type=voice_capture
    # Triggers: Transcription job (async)
    # Triggers: AI processing after transcription

async def create_file_upload(
    account_id: UUID,
    file: bytes,
    filename: str,
    created_by_user_id: UUID
) -> Activity
    # Upload document/file
    # Creates: Activity with type=file_upload
    # Triggers: Text extraction (if PDF/doc)
    # Triggers: AI processing

async def create_text_paste(
    account_id: UUID,
    text: str,
    created_by_user_id: UUID
) -> Activity
    # Paste text from clipboard
    # Creates: Activity with type=text_paste
    # Triggers: AI processing immediately

async def log_field_change(
    account_id: UUID,
    field_name: str,
    old_value: Any,
    new_value: Any,
    changed_by_user_id: UUID
) -> Activity
    # System-generated activity for field changes
    # Creates: Activity with type=field_change
    # Used for: Audit trail

async def log_stage_change(
    account_id: UUID,
    from_stage: str,
    to_stage: str,
    changed_by_user_id: UUID
) -> Activity
    # System-generated activity for stage transitions
    # Creates: Activity with type=stage_change
```

---

## 4. Memory

**Purpose:** AI-extracted persistent facts about accounts. "Bill doesn't like 8am meetings", "Need CFO approval".

### Fields
- `account_id` - Which account this memory relates to
- `content` - The actual insight/fact
- `extracted_from_activity_id` - Which activity generated this
- `extracted_at` - When AI extracted this
- `is_active` - Can be deprecated over time

### MemoryService Methods

```python
async def create(
    account_id: UUID,
    content: str,
    extracted_from_activity_id: UUID
) -> Memory
    # Create new memory (called by AI processor)

async def list_by_account(account_id: UUID, active_only: bool = True) -> list[Memory]
    # Get all memories for account
    # Used for: Memory display, AI context aggregation

async def deactivate(memory_id: UUID) -> Memory
    # Mark memory as no longer relevant
    # Sets: is_active = False

async def search(query: str, limit: int = 20) -> list[Memory]
    # Full-text search across memories
    # Used for: Finding accounts with specific insights
```

---

## 5. Update

**Purpose:** AI-suggested changes waiting for human approval. The approval queue.

### Fields
- `account_id` - Which account to update
- `field_name` - Which field to change (stage, actual_value, next_steps, etc.)
- `old_value` - Current value
- `new_value` - Proposed value
- `source_activity_id` - Which activity triggered this
- `status` - pending, approved, rejected
- `reviewed_by_user_id` - Who reviewed
- `reviewed_at` - When reviewed

### UpdateService Methods

```python
async def create(
    account_id: UUID,
    field_name: str,
    old_value: Any,
    new_value: Any,
    source_activity_id: UUID
) -> Update
    # Create suggested update (called by AI processor)
    # Creates: Update with status=pending

async def list_pending(user_id: UUID | None = None) -> list[Update]
    # Get all pending updates
    # Optionally: Filter by user's owned accounts
    # Used for: Updates approval view

async def approve(update_id: UUID, reviewed_by_user_id: UUID) -> Update
    # Approve update and apply changes
    # Updates: Account field with new value
    # Sets: status=approved, reviewed_by, reviewed_at
    # Triggers: Field change activity log

async def reject(update_id: UUID, reviewed_by_user_id: UUID) -> Update
    # Reject update without applying
    # Sets: status=rejected, reviewed_by, reviewed_at

async def approve_all(update_ids: list[UUID], reviewed_by_user_id: UUID) -> list[Update]
    # Bulk approve multiple updates
    # Used for: "Approve All" button
```

---

## Key Workflows

### Brain Dump Flow
```
1. User uploads voice/file/text
2. ActivityService.create_voice_capture/file_upload/text_paste()
3. Background: Transcribe/extract text
4. Trigger: AI Processing Workflow
```

### AI Processing Workflow
```
1. Get all recent Activities for Account
2. Send to AI:
   - Extract memories
   - Suggest field updates
   - Generate next steps
3. MemoryService.create() for each memory
4. UpdateService.create() for each suggested change
5. AccountService.update() to set ai_next_steps
```

### Update Approval Flow
```
1. User views pending updates
2. User clicks "Approve" on update
3. UpdateService.approve()
   - Applies change to Account
   - Logs activity
   - Updates status
```

### Search Flow
```
1. User searches "pricing concerns"
2. PostgreSQL full-text search on Activity.searchable_content
3. Return matching Activities grouped by Account
```

### Timeline Polling Flow
```
1. Frontend polls every 5 seconds
2. ActivityService.list_by_account(since=last_fetch)
3. Returns only new activities
4. Frontend appends to timeline
```

---

## Service Dependencies

**AccountService** depends on:
- ActivityService (to log changes)
- No other services

**ActivityService** depends on:
- External: Transcription API (for voice)
- External: Text extraction (for files)
- Triggers: AI processing (async, doesn't block)

**MemoryService** depends on:
- ActivityService (for provenance)

**UpdateService** depends on:
- AccountService (to apply changes)
- ActivityService (to log approval)

**AI Processing** depends on:
- ActivityService (to fetch context)
- MemoryService (to create memories)
- UpdateService (to create suggestions)
- AccountService (to update next steps)

---

**End of Document**
