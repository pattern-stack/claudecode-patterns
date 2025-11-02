# Change Tracking in Pattern Stack

## Overview

Pattern Stack provides automatic change tracking for all patterns that inherit from `BasePattern`. This feature creates a complete audit trail of field modifications, enabling compliance, debugging, and data analytics use cases.

## Performance Characteristics

Based on comprehensive benchmarks, change tracking has the following performance characteristics:

### Measured Overhead
- **Write Operations**: <50% overhead on average
  - Single field updates: 35-45% slower
  - Multiple field updates: 25-35% slower
  - Bulk operations: 15-25% slower
- **Read Operations**: No impact on standard queries
- **Memory Usage**: Minimal impact (<5% increase)

### Performance Factors
- Event store backend (memory vs database)
- Number of tracked fields per entity
- Retention policy settings
- Concurrent update volume

## Configuration

### Basic Configuration

Change tracking is enabled by default for all patterns. Configure it in your pattern's `Pattern` inner class:

```python
class MyPattern(BasePattern):
    class Pattern:
        # Basic configuration
        track_changes = True  # Default: True

        # Field-level control
        track_changes_fields = ["*"]  # Default: all fields
        track_changes_exclude = ["updated_at"]  # Default: ["updated_at"]

        # Retention policy
        change_retention = "365d"  # Default: 365 days
```

### Advanced Configuration

```python
class AdvancedPattern(BasePattern):
    class Pattern:
        # Track only specific fields
        track_changes_fields = ["status", "assigned_to", "priority"]

        # Exclude sensitive fields
        track_changes_exclude = ["password_hash", "secret_key"]

        # Custom retention policies
        change_retention = "2y"  # 2 years
        # change_retention = "90d"  # 90 days
        # change_retention = "forever"  # Never expire
```

### Retention Policy Formats
- `"Xd"` - X days (e.g., `"90d"`)
- `"Xm"` - X months (e.g., `"6m"`)
- `"Xy"` - X years (e.g., `"2y"`)
- `"forever"` - Never expire (use with caution)

## Best Practices

### 1. Field Selection Strategy

**Track Important Business Fields Only**
```python
class OrderPattern(BasePattern):
    class Pattern:
        # Good: Track business-critical fields
        track_changes_fields = [
            "status", "total_amount", "shipping_address",
            "assigned_agent", "priority"
        ]

        # Avoid: Tracking all fields including metadata
        # track_changes_fields = ["*"]
```

**Exclude High-Frequency Fields**
```python
class SessionPattern(BasePattern):
    class Pattern:
        track_changes_fields = ["*"]
        track_changes_exclude = [
            "last_seen",      # Updated frequently
            "request_count",  # Incremented constantly
            "session_data"    # Large, frequently changing
        ]
```

### 2. Retention Management

**Set Appropriate Retention Periods**
```python
# Short retention for high-volume entities
class LogEntryPattern(BasePattern):
    class Pattern:
        change_retention = "30d"

# Long retention for compliance
class FinancialRecordPattern(BasePattern):
    class Pattern:
        change_retention = "7y"

# Medium retention for business data
class CustomerPattern(BasePattern):
    class Pattern:
        change_retention = "3y"
```

### 3. Query Optimization

**Use Specific Date Ranges**
```python
# Good: Limit query scope
recent_changes = await entity.get_changes(
    since=datetime.now(UTC) - timedelta(days=30),
    limit=100
)

# Avoid: Open-ended queries
# all_changes = await entity.get_changes()  # Could be huge!
```

**Filter by Relevant Fields**
```python
# Good: Query specific fields
status_changes = await entity.get_changes(
    fields=["status", "assigned_to"],
    since=last_check_time
)

# Better: Use field-specific method
status_history = await entity.get_field_history("status", limit=20)
```

### 4. User Context Management

```python
from pattern_stack.atoms.patterns.context import set_current_user_id

# Set user context for accurate change attribution
async def update_order(order_id: str, updates: dict, user_id: str):
    set_current_user_id(user_id)

    # Changes will be attributed to this user
    order = await OrderPattern.get(order_id)
    for field, value in updates.items():
        setattr(order, field, value)
    await order.save()
```

## API Usage Examples

### Basic Change Tracking

```python
# Create and modify an entity
user = UserPattern(name="John Doe", email="john@example.com")
await user.save()

# Make some changes
user.name = "John Smith"
user.status = "active"
await user.save()

# Get change history
changes = await user.get_changes()
for change in changes:
    print(f"{change.field_name}: {change.old_value} → {change.new_value}")
    print(f"Changed at: {change.timestamp}")
    print(f"Changed by: {change.user_id}")
```

