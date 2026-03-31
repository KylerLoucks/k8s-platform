from urllib.parse import quote_plus

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=None, extra="ignore")

    port: int = Field(default=8000, validation_alias="PORT")
    ws_allowed_origins: str = Field(default="*", validation_alias="WS_ALLOWED_ORIGINS")

    db_host: str = Field(default="", validation_alias="DB_HOST")
    db_port: int = Field(default=5432, validation_alias="DB_PORT")
    db_name: str = Field(default="", validation_alias="DB_NAME")
    db_user: str = Field(default="", validation_alias="DB_USER")
    db_password: str = Field(default="", validation_alias="DB_PASSWORD")

    # redis://host:6379/0 — subscribe for cross-pod fan-out (same Redis as queue/pub-sub)
    redis_url: str = Field(default="", validation_alias="REDIS_URL")

    @property
    def database_url(self) -> str | None:
        if not (self.db_host and self.db_name and self.db_user):
            return None
        pw = quote_plus(self.db_password)
        user = quote_plus(self.db_user)
        return f"postgresql+psycopg2://{user}:{pw}@{self.db_host}:{self.db_port}/{self.db_name}"


settings = Settings()
