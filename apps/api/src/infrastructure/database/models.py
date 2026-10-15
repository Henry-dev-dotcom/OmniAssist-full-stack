"""SQLAlchemy models.

shortcut: the schema lives in migrations/versions/0001_initial_core.py (raw SQL, matches
Implementation Plan section 4.1). ORM models are added per entity by the task that first
reads or writes it (Tasks 9, 10, 17), so unused mapped classes do not drift from the schema.
"""
