"""Delivery adapters. The domain only sees NotificationGateway, so a push provider can be
swapped in later without touching reminder rules. The provider is [TBD]: until one is
chosen, "push" is delivered to the in-app notification center, which always works."""

from dataclasses import dataclass
from typing import Protocol


class DeliveryError(Exception):
    """The provider refused or could not be reached. The reason is stored on the row."""


@dataclass(frozen=True)
class Message:
    notification_id: str
    channel: str
    urgency: str
    title: str
    user_id: str = ""  # who to push to; empty means in-app only


class NotificationGateway(Protocol):
    async def send(self, message: Message) -> None: ...


class InAppGateway:
    """Marks delivery done. The device shows the row in its notification center."""

    async def send(self, message: Message) -> None:
        return None
