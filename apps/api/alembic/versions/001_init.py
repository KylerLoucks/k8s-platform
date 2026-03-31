"""initial schema

Revision ID: 001_init
Revises:
Create Date: 2026-03-30

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "001_init"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "demo_items",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "demo_counters",
        sa.Column("key", sa.String(length=64), nullable=False),
        sa.Column("value", sa.BigInteger(), nullable=False),
        sa.PrimaryKeyConstraint("key"),
    )
    op.create_table(
        "ws_events",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("room", sa.String(length=128), nullable=False),
        sa.Column("payload", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_ws_events_room", "ws_events", ["room"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_ws_events_room", table_name="ws_events")
    op.drop_table("ws_events")
    op.drop_table("demo_counters")
    op.drop_table("demo_items")
