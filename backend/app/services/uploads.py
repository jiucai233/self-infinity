"""Uploaded files (contract endpoint 24): validate, extract text, store.

The file itself is not kept, only the extracted text (cut to MAX_UPLOAD_TEXT_CHARS).
No LLM is involved.
"""

import io
import logging
from pathlib import PurePath

from sqlmodel import Session

from app.models import Upload

logger = logging.getLogger(__name__)

MAX_UPLOAD_BYTES = 4 * 1024 * 1024
MAX_UPLOAD_TEXT_CHARS = 100_000
ALLOWED_EXTENSIONS = (".pdf", ".txt", ".md")

BAD_FILE = "Only PDF, TXT or MD files up to 4 MB."
NO_TEXT = "No text could be read from this file."


class UploadRejected(Exception):
    """The file is not acceptable; the message is the 400 detail."""


def _decode(data: bytes) -> str:
    for encoding in ("utf-8-sig", "cp949"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace")


def _pdf_text(data: bytes) -> str:
    # Imported here so a missing optional dependency only breaks PDF uploads.
    from pypdf import PdfReader

    try:
        reader = PdfReader(io.BytesIO(data))
        if reader.is_encrypted and not reader.decrypt(""):
            return ""
        parts: list[str] = []
        total = 0
        for page in reader.pages:
            text = page.extract_text() or ""
            parts.append(text)
            total += len(text)
            if total >= MAX_UPLOAD_TEXT_CHARS:
                break
    except Exception:
        logger.warning("pdf text extraction failed", exc_info=True)
        return ""
    return "\n".join(parts)


def extract_text(filename: str, data: bytes) -> str:
    extension = PurePath(filename).suffix.lower()
    if extension not in ALLOWED_EXTENSIONS:
        raise UploadRejected(BAD_FILE)
    if len(data) > MAX_UPLOAD_BYTES:
        raise UploadRejected(BAD_FILE)
    text = _pdf_text(data) if extension == ".pdf" else _decode(data)
    text = text.replace("\x00", "").strip()
    if not text:
        raise UploadRejected(NO_TEXT)
    return text[:MAX_UPLOAD_TEXT_CHARS]


def save_upload(session: Session, filename: str, data: bytes) -> Upload:
    # Browsers may send a path-like name; keep only the last component.
    name = PurePath((filename or "").replace("\\", "/")).name
    text = extract_text(name, data)
    upload = Upload(filename=name, text=text)
    session.add(upload)
    session.commit()
    session.refresh(upload)
    return upload
