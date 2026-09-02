from sqlalchemy import inspect, text
from sqlmodel import Session, SQLModel, create_engine

from app.config import settings

# Imported for its side effect: registering every table on SQLModel.metadata,
# which both create_all() and _add_missing_columns() iterate over. Without it,
# importing app.db alone silently sees zero tables.
from app import models  # noqa: F401

connect_args = {"check_same_thread": False} if "sqlite" in settings.database_url else {}
engine = create_engine(settings.database_url, connect_args=connect_args)


def _add_missing_columns() -> None:
    """Bring an existing DB file up to date with newly added model columns.

    create_all() only creates missing *tables*, so a column added to a model
    after the local self_infinity.db was first created stays absent and every
    query on that table fails with "no such column". Alembic is overkill for a
    single-user SQLite app, so this does the one migration shape that actually
    comes up here: additive, nullable columns. Anything else (drops, renames,
    type changes, new NOT NULL columns) is still a manual job.
    """
    inspector = inspect(engine)
    existing_tables = set(inspector.get_table_names())
    with engine.begin() as conn:
        for table in SQLModel.metadata.sorted_tables:
            if table.name not in existing_tables:
                continue
            present = {c["name"] for c in inspector.get_columns(table.name)}
            for column in table.columns:
                if column.name in present:
                    continue
                if not column.nullable:
                    raise RuntimeError(
                        f"{table.name}.{column.name} is a new NOT NULL column; "
                        "migrate it by hand or recreate the database."
                    )
                ddl = column.type.compile(engine.dialect)
                conn.execute(text(f'ALTER TABLE "{table.name}" ADD COLUMN "{column.name}" {ddl}'))


def init_db() -> None:
    SQLModel.metadata.create_all(engine)
    _add_missing_columns()


def get_session():
    with Session(engine) as session:
        yield session
