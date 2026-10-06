import os
from pathlib import Path

from fastapi import Depends
from sqlalchemy import event, inspect, text
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.pool import NullPool
from sqlmodel import Session, SQLModel, create_engine

from app.auth import DEV_USER, CurrentUser, current_user
from app.config import settings

# Imported for its side effect: registering every table on SQLModel.metadata,
# which both create_all() and _add_missing_columns() iterate over. Without it,
# importing app.db alone silently sees zero tables.
from app import models  # noqa: F401


def _make_engine(url: str) -> Engine:
    """SQLite locally; Postgres (Supabase) in production.

    Postgres runs behind Supabase's transaction pooler on serverless functions, so: no pool of our
    own (NullPool — every request opens and closes one connection) and no server-side prepared
    statements (the pooler cannot keep them across transactions).
    """
    if url.startswith(("postgres://", "postgresql://")):
        url = "postgresql+psycopg://" + url.split("://", 1)[1]
    if url.startswith("postgresql"):
        # The Supabase integration's URLs carry tags for other clients (`supa=…`, Prisma's
        # `pgbouncer=true`); libpq rejects unknown options, so drop them.
        parsed = make_url(url).difference_update_query(["supa", "pgbouncer"])
        return create_engine(parsed, poolclass=NullPool, connect_args={"prepare_threshold": None})
    if os.environ.get("VERCEL"):
        # The function's file system is read-only: SQLite would fail on the first write anyway.
        raise RuntimeError(
            "No Postgres database on Vercel: set DATABASE_URL, or connect the Supabase "
            "integration (it sets POSTGRES_URL)."
        )
    sqlite = create_engine(url, connect_args={"check_same_thread": False})
    event.listen(sqlite, "connect", _attach_known_schemas)
    return sqlite


# ---------------------------------------------------------------- one schema per account
#
# With AUTH_MODE=supabase every account gets a schema of its own (`u_<id>`, see app/auth.py).
# The tables are the same everywhere; a request's session carries
# `schema_translate_map={None: "u_<id>"}`, so every statement SQLAlchemy emits — reads, writes,
# DDL — is qualified with that schema. No service filters by user, and none can forget to.
# In SQLite a schema is an attached database file (`self_infinity.u_<id>.db` next to the main
# one, or a fresh in-memory database for an in-memory engine).

_ready: set[tuple[int, str]] = set()  # (id(engine), schema) whose tables exist
_sqlite_files: dict[str, str] = {}  # schema -> attached file, re-attached on every new connection


def _sqlite_file_for(eng: Engine, schema: str) -> str:
    database = eng.url.database
    if not database or database == ":memory:":
        return ":memory:"
    path = Path(database)
    return str(path.with_name(f"{path.stem}.{schema}{path.suffix or '.db'}"))


def _attach_known_schemas(dbapi_connection, _record) -> None:
    for schema, file in _sqlite_files.items():
        dbapi_connection.execute(f"ATTACH DATABASE '{file}' AS \"{schema}\"")


def _attach_sqlite(eng: Engine, schema: str) -> None:
    file = _sqlite_file_for(eng, schema)
    with eng.connect() as conn:
        attached = {row[1] for row in conn.exec_driver_sql("PRAGMA database_list")}
        if schema not in attached:
            conn.exec_driver_sql(f"ATTACH DATABASE '{file}' AS \"{schema}\"")
    if file != ":memory:":
        _sqlite_files[schema] = file
        # Pooled connections opened before this schema existed do not have it attached.
        eng.dispose()


def ensure_schema(eng: Engine, schema: str) -> Engine:
    """Creates [schema] and its tables once per process; returns the engine bound to it."""
    scoped = eng.execution_options(schema_translate_map={None: schema})
    key = (id(eng), schema)
    if key in _ready:
        return scoped
    if eng.dialect.name == "sqlite":
        _attach_sqlite(eng, schema)
    else:
        with eng.begin() as conn:
            conn.execute(text(f'CREATE SCHEMA IF NOT EXISTS "{schema}"'))
    SQLModel.metadata.create_all(scoped)
    _add_missing_columns(scoped, schema)
    _ready.add(key)
    return scoped


engine = _make_engine(settings.database_url)


def _refuse_legacy_database() -> None:
    """Fail loudly on a database file from before courses existed.

    The old schema had SkillNode.parent_id and no Course table. There is no
    migration for it (the data model changed shape), and letting create_all()
    add the new tables next to the old ones would leave a half-migrated file
    that fails later in confusing ways.
    """
    inspector = inspect(engine)
    if "skillnode" not in inspector.get_table_names():
        return
    columns = {c["name"] for c in inspector.get_columns("skillnode")}
    if "course_id" not in columns:
        raise RuntimeError(
            "The database was created by an older version of Self-Infinity and has no "
            "course tables. Move the file away (or point DATABASE_URL elsewhere) to start fresh."
        )


def _add_missing_columns(eng: Engine | None = None, schema: str | None = None) -> None:
    """Bring an existing DB file up to date with newly added model columns.

    create_all() only creates missing *tables*, so a column added to a model
    after the local database was first created stays absent and every query
    on that table fails with "no such column". Plan section 5.7 requires
    columns added after the first release to be nullable, so this does the one
    migration shape that actually comes up: additive, nullable columns.
    Anything else (drops, renames, type changes, new NOT NULL columns) is a
    manual job.
    """
    eng = eng or engine
    inspector = inspect(eng)
    existing_tables = set(inspector.get_table_names(schema=schema))
    with eng.begin() as conn:
        for table in SQLModel.metadata.sorted_tables:
            if table.name not in existing_tables:
                continue
            present = {c["name"] for c in inspector.get_columns(table.name, schema=schema)}
            for column in table.columns:
                if column.name in present:
                    continue
                if not column.nullable:
                    raise RuntimeError(
                        f"{table.name}.{column.name} is a new NOT NULL column; "
                        "migrate it by hand or recreate the database."
                    )
                ddl = column.type.compile(eng.dialect)
                qualified = f'"{schema}"."{table.name}"' if schema else f'"{table.name}"'
                conn.execute(text(f'ALTER TABLE {qualified} ADD COLUMN "{column.name}" {ddl}'))


def init_db() -> None:
    # With accounts, each schema is set up on its user's first request (ensure_schema).
    if settings.auth_mode == "supabase":
        return
    _refuse_legacy_database()
    SQLModel.metadata.create_all(engine)
    _add_missing_columns()


def get_session(user: CurrentUser = Depends(current_user)):
    # 读模块级的 engine，所以测试里换掉 app.db.engine，请求、后台任务和 lifespan 就一起换。
    # 后台任务拿 session.get_bind()，它带着同一个 schema_translate_map。
    # Called directly (not through FastAPI), `user` is still the Depends marker: the local user.
    schema = user.schema if isinstance(user, CurrentUser) else DEV_USER.schema
    bind = engine if schema is None else ensure_schema(engine, schema)
    with Session(bind) as session:
        yield session
