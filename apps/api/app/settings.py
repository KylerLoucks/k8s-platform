from urllib.parse import quote_plus

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=None, extra="ignore")

    port: int = Field(default=8000, validation_alias="PORT")
    cors_allow_origin: str = Field(default="*", validation_alias="CORS_ALLOW_ORIGIN")

    db_host: str = Field(default="", validation_alias="DB_HOST")
    db_port: int = Field(default=5432, validation_alias="DB_PORT")
    db_name: str = Field(default="", validation_alias="DB_NAME")
    db_user: str = Field(default="", validation_alias="DB_USER")
    db_password: str = Field(default="", validation_alias="DB_PASSWORD")
    db_sslmode: str = Field(default="require", validation_alias="DB_SSLMODE")

    # e.g. redis.dev-redis.svc.cluster.local:6379 — used to enqueue jobs and (elsewhere) pub/sub
    redis_addr: str = Field(default="", validation_alias="REDIS_ADDR")

    @property
    def database_url(self) -> str | None:
        if not (self.db_host and self.db_name and self.db_user):
            return None
        pw = quote_plus(self.db_password)
        user = quote_plus(self.db_user)
        return (
            f"postgresql+psycopg2://{user}:{pw}@{self.db_host}:{self.db_port}/{self.db_name}"
            f"?sslmode={quote_plus(self.db_sslmode)}"
        )


settings = Settings()
