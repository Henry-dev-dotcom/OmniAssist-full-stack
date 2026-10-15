"""In-memory auth provider for tests. Tokens look like `access:<email>`."""

from src.auth.provider import AuthSession, Identity, unauthenticated


class FakeProvider:
    def __init__(self) -> None:
        self.passwords: dict[str, str] = {"ada@example.com": "pw", "bob@example.com": "pw"}
        self.revoked: list[str] = []

    def _session(self, email: str) -> AuthSession:
        return AuthSession(f"access:{email}", f"refresh:{email}", 3600)

    async def register(self, email: str, password: str, display_name: str) -> AuthSession:
        self.passwords[email] = password
        return self._session(email)

    async def login(self, email: str, password: str) -> AuthSession:
        if self.passwords.get(email) != password:
            raise unauthenticated("Email or password is incorrect.")
        return self._session(email)

    async def refresh(self, refresh_token: str) -> AuthSession:
        if not refresh_token.startswith("refresh:"):
            raise unauthenticated()
        return self._session(refresh_token.removeprefix("refresh:"))

    async def logout(self, refresh_token: str) -> None:
        self.revoked.append(refresh_token)

    async def verify_access_token(self, token: str) -> Identity:
        if not token.startswith("access:"):
            raise unauthenticated()
        email = token.removeprefix("access:")
        return Identity(subject=f"sub-{email}", email=email, name=email.split("@")[0].title())
