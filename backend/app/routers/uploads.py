"""POST /api/uploads (contract endpoint 24). No LLM."""

from fastapi import APIRouter, Depends, HTTPException, UploadFile
from sqlmodel import Session

from app.db import get_session
from app.schemas import UploadOut
from app.services import uploads

router = APIRouter(prefix="/api/uploads", tags=["uploads"])


@router.post("", response_model=UploadOut)
def post_upload(file: UploadFile, session: Session = Depends(get_session)):
    # Read one byte past the limit so an oversized file is rejected without loading all of it.
    data = file.file.read(uploads.MAX_UPLOAD_BYTES + 1)
    try:
        upload = uploads.save_upload(session, file.filename or "", data)
    except uploads.UploadRejected as exc:
        raise HTTPException(400, str(exc))
    return UploadOut(id=upload.id, filename=upload.filename, chars=len(upload.text), created_at=upload.created_at)