### Field-Specific Tracking

```python
# Get history for a specific field
status_history = await user.get_field_history("status")
for entry in status_history:
    print(f"{entry['timestamp']}: {entry['old_value']} → {entry['new_value']}")

# Get last modification times
last_modified = await user.get_last_modified_fields()
if "email" in last_modified:
    print(f"Email last changed: {last_modified['email']}")
```

### Advanced Queries

```python
# Get changes in a date range
start_date = datetime(2024, 1, 1, tzinfo=UTC)
end_date = datetime(2024, 1, 31, tzinfo=UTC)

january_changes = await user.get_changes(
    since=start_date,
    until=end_date,
    fields=["name", "email", "status"]
)

# Get recent changes for multiple fields
critical_fields = ["status", "assigned_to", "priority"]
recent_critical_changes = await entity.get_changes(
    fields=critical_fields,
    since=datetime.now(UTC) - timedelta(hours=24),
    limit=50
)
```

## Troubleshooting

### Common Issues

#### 1. Changes Not Being Tracked

**Symptoms**: No change events in the event store despite field modifications.

**Causes & Solutions**:
```python
# Check if tracking is enabled
class MyPattern(BasePattern):
    class Pattern:
        track_changes = True  # Must be True

# Verify field is not excluded
class MyPattern(BasePattern):
    class Pattern:
        track_changes_exclude = ["updated_at"]  # Check this list

# Ensure field exists and is tracked
tracked_fields = MyPattern._get_tracked_fields()
print(f"Tracked fields: {tracked_fields}")
```

#### 2. Missing User Attribution

**Symptoms**: Changes show `user_id: None`

**Solution**:
```python
from pattern_stack.atoms.patterns.context import set_current_user_id

# Always set user context before making changes
set_current_user_id(current_user.id)
await entity.save()
```

#### 3. Performance Issues

**Symptoms**: Slow write operations

**Solutions**:
```python
# Reduce tracked fields
class MyPattern(BasePattern):
    class Pattern:
        track_changes_fields = ["critical_field_only"]

# Use memory event store for high-volume operations
from pattern_stack.atoms.events.factory import configure_event_store
configure_event_store("memory")  # In test/dev environments

# Implement batching for bulk operations
async def bulk_update(entities: list):
    # Disable tracking temporarily for bulk operations
    # (Advanced: requires custom implementation)
    pass
```

#### 4. Event Store Connection Issues

**Symptoms**: `RuntimeError: Event store not available`

**Solutions**:
```python
# Check event store configuration
from pattern_stack.atoms.events.factory import get_event_store
event_store = get_event_store()
print(f"Event store type: {type(event_store)}")

# For database event store, check connection
from pattern_stack.atoms.data.session import get_db_session
async with get_db_session() as session:
    # Test database connectivity
    result = await session.execute("SELECT 1")
    print(f"Database connection: OK")
```

#### 5. Large Query Results

**Symptoms**: Memory issues or slow queries when retrieving change history

**Solutions**:
```python
# Use pagination
page_size = 100
offset = 0

while True:
    changes = await entity.get_changes(
        limit=page_size,
        since=datetime.now(UTC) - timedelta(days=1)
    )

    if not changes:
        break

    # Process this batch
    process_changes(changes)
    offset += page_size

# Use streaming for large datasets
async def stream_changes(entity, since=None):
    limit = 100
    last_timestamp = since

    while True:
        changes = await entity.get_changes(
            since=last_timestamp,
            limit=limit
        )

        if not changes:
            break

        for change in changes:
            yield change
            last_timestamp = max(last_timestamp or change.timestamp,
                               change.timestamp)
```

## Migration and Rollback

### Enabling Change Tracking on Existing Patterns

```python
# 1. Add tracking configuration to existing pattern
class ExistingPattern(BasePattern):
    class Pattern:
        track_changes = True  # Add this
        track_changes_fields = ["critical_field"]  # Start with subset

# 2. Migrate existing data (optional)
async def migrate_existing_entities():
    entities = await ExistingPattern.all()

    for entity in entities:
        # Create initial "creation" event for existing entities
        # (This requires custom implementation)
        pass
```

### Disabling Change Tracking

```python
# Option 1: Disable for specific pattern
class MyPattern(BasePattern):
    class Pattern:
        track_changes = False

# Option 2: Disable globally (not recommended)
# Modify event store configuration to use a null backend
```

### Data Cleanup

