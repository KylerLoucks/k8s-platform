from datetime import datetime

from sqlalchemy import BigInteger, DateTime, String, Text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class WsEvent(Base):
    __tablename__ = "ws_events"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    room: Mapped[str] = mapped_column(String(128), nullable=False, index=True)
    payload: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