```python
# Clean up old change events based on retention policy
from pattern_stack.atoms.events.service import EventService

async def cleanup_old_events():
    event_service = EventService()

    # Events older than retention policy will be automatically
    # cleaned up based on expires_at field

    # Manual cleanup if needed
    cutoff_date = datetime.now(UTC) - timedelta(days=365)
    await event_service.delete_events_before(cutoff_date)
```

## Monitoring and Observability

### Metrics to Track

```python
# Change volume metrics
async def get_change_metrics():
    event_service = EventService()

    # Changes in last 24 hours
    recent_changes = await event_service.count_events(
        category=EventCategory.CHANGE,
        since=datetime.now(UTC) - timedelta(days=1)
    )

    # Changes by entity type
    by_entity = await event_service.count_by_entity_type(
        category=EventCategory.CHANGE
    )

    # Most changed fields
    by_field = await event_service.count_by_field_name(
        category=EventCategory.CHANGE
    )

    return {
        "recent_changes": recent_changes,
        "by_entity": by_entity,
        "by_field": by_field
    }
```

### Health Checks

```python
async def check_change_tracking_health():
    """Health check for change tracking system."""
    try:
        # Test event store connectivity
        event_store = get_event_store()

        # Test write capability
        test_event = EventData(
            event_category=EventCategory.SYSTEM,
            event_type="health_check",
            entity_type="HealthCheck",
            entity_id="test",
            timestamp=datetime.now(UTC)
        )

        await event_store.emit(test_event)

        # Test read capability
        events = await event_store.query(EventFilters(
            event_type="health_check",
            limit=1
        ))

        return {
            "status": "healthy",
            "event_store": type(event_store).__name__,
            "can_write": True,
            "can_read": len(events) > 0
        }

    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e)
        }
```

## Security Considerations

### Sensitive Data Handling

```python
class UserPattern(BasePattern):
    class Pattern:
        # Exclude sensitive fields from change tracking
        track_changes_exclude = [
            "password_hash",
            "secret_token",
            "payment_info",
            "ssn"
        ]

# For fields that need tracking but contain sensitive data,
# implement custom serialization
@staticmethod
def _serialize_value(value: Any) -> Any:
    if isinstance(value, SensitiveData):
        return "[REDACTED]"
    return super()._serialize_value(value)
```

### Access Control

```python
# Implement access control for change history
async def get_changes_with_permission_check(
    entity: BasePattern,
    user_id: str,
    **kwargs
) -> list[Any]:
    # Check if user can view change history
    if not can_user_view_changes(user_id, entity):
        raise PermissionError("Not authorized to view change history")

    return await entity.get_changes(**kwargs)
```

## Integration with External Systems

### Webhook Integration

```python
# Listen for change events and trigger webhooks
async def setup_change_webhooks():
    event_store = get_event_store()

    async def change_handler(event: EventData):
        if event.event_category == EventCategory.CHANGE:
            await send_webhook(
                url=settings.CHANGE_WEBHOOK_URL,
                data={
                    "entity_type": event.entity_type,
                    "entity_id": event.entity_id,
                    "field_name": event.field_name,
                    "old_value": event.old_value,
                    "new_value": event.new_value,
                    "timestamp": event.timestamp.isoformat()
                }
            )

    # Register event handler
    event_store.add_listener(change_handler)
```

### Audit Log Export

```python
async def export_audit_log(
    entity_type: str = None,
    since: datetime = None,
    until: datetime = None,
    format: str = "json"
) -> str:
    """Export change tracking data for external audit systems."""

    filters = EventFilters(
        event_category=EventCategory.CHANGE,
        entity_type=entity_type,
        timestamp_from=since,
        timestamp_to=until
    )

    events = await get_event_store().query(filters)

    if format == "json":
        return json.dumps([
            {
                "timestamp": event.timestamp.isoformat(),
                "entity_type": event.entity_type,
                "entity_id": str(event.entity_id),
                "field_name": event.field_name,
                "old_value": event.old_value,
                "new_value": event.new_value,
                "user_id": str(event.user_id) if event.user_id else None
            }
            for event in events
        ], indent=2)

    elif format == "csv":
        # Implement CSV export
        pass

    else:
        raise ValueError(f"Unsupported format: {format}")
```

## Conclusion

Change tracking in Pattern Stack provides a robust foundation for audit trails, compliance, and data analytics. By following these best practices and guidelines, you can implement effective change tracking while maintaining optimal performance.

For additional support or questions, refer to the Pattern Stack documentation or open an issue in the project repository.
